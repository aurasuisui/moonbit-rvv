///|
/// Black-box tests for the public API of aurasuisui/rvv.
///
/// Only `@rvv.*` is used here: no access to `src/scalar` or any other
/// implementation detail. Each primitive covers empty, singleton,
/// all-equal, strictly increasing, Int32 extremes and a length that is not a
/// multiple of 4, plus the cross-primitive invariants listed at the end.
///
/// `dot` with mismatched lengths deliberately has no test here: the panic is
/// verified by code review and a manual run (see docs/SPEC.md).

///|
/// Shorthand for building a `FixedArray[Int32]` from an array literal.
fn fa(xs : ArrayView[Int32]) -> FixedArray[Int32] {
  FixedArray::from_array(xs)
}

// sum -----------------------------------------------------------------------

///|
test "sum empty" {
  assert_eq(@rvv.sum(fa([])), 0L)
}

///|
test "sum single" {
  assert_eq(@rvv.sum(fa([7])), 7L)
}

///|
test "sum all equal" {
  assert_eq(@rvv.sum(fa([5, 5, 5, 5, 5])), 25L)
}

///|
test "sum strictly increasing" {
  assert_eq(@rvv.sum(fa([1, 2, 3, 4, 5, 6, 7, 8])), 36L)
}

///|
test "sum int32 extremes" {
  assert_eq(@rvv.sum(fa([2147483647, 1, -2147483648, -1])), -1L)
  assert_eq(@rvv.sum(fa([-2147483648, -2147483648])), -4294967296L)
}

///|
test "sum length not multiple of 4" {
  assert_eq(@rvv.sum(fa([1, 2, 3, 4, 5])), 15L)
  assert_eq(@rvv.sum(fa([1, 2, 3])), 6L)
}

///|
test "sum accumulates in int64" {
  assert_eq(@rvv.sum(fa([2147483647, 2147483647])), 4294967294L)
}

// count_ge ------------------------------------------------------------------

///|
test "count_ge empty" {
  assert_eq(@rvv.count_ge(fa([]), 0), 0)
}

///|
test "count_ge single inclusive" {
  assert_eq(@rvv.count_ge(fa([42]), 42), 1)
  assert_eq(@rvv.count_ge(fa([42]), 43), 0)
}

///|
test "count_ge all equal" {
  assert_eq(@rvv.count_ge(fa([7, 7, 7, 7]), 7), 4)
}

///|
test "count_ge strictly increasing" {
  assert_eq(@rvv.count_ge(fa([1, 2, 3, 4, 5, 6, 7, 8]), 4), 5)
}

///|
test "count_ge int32 extremes" {
  assert_eq(@rvv.count_ge(fa([2147483647, -2147483648, 0]), 0), 2)
  assert_eq(@rvv.count_ge(fa([2147483647, -2147483648, 0]), -2147483648), 3)
}

///|
test "count_ge length not multiple of 4" {
  assert_eq(@rvv.count_ge(fa([5, 1, 5, 2, 5, 3, 5]), 5), 4)
}

///|
test "count_ge threshold outside range" {
  assert_eq(@rvv.count_ge(fa([1, 2, 3]), 2147483647), 0)
  assert_eq(@rvv.count_ge(fa([1, 2, 3]), -2147483648), 3)
}

// prefix_sum ----------------------------------------------------------------

///|
test "prefix_sum empty" {
  let xs : FixedArray[Int32] = fa([])
  @rvv.prefix_sum(xs)
  assert_eq(xs, fa([]))
}

///|
test "prefix_sum single" {
  let xs : FixedArray[Int32] = fa([7])
  @rvv.prefix_sum(xs)
  assert_eq(xs, fa([7]))
}

///|
test "prefix_sum all equal" {
  let xs : FixedArray[Int32] = fa([3, 3, 3, 3])
  @rvv.prefix_sum(xs)
  assert_eq(xs, fa([3, 6, 9, 12]))
}

///|
test "prefix_sum strictly increasing" {
  let xs : FixedArray[Int32] = fa([1, 2, 3, 4, 5, 6, 7, 8])
  @rvv.prefix_sum(xs)
  assert_eq(xs, fa([1, 3, 6, 10, 15, 21, 28, 36]))
}

///|
test "prefix_sum int32 max wraps" {
  let xs : FixedArray[Int32] = fa([2147483647, 1, 1])
  @rvv.prefix_sum(xs)
  assert_eq(xs, fa([2147483647, -2147483648, -2147483647]))
}

///|
test "prefix_sum int32 min wraps" {
  let xs : FixedArray[Int32] = fa([-2147483648, -1, -1])
  @rvv.prefix_sum(xs)
  assert_eq(xs, fa([-2147483648, 2147483647, 2147483646]))
}

///|
test "prefix_sum length not multiple of 4" {
  let xs : FixedArray[Int32] = fa([10, -5, -5])
  @rvv.prefix_sum(xs)
  assert_eq(xs, fa([10, 5, 0]))
  let ys : FixedArray[Int32] = fa([4, 3, 2, 1, 0])
  @rvv.prefix_sum(ys)
  assert_eq(ys, fa([4, 7, 9, 10, 10]))
}

// filter --------------------------------------------------------------------

///|
test "filter empty" {
  assert_eq(@rvv.filter(fa([]), 0), fa([]))
}

///|
test "filter single" {
  assert_eq(@rvv.filter(fa([5]), 5), fa([5]))
  assert_eq(@rvv.filter(fa([5]), 6), fa([]))
}

///|
test "filter all equal" {
  assert_eq(@rvv.filter(fa([7, 7, 7, 7]), 7), fa([7, 7, 7, 7]))
}

///|
test "filter strictly increasing" {
  assert_eq(@rvv.filter(fa([1, 2, 3, 4, 5, 6, 7, 8]), 5), fa([5, 6, 7, 8]))
}

///|
test "filter int32 extremes" {
  assert_eq(
    @rvv.filter(fa([2147483647, -2147483648, 0]), 0),
    fa([2147483647, 0]),
  )
}

///|
test "filter length not multiple of 4" {
  assert_eq(@rvv.filter(fa([5, 1, 5, 2, 5]), 5), fa([5, 5, 5]))
}

///|
test "filter preserves order" {
  assert_eq(@rvv.filter(fa([3, 1, 2, 3, 1]), 2), fa([3, 2, 3]))
}

///|
test "filter no match returns empty" {
  assert_eq(@rvv.filter(fa([1, 2, 3]), 100), fa([]))
}

// dot -----------------------------------------------------------------------

///|
test "dot empty" {
  assert_eq(@rvv.dot(fa([]), fa([])), 0L)
}

///|
test "dot single" {
  assert_eq(@rvv.dot(fa([6]), fa([7])), 42L)
}

///|
test "dot all equal" {
  assert_eq(@rvv.dot(fa([2, 2, 2, 2]), fa([3, 3, 3, 3])), 24L)
}

///|
test "dot strictly increasing" {
  assert_eq(
    @rvv.dot(fa([1, 2, 3, 4, 5, 6, 7, 8]), fa([1, 2, 3, 4, 5, 6, 7, 8])),
    204L,
  )
}

///|
test "dot int32 extremes" {
  assert_eq(@rvv.dot(fa([2147483647]), fa([2147483647])), 4611686014132420609L)
  assert_eq(
    @rvv.dot(fa([-2147483648]), fa([-2147483648])),
    4611686018427387904L,
  )
}

///|
test "dot length not multiple of 4" {
  assert_eq(@rvv.dot(fa([1, 2, 3, 4, 5, 6, 7]), fa([2, 2, 2, 2, 2, 2, 2])), 56L)
}

///|
test "dot negative values" {
  assert_eq(@rvv.dot(fa([-1, -2, -3]), fa([4, 5, 6])), -32L)
}

// cross-primitive invariants -------------------------------------------------

///|
test "filter length equals count_ge" {
  let xs : FixedArray[Int32] = fa([2147483647, -1, 0, 5, -2147483648, 5])
  assert_eq(@rvv.filter(xs, 5).length(), @rvv.count_ge(xs, 5))
  assert_eq(@rvv.filter(xs, 5), fa([2147483647, 5, 5]))
}

///|
test "filter returns a new array" {
  let xs : FixedArray[Int32] = fa([1, 2, 3, 4])
  let ys = @rvv.filter(xs, 2)
  ys[0] = 99
  assert_eq(xs, fa([1, 2, 3, 4]))
}

///|
test "prefix_sum and sum stay consistent" {
  let xs : FixedArray[Int32] = fa([3, 1, 4, 1, 5])
  @rvv.prefix_sum(xs)
  assert_eq(@rvv.sum(xs), 38L)
}
