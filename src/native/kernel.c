/* M0 probe: native stub for aurasuisui/rvv.
 *
 * MoonBit `Int` maps to int32_t on the native backend. M2 adds the real
 * kernels and the `__riscv_vector` branch here.
 */
#include <stdint.h>

int32_t rvv_probe_add(int32_t x) {
  return x + 1;
}
