# docs/ — 文档枢纽(全量地图)

> **这是整个仓库文档的唯一入口与目录。** 每份文档在这里登记角色、状态与唯一落点。
> **新增或删除任何文档,必须同步本表。**

## 单一真源(SSOT)纪律

每条事实只住一个文件,别处只链接、不复制。复制是文档漂移和死文件的根源。

| 这条信息 | 唯一的家 |
|---|---|
| 是什么 / 为什么 / 安装 / API 概览 | [`README.md`](../README.md) |
| 分支模型 / 提交规则 / 测试约定 / 文档同步 | [`CONTRIBUTING.md`](../CONTRIBUTING.md) |
| 每次改动与关键决策 | [`CHANGELOG.md`](../CHANGELOG.md) |
| API 契约:签名、语义、边界、panic、回绕 | [`SPEC.md`](SPEC.md)(M1) |
| MoonBit↔C ABI、数组布局、所有权 | [`NATIVE_ABI.md`](NATIVE_ABI.md)(M2) |
| RV64 交叉编译配方 | [`CROSS_COMPILE.md`](CROSS_COMPILE.md)(M2) |
| 性能口径、方法、结果、限制 | [`BENCHMARKS.md`](BENCHMARKS.md)(M3) |
| 发布步骤与门禁 | [`RELEASE_CHECKLIST.md`](RELEASE_CHECKLIST.md)(M4) |
| 里程碑、看板、缺陷台账 | [`plans/v0.1.0.md`](plans/v0.1.0.md) |
| agent 入口与硬规矩 | [`AGENTS.md`](../AGENTS.md) |

## 文档地图

### 活文档(已存在)

| 文件 | 角色 | 何时读 |
|---|---|---|
| [`../README.md`](../README.md) | 产品门面:用途、原语表、后端、文档入口 | 想了解项目 |
| [`../CONTRIBUTING.md`](../CONTRIBUTING.md) | 开发圣经:布局、分支、测试、文档同步 | 要改代码 |
| [`../AGENTS.md`](../AGENTS.md) | agent 会话入口与硬规矩 | 开 agent 会话 |
| [`../CHANGELOG.md`](../CHANGELOG.md) | 变更史与偏离 | 想知道改过什么 |
| [`plans/v0.1.0.md`](plans/v0.1.0.md) | v0.1.0 计划:范围、里程碑、看板、缺陷台账 | 执行/审核里程碑 |
| `README.md`(本文件) | 文档枢纽 / SSOT / 全量地图 | 不知道读哪份 |

### 计划中(按里程碑落地)

| 文件 | 角色 | 里程碑 |
|---|---|---|
| `SPEC.md` | API 唯一真源 | M1 |
| `NATIVE_ABI.md` | MoonBit↔C ABI | M2 |
| `CROSS_COMPILE.md` | RV64 交叉配方 | M2 |
| `BENCHMARKS.md` | 性能口径与结果 | M3 |
| `RELEASE_CHECKLIST.md` | 发布门禁 | M4 |

## 阅读顺序

- 新会话:`AGENTS.md` → `README.md` → `CONTRIBUTING.md` → 计划。
- 动 API:先读 `SPEC.md`(M1 起)。
- 做 RVV / 交叉:先读 `CROSS_COMPILE.md`(M2 起)。
- 发版:先读 `RELEASE_CHECKLIST.md`(M4 起)。

## 规则

1. 新文档必须在上表登记角色与唯一落点;删除文档同步删行。
2. 文档之间只链接,不复制事实。
3. 文档改动随对应 milestone 分支提交,不单独漂移。
