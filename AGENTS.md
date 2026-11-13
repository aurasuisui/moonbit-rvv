# AGENTS.md

本文件是 agent 在本仓库工作的入口。先读 `docs/README.md`(文档枢纽)与本文件,再读 `docs/plans/v0.1.0.md` 的当前里程碑。

## 这是什么

`aurasuisui/rvv` — MoonBit 的 RISC-V 向量(RVV)数组原语后端:wasm/js 纯 MoonBit 标量,native 走 C,RISC-V 走 RVV intrinsics。它不是 MoonBit 编译器的 RISC-V 后端。

## 硬规矩

1. 一次只做一个里程碑;做完报「待审核」,不自评 ✅、不改看板/台账。
2. 只在 `milestone/Mx-<slug>` 分支提交;`main` 只收初始化、里程碑 `--no-ff` 合并、发布提交。
3. 不改公开 API 语义、不放宽测试断言、不引入依赖,除非计划明确要求。
4. 性能数字只认 spike 退休指令数(`--isa=rv64gcv_zicntr`);禁止用 QEMU 的 rdcycle/rdinstret 下结论。
5. 文档遵守 SSOT:每条事实只住一个文件;新增/删除文档必须同步 `docs/README.md`。
6. 不 push、不打 tag、不发布,除非人类明确口令。
7. 遇到失败或与预期不符,立即停下报告,不做补救式重试。

## 命令

在 WSL 中执行:

```bash
cd /mnt/c/Users/aurasui/Desktop/moonbit-dev/moonbit-rvv
export PATH=$HOME/.moon/bin:$PATH

moon check
moon fmt --check
moon test --target wasm-gc
moon test --target native
moon package --list

bash scripts/cross-riscv.sh          # M0 起
bash scripts/bench.sh                # M3 起
```

## 结构

```
src/           公开包(lib + dispatch + probe/;M1 加 scalar/ + tests/);native/ 只放 kernel.c
scripts/       交叉编译、qemu、bench
bench/         裸机 C harness
docs/          文档枢纽与计划
```

## 文档地图

- `docs/README.md` — 唯一入口、SSOT 表、全量地图
- `docs/plans/v0.1.0.md` — 当前计划、里程碑、缺陷台账、看板
- `docs/SPEC.md` — API 唯一真源(M1)
- `docs/NATIVE_ABI.md` — MoonBit↔C ABI(M2)
- `docs/CROSS_COMPILE.md` — RV64 交叉配方(M2)
- `docs/BENCHMARKS.md` — 口径与结果(M3)
- `docs/RELEASE_CHECKLIST.md` — 发布门禁(M4)

## 当前状态

M0、M1 已完成并合并(M0 结论见计划附录 C;M1 = 5 原语标量实现 + 40 个黑盒用例)。M2 待执行:`kernel.c` 的 C 标量/RVV 双分支、交叉脚本、`docs/NATIVE_ABI.md` 与 `docs/CROSS_COMPILE.md`。
