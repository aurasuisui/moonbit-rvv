///|
/// The five array primitives of aurasuisui/rvv.
///
/// Semantics, edge cases, panic behaviour and integer widths are specified in
/// `docs/SPEC.md`; this file only checks arguments and forwards to the
/// backend-specific implementation (M1: pure MoonBit scalar on both hosts).

///|
/// Sum of all elements, accumulated in `Int64`. Empty input returns `0`.
pub fn sum(xs : FixedArray[Int32]) -> Int64 {
  sum_impl(xs)
}

///|
/// Number of elements `>= thr`. Empty input returns `0`.
pub fn count_ge(xs : FixedArray[Int32], thr : Int32) -> Int32 {
  count_ge_impl(xs, thr)
}

///|
/// In-place prefix sum; each step wraps modulo 2^32. Empty input is a no-op.
pub fn prefix_sum(xs : FixedArray[Int32]) -> Unit {
  prefix_sum_impl(xs)
}

///|
/// Elements `>= thr` in original order, as a new `FixedArray`.
/// No match yields an empty array.
pub fn filter(xs : FixedArray[Int32], thr : Int32) -> FixedArray[Int32] {
  filter_impl(xs, thr)
}

///|
/// Dot product, accumulated in `Int64`.
/// Panics with `rvv: dot length mismatch` when the lengths differ.
pub fn dot(a : FixedArray[Int32], b : FixedArray[Int32]) -> Int64 {
  dot_impl(a, b)
}
