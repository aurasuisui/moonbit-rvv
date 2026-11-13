///|
/// M1 dispatch: both backends forward to the pure MoonBit scalar package so
/// results agree on every host. M2 replaces the native bodies with
/// `extern "C"` calls into `native/kernel.c`.

///|
fn sum_impl(xs : FixedArray[Int32]) -> Int64 {
  @scalar.sum(xs)
}

///|
fn count_ge_impl(xs : FixedArray[Int32], thr : Int32) -> Int32 {
  @scalar.count_ge(xs, thr)
}

///|
fn prefix_sum_impl(xs : FixedArray[Int32]) -> Unit {
  @scalar.prefix_sum(xs)
}

///|
fn filter_impl(xs : FixedArray[Int32], thr : Int32) -> FixedArray[Int32] {
  @scalar.filter(xs, thr)
}

///|
fn dot_impl(a : FixedArray[Int32], b : FixedArray[Int32]) -> Int64 {
  @scalar.dot(a, b)
}
