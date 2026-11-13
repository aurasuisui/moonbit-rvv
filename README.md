# aurasuisui/rvv

MoonBit 的 RISC-V 向量(RVV)后端:一套数组原语,wasm/js 走纯 MoonBit 标量,native 走 C,RISC-V 走 RVV。

> **状态**:`v0.1.0` 开发中。M1 已落地 5 个原语的纯 MoonBit 标量实现与黑盒测试(wasm-gc 与 native 均通过);native C 内核、RVV 与基准在 M2–M4。API 契约见 [docs/SPEC.md](docs/SPEC.md)。

## 5 个原语

| API | 语义(概览,唯一真源是 [docs/SPEC.md](docs/SPEC.md)) |
|---|---|
| `sum(xs : FixedArray[Int32]) -> Int64` | 求和,累加在 Int64;空数组返回 0 |
| `count_ge(xs : FixedArray[Int32], thr : Int32) -> Int32` | 统计 `>= thr` 的元素数;空数组返回 0 |
| `prefix_sum(xs : FixedArray[Int32]) -> Unit` | 原地前缀和,按 32 位二进制补码回绕 |
| `filter(xs : FixedArray[Int32], thr : Int32) -> FixedArray[Int32]` | 取出 `>= thr` 的元素,保持原序,返回新数组 |
| `dot(a : FixedArray[Int32], b : FixedArray[Int32]) -> Int64` | 点积,累加在 Int64;长度不等 panic |

> 本工具链中 `Int` 是 `#alias(Int32)`,`FixedArray[Int]` 与 `FixedArray[Int32]` 是同一类型;源码与契约统一写作 `Int32`。

## 后端

| 目标 | 实现 |
|---|---|
| wasm / wasm-gc / js | 纯 MoonBit 标量 |
| native(x86_64 / aarch64) | C 标量(`native-stub`) |
| native RISC-V | C + RVV intrinsics(`__riscv_vector`) |

RVV 走 C 是刻意的:MoonBit 无内联汇编、无 RVV intrinsics、无 riscv 编译目标,但 native 经 C 与 `MOON_CC` 可以到 RV64。详见 [docs/plans/v0.1.0.md](docs/plans/v0.1.0.md)。

## 文档

- [文档枢纽 / SSOT 地图](docs/README.md)
- [API 契约 SPEC](docs/SPEC.md)
- [v0.1.0 计划](docs/plans/v0.1.0.md)
- 计划中:`docs/NATIVE_ABI.md` / `docs/CROSS_COMPILE.md`(M2)、`docs/BENCHMARKS.md`(M3)、`docs/RELEASE_CHECKLIST.md`(M4)

## 许可证

Apache-2.0。见 [LICENSE](LICENSE)。
