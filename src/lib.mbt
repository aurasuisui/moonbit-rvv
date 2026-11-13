///|
/// M0 probe for the target dispatch skeleton.
///
/// Returns `x + 2` on wasm / wasm-gc / js (pure MoonBit scalar) and
/// `x + 1` on native (C stub). M1 replaces this probe with the five
/// public array primitives and their per-backend implementations.
pub fn rvv_probe_add(x : Int32) -> Int32 {
  probe_add_impl(x)
}
