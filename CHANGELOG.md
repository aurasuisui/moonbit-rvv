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

### Notes / Deviations

- M0 骨架与 target 分派探针已完成并合并(native=42、wasm-gc=43);M1 用 5 原语 API 替换该探针。
- `dot` 长度不等 panic:初版按“in-process 不能断言 panic”的前提未写入测试;复核确认工具链支持 `test "panic …"` 约定(发生 panic 即通过)后,已补入 `src/tests/api_test.mbt` 的 `test "panic dot length mismatch"`,wasm-gc 与 native 均 40/40 通过。该约定不断言消息文本,消息另行以代码审查 + 手工运行确认(native 打印 `rvv: dot length mismatch` 并 exit 134;wasm-gc 报 `RuntimeError: unreachable` 并 exit 1)。
- `moon fmt` 会把 `Int` 规范化为 `Int32`;本仓库源码与 SPEC 统一采用 `Int32` 写法,并在 SPEC 中声明 `Int == Int32` 别名。
