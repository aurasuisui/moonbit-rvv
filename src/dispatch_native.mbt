///|
/// M2 native dispatch: the five primitives call the C kernel in
/// `src/native/kernel.c` through `extern "C"`, so host-native builds exercise
/// the C scalar branch and RV64 builds (clang, `-march=rv64gcv`) exercise the
/// RVV branch. wasm / wasm-gc / js keep the pure MoonBit scalar implementation
/// (`dispatch_wasm.mbt`).
///
/// `#borrow` declares that the C side never takes ownership of the array. The
/// pointer MoonBit passes is the element data (not the header); layout and
/// ownership rules are documented in `docs/NATIVE_ABI.md`. Public signatures
/// and semantics are unchanged (`docs/SPEC.md`).

///|
#borrow(xs)
extern "C" fn c_sum(xs : FixedArray[Int32], n : Int32) -> Int64 = "rvv_sum"

///|
#borrow(xs)
extern "C" fn c_count_ge(
  xs : FixedArray[Int32],
  n : Int32,
  thr : Int32,
) -> Int32 = "rvv_count_ge"

///|
#borrow(xs)
extern "C" fn c_prefix_sum(xs : FixedArray[Int32], n : Int32) -> Unit = "rvv_prefix_sum"

///|
#borrow(xs, out)
extern "C" fn c_filter(
  xs : FixedArray[Int32],
  n : Int32,
  thr : Int32,
  out : FixedArray[Int32],
) -> Int32 = "rvv_filter"

///|
#borrow(a, b)
extern "C" fn c_dot(
  a : FixedArray[Int32],
  b : FixedArray[Int32],
  n : Int32,
) -> Int64 = "rvv_dot"

///|
fn sum_impl(xs : FixedArray[Int32]) -> Int64 {
  c_sum(xs, xs.length())
}

///|
fn count_ge_impl(xs : FixedArray[Int32], thr : Int32) -> Int32 {
  c_count_ge(xs, xs.length(), thr)
}

///|
fn prefix_sum_impl(xs : FixedArray[Int32]) -> Unit {
  c_prefix_sum(xs, xs.length())
}

///|
/// `count_ge` sizes the output; C then compacts into it. The returned count is
/// the invariant already checked by `count_ge_impl`, so it is ignored here.
fn filter_impl(xs : FixedArray[Int32], thr : Int32) -> FixedArray[Int32] {
  let n = c_count_ge(xs, xs.length(), thr)
  let out : FixedArray[Int32] = FixedArray::make(n, 0)
  c_filter(xs, xs.length(), thr, out) |> ignore
  out
}

///|
/// The mismatch case is delegated to the scalar implementation so that the
/// panic contract (`rvv: dot length mismatch`, docs/SPEC.md §5) keeps its single
/// abort point in `src/scalar/impl.mbt`; the equal-length case goes to C.
fn dot_impl(a : FixedArray[Int32], b : FixedArray[Int32]) -> Int64 {
  if a.length() != b.length() {
    @scalar.dot(a, b) |> ignore
  }
  c_dot(a, b, a.length())
}
