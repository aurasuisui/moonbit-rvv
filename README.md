# aurasuisui/rvv

MoonBit 的 RISC-V 向量(RVV)后端:一套数组原语,wasm/js 走纯 MoonBit 标量,native 走 C,RISC-V 走 RVV。

> **状态**:`v0.1.0` 开发中。M1 已落地 5 个原语的纯 MoonBit 标量实现与黑盒测试;**M2 已落地 native 的双分支 C 内核**(C 标量 + `__riscv_vector` RVV intrinsics)、`extern "C"` 分派、C 自检与 RV64 交叉/qemu 验证配方;**M3 已落地 spike 退休指令数基准**(三档 × 5 原语 × 3 规模,45 行表);M4 已落地发布门禁([docs/RELEASE_CHECKLIST.md](docs/RELEASE_CHECKLIST.md))与"发布内核 vs 基准内核"的运行期对拍,待 lead 复核;**实际发布与打 tag 需人类口令**。API 契约见 [docs/SPEC.md](docs/SPEC.md),ABI 与交叉配方分别见 [docs/NATIVE_ABI.md](docs/NATIVE_ABI.md)、[docs/CROSS_COMPILE.md](docs/CROSS_COMPILE.md)。

## 5 个原语

| API | 语义(概览,唯一真源是 [docs/SPEC.md](docs/SPEC.md)) |
|---|---|
| `sum(xs : FixedArray[Int32]) -> Int64` | 求和,累加在 Int64;空数组返回 0 |
| `count_ge(xs : FixedArray[Int32], thr : Int32) -> Int32` | 统计 `>= thr` 的元素数;空数组返回 0 |
| `prefix_sum(xs : FixedArray[Int32]) -> Unit` | 原地前缀和,按 32 位二进制补码回绕 |
| `filter(xs : FixedArray[Int32], thr : Int32) -> FixedArray[Int32]` | 取出 `>= thr` 的元素,保持原序,返回新数组 |
| `dot(a : FixedArray[Int32], b : FixedArray[Int32]) -> Int64` | 点积,累加在 Int64;长度不等 panic |

> 本工具链中 `Int` 是 `#alias(Int32)`,`FixedArray[Int]` 与 `FixedArray[Int32]` 是同一类型;源码与契约统一写作 `Int32`。

## 安装与使用

发布到 mooncakes.io 后:

```bash
moon add aurasuisui/rvv@0.1.0
```

在用到它的包的 `moon.pkg` 里 `import { "aurasuisui/rvv" }`(别名 `@rvv`),然后直接调用:

```moonbit
///|
test "readme example" {
  let xs : FixedArray[Int32] = FixedArray::from_array([1, 2, 3, 4])
  assert_eq(@rvv.sum(xs), 10L)                    // 累加在 Int64
  assert_eq(@rvv.count_ge(xs, 3), 2)              // >= 3 的元素个数
  assert_eq(@rvv.filter(xs, 3).length(), 2)       // 保序,返回新数组
  let p : FixedArray[Int32] = FixedArray::from_array([1, 2, 3])
  @rvv.prefix_sum(p)                              // 原地,32 位回绕
  assert_eq(p[2], 6)
  let a : FixedArray[Int32] = FixedArray::from_array([1, 2, 3])
  let b : FixedArray[Int32] = FixedArray::from_array([4, 5, 6])
  assert_eq(@rvv.dot(a, b), 32L)                  // 长度不等 panic
}
```

> **0.1.0 尚未发布**:现在执行 `moon add aurasuisui/rvv@0.1.0` 会报
> `Error: module aurasuisui/rvv was not found in the registry`。发布前的"干净目录"验证只能做到
> "`moon package` 产物解包后在干净目录里自建 + 自测(40/40 × 两个 target)";发布后必须补做
> `moon add` + 消费者工程的 S1/S2,判定标准与证据落点见
> [docs/RELEASE_CHECKLIST.md](docs/RELEASE_CHECKLIST.md) Tier 3。API 语义、边界与 panic 见 [docs/SPEC.md](docs/SPEC.md)。

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

> **CI 不含 RVV**:RVV 分支的验证需在 WSL 本地运行 `bash scripts/cross-riscv.sh`;CI 只覆盖 wasm-gc 与 native(见 [.github/workflows/ci.yml](.github/workflows/ci.yml),与计划风险 R6 一致)。

## 基准(spike 退休指令数)

一条命令(WSL,需要 spike 1.1.1 + clang-19 + riscv64-unknown-elf-gcc):

```bash
bash scripts/bench.sh
```

脚本构建 3 个裸机 ELF(标量 `-O2 -march=rv64gc` / 自动向量化 `-O3 -march=rv64gcv` /
手写 RVV intrinsics `-O2 -march=rv64gcv`),用 spike(`--isa=rv64gcv_zicntr`)各跑两遍,断言
三档 checksum 逐位相同、同一 ELF 连跑两次指令数逐位相同、全程不读 cycle CSR,并生成
`bench/results.md`(45 行 = 5 原语 × 3 规模 × 3 档);末尾还会运行 `scripts/bench_parity.sh`,在同一份输入下
逐值比较发布内核 `src/native/kernel.c` 与基准内核,要求打印 `PARITY_OK`(见 [docs/BENCHMARKS.md](docs/BENCHMARKS.md) §7.1)。
口径、VLEN、编译器版本、结果与限制见 [docs/BENCHMARKS.md](docs/BENCHMARKS.md)。

> **`prefix_sum` 例外**:VLEN=128 的当前实现下 `prefix_sum` 不加速:auto 档 1.00×、手写 RVV 档 1.25×
> (比标量多 25% 退休指令);其余原语与口径见 [docs/BENCHMARKS.md](docs/BENCHMARKS.md) §4.1 与 §4.4。

## 文档

- [文档枢纽 / SSOT 地图](docs/README.md)
- [API 契约 SPEC](docs/SPEC.md)
- [MoonBit↔C ABI](docs/NATIVE_ABI.md)
- [RV64 交叉配方](docs/CROSS_COMPILE.md)
- [性能口径与结果(基准)](docs/BENCHMARKS.md)
- [发布门禁 / RELEASE CHECKLIST](docs/RELEASE_CHECKLIST.md)
- [v0.1.0 计划](docs/plans/v0.1.0.md)

## 许可证

Apache-2.0。见 [LICENSE](LICENSE)。
