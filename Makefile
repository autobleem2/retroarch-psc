# RetroArch + libretro cores for the PlayStation Classic.
#
#   make retroarch            the retroarch binary -> dist/retroarch/ (autobleem-build image; -ctng = Dockerfile toolchain)
#   make cores                every core in cores/cores.txt -> dist/cores/ (parallel, skips what is built)
#   make core CORE=snes9x     one core
#   make package              dist/release/: retroarch-psc-<tag>.zip, libretro-cores-psc-<tag>.tar.gz,
#                             manifest.json (what the PC installer reads)
#   make release              everything above
#   make package-retroarch    the zip + manifest.json without cores (no cores image needed)
#   make publish              dist/release/ -> https://autobleem.retromenele.pl/psc/retroarch/<tag>/ (via ../AutoBleem2)
#   make pack-retroboot-cores | publish-cores   RetroBoot's cores from a stick -> psc/cores/ (until we build our own)
#   make pack-retroboot-libs | publish-libs     RetroBoot's runtime libraries (its apps and ours need them) -> psc/libs/
#   make status | retry-failed | audit-cores | check-version | shell | clean | distclean | help
#
# Knobs: PARALLEL (cores built at once), JOBS_PER_CORE, FORCE=1 (rebuild built cores), TAG (release
# name, default `git describe`), LIBRETRO_SUPER_REF / RETROARCH_VERSION (override the Dockerfile's pins),
# CORES_IMAGE (a prebuilt cores image, e.g. from GHCR, instead of building one here).
#
# One Dockerfile, three targets (see its header): the toolchain stage is shared, so the first `make`
# builds it once (~1 h) and both products reuse it from the Docker cache.

DOCKER      ?= docker
CORES_IMAGE ?= retroarch-psc-cores
BASE_IMAGE  ?= retroarch-psc-base

DIST_DIR     := dist
RA_OUT       := $(DIST_DIR)/retroarch
CORES_OUT    := $(DIST_DIR)/cores
INFO_OUT     := $(DIST_DIR)/info
RELEASE_DIR  := $(DIST_DIR)/release
METADATA_DIR := build_metadata
COMMIT_DIR   := $(METADATA_DIR)/commits
STATUS_DIR   := build_status
FAILED_FILE  := $(STATUS_DIR)/failed.txt
SUCCESS_FILE := $(STATUS_DIR)/success.txt
SKIPPED_FILE := $(STATUS_DIR)/skipped.txt
LOG_DIR      := $(STATUS_DIR)/logs
CORES_FILE   := cores/cores.txt
CORE ?=

# Version pinning (override with: make LIBRETRO_SUPER_REF=<commit> / RETROARCH_VERSION=v1.23.0)
LIBRETRO_SUPER_REF ?=
RETROARCH_VERSION  ?=
RA_VERSION := $(if $(RETROARCH_VERSION),$(RETROARCH_VERSION),$(shell grep -oP 'ARG RETROARCH_VERSION=\K[^\s]+' Dockerfile))

# The release name: the git tag (v1.22.2-1 = RetroArch version + build number), else describe/hash
TAG ?= $(shell git describe --tags --always --dirty 2>/dev/null || echo dev)
BUILD_NUM := $(shell echo "$(TAG)" | grep -oP '\d+$$' || echo 1)

# Parallel core builds (default: half of available CPUs)
PARALLEL ?= $(shell n=$$(nproc); p=$$(( (n + 1) / 2 )); [ $$p -lt 1 ] && p=1; echo $$p)
# Jobs per core build (uses remaining CPUs)
JOBS_PER_CORE ?= $(shell n=$$(nproc); j=$$(( n / $(PARALLEL) )); [ $$j -lt 1 ] && j=1; echo $$j)

BUILD_ARGS := $(if $(LIBRETRO_SUPER_REF),--build-arg LIBRETRO_SUPER_REF=$(LIBRETRO_SUPER_REF)) \
              $(if $(RETROARCH_VERSION),--build-arg RETROARCH_VERSION=$(RETROARCH_VERSION))

# The enabled cores, one per line
ENABLED_CORES = sed 's/\#.*//' $(CORES_FILE) | tr -d ' \t' | grep -v '^$$'

.PHONY: all docker-check image-base image-cores ensure-cores-image retroarch retroarch-ctng cores core parallel-build version-info core-info \
        commits package package-retroarch publish pack-retroboot-cores publish-cores pack-retroboot-libs publish-libs release status retry-failed audit-cores check-version list shell clean distclean help

all: retroarch cores

# Check Docker availability before attempting builds.
docker-check:
	@command -v $(DOCKER) >/dev/null 2>&1 || { echo "Error: docker is not installed or not in PATH."; exit 1; }
	@$(DOCKER) info >/dev/null 2>&1 || { \
		echo "Error: cannot access the Docker daemon (is it running, and is this user in the docker group?)"; \
		exit 1; }

# ------------------------------------------------------------------------------------------------
# Images
# ------------------------------------------------------------------------------------------------

# The toolchain alone (a shell to experiment in: make shell IMAGE=retroarch-psc-base)
image-base: docker-check
	DOCKER_BUILDKIT=1 $(DOCKER) build --target base -t $(BASE_IMAGE) $(BUILD_ARGS) .

# The core build environment (includes the toolchain build the first time, ~1 h)
image-cores: docker-check
	@echo "Building the cores image (the crosstool-ng toolchain is built the first time, then cached)..."
	DOCKER_BUILDKIT=1 $(DOCKER) build --target cores -t $(CORES_IMAGE) $(BUILD_ARGS) .

# What the core targets depend on: the image, built here only when there is none by that name
# (a pulled ghcr.io image, or the last build). `make image-cores` is the explicit rebuild.
ensure-cores-image: docker-check
	@$(DOCKER) image inspect $(CORES_IMAGE) >/dev/null 2>&1 || $(MAKE) --no-print-directory image-cores

# ------------------------------------------------------------------------------------------------
# RetroArch
# ------------------------------------------------------------------------------------------------

# With AutoBleem's own console toolchain - the autobleem-build image (AutoBleem2/docker), the compiler and
# sysroot pcsx-ab and the launcher are built with. retroarch/build.sh has the details; the RetroArch
# checkout lives on in work/RetroArch, so a second run is incremental. AB_BUILD_IMAGE names the image.
AB_BUILD_IMAGE ?= autobleem-build:latest
JOBS ?= $(shell nproc)
retroarch: docker-check
	@$(DOCKER) image inspect $(AB_BUILD_IMAGE) >/dev/null 2>&1 || \
		{ echo "Error: no $(AB_BUILD_IMAGE) image here - build it from AutoBleem2/docker, or use 'make retroarch-ctng'."; exit 1; }
	$(DOCKER) run --rm -u root -v "$(PWD):$(PWD)" -w "$(PWD)" \
		-e RETROARCH_VERSION=$(RA_VERSION) -e PSC_BUILD_NUM=$(BUILD_NUM) -e JOBS=$(JOBS) \
		-e OUT_UID=$$(id -u) -e OUT_GID=$$(id -g) -e OUT_DIR=$(RA_OUT) \
		$(AB_BUILD_IMAGE) retroarch/build.sh

# The self-contained route: AutoBleem-NG's crosstool-ng toolchain (GCC 9 / glibc 2.23, built by the
# Dockerfile's first stage, ~1 h the first time) - for a machine without the autobleem-build image.
retroarch-ctng: docker-check
	@mkdir -p $(RA_OUT)
	DOCKER_BUILDKIT=1 $(DOCKER) build --target retroarch-out -o $(RA_OUT) \
		--build-arg PSC_BUILD_NUM=$(BUILD_NUM) $(BUILD_ARGS) .
	@ls -lh $(RA_OUT)/

# ------------------------------------------------------------------------------------------------
# Cores
# ------------------------------------------------------------------------------------------------

cores: ensure-cores-image
	@if [ -n "$(CORE)" ]; then $(MAKE) core CORE=$(CORE); else $(MAKE) parallel-build; fi

# Write version info to metadata directory
version-info: ensure-cores-image
	@mkdir -p $(METADATA_DIR)
	@echo "Fetching libretro-super version info..."
	@$(DOCKER) run --rm $(CORES_IMAGE) sh -c '\
			cd /build/libretro-super && \
			echo "libretro_super_commit_full=$$(git rev-parse HEAD)" && \
			echo "libretro_super_commit=$$(git rev-parse --short HEAD)" && \
			echo "libretro_super_date=$$(git log -1 --format=%cd --date=short)" && \
			echo "build_date=$$(date -u +%Y-%m-%d)" && \
			echo "toolchain=crosstool-ng-gcc9-glibc2.23" && \
			echo "target=armv8-a-cortex-a35-neon"' > $(METADATA_DIR)/VERSION
	@cat $(METADATA_DIR)/VERSION

# Write libretro core info files for the enabled core set.
core-info: ensure-cores-image
	@mkdir -p $(INFO_OUT)
	@$(DOCKER) run --rm \
		-v $(PWD)/$(CORES_FILE):/build/cores.txt:ro \
		-v $(PWD)/$(DIST_DIR):/build/dist \
		$(CORES_IMAGE) \
		/build/scripts/sync-core-info.sh /build/cores.txt /build/libretro-super /build/dist/info

# Build all cores in parallel. FORCE=1 rebuilds the ones already built.
parallel-build: ensure-cores-image version-info
	@mkdir -p $(CORES_OUT) $(METADATA_DIR) $(STATUS_DIR) $(LOG_DIR)
	@rm -f $(FAILED_FILE) $(SUCCESS_FILE) $(SKIPPED_FILE)
	@rm -f $(LOG_DIR)/*.log 2>/dev/null || true
	@echo "=== Building cores ($(PARALLEL) parallel, $(JOBS_PER_CORE) jobs each) ==="
	@current_libretro_super_commit=$$(. $(METADATA_DIR)/VERSION && printf '%s' "$$libretro_super_commit_full"); \
	export CURRENT_LIBRETRO_SUPER_COMMIT="$$current_libretro_super_commit"; \
	$(ENABLED_CORES) | \
		xargs -P $(PARALLEL) -I {} sh -c ' \
			commit_file="$(COMMIT_DIR)/{}_libretro.so.commit"; \
			if [ -z "$(FORCE)" ] && [ -f "$(CORES_OUT)/{}_libretro.so" ] && [ -f "$$commit_file" ] && grep -Fxq "libretro_super_commit=$$CURRENT_LIBRETRO_SUPER_COMMIT" "$$commit_file"; then \
				echo "--- Skipping: {} (already built)"; \
				echo "{}" >> $(SKIPPED_FILE); \
			else \
				echo ">>> Building: {}"; \
				rm -f "$(CORES_OUT)/{}_libretro.so"; \
				log_file="$(LOG_DIR)/{}.log"; \
				$(DOCKER) run --rm \
					-e JOBS=$(JOBS_PER_CORE) \
					-v $(PWD)/$(CORES_OUT):/build/output \
					-v $(PWD)/$(METADATA_DIR):/build/metadata \
					$(CORES_IMAGE) \
					/build/build-core.sh "{}" > "$$log_file" 2>&1; \
				if [ -f "$(CORES_OUT)/{}_libretro.so" ]; then \
					echo "<<< Done: {}"; \
					echo "{}" >> $(SUCCESS_FILE); \
				else \
					echo "<<< FAILED: {}"; \
					echo "    log: $$log_file"; \
					tail -20 "$$log_file" 2>/dev/null || true; \
					echo "{}" >> $(FAILED_FILE); \
				fi \
			fi \
		'
	@echo ""
	@echo "=== Build Complete ==="
	@echo "Skipped: $$(cat $(SKIPPED_FILE) 2>/dev/null | wc -l) (already built)"
	@echo "Successful: $$(cat $(SUCCESS_FILE) 2>/dev/null | wc -l)"
	@echo "Failed: $$(cat $(FAILED_FILE) 2>/dev/null | wc -l)"
	@if [ -f $(FAILED_FILE) ]; then echo ""; echo "Failed cores:"; sed 's/^/  /' $(FAILED_FILE); fi
	@$(MAKE) --no-print-directory commits
	@echo ""
	@echo "Total size:"
	@du -sh $(CORES_OUT)/ 2>/dev/null || echo "0"

# Build one core (the log goes to the terminal)
core: ensure-cores-image
	@if [ -z "$(CORE)" ]; then echo "Usage: make core CORE=<name>"; exit 1; fi
	@mkdir -p $(CORES_OUT) $(METADATA_DIR)
	$(DOCKER) run --rm \
		-e JOBS=$(JOBS_PER_CORE) \
		-v $(PWD)/$(CORES_OUT):/build/output \
		-v $(PWD)/$(METADATA_DIR):/build/metadata \
		$(CORES_IMAGE) \
		/build/build-core.sh "$(CORE)"
	@$(MAKE) --no-print-directory commits

# Aggregate per-core .so.commit sidecar files into COMMITS.txt
# Format: <core> <short_commit> <full_commit> <url>
commits:
	@mkdir -p $(METADATA_DIR) $(COMMIT_DIR)
	@for d in $(CORES_OUT)/.metadata/commits $(CORES_OUT) $(CORES_OUT)/.metadata; do \
		[ -d "$$d" ] && find "$$d" -maxdepth 1 -type f -name '*.so.commit' -exec mv -f {} $(COMMIT_DIR)/ \; ; \
	done; true
	@rm -f $(CORES_OUT)/COMMITS.txt
	@if ls $(COMMIT_DIR)/*.so.commit >/dev/null 2>&1; then \
		: > $(METADATA_DIR)/COMMITS.txt; \
		for f in $(COMMIT_DIR)/*.so.commit; do \
			core=$$(grep '^core=' "$$f" | cut -d= -f2); \
			commit=$$(grep '^commit=' "$$f" | cut -d= -f2); \
			url=$$(grep '^url=' "$$f" | cut -d= -f2-); \
			short=$$(echo "$$commit" | cut -c1-7); \
			printf '%-32s %s %s %s\n' "$$core" "$$short" "$$commit" "$$url" >> $(METADATA_DIR)/COMMITS.txt; \
		done; \
		sort -o $(METADATA_DIR)/COMMITS.txt $(METADATA_DIR)/COMMITS.txt; \
		echo "Wrote $(METADATA_DIR)/COMMITS.txt ($$(wc -l < $(METADATA_DIR)/COMMITS.txt) cores)"; \
	fi

# Retry the cores that failed in the last run (or are simply missing)
retry-failed: ensure-cores-image
	@mkdir -p $(CORES_OUT) $(METADATA_DIR) $(STATUS_DIR) $(LOG_DIR)
	@$(ENABLED_CORES) | while read -r core; do \
		if [ ! -f "$(CORES_OUT)/$${core}_libretro.so" ]; then \
			echo ">>> Retrying: $$core"; \
			$(DOCKER) run --rm -e JOBS=$(JOBS_PER_CORE) \
				-v $(PWD)/$(CORES_OUT):/build/output \
				-v $(PWD)/$(METADATA_DIR):/build/metadata \
				$(CORES_IMAGE) /build/build-core.sh "$$core" > "$(LOG_DIR)/$$core.log" 2>&1 \
				&& { echo "<<< Done: $$core"; [ -f $(FAILED_FILE) ] && sed -i "/^$$core$$/d" $(FAILED_FILE); } \
				|| { echo "<<< Still failed: $$core (log: $(LOG_DIR)/$$core.log)"; }; \
		fi; \
	done; true
	@$(MAKE) --no-print-directory commits

# ------------------------------------------------------------------------------------------------
# Release
# ------------------------------------------------------------------------------------------------

# dist/release/: the RetroArch zip, the cores tarball (cores + info + VERSION + COMMITS.txt) and
# manifest.json describing both - what the PC installer downloads by.
package: version-info core-info
	@test -f $(RA_OUT)/retroarch || { echo "Error: no RetroArch binary. Run 'make retroarch' first."; exit 1; }
	@missing=$$($(ENABLED_CORES) | while read -r core; do \
		[ -f "$(CORES_OUT)/$${core}_libretro.so" ] || echo "$$core"; done); \
	if [ -n "$$missing" ] && [ -z "$(ALLOW_MISSING)" ]; then \
		echo "Error: enabled cores in $(CORES_FILE) are missing .so output:"; \
		echo "$$missing" | sed 's/^/  /'; \
		echo "Run 'make cores' or 'make retry-failed' first, or ALLOW_MISSING=1 to package without them."; \
		exit 1; \
	fi
	@$(MAKE) --no-print-directory commits
	@rm -rf $(RELEASE_DIR) && mkdir -p $(RELEASE_DIR)
	@echo "=== Packaging RetroArch ==="
	@tmp=$$(mktemp -d) && cp $(RA_OUT)/retroarch $(RA_OUT)/VERSION "$$tmp/" && \
		cp -r retroarch/docs "$$tmp/docs" && \
		(cd "$$tmp" && zip -q -r "$(PWD)/$(RELEASE_DIR)/retroarch-psc-$(TAG).zip" .) && rm -rf "$$tmp"
	@echo "=== Packaging cores ==="
	@tmp=$$(mktemp -d) && mkdir -p "$$tmp/cores" "$$tmp/info" && \
		$(ENABLED_CORES) | while read -r core; do \
			[ -f "$(CORES_OUT)/$${core}_libretro.so" ] && cp "$(CORES_OUT)/$${core}_libretro.so" "$$tmp/cores/"; \
		done; \
		cp $(INFO_OUT)/*.info "$$tmp/info/" && \
		cp $(METADATA_DIR)/VERSION $(METADATA_DIR)/COMMITS.txt "$$tmp/" && \
		bash cores/scripts/generate-release-notes.sh "libretro-cores-psc-$(TAG)" "$$tmp" \
			"$$tmp/VERSION" "$$tmp/COMMITS.txt" "$(RELEASE_DIR)/libretro-cores-psc-$(TAG).md" && \
		tar -czf "$(RELEASE_DIR)/libretro-cores-psc-$(TAG).tar.gz" -C "$$tmp" . && rm -rf "$$tmp"
	@echo "=== manifest.json ==="
	@python3 tools/make_manifest.py --tag "$(TAG)" --release-dir $(RELEASE_DIR) \
		--retroarch-version-file $(RA_OUT)/VERSION --cores-version-file $(METADATA_DIR)/VERSION \
		--cores-dir $(CORES_OUT) --cores-file $(CORES_FILE) --info-dir $(INFO_OUT)
	@ls -lh $(RELEASE_DIR)/

release: retroarch cores package

# A RetroArch-only release: the zip (the UPX-packed binary build.sh made next to the stripped one, as
# AutoBleem's own console binaries are packed - AB_NO_UPX=1 ships the stripped one) with the docs and
# theme/, plus a manifest.json with "cores": null. Needs no cores image.
package-retroarch:
	@test -f $(RA_OUT)/retroarch || { echo "Error: no RetroArch binary. Run 'make retroarch' first."; exit 1; }
	@rm -rf $(RELEASE_DIR) && mkdir -p $(RELEASE_DIR)
	@echo "=== Packaging RetroArch ==="
	@tmp=$$(mktemp -d) && cp $(RA_OUT)/VERSION "$$tmp/" && \
		if [ -z "$(AB_NO_UPX)" ] && [ -f $(RA_OUT)/retroarch.upx ]; then cp $(RA_OUT)/retroarch.upx "$$tmp/retroarch"; \
		else cp $(RA_OUT)/retroarch "$$tmp/retroarch"; fi && \
		cp -r retroarch/docs "$$tmp/docs" && cp -r theme "$$tmp/theme" && \
		(cd "$$tmp" && zip -q -r "$(PWD)/$(RELEASE_DIR)/retroarch-psc-$(TAG).zip" .) && rm -rf "$$tmp"
	@python3 tools/make_manifest.py --tag "$(TAG)" --release-dir $(RELEASE_DIR) \
		--retroarch-version-file $(RA_OUT)/VERSION
	@ls -lh $(RELEASE_DIR)/

# Publish dist/release/ to the download repository, https://autobleem.retromenele.pl/psc/retroarch/<tag>/,
# through AutoBleem2's tools/repo_publish.sh (rsync to the build server + the index rerun there). AB2_DIR
# is that checkout (../AutoBleem2 by default). Only the newest tag is kept there - the repository's rule.
AB2_DIR ?= ../AutoBleem2
PUBLISH_FLAGS ?=          # --local when this runs on the build server itself
publish:
	@test -f $(RELEASE_DIR)/manifest.json || { echo "Error: nothing in $(RELEASE_DIR). Run 'make package' or 'make package-retroarch' first."; exit 1; }
	@test -x $(AB2_DIR)/tools/repo_publish.sh || { echo "Error: $(AB2_DIR)/tools/repo_publish.sh not found (AB2_DIR=...)."; exit 1; }
	$(AB2_DIR)/tools/repo_publish.sh $(PUBLISH_FLAGS) psc-retroarch $(TAG) $(RELEASE_DIR)/retroarch-psc-$(TAG).zip $(RELEASE_DIR)/manifest.json

# The console's cores until we build our own: RetroBoot 1.2's, packed from a stick (RETROBOOT_DIR = its
# retroarch/ folder) by tools/pack_retroboot_cores.py, and published to psc/cores/ (newest date kept).
RETROBOOT_DIR ?= F:/retroarch
pack-retroboot-cores:
	python3 tools/pack_retroboot_cores.py "$(RETROBOOT_DIR)" --out $(RELEASE_DIR)
pack-retroboot-libs:
	python3 tools/pack_retroboot_libs.py "$(RETROBOOT_DIR)/retroboot" --out $(RELEASE_DIR)
publish-libs:
	@ls $(RELEASE_DIR)/libs-psc-*.tar.gz >/dev/null 2>&1 || { echo "Error: no libs tarball in $(RELEASE_DIR) (make pack-retroboot-libs)."; exit 1; }
	$(AB2_DIR)/tools/repo_publish.sh $(PUBLISH_FLAGS) psc-libs $(RELEASE_DIR)/libs-psc-*.tar.gz $(RELEASE_DIR)/libs-psc-*.json
publish-cores:
	@ls $(RELEASE_DIR)/cores-psc-*.tar.gz >/dev/null 2>&1 || { echo "Error: no cores tarball in $(RELEASE_DIR) (make pack-retroboot-cores)."; exit 1; }
	$(AB2_DIR)/tools/repo_publish.sh $(PUBLISH_FLAGS) psc-cores $(RELEASE_DIR)/cores-psc-*.tar.gz $(RELEASE_DIR)/cores-psc-*.json

# ------------------------------------------------------------------------------------------------
# Information
# ------------------------------------------------------------------------------------------------

status:
	@echo "=== Build Summary ==="
	@echo "RetroArch: $$( [ -f $(RA_OUT)/retroarch ] && cat $(RA_OUT)/VERSION | tr '\n' ' ' || echo 'not built')"
	@enabled=$$($(ENABLED_CORES) | wc -l); \
	built=$$($(ENABLED_CORES) | while read -r core; do [ -f "$(CORES_OUT)/$${core}_libretro.so" ] && echo "$$core"; done | wc -l); \
	echo "Cores: $$built/$$enabled enabled cores built"
	@if [ -f $(METADATA_DIR)/VERSION ]; then echo "Version file: $(METADATA_DIR)/VERSION"; fi
	@echo ""
	@echo "=== Missing Cores ==="
	@$(ENABLED_CORES) | while read -r core; do \
		[ -f "$(CORES_OUT)/$${core}_libretro.so" ] || echo "  $$core"; done | { grep . || echo "  none"; }

# Compare cores.txt against the pinned libretro-super core rule list.
audit-cores: ensure-cores-image
	@$(DOCKER) run --rm -v $(PWD)/$(CORES_FILE):/build/cores.txt:ro $(CORES_IMAGE) \
		/build/scripts/audit-cores.sh /build/cores.txt /build/libretro-super

# List available cores (from libretro-super)
list: ensure-cores-image
	@$(DOCKER) run --rm $(CORES_IMAGE) ls /build/libretro-super/recipes/*/

# Show the pins against upstream
check-version:
	@echo "Pinned in the Dockerfile:"
	@grep -E "ARG (LIBRETRO_SUPER_REF|RETROARCH_VERSION)=" Dockerfile
	@echo ""
	@echo "Latest upstream libretro-super:"
	@git ls-remote https://github.com/libretro/libretro-super.git HEAD
	@echo "Latest RetroArch tags:"
	@git ls-remote --tags --refs https://github.com/libretro/RetroArch.git 'v*' | awk -F/ '{print $$NF}' | sort -V | tail -3

# Interactive shell in the cores image (IMAGE=... for another one)
IMAGE ?= $(CORES_IMAGE)
shell:
	@mkdir -p $(CORES_OUT) $(METADATA_DIR)
	$(DOCKER) run --rm -it \
		-v $(PWD)/$(CORES_OUT):/build/output \
		-v $(PWD)/$(METADATA_DIR):/build/metadata \
		$(IMAGE) /bin/bash

clean:
	rm -rf $(DIST_DIR) $(METADATA_DIR) $(STATUS_DIR)

distclean: clean
	$(DOCKER) rmi $(CORES_IMAGE) $(BASE_IMAGE) 2>/dev/null || true

help:
	@sed -n '2,20p' Makefile | sed 's/^# \{0,1\}//'
