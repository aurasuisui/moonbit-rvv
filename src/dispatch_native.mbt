///|
extern "C" fn rvv_probe_add_c(x : Int32) -> Int32 = "rvv_probe_add"

///|
fn probe_add_impl(x : Int32) -> Int32 {
  rvv_probe_add_c(x)
}
