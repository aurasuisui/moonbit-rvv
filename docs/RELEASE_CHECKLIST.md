# RELEASE CHECKLIST — 发布门禁(v0.1.0 / M4)

> **本文件是"发布步骤与门禁"的唯一真源**(见 [`docs/README.md`](README.md) 的 SSOT 表)。
> 逐层执行 Tier 0 → Tier 4,同层内顺序无关;**任一断言失败即停止发布**,修完从失败层的上一层重跑。
> 不可逆动作(`moon publish`、`git tag`、`git push`)由**人类**执行;执行会话只准备到 Tier 4 的 `--dry-run`。

## 0. 适用范围与角色

| 角色 | 范围 |
|---|---|
| 执行会话(agent) | Tier 0–3 全部;Tier 4 只跑 `moon publish --dry-run`。**不** `moon login`、不 publish、不打 tag、不 push |
| 人类发布者 | Tier 4 的实际 `moon publish`、`git tag` / `git push`、发布后验证与回滚决策 |

- 目标版本:`0.1.0`(`moon.mod` 的 `version`;zip 文件名、CHANGELOG 标题必须一致)。
- 发布分支:`main`(只收里程碑 `--no-ff` 合并与发布提交,规则见 [`CONTRIBUTING.md`](../CONTRIBUTING.md))。
- 环境:WSL Ubuntu 22.04;`moon`、`clang-19`、`riscv64-linux-gnu-gcc`、`riscv64-unknown-elf-gcc`、
  `~/qemu82`(qemu-user 8.2)、`~/spike`(1.1.1)。版本基线见 [`CROSS_COMPILE.md`](CROSS_COMPILE.md) §2 与
  [`BENCHMARKS.md`](BENCHMARKS.md) §2。
- 一次性前置:

```bash
cd /mnt/c/Users/aurasui/Desktop/moonbit-dev/moonbit-rvv
export PATH=$HOME/.moon/bin:$PATH
mkdir -p _build/release
```

## 记法与证据落点

每条 = **勾选框 / 命令 / 预期 / 证据落点**。勾选条件:命令**原样跑过**,且输出与"预期"逐条一致。

| Tier | 证据落点 |
|---|---|
| 0 主机门禁 | CI 运行记录(ubuntu-22.04 的 `Host gates (wasm-gc + native)` job)+ 本地 `_build/release/t0-*.log` |
| 1 交叉 / RVV | 本地 `_build/release/t1-*.log`;产物在 `scripts/.toolchain/build/` |
| 2 基准 / 对拍 | 本地 `_build/release/t2-*.log`;`_build/bench/`、`_build/bench-control/`、`_build/parity/` 下的原始日志 |
| 3 打包 / 安装 | 本地 `_build/release/t3-*.log`;`_build/publish/`;本节 T3.4 的实测输出 |
| 4 发布 | 本节 T4.1 的实测输出;CHANGELOG 的 `[0.1.0]` 条目;mooncakes 页面与 tag sha |

- `_build/` 已被 `.gitignore` 忽略,**日志不入库**;需要长期留存的结论写进 `CHANGELOG.md` 的发布条目与提交信息。
- 性能数字只有一个家:[`bench/results.md`](../bench/results.md)(生成物)+ [`BENCHMARKS.md`](BENCHMARKS.md)(口径),
  本文件**不复述**任何数字。CI 不跑 RVV(Tier 1–2 只能本地跑,计划 R6,README 已写明)。

## Tier 0 — 主机门禁(CI 同款,必过)

- [ ] **T0.1 类型检查** — `moon check`
  - 预期:exit 0(`Check passed`)。
  - 证据:CI `Check` 步骤;`_build/release/t0-check.log`。
- [ ] **T0.2 格式** — `moon fmt --check`
  - 预期:exit 0,且没有文件被改写(`git status` 干净)。
  - 证据:CI `Format` 步骤;`_build/release/t0-fmt.log`。
- [ ] **T0.3 wasm-gc 测试** — `moon test --target wasm-gc`
  - 预期:`Total tests: 40, passed: 40, failed: 0.`
  - 证据:CI `Test wasm-gc` 步骤;`_build/release/t0-test-wasm-gc.log`。
- [ ] **T0.4 native 测试** — `moon test --target native`
  - 预期:同上,40/40。
  - 证据:CI `Test native` 步骤;`_build/release/t0-test-native.log`。
- [ ] **T0.5 两个 target 构建** — `moon build --target wasm-gc` / `moon build --target native`
  - 预期:均 exit 0。
  - 证据:CI `Build wasm-gc` / `Build native` 步骤;`_build/release/t0-build.log`。
- [ ] **T0.6 探针 wasm-gc** — `moon run --target wasm-gc src/probe`
  - 预期:stdout 恰为 `15,3,35,325`。
  - 证据:CI `Probe wasm-gc` 步骤;`_build/release/t0-probe-wasm-gc.log`。
- [ ] **T0.7 探针 native** — `moon run --target native src/probe`
  - 预期:两行,`SELFTEST_PASS` 与 `15,3,35,325`(C 自检先跑,见 [`NATIVE_ABI.md`](NATIVE_ABI.md))。
  - 证据:CI `Probe native` 步骤;`_build/release/t0-probe-native.log`。

## Tier 1 — RV64 交叉与 RVV 正确性(仅 WSL,CI 不覆盖)

- [ ] **T1.1 工具链基线** — `clang-19 --version` / `riscv64-linux-gnu-gcc --version` / `$HOME/qemu82/bin/qemu-riscv64 --version`
  - 预期:与 [`CROSS_COMPILE.md`](CROSS_COMPILE.md) §2 基线一致(clang 19.x、gcc 11.4.0、qemu 8.2.x);
    qemu 主版本必须 ≥ 8(系统 6.2 没有 RVV)。
  - 证据:`_build/release/t1-toolchain.log`;版本变化要在 CHANGELOG 记偏离。
- [ ] **T1.2 交叉 + qemu 自检** — `bash scripts/cross-riscv.sh`
  - 预期:exit 0,且输出同时满足:
    - `kernel.o` 的 `.comment` 段由 clang 编译(RVV intrinsics 只能 clang 编);
    - `file` / `readelf -h` 显示 ELF64、`Machine: RISC-V`;
    - 产物含 `vsetvli` 与 `vle32`(各 ≥ 1;基线 19 / 12);
    - qemu 输出含 `SELFTEST_PASS` 与 `15,3,35,325`。
  - 证据:脚本 stdout → `_build/release/t1-cross.log`;产物 `scripts/.toolchain/build/`(git-ignored)。
- [ ] **T1.3 双分支逐元素相等** — `bash scripts/run-qemu.sh "$(find scripts/.toolchain/build/native -name probe.exe -print -quit)"`
  - 预期:输出 `SELFTEST_PASS`(随后是冒烟行 `15,3,35,325`)。`rvv_selftest` 对 n = 0,1,2,3,5,7,17,1024 逐个比较
    5 原语的 C 标量 / RVV 两分支;失败时探针打印 `SELFTEST_FAIL:<code>` 而不是 `SELFTEST_PASS`。
  - 证据:T1.2 的交叉产物 + 本命令输出 → `_build/release/t1-selftest.log`;契约见 [`NATIVE_ABI.md`](NATIVE_ABI.md)。

## Tier 2 — 基准、控制实验与发布内核对拍(仅 WSL)

- [ ] **T2.1 基准主表** — `bash scripts/bench.sh`
  - 预期:exit 0;输出含 `PARITY_OK` 与 `BENCH_OK`;主表 45 行(5 原语 × 3 规模 × 3 档);
    脚本自带的 6 条断言全部通过(每档 15 条 RESULT / 两遍逐位相同 / 三档 checksum 相同 / 无 cycle CSR 读取 /
    VLEN=128 / 发布内核对拍),见 [`BENCHMARKS.md`](BENCHMARKS.md) §7。
  - 证据:`_build/release/t2-bench.log`;`_build/bench/` 下的 ELF、两次运行日志与 `parity.log`。
- [ ] **T2.2 生成物无漂移** — `git status --porcelain bench/results.md`
  - 预期:无输出(重跑后 `bench/results.md` 与入库版本逐字节相同,即文档与生成物一致,D9)。
  - 证据:T2.1 之后执行;数字的唯一真源仍是 `bench/results.md` + [`BENCHMARKS.md`](BENCHMARKS.md)。
- [ ] **T2.3 发布内核 vs 基准内核对拍** — `bash scripts/bench_parity.sh`
  - 预期:exit 0;输出 `A1 PARITY_OK`、`A2 PARITY_OK` 与末行 `PARITY_OK`;
    A1(gcc `-march=rv64gc`,标量分支)与 A2(clang `-march=rv64gcv`,RVV 分支)的 kernel 对象向量指令数分别为
    **0** 与 **> 0**(未装 `llvm-objdump` 时该条跳过并注明)。
  - 范围:`auto` 档没有发布侧对应物,**不在**对拍内(见 [`BENCHMARKS.md`](BENCHMARKS.md) §7.1)。
  - 证据:`_build/release/t2-parity.log`;`_build/parity/run_A1.log`、`run_A2.log`。
- [ ] **T2.4 控制实验** — `bash scripts/bench_control.sh`
  - 预期:exit 0,以 `CONTROL_OK` 结束;控制表与 [`BENCHMARKS.md`](BENCHMARKS.md) §4.4 一致
    (每个控制 ELF 两遍逐位一致、N=8192 的 checksum 与主表对应行相同)。
  - 证据:`_build/release/t2-control.log`;`_build/bench-control/control-table.md`。
- [ ] **T2.5 口径卫生** — `grep -rn --binary-files=without-match --exclude-dir=.toolchain 'rd[c]ycle' bench scripts`
  - 预期:无输出(0 命中),即 `bench/` 与 `scripts/` 不读取 cycle CSR(D7);性能口径只认 spike 退休指令数。
    (正则 `rd[c]ycle` 是刻意的:这样检查命令本身不会在脚本里写出该字面量,T2.1 的断言 4 用同样方式复查。)
  - 证据:`_build/release/t2-metric-grep.log`;T2.1 日志中的断言清单。

## Tier 3 — 打包与干净目录安装

- [ ] **T3.1 发布内容清单** — `moon package --list`
  - 预期:exit 0;清单含 `src/native/kernel.c`(D1 的关闭条件),并含 `moon.mod`、`src/tests/`、`bench/`、
    `docs/`、`scripts/`;清单的文件条目数与 T3.2 的 zip 文件数一致。
  - 证据:`_build/release/t3-package-list.log`。
- [ ] **T3.2 打 zip** — `moon package`
  - 预期:输出 `Package to .../_build/publish/aurasuisui-rvv-0.1.0.zip`;zip 名中的版本 = `moon.mod` 的 `version`。
  - 证据:`_build/publish/`(git-ignored);`unzip -l` 输出 → `_build/release/t3-zip-list.log`。
- [ ] **T3.3 干净目录自建自测** — 解包到**仓库之外**的临时目录,在解包目录里自建 + 自测
  - 命令:

```bash
CLEAN=$(mktemp -d)
unzip -q _build/publish/aurasuisui-rvv-0.1.0.zip -d "$CLEAN/pkg"
cd "$CLEAN/pkg"
moon check
moon test --target wasm-gc     # 40/40
moon test --target native      # 40/40
moon run --target native src/probe    # SELFTEST_PASS + 15,3,35,325
moon run --target wasm-gc src/probe   # 15,3,35,325
rm -rf "$CLEAN"
```

  - 预期:`src/native/kernel.c` 在包里;`moon check` 通过;两个 target 各 40/40;两个探针输出如上。
  - 这一步证明:**发布 zip 是自足的**(src/bench/docs/scripts 全在包内),且包内公开 API 在 40 个黑盒用例下通过。
  - 证据:`_build/release/t3-clean.log`(临时目录用完即删)。
- [ ] **T3.4 消费者工程 `moon add`** — 在一个全新的干净工程里安装发布包
  - **发布前(现状)**:`moon add aurasuisui/rvv@0.1.0` 预期失败。2026-11-13 实测(exit 255):

```text
Registry index updated successfully
Symbols updated successfully
Error: module `aurasuisui/rvv` was not found in the registry
```

    这是**预期阻塞**(包还没发布),不是缺陷;它同时说明"用本地拷贝到 `.mooncakes/` 伪装安装"不可行 ——
    实测仅把包拷进 `.mooncakes/aurasuisui/rvv` 而不经 registry,`moon check` 仍报
    `Cannot find import 'aurasuisui/rvv' in someone/consumer@0.1.0`。**不要绕过。**
  - **发布后(必须补做)**:`moon new` 一个干净工程 → `moon add aurasuisui/rvv@0.1.0` →
    在 `moon.pkg` 里 `import { "aurasuisui/rvv" }` → 写 S1/S2 消费者用例(5 个原语各一条)→
    `moon test --target wasm-gc` 与 `moon test --target native` 均通过。
  - 证据:发布前的失败输出 `_build/release/t3-moon-add.log` + 本节实测行;发布后追加消费者工程日志与 CHANGELOG。
- [ ] **T3.5 版本一致性** — `grep '^version' moon.mod` / `unzip -l ...zip` / `CHANGELOG.md`
  - 预期:三处都是 `0.1.0`;`git status -uall` 干净(构建产物与 `pkg.generated.mbti` 不入库)。
  - 证据:`_build/release/t3-version.log`。

## Tier 4 — 发布(人类门禁)

- [ ] **T4.1 发布预演** — `moon publish --dry-run`
  - 预期:exit 0,输出表明校验通过且**没有**创建 release;若因认证/网络失败,原样记录并把该条标成人类门禁,
    **不得**用 `moon login` 或输入凭据绕过。
  - 证据:`_build/release/t4-publish-dry-run.log`;原样输出见下方 T4.1 实测输出。
- [ ] **T4.2 实际发布(仅人类)** — `moon publish`
  - 前置:Tier 0–3 全绿、T4.1 exit 0、`git status` 干净、当前在 `main`、人类已 `moon login`。
  - 预期:registry 上出现 `aurasuisui/rvv@0.1.0`;`moon view aurasuisui/rvv` 能看到该版本。
  - 证据:mooncakes 页面 URL + 终端输出 → CHANGELOG 的 `[0.1.0]` 条目。
- [ ] **T4.3 打 tag 与推送(仅人类)** — `git tag -a v0.1.0 -m "v0.1.0"` / `git push origin v0.1.0`
  - 前置:先把发布提交 push 到 `main`,再 push tag;tag 必须指向 `main` 上的发布提交。
  - 预期:`git describe --tags` 指向发布提交;`git ls-remote --tags origin` 可见 `v0.1.0`。
  - 证据:发布提交 sha + tag 对象 sha 记入 CHANGELOG。
- [ ] **T4.4 发布后验证(人类/CI)** — `moon add aurasuisui/rvv@0.1.0`(干净工程)→ `moon test --target wasm-gc` / `moon test --target native`
  - 预期:补齐 T3.4 的"发布后"步骤:add 成功、消费者工程 S1/S2 在两个 target 通过;`main` 上 CI 绿。
  - 证据:消费者工程日志 → `_build/release/t4-after-publish.log` + CI 运行链接。
- [ ] **T4.5 CHANGELOG 收尾** — `grep -n '^## \[0.1.0\]' CHANGELOG.md`
  - 预期:命中 `[0.1.0] - YYYY-MM-DD` 标题,且条目含版本对比链接、偏离与已知债(无 RVV 硬件、CI 不跑 RVV、
    Windows native 不支持、基准测的是等价 C 内核)。
  - 证据:CHANGELOG diff。


## 回滚与异常处理

| 情形 | 动作 |
|---|---|
| Tier 0–3 任一失败 | 停止,不发布;修复后从该层重跑(必要时从 Tier 0 重跑)。 |
| `moon publish --dry-run` 非 0 | 原样记录;区分"认证/网络"与"包内容"问题。认证/网络 → 挂起等人类;包内容 → 修复后重跑整个清单。 |
| 已发布版本有缺陷 | `moon deprecate aurasuisui/rvv@0.1.0`(registry 不删版本),CHANGELOG 记原因;**不得**用同一版本号重发。 |
| tag 打错 | 未 push:删本地 tag 重打;已 push:**不 force push**,改发补丁版本 `v0.1.1` 并在 CHANGELOG 说明。 |
| 文档与产物漂移 | 以生成物/脚本为准(`bench/results.md`、`moon package --list`),修文档后重跑清单(D9)。 |

## 本次(M4)执行状态

| 项 | 状态 |
|---|---|
| Tier 0 | 已跑(见 M4 验收报告;`_build/release/t0-*.log`) |
| Tier 1 | 已跑(`bash scripts/cross-riscv.sh` exit 0) |
| Tier 2 | 已跑(`bench.sh` / `bench_parity.sh` / `bench_control.sh` 均 exit 0) |
| Tier 3 | 已跑(T3.1–T3.3、T3.5);T3.4 为**发布后**步骤,现在按预期阻塞 |
| Tier 4.1 | 已跑,**被认证阻塞**,原样输出见下 |
| Tier 4.2–4.5 | **未执行**,等人类口令(agent 不 publish / 不打 tag / 不 push) |

### T4.1 实测输出(2026-11-13,`moon 0.1.20261104`)

```text
$ moon publish --dry-run
Registry login is required; run `moon login`
Error: `moon publish` failed

$ echo $?
255
```

**判定:明确阻塞(认证),人类门禁。** 该失败**不**代表包内容有问题 —— `moon publish` 在校验包之前就要求 registry 登录。
执行会话按规矩不 `moon login`、不输入凭据、不重试绕过;人类登录后需重跑 T4.1,确认 exit 0 再进 T4.2。
