# Changelog

本项目遵循 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/) 的结构;版本号遵循 SemVer。

## [Unreleased]

### Added

- 初始化仓库:`moon.mod`、Apache-2.0 LICENSE、文档体系、Git 分支模型。
- 计划 `docs/plans/v0.1.0.md` 第 3 稿:加入 SSOT 文档体系、`main` 只收里程碑合并的分支模型、`src/` 分包结构、进度看板与缺陷台账。
- M1:5 个公开原语 `sum` / `count_ge` / `prefix_sum` / `filter` / `dot`(`src/lib.mbt`),纯 MoonBit 标量实现 `src/scalar/impl.mbt`;wasm/js 与 native 的 dispatch 文件保留 target 分派结构,当前都转发标量实现(M2 native 换 C 内核)。
- M1:黑盒测试 `src/tests/api_test.mbt`,40 个用例,覆盖空 / 单元素 / 全相同 / 严格递增 / Int32 极值 / 长度非 4 倍数,以及 `filter` 返回新数组、`filter` 长度等于 `count_ge` 等跨原语不变量;另含 `test "panic dot length mismatch"` 回归用例(工具链 `test "panic …"` 约定)。wasm-gc 与 native 各 passed 40。
- M1:`docs/SPEC.md` 落地(签名、语义、边界、panic、32 位回绕、整数口径、非目标),README API 表与文档链接同步,`docs/README.md` 把 SPEC 移入已存在文档。
- M1:probe 冒烟与 CI 期望改为 5 原语组合(输出 `15,3,35,325`);CI 增加两个 `moon test` 步骤。
- M2:`src/native/kernel.c` 重写为 5 个函数 × 两条分支:C 标量分支(`int32_t` 显式回绕,无有符号溢出 UB)与 `__riscv_vector` RVV intrinsics 分支(`vsetvl` / `vle32` / `vwadd` / `vwmacc` / `vmsge` / `vcpop` / `vcompress` / `vslideup` / `vredsum`);`rvv_selftest` 对 n=0,1,2,3,5,7,17,1024 逐元素比较两条分支并检查 RVV 入口确实执行。
- M2:`src/dispatch_native.mbt` 改为 `extern "C"` 调用 C 内核(`#borrow` 标注所有权),公开签名与语义不变;wasm/js 仍走 `@scalar`;`dot` 长度不等仍在 MoonBit 侧 panic(唯一 abort 点保留在 `src/scalar/impl.mbt`)。
- M2:probe 拆分 target 入口——`src/probe/main.mbt` 共享冒烟 helper,`main_native.mbt` 先跑 C 自检再打印冒烟行,`main_wasm.mbt` 纯标量;`src/probe/moon.pkg` 加文件级 `targets`。
- M2:`scripts/cross-riscv.sh` 与 `scripts/run-qemu.sh` 扩展为交叉构建 + qemu 运行 + 断言:生成按文件名分派的 `MOON_CC` 包装器(kernel.c → clang-19,`-march=rv64gcv`;其余 C 与链接 → `riscv64-linux-gnu-gcc`)与 `ar`/`ranlib`;断言 `kernel.o` 由 clang 编译、`file`/`readelf` 为 RISC-V、`objdump` 含 `vsetvli`/`vle32`、qemu 8.2 输出 `SELFTEST_PASS` 与 `15,3,35,325`。
- M2:`docs/NATIVE_ABI.md`(类型映射、FixedArray 指针/长度/布局、所有权与借用、对齐、修改入参规则、布局探针与 40 用例验证、`rvv_selftest` 契约)与 `docs/CROSS_COMPILE.md`(clang/gcc 分工、`MOON_CC` 契约、手动与一键配方、预期输出、限制、故障排查)落地;README 增加交叉入口,`docs/README.md` 地图把两份文档移入已存在。
- M2:CI 的 native probe 断言更新为两行(`SELFTEST_PASS` + `15,3,35,325`)。
- M3:`bench/` 裸机 C harness(`crt0.S`、`link.ld`、`platform_htif.c`、`bench.h`、`main.c`,以及 `kernels.c` / `kernels_rvv.c` 三档内核)——不是 MoonBit 包、无 `moon.pkg`、不参与 `moon` 构建;三档共用同一份驱动,只替换内核对象。
- M3:`scripts/bench.sh` 一条命令构建 3 个 ELF(scalar / auto / rvv),用 spike(`--isa=rv64gcv_zicntr`)各跑两遍,解析 5 原语 × 3 规模 × 3 档 = 45 行,生成 `bench/results.md`;脚本内断言:每档 15 行、同一 ELF 连跑两次 instret 与 chk 逐位相同、三档 checksum 相同、`bench/` 与 `scripts/` 中无 cycle CSR 读取、rvv 档 VLPROBE 为 `vlenb=16 vlen=128 vlmax(e32m1)=4`。
- M3:`docs/BENCHMARKS.md` 落地:口径(只认 spike 退休指令数,不认 QEMU 计数器,指令数≠周期)、环境与 VLEN、N 与 REPS、45 行结果表与 5×3 相对 scalar 比值矩阵、向量化诊断、结论、限制(等价 C 内核而非 MoonBit 产物、无硬件、单 VLEN、单数据分布、编译器版本绑定)、复现与断言;README 增加基准入口,`docs/README.md` 把 BENCHMARKS 移入已存在并把 `bench/results.md` 登记为生成物。

### Notes / Deviations

- M0 骨架与 target 分派探针已完成并合并(native=42、wasm-gc=43);M1 用 5 原语 API 替换该探针。
- `dot` 长度不等 panic:初版按“in-process 不能断言 panic”的前提未写入测试;复核确认工具链支持 `test "panic …"` 约定(发生 panic 即通过)后,已补入 `src/tests/api_test.mbt` 的 `test "panic dot length mismatch"`,wasm-gc 与 native 均 40/40 通过。该约定不断言消息文本,消息另行以代码审查 + 手工运行确认(native 打印 `rvv: dot length mismatch` 并 exit 134;wasm-gc 报 `RuntimeError: unreachable` 并 exit 1)。
- `moon fmt` 会把 `Int` 规范化为 `Int32`;本仓库源码与 SPEC 统一采用 `Int32` 写法,并在 SPEC 中声明 `Int == Int32` 别名。
- M2 偏离与取舍:①GNU `riscv64-linux-gnu-gcc` 11.4 没有 `riscv_vector.h`、不定义 `__riscv_vector`,因此 `kernel.c` 的 RVV 分支只能用 clang-19 交叉编译,链接与其余 C 交给 gcc;②`rvv_selftest` 在没有 `__riscv_vector` 的宿主构建里直接返回 0(不存在 RVV 分支可比较,标量分支由 40 个 native 用例覆盖);③`dot` 的长度检查不进入 C,不等时委托给 `@scalar.dot` 触发既有 panic,避免新增第二个 abort 点使 SPEC §5 的描述失真;④clang 默认 DWARF-5 与 Ubuntu 22.04 binutils 2.38 不兼容,包装器固定 `-gdwarf-4` 以保持 `objdump`/`readelf` 输出干净;⑤无 RISC-V 硬件,RVV 结论全部来自 qemu 8.2,不产出性能数字(M3 用 spike 指令数口径)。
- M2 交叉脚本使用 `--target-dir scripts/.toolchain/build`(git-ignored),避免 RV64 产物与宿主 `_build/native` 混用;qemu 8.2 位于 `~/qemu82`,系统 6.2 不支持 V。
- M3 偏离与取舍:①计划 M3 出口条件写的是"生成 `bench/results.md`,9 行"(首轮只有 scan/count/filter 三个原语),本次按里程碑要求覆盖 **5 原语 × 3 档 × 3 规模 = 45 行**,每行含 VLEN/编译器/N/REPS/checksum,并在 BENCHMARKS §4.1 注明该差异;②REPS 按规模固定为 16/8/4(每次测量元素访问数 16 384 / 65 536 / 262 144),目的是同时控制单次测量区间长度与全流程总元素量(约 5.2 M),三档各跑两遍的 spike 总耗时约 6~8 s;③构建产物全部落在 `_build/bench/`(`_build/` 已被现有 `.gitignore` 忽略),没有修改 `.gitignore`;④`bench/results.md` 作为里程碑证据入库,理由:M3 出口条件点名该文件、`docs/BENCHMARKS.md` 的数字直接引用它,且文件不含时间戳、同环境重跑逐字节相同;⑤如实标注不利结果:auto 档只有 3/5 内核被自动向量化(`k_prefix_sum`/`k_filter` 未向量化),手写 RVV 档在 `prefix_sum` 上比标量多 25% 指令,auto 档在 `sum`/`count_ge`/`dot` 上优于手写档(LLVM 用更大 LMUL),不凑数、不调参掩盖;⑥`bench/` 与 `scripts/` 中不出现 cycle CSR 的读取(连注释也不出现该字面量),以便 D7 的 `grep` 断言为 0 命中。
- M3 未改动 `src/**`、`docs/plans/**`、`CONTRIBUTING.md`、`AGENTS.md`、`moon.mod`、`scripts/cross-riscv.sh`、`scripts/run-qemu.sh`;宿主 `moon check` / `moon fmt --check` / `moon test --target wasm-gc` / `moon test --target native` 仍为 exit 0、40/40。
