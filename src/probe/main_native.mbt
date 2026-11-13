///|
/// Native probe entry (target: native).
///
/// Runs the C kernel self test first: it compares the C scalar branch with the
/// RVV branch over n = 0, 1, 2, 3, 5, 7, 17, 1024 for all five primitives, and
/// fails with `SELFTEST_FAIL:<code>` on the first mismatch. On a host without
/// the V extension the C kernel has only the scalar branch and the self test
/// returns 0 (`SELFTEST_PASS`); `scripts/cross-riscv.sh` builds this probe for
/// RV64 with `-march=rv64gcv` and runs it under qemu.
extern "C" fn rvv_selftest() -> Int32 = "rvv_selftest"

///|
fn main {
  let rc = rvv_selftest()
  if rc == 0 {
    println("SELFTEST_PASS")
  } else {
    println("SELFTEST_FAIL:" + rc.to_string())
  }
  println(smoke_line())
}
