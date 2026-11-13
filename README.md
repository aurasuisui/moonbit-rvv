# aurasuisui/rvv

MoonBit 的 RISC-V 向量(RVV)后端:一套数组原语,wasm/js 走纯 MoonBit 标量,native 走 C,RISC-V 走 RVV。

> **状态**:`v0.1.0` 开发中。M1 已落地 5 个原语的纯 MoonBit 标量实现与黑盒测试;**M2 已落地 native 的双分支 C 内核**(C 标量 + `__riscv_vector` RVV intrinsics)、`extern "C"` 分派、C 自检与 RV64 交叉/qemu 验证配方;**M3 已落地 spike 退休指令数基准**(三档 × 5 原语 × 3 规模,45 行表);M4(发布门禁)待做。API 契约见 [docs/SPEC.md](docs/SPEC.md),ABI 与交叉配方分别见 [docs/NATIVE_ABI.md](docs/NATIVE_ABI.md)、[docs/CROSS_COMPILE.md](docs/CROSS_COMPILE.md)。

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
| wasm / wasm-gc / js | 纯 MoonBit 标量(`src/scalar/impl.mbt`) |
| native(x86_64 / aarch64) | C 标量分支(`src/native/kernel.c`,经 `extern "C"`) |
| native RISC-V | C + RVV intrinsics(`__riscv_vector`;需 clang 交叉编译 `kernel.c`) |

RVV 走 C 是刻意的:MoonBit 无内联汇编、无 RVV intrinsics、无 riscv 编译目标,但 native 经 C 与 `MOON_CC` 可以到 RV64。详见 [docs/plans/v0.1.0.md](docs/plans/v0.1.0.md)。

## 交叉构建 / RVV 验证

一条命令(WSL,需要 clang-19 + riscv64 交叉 gcc + qemu 8.x):

```bash
export PATH=$HOME/.moon/bin:$PATH
bash scripts/cross-riscv.sh
```

预期最后几行:

```text
   vsetvli: 19
   vle32:   12
== qemu run (8.x user-mode, -cpu rv64,v=true)
SELFTEST_PASS
15,3,35,325
```

脚本会断言 `kernel.o` 由 clang 编译、产物含 RVV 指令、qemu 输出含 `SELFTEST_PASS` 与冒烟值。完整配方、clang/gcc 分工、`MOON_CC` 包装器与已知限制见 [docs/CROSS_COMPILE.md](docs/CROSS_COMPILE.md)。宿主 native 构建走 C 标量分支,可用 `nm` 在测试产物里看到 `rvv_sum` 等符号(见 [docs/NATIVE_ABI.md](docs/NATIVE_ABI.md) §8.3)。

## 基准(spike 退休指令数)

一条命令(WSL,需要 spike 1.1.1 + clang-19 + riscv64-unknown-elf-gcc):

```bash
bash scripts/bench.sh
```

脚本构建 3 个裸机 ELF(标量 `-O2 -march=rv64gc` / 自动向量化 `-O3 -march=rv64gcv` /
手写 RVV intrinsics `-O2 -march=rv64gcv`),用 spike(`--isa=rv64gcv_zicntr`)各跑两遍,断言
三档 checksum 逐位相同、同一 ELF 连跑两次指令数逐位相同、全程不读 cycle CSR,并生成
`bench/results.md`(45 行 = 5 原语 × 3 规模 × 3 档)。口径、VLEN、编译器版本、结果与限制见
[docs/BENCHMARKS.md](docs/BENCHMARKS.md)。

## 文档

- [文档枢纽 / SSOT 地图](docs/README.md)
- [API 契约 SPEC](docs/SPEC.md)
- [MoonBit↔C ABI](docs/NATIVE_ABI.md)
- [RV64 交叉配方](docs/CROSS_COMPILE.md)
- [性能口径与结果(基准)](docs/BENCHMARKS.md)
- [v0.1.0 计划](docs/plans/v0.1.0.md)
- 计划中:`docs/RELEASE_CHECKLIST.md`(M4)

## 许可证

Apache-2.0。见 [LICENSE](LICENSE)。
