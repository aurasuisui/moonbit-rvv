# aurasuisui/rvv

MoonBit 的 RISC-V 向量(RVV)后端:一套数组原语,wasm/js 走纯 MoonBit 标量,native 走 C,RISC-V 走 RVV。

> **状态**:`v0.1.0` 开发中。API 契约、交叉编译配方与基准在 M1–M4 定稿;当前仓库以计划与文档体系为主,尚无可用实现。

## 5 个原语

| API | 语义 |
|---|---|
| `sum(xs) -> Int64` | 求和,中间值 Int64;空数组返回 0 |
| `count_ge(xs, thr) -> Int` | 统计 `>= thr` 的元素数;空数组返回 0 |
| `prefix_sum(xs) -> Unit` | 原地前缀和,按 32 位回绕 |
| `filter(xs, thr) -> FixedArray[Int]` | 取出 `>= thr` 的元素,保持原序 |
| `dot(a, b) -> Int64` | 点积;长度不等 panic |

## 后端

| 目标 | 实现 |
|---|---|
| wasm / wasm-gc / js | 纯 MoonBit 标量 |
| native(x86_64 / aarch64) | C 标量(`native-stub`) |
| native RISC-V | C + RVV intrinsics(`__riscv_vector`) |

RVV 走 C 是刻意的:MoonBit 无内联汇编、无 RVV intrinsics、无 riscv 编译目标,但 native 经 C 与 `MOON_CC` 可以到 RV64。详见 [docs/plans/v0.1.0.md](docs/plans/v0.1.0.md)。

## 文档

- [文档枢纽 / SSOT 地图](docs/README.md)
- [v0.1.0 计划](docs/plans/v0.1.0.md)
- 计划中:`docs/SPEC.md`(M1)、`docs/NATIVE_ABI.md` / `docs/CROSS_COMPILE.md`(M2)、`docs/BENCHMARKS.md`(M3)、`docs/RELEASE_CHECKLIST.md`(M4)

## 许可证

Apache-2.0。见 [LICENSE](LICENSE)。
