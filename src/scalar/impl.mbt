///|
/// Pure MoonBit scalar implementations of the five array primitives.
///
/// v0.1.0 (M1): this package is the single implementation used by every
/// backend; the native dispatch forwards here as well so that both host
/// targets agree. M2 replaces the native path with the C kernel while
/// these functions stay the wasm / wasm-gc / js implementation.

///|
/// Sum of all elements, accumulated in `Int64`. Empty input returns `0`.
pub fn sum(xs : FixedArray[Int32]) -> Int64 {
  let mut acc : Int64 = 0L
  for i = 0; i < xs.length(); i = i + 1 {
    acc = acc + xs[i].to_int64()
  }
  acc
}

///|
/// Number of elements `>= thr`. Empty input returns `0`.
pub fn count_ge(xs : FixedArray[Int32], thr : Int32) -> Int32 {
  let mut n = 0
  for i = 0; i < xs.length(); i = i + 1 {
    if xs[i] >= thr {
      n = n + 1
    }
  }
  n
}

///|
/// In-place prefix sum; each step wraps modulo 2^32 (two's complement).
/// Empty input is a no-op.
pub fn prefix_sum(xs : FixedArray[Int32]) -> Unit {
  let mut acc : Int32 = 0
  for i = 0; i < xs.length(); i = i + 1 {
    acc = acc + xs[i]
    xs[i] = acc
  }
}

///|
/// Elements `>= thr` in original order, as a new `FixedArray`.
/// No match yields an empty array.
pub fn filter(xs : FixedArray[Int32], thr : Int32) -> FixedArray[Int32] {
  let n = count_ge(xs, thr)
  let out : FixedArray[Int32] = FixedArray::make(n, 0)
  let mut j = 0
  for i = 0; i < xs.length(); i = i + 1 {
    if xs[i] >= thr {
      out[j] = xs[i]
      j = j + 1
    }
  }
  out
}

///|
/// Dot product, accumulated in `Int64`. Panics when lengths differ.
pub fn dot(a : FixedArray[Int32], b : FixedArray[Int32]) -> Int64 {
  if a.length() != b.length() {
    abort("rvv: dot length mismatch")
  }
  let mut acc : Int64 = 0L
  for i = 0; i < a.length(); i = i + 1 {
    acc = acc + a[i].to_int64() * b[i].to_int64()
  }
  acc
}
