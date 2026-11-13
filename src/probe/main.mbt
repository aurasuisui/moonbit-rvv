///|
/// Shared smoke body for the M2 probe executables: exercises all five
/// primitives and returns one line. `xs = [1, 2, 3, 4, 5]`; expected output is
/// `15,3,35,325` (sum before, count_ge >= 3, sum after prefix_sum,
/// dot(filter(xs, 10), filter(xs, 10))).
fn smoke_line() -> String {
  let xs : FixedArray[Int32] = [1, 2, 3, 4, 5]
  let sum_before = @rvv.sum(xs)
  let ge_three = @rvv.count_ge(xs, 3)
  @rvv.prefix_sum(xs)
  let sum_after = @rvv.sum(xs)
  let tail = @rvv.filter(xs, 10)
  let dot_tail = @rvv.dot(tail, tail)
  sum_before.to_string() +
  "," +
  ge_three.to_string() +
  "," +
  sum_after.to_string() +
  "," +
  dot_tail.to_string()
}
