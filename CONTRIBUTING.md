# Contributing to aurasuisui/rvv

## 环境

开发在 WSL Ubuntu 22.04;仓库在 Windows 路径下,`moon` 在 WSL 中。

```bash
cd /mnt/c/Users/aurasui/Desktop/moonbit-dev/moonbit-rvv
export PATH=$HOME/.moon/bin:$PATH

moon check
moon fmt
moon test --target wasm-gc
moon test --target native
```

RVV 相关(仅 WSL):

```bash
clang-19 --version                    # RVV intrinsics / 汇编
riscv64-linux-gnu-gcc --version       # 11.4.0,交叉链接
qemu-riscv64 -L /usr/riscv64-linux-gnu ./_build/.../probe.exe
~/spike/bin/spike --isa=rv64gcv_zicntr bench/bench.elf
```

## 仓库布局

```
src/                       # 公开包 aurasuisui/rvv
├── lib.mbt                # 公开 API(M0 探针;M1 起 5 原语)
├── dispatch_wasm.mbt      # targets: wasm / wasm-gc / js
├── dispatch_native.mbt    # targets: native → extern "C"
├── scalar/                # M1 起:纯 MoonBit 标量实现(可无条件导入)
├── native/kernel.c        # C 源文件(native-stub 引用),不是包
├── tests/                 # M1 起:黑盒测试(只依赖公开 API)
└── probe/                 # 可执行探针(M0 用;M4 决定去留)
scripts/                   # 交叉编译 / qemu / bench
bench/                     # 裸机 C harness,不是 MoonBit 包
docs/                      # 文档,入口是 docs/README.md
```

原则:**有 `moon.pkg` 的目录才是包**;实现按职责分目录,不把实现文件堆在 `src/` 根;每个包只暴露一件事。target 条件包导入在本工具链不可用,因此 native 侧用文件级 `targets` 隔离,不建 native 子包(见计划 M0 结论)。

## 分支与提交模型

`main` 是受保护基线,只允许三类提交:

1. 仓库初始化;
2. 每个里程碑的 `git merge --no-ff milestone/Mx-<slug>`;
3. 发布提交 / 标签(需人类口令)。

工作规则:

- 每个里程碑从 `main` 拉 `milestone/Mx-<slug>`,所有改动只在该分支。
- 每个里程碑最多 **3 个逻辑提交**;过程性 WIP 在合并前 squash。
- 提交信息:`Mx: <一句话>`;正文列验收命令与关键输出摘要。
- 合并前由 lead 独立复跑验收;子智能体不自评通过、不改看板/台账。
- 不 `git push`、不打 tag、不发布,除非人类明确口令。

## 测试约定

- 黑盒测试放 `src/tests/`,通过 `@aurasuisui/rvv` 公开 API 调用。
- 每个原语至少覆盖 6 类边界:空数组、单元素、全相同值、严格递增、`Int::max`/`Int::min`、长度非 4 的倍数。
- native 测试会编译 `native-stub`,依赖宿主 C 编译器;交叉/裸机验证放 `scripts/`。
- 断言不得为了通过而放宽;测试文件的 diff 是审核重点。

## 文档同步约定(SSOT)

每条事实只住一个文件,别处只链接、不复制:

| 信息 | 唯一落点 |
|---|---|
| API 语义、边界、panic、回绕 | `docs/SPEC.md` |
| 安装、用法、配方入口 | `README.md` |
| 交叉编译步骤与约束 | `docs/CROSS_COMPILE.md` |
| MoonBit↔C ABI | `docs/NATIVE_ABI.md` |
| 性能数字、方法、限制 | `docs/BENCHMARKS.md` |
| 发布步骤与门禁 | `docs/RELEASE_CHECKLIST.md` |
| 分支/提交/测试/文档规则 | 本文件 |
| 变更史与偏离 | `CHANGELOG.md` |
| 文档增删与地图 | `docs/README.md` |

任何改动完成后,按上表更新对应文档;**新增或删除文档必须同步 `docs/README.md`**。

## 验收与审核

- 一次只做一个里程碑;执行者报「待审核」,附四件证据:验证命令原样输出、测试计数、commit 列表、做法与偏离。
- 审核者独立复跑同一命令,并检查 `git diff --stat` 与禁止文件。
- 失败两次即停下问人类,不做补救式重试。

## 提交信息模板

```text
M0: skeleton + target dispatch probe

- native probe returns x+1 via kernel.c
- wasm-gc probe returns x+2 via scalar

Verify:
  moon build --target native      # exit 0
  moon build --target wasm-gc     # exit 0
  moon package --list | grep kernel.c
```
