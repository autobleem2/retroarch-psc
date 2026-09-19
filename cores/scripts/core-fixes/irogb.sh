build_core() {
    SRC_DIR="$(core_source_dir)"
    cd "$SRC_DIR"

    cat > includes/span <<'SPAN_EOF'
#ifndef PSC_STD_SPAN_POLYFILL
#define PSC_STD_SPAN_POLYFILL

#include <algorithm>
#include <array>
#include <cstddef>
#include <type_traits>
#include <vector>

namespace std {
inline constexpr size_t dynamic_extent = static_cast<size_t>(-1);

template <typename T, size_t Extent = dynamic_extent>
class span {
public:
  using element_type = T;
  using value_type = remove_cv_t<T>;
  using size_type = size_t;
  using iterator = T *;
  using const_iterator = const T *;

  constexpr span() noexcept : ptr_(nullptr), size_(0) {}
  constexpr span(T *ptr, size_type count) noexcept : ptr_(ptr), size_(count) {}
  constexpr span(T *first, T *last) noexcept : ptr_(first), size_(last - first) {}

  template <size_t N>
  constexpr span(T (&arr)[N]) noexcept : ptr_(arr), size_(N) {}

  template <typename U, size_t OtherExtent,
            typename = enable_if_t<is_convertible<U (*)[], T (*)[]>::value>>
  constexpr span(const span<U, OtherExtent> &other) noexcept
      : ptr_(other.data()), size_(other.size()) {}

  template <typename U, size_t N,
            typename = enable_if_t<is_convertible<U (*)[], T (*)[]>::value>>
  constexpr span(array<U, N> &arr) noexcept : ptr_(arr.data()), size_(N) {}

  template <typename U, size_t N,
            typename = enable_if_t<is_convertible<const U (*)[], T (*)[]>::value>>
  constexpr span(const array<U, N> &arr) noexcept : ptr_(arr.data()), size_(N) {}

  template <typename U, typename Alloc,
            typename = enable_if_t<is_convertible<U (*)[], T (*)[]>::value>>
  span(vector<U, Alloc> &vec) noexcept : ptr_(vec.data()), size_(vec.size()) {}

  template <typename U, typename Alloc,
            typename = enable_if_t<is_convertible<const U (*)[], T (*)[]>::value>>
  span(const vector<U, Alloc> &vec) noexcept : ptr_(vec.data()), size_(vec.size()) {}

  constexpr iterator begin() const noexcept { return ptr_; }
  constexpr iterator end() const noexcept { return ptr_ + size_; }
  constexpr T *data() const noexcept { return ptr_; }
  constexpr size_type size() const noexcept { return size_; }
  constexpr size_type size_bytes() const noexcept { return size_ * sizeof(T); }
  constexpr bool empty() const noexcept { return size_ == 0; }
  constexpr T &operator[](size_type idx) const noexcept { return ptr_[idx]; }

  constexpr span<T> subspan(size_type offset, size_type count = dynamic_extent) const noexcept {
    const size_type remaining = size_ - offset;
    return span<T>(ptr_ + offset, count == dynamic_extent ? remaining : count);
  }

  constexpr span<T> first(size_type count) const noexcept { return span<T>(ptr_, count); }
  constexpr span<T> last(size_type count) const noexcept { return span<T>(ptr_ + size_ - count, count); }

private:
  T *ptr_;
  size_type size_;
};

namespace ranges {
template <typename Range, typename OutputIt>
OutputIt copy(Range &&range, OutputIt out) {
  return std::copy(std::begin(range), std::end(range), out);
}

template <typename Range, typename Generator>
void generate(Range &&range, Generator gen) {
  std::generate(std::begin(range), std::end(range), gen);
}

template <typename Range, typename Compare>
void sort(Range &&range, Compare comp) {
  std::sort(std::begin(range), std::end(range), comp);
}
} // namespace ranges
} // namespace std

#endif
SPAN_EOF

    rm -rf build
    cmake -S . -B build \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_SYSTEM_NAME=Linux \
        -DCMAKE_SYSTEM_PROCESSOR=arm \
        -DCMAKE_C_COMPILER=arm-linux-gnueabihf-gcc \
        -DCMAKE_CXX_COMPILER=arm-linux-gnueabihf-g++ \
        -DBUILD_SIMPLE=OFF \
        -DBUILD_LIBRETRO=ON \
        -DNO_CORE_FILESYSTEM=ON

    cmake --build build --target irogb_libretro --parallel "$JOBS"

    OUT="$(find build -name irogb_libretro.so -type f | head -1)"
    cp "$OUT" /build/output/
}
