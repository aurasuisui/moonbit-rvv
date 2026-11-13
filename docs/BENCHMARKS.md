# BENCHMARKS — spike 退休指令数基准(v0.1.0 / M3)

> **本文件是性能口径、方法、结果与限制的唯一真源。**
> 数字由 `bash scripts/bench.sh` 生成,机器可读的原始表在
> [`../bench/results.md`](../bench/results.md);§4 的表是**同一次脚本产出的逐字副本**,
> 两者不一致即为文档漂移(D9),以重跑脚本为准。
> API 语义见 [SPEC.md](SPEC.md);交叉编译配方见 [CROSS_COMPILE.md](CROSS_COMPILE.md)。

## 1. 口径:只认 spike 退休指令数

- **主指标**:spike 的 `rdinstret`(退休指令数)。一次测量 = 读计数器 → 调内核 → 读计数器,取差值;
  内核内部对输入做 REPS 遍(§3),所以一次测量覆盖 REPS 遍的完整工作。
- **运行方式**:`spike --isa=rv64gcv_zicntr _build/bench/bench_<tier>.elf`。
  `zicntr` 是读 `instret` 的前提;spike 的退休指令数**逐位确定**,同一 ELF 连跑两次结果完全相同。
- **不用 QEMU 计数器下结论**(F10):QEMU 的周期/指令数有 0.2~40% 波动、1.6~24× 虚高,
  因此仓库的基准 harness 与脚本**完全不读 cycle CSR**;`scripts/bench.sh` 每次运行都用
  `grep` 断言 `bench/` 与 `scripts/` 中不存在对 cycle CSR 的读取(D7)。
- **指令数 ≠ 周期**:spike 是功能模型,只回答"退休了多少条指令",不建模流水线、发射宽度、
  向量单元吞吐、缓存与访存停顿。该口径适合**确定性、可复现的实现间对比**,不能当作墙钟性能、
  周期数或硬件加速比。
- **比值方向**:`相对 scalar` < 1.00 表示该档比标量档**少**退休指令(更好);> 1.00 表示更多。

## 2. 环境

| 项 | 值 |
|---|---|
| spike | Spike RISC-V ISA Simulator 1.1.1-dev(`~/spike/bin/spike`) |
| ISA | `--isa=rv64gcv_zicntr` |
| VLEN | **128 bit**(spike 默认;rvv 档 VLPROBE 实测 `vlenb=16` → VLEN=128,`vlmax(e32m1)=4`) |
| 标量档 | riscv64-unknown-elf-gcc 10.2.0,`-O2 -march=rv64gc`(ISA 串无 V,不可能向量化) |
| 自动档 | clang 19.1.7,`-O3 -march=rv64gcv`(`--target=riscv64-unknown-elf`),与标量档同一份 plain C |
| RVV 档 | clang 19.1.7,`-O2 -march=rv64gcv`,手写 `<riscv_vector.h>` intrinsics |
| 宿主 | WSL2 Ubuntu 22.04,**无 RISC-V 硬件** |
| 公共编译选项 | `-mabi=lp64d -mcmodel=medany -ffreestanding -fno-builtin -nostdlib` |

> **注意**:三档的编译器/优化档并不相同(scalar = gcc `-O2`、auto = clang `-O3`、rvv = clang `-O2`)。
> 主表因此只能描述"每档各自的表现",档间差异不能直接归因于单一因素;定量拆分见 §4.4,
> 该混淆同时列为 §6 的限制。

## 3. harness 与参数

`bench/` 是裸机 harness,**不是** MoonBit 包(没有 `moon.pkg`,不参与包构建),也不改 `src/**`:

| 文件 | 作用 |
|---|---|
| `bench/crt0.S` | 裸机入口:置 `mstatus.VS`(否则第一条向量指令非法)、装 trap、跳 main |
| `bench/link.ld` | 加载地址 0x80000000、1 MiB 栈 |
| `bench/platform_htif.c` | spike HTIF 控制台/退出、`rdinstret` 读取、trap 现场打印 |
| `bench/bench.h` | 平台与三档内核的共享声明 |
| `bench/kernels.c` | plain C 五内核,**同一份源码**分别给标量档与自动档 |
| `bench/kernels_rvv.c` | 手写 RVV intrinsics 五内核(策略对齐 `src/native/kernel.c`) |
| `bench/main.c` | 驱动:三档**完全相同**(同一份 gcc 产物),只替换内核对象 |
| `bench/parity_main.c` | M4 运行期对拍的驱动(hosted C,不是裸机):逐值比较发布内核与 bench 内核,见 §7.1 |

三档各链一个 ELF,驱动代码逐字节相同,差异只来自内核对象;每个 ELF 依次跑 5 原语 × 3 规模,
打印 `RESULT <prim> <N> <REPS> <instret> <chk>`,由 `scripts/bench.sh` 解析。

| N | REPS | 每次测量元素访问数 = N × REPS |
|---:|---:|---:|
| 1024 | 16 | 16 384 |
| 8192 | 8 | 65 536 |
| 65536 | 4 | 262 144 |

- **为什么 N×REPS 固定成三档**:小 N 多跑几遍、大 N 少跑几遍,既让每次测量都有足够长的区间
  (稀释调用开销),又让全流程总元素量可控(全部 45 次测量共约 5.2 M 次元素访问,
  三档各跑两遍的 spike 总耗时约 6~8 s)。
- **输入**:固定 LCG 种子;`a[0]=INT32_MAX`、`a[1]=INT32_MIN` 保证极值参与每次测量;
  `thr=0`(约一半元素通过);三档使用完全相同的输入。
- **校验和**:`sum`/`dot` 用 64 位结果位型,`count_ge` 用计数,`prefix_sum`/`filter` 用结果序列的
  FNV-1a 64(`filter` 另把长度折入)。校验和与输入重建都在测量区间之外。
- **语义**:五内核严格按 [SPEC.md](SPEC.md):`sum`/`dot` 在 Int64 累加,`prefix_sum` 按 32 位回绕
  (用 `uint32_t` 累加,不依赖有符号溢出 UB),`filter` 保序;`dot` 长度相等由驱动保证
  (bench 不测 panic 路径,panic 语义由 `src/tests/api_test.mbt` 覆盖)。

## 4. 结果

### 4.1 45 行总表(5 原语 × 3 规模 × 3 档)

本表与 `bench/results.md` 的 45 行逐字相同(同一次脚本运行产出);每行含 VLEN、编译器、N、REPS
与 checksum,`相对 scalar` = 该行 instret ÷ 同 (原语, N) 的标量档 instret。

| # | 原语 | N | REPS | 档 | 编译器 | VLEN | instret | chk | 相对 scalar |
|---:|---|---:|---:|---|---|---:|---:|---|---:|
| 1 | `sum` | 1024 | 16 | scalar | gcc 10.2.0 | 128 | 65619 | `0x00000070b2e99e80` | 1.00x(基准) |
| 2 | `sum` | 1024 | 16 | auto | clang 19.1.7 | 128 | 24847 | `0x00000070b2e99e80` | 0.38x |
| 3 | `sum` | 1024 | 16 | rvv | clang 19.1.7 | 128 | 32962 | `0x00000070b2e99e80` | 0.50x |
| 4 | `count_ge` | 1024 | 16 | scalar | gcc 10.2.0 | 128 | 73940 | `0x0000000000002060` | 1.00x(基准) |
| 5 | `count_ge` | 1024 | 16 | auto | clang 19.1.7 | 128 | 14544 | `0x0000000000002060` | 0.20x |
| 6 | `count_ge` | 1024 | 16 | rvv | clang 19.1.7 | 128 | 45184 | `0x0000000000002060` | 0.61x |
| 7 | `prefix_sum` | 1024 | 16 | scalar | gcc 10.2.0 | 128 | 82016 | `0x59ada67630ec9ee5` | 1.00x(基准) |
| 8 | `prefix_sum` | 1024 | 16 | auto | clang 19.1.7 | 128 | 81998 | `0x59ada67630ec9ee5` | 1.00x |
| 9 | `prefix_sum` | 1024 | 16 | rvv | clang 19.1.7 | 128 | 102511 | `0x59ada67630ec9ee5` | 1.25x |
| 10 | `filter` | 1024 | 16 | scalar | gcc 10.2.0 | 128 | 114981 | `0x7b45f82761862729` | 1.00x(基准) |
| 11 | `filter` | 1024 | 16 | auto | clang 19.1.7 | 128 | 107077 | `0x7b45f82761862729` | 0.93x |
| 12 | `filter` | 1024 | 16 | rvv | clang 19.1.7 | 128 | 65649 | `0x7b45f82761862729` | 0.57x |
| 13 | `dot` | 1024 | 16 | scalar | gcc 10.2.0 | 128 | 114788 | `0x100a88591c8e63a0` | 1.00x(基准) |
| 14 | `dot` | 1024 | 16 | auto | clang 19.1.7 | 128 | 33056 | `0x100a88591c8e63a0` | 0.29x |
| 15 | `dot` | 1024 | 16 | rvv | clang 19.1.7 | 128 | 41155 | `0x100a88591c8e63a0` | 0.36x |
| 16 | `sum` | 8192 | 8 | scalar | gcc 10.2.0 | 128 | 262195 | `0x00000085eba5bf40` | 1.00x(基准) |
| 17 | `sum` | 8192 | 8 | auto | clang 19.1.7 | 128 | 98455 | `0x00000085eba5bf40` | 0.38x |
| 18 | `sum` | 8192 | 8 | rvv | clang 19.1.7 | 128 | 131178 | `0x00000085eba5bf40` | 0.50x |
| 19 | `count_ge` | 8192 | 8 | scalar | gcc 10.2.0 | 128 | 295276 | `0x0000000000008128` | 1.00x(基准) |
| 20 | `count_ge` | 8192 | 8 | auto | clang 19.1.7 | 128 | 57464 | `0x0000000000008128` | 0.19x |
| 21 | `count_ge` | 8192 | 8 | rvv | clang 19.1.7 | 128 | 180296 | `0x0000000000008128` | 0.61x |
| 22 | `prefix_sum` | 8192 | 8 | scalar | gcc 10.2.0 | 128 | 327736 | `0x9259a51ab7881f25` | 1.00x(基准) |
| 23 | `prefix_sum` | 8192 | 8 | auto | clang 19.1.7 | 128 | 327726 | `0x9259a51ab7881f25` | 1.00x |
| 24 | `prefix_sum` | 8192 | 8 | rvv | clang 19.1.7 | 128 | 409663 | `0x9259a51ab7881f25` | 1.25x |
| 25 | `filter` | 8192 | 8 | scalar | gcc 10.2.0 | 128 | 459405 | `0xecf95aa1a1083c97` | 1.00x(基准) |
| 26 | `filter` | 8192 | 8 | auto | clang 19.1.7 | 128 | 427525 | `0xecf95aa1a1083c97` | 0.93x |
| 27 | `filter` | 8192 | 8 | rvv | clang 19.1.7 | 128 | 262209 | `0xecf95aa1a1083c97` | 0.57x |
| 28 | `dot` | 8192 | 8 | scalar | gcc 10.2.0 | 128 | 458812 | `0x878091789b97a1d0` | 1.00x(基准) |
| 29 | `dot` | 8192 | 8 | auto | clang 19.1.7 | 128 | 131232 | `0x878091789b97a1d0` | 0.29x |
| 30 | `dot` | 8192 | 8 | rvv | clang 19.1.7 | 128 | 163947 | `0x878091789b97a1d0` | 0.36x |
| 31 | `sum` | 65536 | 4 | scalar | gcc 10.2.0 | 128 | 1048611 | `0x00000254bd969fa0` | 1.00x(基准) |
| 32 | `sum` | 65536 | 4 | auto | clang 19.1.7 | 128 | 393307 | `0x00000254bd969fa0` | 0.38x |
| 33 | `sum` | 65536 | 4 | rvv | clang 19.1.7 | 128 | 524350 | `0x00000254bd969fa0` | 0.50x |
| 34 | `count_ge` | 65536 | 4 | scalar | gcc 10.2.0 | 128 | 1180772 | `0x0000000000020438` | 1.00x(基准) |
| 35 | `count_ge` | 65536 | 4 | auto | clang 19.1.7 | 128 | 229452 | `0x0000000000020438` | 0.19x |
| 36 | `count_ge` | 65536 | 4 | rvv | clang 19.1.7 | 128 | 720940 | `0x0000000000020438` | 0.61x |
| 37 | `prefix_sum` | 65536 | 4 | scalar | gcc 10.2.0 | 128 | 1310756 | `0x6532f3fc35c56325` | 1.00x(基准) |
| 38 | `prefix_sum` | 65536 | 4 | auto | clang 19.1.7 | 128 | 1310750 | `0x6532f3fc35c56325` | 1.00x |
| 39 | `prefix_sum` | 65536 | 4 | rvv | clang 19.1.7 | 128 | 1638439 | `0x6532f3fc35c56325` | 1.25x |
| 40 | `filter` | 65536 | 4 | scalar | gcc 10.2.0 | 128 | 1837209 | `0xf72e6d0ad9af361c` | 1.00x(基准) |
| 41 | `filter` | 65536 | 4 | auto | clang 19.1.7 | 128 | 1709377 | `0xf72e6d0ad9af361c` | 0.93x |
| 42 | `filter` | 65536 | 4 | rvv | clang 19.1.7 | 128 | 1048617 | `0xf72e6d0ad9af361c` | 0.57x |
| 43 | `dot` | 65536 | 4 | scalar | gcc 10.2.0 | 128 | 1835048 | `0xd47a75d3520d90e8` | 1.00x(基准) |
| 44 | `dot` | 65536 | 4 | auto | clang 19.1.7 | 128 | 524384 | `0xd47a75d3520d90e8` | 0.29x |
| 45 | `dot` | 65536 | 4 | rvv | clang 19.1.7 | 128 | 655423 | `0xd47a75d3520d90e8` | 0.36x |

> 计划 M3 出口条件里的"9 行"是首轮基准(只有 scan / count / filter 三个原语)的遗留表述;
> 本里程碑按要求覆盖 **5 原语 × 3 档 × 3 规模 = 45 行**,每行都带 VLEN / 编译器 / N / REPS / checksum。

### 4.2 相对 scalar 比值矩阵

自动向量化档(auto)÷ 标量档(scalar):

| 原语 | N=1024 | N=8192 | N=65536 |
|---|---:|---:|---:|
| `sum` | 0.38x | 0.38x | 0.38x |
| `count_ge` | 0.20x | 0.19x | 0.19x |
| `prefix_sum` | 1.00x | 1.00x | 1.00x |
| `filter` | 0.93x | 0.93x | 0.93x |
| `dot` | 0.29x | 0.29x | 0.29x |

手写 RVV 档(rvv)÷ 标量档(scalar):

| 原语 | N=1024 | N=8192 | N=65536 |
|---|---:|---:|---:|
| `sum` | 0.50x | 0.50x | 0.50x |
| `count_ge` | 0.61x | 0.61x | 0.61x |
| `prefix_sum` | 1.25x | 1.25x | 1.25x |
| `filter` | 0.57x | 0.57x | 0.57x |
| `dot` | 0.36x | 0.36x | 0.36x |

> 主表的 `相对 scalar` 列以 **gcc 标量档**为基线,auto/rvv 两档与 scalar 的差异里混有编译器与
> 优化档因素(见 §4.4);例如 `count_ge` 上 clang 的标量代码就比 gcc 慢 33%。

### 4.3 向量化诊断

各档内核目标文件里每个内核函数的向量指令条数(`llvm-objdump -d`;Ubuntu 22.04 的 binutils 2.35/2.38
解不出 RVV 1.0 编码,因此用 LLVM 反汇编器):

| 内核函数 | scalar | auto | rvv |
|---|---:|---:|---:|
| `k_sum` | 0 | 16 | 11 |
| `k_count_ge` | 0 | 11 | 5 |
| `k_prefix_sum` | 0 | 0 | 11 |
| `k_filter` | 0 | 0 | 8 |
| `k_dot` | 0 | 17 | 12 |

- **auto 档命中 3/5**:`k_sum` / `k_count_ge` / `k_dot` 被 LLVM 自动向量化;
  `k_prefix_sum`(扫描线有跨元素依赖)与 `k_filter`(需要顺序压缩)未向量化 —— **如实标注,不凑数**。
- **rvv 档 5/5 都含向量指令**;VLPROBE 在运行时打印 `vlenb=16`,证明 V 状态与向量指令确实执行过
  (不是"编出来但没跑到")。

### 4.4 控制实验:编译器与优化档的影响

主表三档在「编译器/优化档」和「ISA/实现策略」两个维度上同时不同,单看主表无法归因。
控制实验(`bash scripts/bench_control.sh`,N=8192、REPS=8)每次只动一个变量,构建 3 个控制 ELF
并各跑两遍(spike `--isa=rv64gcv_zicntr`);**所有控制档的 checksum 都与主表同 (原语, N)
逐位相同**,因此工作负载没有变,差异只来自代码生成。

| 记号 | 构建 | 相对主表 |
|---|---|---|
| (1) scalar | gcc 10.2 `-O2 -march=rv64gc` | 主表 scalar 档 |
| (2) | clang 19 `-O2 -march=rv64gc`,`bench/kernels.c` | 与 (1) 同优化档,换编译器 |
| (3) | clang 19 `-O3 -march=rv64gc`,`bench/kernels.c` | 与 auto 同编译器/优化档,但无 V |
| (4) auto | clang 19 `-O3 -march=rv64gcv`,`bench/kernels.c` | 主表 auto 档 |
| (5) rvv | clang 19 `-O2 -march=rv64gcv`,`bench/kernels_rvv.c` | 主表 rvv 档 |
| (6) | clang 19 `-O3 -march=rv64gcv`,`bench/kernels_rvv.c` | 与 (5) 同 intrinsics,只抬高优化档 |

绝对退休指令数(spike;N=8192、REPS=8;单位同主表):

| 原语 | (1) | (2) | (3) | (4) | (5) | (6) |
|---|---:|---:|---:|---:|---:|---:|
| `sum` | 262195 | 262202 | 262186 | 98455 | 131178 | 131154 |
| `count_ge` | 295276 | 393291 | 393275 | 57464 | 180296 | 180281 |
| `prefix_sum` | 327736 | 327743 | 327726 | 327726 | 409663 | 409656 |
| `filter` | 459405 | 427532 | 427525 | 427525 | 262209 | 262194 |
| `dot` | 458812 | 458819 | 458803 | 131232 | 163947 | 163923 |

派生比值(< 1.00 表示比参照少退休指令):

| 原语 | (2)/(1) 编译器<br>(同 -O2,无 V) | (3)/(1) 编译器+优化档<br>(无 V) | (4)/(3) 向量化本身 | (6)/(5) -O2→-O3<br>(intrinsics) | (6)/(4) 实现策略<br>(同 clang -O3 +V) |
|---|---:|---:|---:|---:|---:|
| `sum` | 1.00 | 1.00 | 0.38 | 1.00 | 1.33 |
| `count_ge` | 1.33 | 1.33 | 0.15 | 1.00 | 3.14 |
| `prefix_sum` | 1.00 | 1.00 | 1.00 | 1.00 | 1.25 |
| `filter` | 0.93 | 0.93 | 1.00 | 1.00 | 0.61 |
| `dot` | 1.00 | 1.00 | 0.29 | 1.00 | 1.25 |

解读:

1. **-O2→-O3 对手写 intrinsics 几乎零影响**:(6)/(5) 全为 1.00(差值 7~24 条指令,约 0.004%~0.02%)。
   因此主表 auto(-O3)与 rvv(-O2)的差距**不是优化档造成的**。
2. **gcc vs clang 只影响标量基线**:`sum`/`prefix_sum`/`dot` 两编译器同量级(1.00),
   `count_ge` 上 clang 的标量循环比 gcc **多 33%** 指令(每元素约 6.0 条 vs 4.5 条),
   `filter` 上 clang 少 7%。主表 `相对 scalar` 列以 gcc 为基线,所以 `count_ge` 上把向量化收益
   算小了:同编译器基线下向量化本身是 0.15×,对 gcc 基线是 0.19×。
3. **同编译器、同优化档的策略对比 (6) vs (4)**:自动向量化在 `count_ge`(3.14×)、`sum`(1.33×)、
   `dot`(1.25×)、`prefix_sum`(1.25×)上仍显著少于手写 intrinsics;手写档只在 `filter`
   胜出(0.61×)。→ §5 结论 2 的方向成立,并且可以归因于**实现策略**
   (LLVM 的宽 LMUL/VLS 向量化 vs e32m1 手写内核),而不是编译器或优化档。
4. **向量化本身的收益** (4)/(3):`sum` 0.38、`dot` 0.29、`count_ge` 0.15;
   `prefix_sum`/`filter` = 1.00,与 §4.3「这两个内核没有生成向量指令」的诊断一致。

## 5. 结论

1. **手写 RVV 档在 4/5 原语上少退休指令**:`dot` 0.36×(2.8×)、`sum` 0.50×(2.0×)、
   `filter` 0.57×(1.75×)、`count_ge` 0.61×(1.64×);**`prefix_sum` 反而多 25%**(1.25×)。
2. **同编译器、同优化档下,自动向量化档仍比手写档更省**(§4.4 控制实验 (6) vs (4),两者都是
   clang `-O3 -march=rv64gcv`):`count_ge` 3.14×、`sum` 1.33×、`prefix_sum` 1.25×、
   `dot` 1.25×;**`filter` 是手写档唯一胜出的原语**(0.61×,LLVM 不生成 `vcompress`)。
   所以主表里 auto 相对 rvv 的优势(0.38×/0.19×/0.29× 对 0.50×/0.61×/0.36×)**主要来自向量化
   策略本身**:控制实验显示 `-O2`→`-O3` 对手写内核几乎零影响(§4.4 (6)/(5) = 1.00),
   而两档同为 clang,gcc-vs-clang 不进入这一比较。
3. **原因**:手写内核沿用 `src/native/kernel.c` 的 e32m1 策略,VLEN=128 时每块只有 4 个元素,
   `vsetvli` 与循环开销摊薄不足;LLVM 的自动向量化用更大的 LMUL(VLS 风格,反汇编里可见 `csrr vlenb`),
   因此**在纯指令数口径下**更优。`prefix_sum` 的 Hillis-Steele 每块要做 log2(vl) 轮
   `vslideup`+`vadd`,VLMAX=4 时固定开销最高,而标量版本已经把每元素压到约 5 条指令。
   控制实验排除了"优化档不够"这一解释:把手写内核从 `-O2` 提到 `-O3` 几乎不改变指令数(§4.4)。
4. **规模无关性**:三个规模的比值几乎完全相同(`count_ge` 0.20/0.19/0.19、其余各档逐位一致),
   说明 per-element 成本由内核结构决定,而不是边界效应;同时也说明测量区间足够长,调用开销已可忽略。
5. **与计划附录 A 首轮基准方向一致**:计划里 `scan` 的 auto=1.00×/rvv=1.45×、
   `count` 的 auto≈0.19×/rvv≈0.56×、`filter` 的 auto≈0.93×/rvv≈0.54×;
   本次(不同 harness、REPS 与数据宽度)对应值为 1.00×/1.25×、0.19×/0.61×、0.93×/0.57× ——
   排序完全一致,量级接近。**结论不应从旧数字外推**,以本表为准。
6. **v0.2 的方向**:`prefix_sum` 需要换算法(分块/宽 LMUL/unrolled scan),
   `sum`/`dot`/`count_ge` 需要按 VLEN 调 LMUL;这与计划 §十二「LMUL 调优」一致,属 v0.2 范围。

## 6. 限制(必读)

1. **测的是等价 C 内核,不是 MoonBit 生成产物**(D8)。`bench/` 是独立裸机 harness,直接跑
   `bench/kernels*.c`;语义与策略对齐 `src/native/kernel.c`,但**不经过** MoonBit 编译器、
   `native-stub` 包装、`FixedArray` 读写与 ABI 转换。因此这些数字只能用于**三档实现之间的相对比较**,
   不能当作 MoonBit 用户可见的加速比。
   M4 起,"`bench/kernels*.c` 是另一份会与发布内核漂移的实现"这一条已由运行期对拍关闭(§7.1 证明
   两边逐值相等),所以数字描述的就是发布内核的算法;但**包装差异**(MoonBit 编译器、`native-stub`、
   `FixedArray` 读写与 ABI 转换)仍然存在,限制不变。
2. **主表三档的编译器/优化档不一致**。scalar = gcc 10.2 `-O2`、auto = clang 19 `-O3`、
   rvv = clang 19 `-O2`:主表只能描述"每档各自的表现",**不能**把档间差异直接归因于单一因素;
   `相对 scalar` 列还以 gcc 标量档为基线,而同一原语换编译器本身就能差 33%(§4.4 的 `count_ge`)。
   任何归因都必须看 §4.4 的控制实验,不能只读主表。
3. **指令数不是周期**。spike 不建模流水线、向量单元宽度、缓存与访存;指令数少的实现不一定在硬件上
   更快(例如宽 LMUL 在真实核上可能受寄存器/端口限制)。这里报告的是"退休指令条数"这个确定量。
4. **无硬件**。所有 RVV 结论来自 spike(以及 M2 的 qemu 8.2 正确性验证),没有 RVV 硬件实测。
5. **单一 VLEN**。只测 VLEN=128;未验证 VLEN=256/512 等其他配置。RVV 档固定 e32m1,
   auto 档的 LMUL 由 LLVM 决定。
6. **单一数据分布**。`thr=0`、LCG 随机数据;未覆盖"全通过/全不通过/极值密集"等分布
   (`filter` 的输出量、`count_ge` 的压缩率都会影响真实成本)。
7. **编译器版本绑定**。数字与 gcc 10.2.0 / clang 19.1.7 / spike 1.1.1-dev 绑定,换版本会变。
8. **auto 档不是"最优自动向量化"**。只用 `-O3 -march=rv64gcv` 一组 flag,没有调 LLVM 向量化器参数;
   "auto 档"衡量的是**默认设置**下 LLVM 的表现。

## 7. 复现与断言

```bash
bash scripts/bench.sh
```

依赖:spike 1.1.1(`BENCH_SPIKE` 可覆盖路径)、clang-19(含 `llvm-objdump-19`,缺失时只跳过反汇编诊断)、
riscv64-unknown-elf-gcc 10.2、`readelf`。构建产物写在 `_build/bench/`(`_build/` 已被 `.gitignore` 忽略)。
对拍步骤(§7.1)另需 `riscv64-linux-gnu-gcc`、RISC-V sysroot(`/usr/riscv64-linux-gnu`)与 qemu-user 8.2
(由 `scripts/run-qemu.sh` 选择并校验版本)。
脚本每次运行都会断言:

1. 每档恰好 **15 条 `RESULT`**(5 原语 × 3 规模),缺行即失败;
2. **确定性**:同一 ELF 连跑两次,`RESULT` 行(instret 与 chk)逐位相同;
3. **校验和**:15 个 (原语, N) 的三档 `chk` 完全相同;
4. **口径**:`bench/` 与 `scripts/` 中没有对 cycle CSR 的读取;
5. **VLEN**:rvv 档 VLPROBE = `vlenb=16 vlen=128 vlmax(e32m1)=4`;
6. **运行期对拍**:`scripts/bench_parity.sh` 以裸行 `PARITY_OK` 结束,即发布内核与 bench 内核逐值相等(§7.1)。

脚本结束时生成 `bench/results.md`(45 行数据)并以 `BENCH_OK` 结束;该文件**不含时间戳**,
同一环境重跑逐字节相同,可直接作为提交证据。

控制实验(§4.4)是独立命令,只读主表、不写 `bench/results.md`:

```bash
bash scripts/bench_control.sh
# -> _build/bench-control/control-table.md,以 CONTROL_OK 结束
```

它断言:每个控制 ELF 跑两次逐位一致、N=8192 的 checksum 与主表对应行相同、两个 `-march=rv64gc`
控制对象不含向量指令(反汇编器缺失时跳过该 sanity check)。

### 7.1 发布内核 vs bench 内核的运行期对拍(M4 / P1)

主表的数字来自 `bench/kernels*.c`,而它们是 `src/native/kernel.c` 的**独立实现**;两份实现一旦漂移,
表就不再描述用户实际拿到的代码。`scripts/bench_parity.sh` 用同一份确定性输入在**运行期**证明两边逐值相等
(`scripts/bench.sh` 末尾会自动调用它并断言 `PARITY_OK`):

```bash
bash scripts/bench_parity.sh
# -> _build/parity/ 下两个宿主程序,qemu-user 8.2 各跑一次,以裸行 PARITY_OK 结束
```

| 对 | 发布侧(编译方式) | bench 侧 | 比较内容 |
|---|---|---|---|
| **A1** | `src/native/kernel.c`,gcc `-march=rv64gc`(C 标量分支) | `bench/kernels.c`,`k_*(..., reps=1)` | 5 原语的返回值 / 输出数组与长度 |
| **A2** | `src/native/kernel.c`,clang-19 `-march=rv64gcv`(RVV 分支) | `bench/kernels_rvv.c`,`k_*(..., reps=1)` | 同上 |

- **形态**:RV64 Linux **用户态**宿主程序(不是裸机 harness)。`kernel.c` 交给
  `clang-19 --target=riscv64-linux-gnu --sysroot=/usr/riscv64-linux-gnu -march=rv64gcv`,其余 C 与链接交给
  `riscv64-linux-gnu-gcc`(与 [CROSS_COMPILE.md](CROSS_COMPILE.md) §3 的分工相同),再在 qemu-user 8.2
  (`-cpu rv64,v=true`)下运行。
- **规模**:`n = 0, 1, 2, 3, 5, 7, 17, 1024`(与 M2 出口条件、`rvv_selftest` 同一组,非 VL 整数倍的尾部也在内)。
- **阈值**:`INT32_MIN / 0 / INT32_MAX`(`count_ge`、`filter` 各 3 组);`prefix_sum`、`filter` 比较结果数组与长度。
- **输入**:与 `bench/main.c` 完全相同的一份 LCG 数据(同种子,`a[0]=INT32_MAX`、`a[1]=INT32_MIN`),
  所以对拍失败也意味着主表描述的不是这份数据。
- **失败/通过**:失败打印 `PARITY_FAIL:<原语>:<A1|A2>:<n>` 并以非 0 退出;通过时只打印裸行 `PARITY_OK`。
- **防伪**(避免"对拍了两份标量代码"的空转):A2 的 harness 先用 `-DPARITY_EXPECT_RVV` 调 `rvv_selftest()`,
  返回 600 即"RVV 分支编译了但没执行",直接判失败;脚本另外用 `llvm-objdump` 断言两个 `kernel.o` 的
  向量指令数分别为 0(A1 是标量分支)与 > 0(A2 是 RVV 分支),反汇编器缺失时跳过该条并注明。
- **不在覆盖范围**:`auto` 档。发布侧只有"C 标量分支"与"手写 RVV 分支",没有"交给 LLVM 自动向量化的
  plain C"这一对应物,所以 auto 档只存在于基准里(§6 限制 8 仍然成立)。
