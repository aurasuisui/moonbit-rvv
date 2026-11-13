# SPEC — API 契约(v0.1.0)

> **本文件是 `aurasuisui/rvv` 五个数组原语的唯一真源**:签名、语义、边界、panic、回绕与整数口径。
> README 只给概览并链接本文件;实现见 `src/scalar/impl.mbt`,黑盒测试见 `src/tests/api_test.mbt`。

## 1. 适用范围

- 包:`aurasuisui/rvv` 0.1.0,公开 API 共 5 个函数。
- 后端:wasm / wasm-gc / js / native(x86_64、aarch64)。
- M1 现状:5 个原语在**所有后端**共用纯 MoonBit 标量实现(`src/scalar/impl.mbt`);native 的 C 内核替换是 M2,签名与语义不因此改变。
- 本文件不覆盖:RVV 实现细节(M2)、交叉编译配方(M2)、性能数字(M3)。

## 2. 签名

```moonbit
pub fn sum(xs : FixedArray[Int32]) -> Int64
pub fn count_ge(xs : FixedArray[Int32], thr : Int32) -> Int32
pub fn prefix_sum(xs : FixedArray[Int32]) -> Unit
pub fn filter(xs : FixedArray[Int32], thr : Int32) -> FixedArray[Int32]
pub fn dot(a : FixedArray[Int32], b : FixedArray[Int32]) -> Int64
```

## 3. 整数口径

| 名称 | 位宽 | 在本 API 中的角色 |
|---|---|---|
| `Int` / `Int32` | 32 位有符号 | 数组元素与阈值的类型。本工具链中 `Int` 是 `#alias(Int32)`,`Int` 与 `Int32` 是**同一个类型**的两个名字。`moon fmt` 会把源码里的 `Int` 规范化为 `Int32`,因此源码与本文件统一写作 `Int32`;计划文档里的 `FixedArray[Int]` 与这里的 `FixedArray[Int32]` 完全等价。 |
| `Int64` | 64 位有符号 | 只用于 `sum` / `dot` 的累加器与返回值。 |
| `FixedArray[T]` | — | 定长数组,元素可变;本 API 的 `T` 固定为 32 位有符号整数。 |

- 比较一律是**有符号** 32 位比较:`x >= thr` 中 `Int32::min` 小于一切其他值,`Int32::max` 大于一切其他值。
- `Int32` 加法按 2^32 取模回绕(二进制补码)。该规则只在 `prefix_sum` 的计算过程中可见;见 §4.3。
- `Int64` 溢出不在本契约的保证范围内;实现按 64 位二进制补码回绕,调用方不应依赖溢出后的值。
- v0.1.0 **不含浮点**(无 f16/f32/f64 版本,无 NaN/Inf 概念),**不含 `@v128`**(不提供 SIMD 向量类型参数或重载)。

## 4. 语义与边界

总则:

- 输入是 `FixedArray[Int32]`,不接受空引用(MoonBit 中 `FixedArray` 非空类型);“空数组”指 `length() == 0`。
- 只有 `prefix_sum` 修改入参;其余四个函数不修改入参。
- 所有函数对任意长度的数组(含 0)都有定义;除 `dot` 的长度检查外没有 panic 条件。
- `O(n)` 时间:`sum` / `count_ge` / `prefix_sum` / `dot` 额外空间 `O(1)`;`filter` 额外空间为结果长度。

### 4.1 `sum(xs) -> Int64`

返回所有元素之和,累加在 `Int64` 中进行。

- 空数组返回 `0`。
- 单个元素返回该元素的 `Int64` 值。
- 中间值**不**按 32 位截断:`sum([2147483647, 2147483647]) == 4294967294`。

### 4.2 `count_ge(xs, thr) -> Int32`

返回满足 `xs[i] >= thr` 的元素个数(含等号)。

- 空数组返回 `0`。
- `thr` 等于某个元素时该元素计入;阈值高于全部元素时为 `0`,低于或等于全部元素时为 `length()`。
- 返回值范围 `0..=xs.length()`。

### 4.3 `prefix_sum(xs) -> Unit`

**原地**前缀和:返回前写入 `xs[i] = xs_orig[0] + ... + xs_orig[i]`;返回 `Unit`。

- 回绕定义:每一步加法是“两个 32 位二进制补码整数相加,结果对 2^32 取模后按二进制补码解释为 32 位有符号整数”。
  例:`prefix_sum([2147483647, 1]) == [2147483647, -2147483648]`;这里不是 `Int64` 的 `2147483648`。
- 空数组是无操作(不 panic、不分配)。
- 单元素数组的结果等于原值(仍按回绕规则重写该元素)。
- 调用方必须预期入参数组被就地改写;需要保留原值时先复制。

### 4.4 `filter(xs, thr) -> FixedArray[Int32]`

返回**新** `FixedArray`,包含所有满足 `xs[i] >= thr` 的元素,并保持它们在原数组中的相对顺序。

- 空数组或无匹配时返回长度为 `0` 的数组(不是 nil)。
- `filter(xs, thr).length() == count_ge(xs, thr)`(对任意输入恒成立)。
- 不修改入参;返回值与入参不共享存储,改写返回值不会影响入参。

### 4.5 `dot(a, b) -> Int64`

返回点积 `Σ a[i] * b[i]`:每个乘积在 `Int64` 中计算,再在 `Int64` 中累加。

- 两个空数组返回 `0`。
- 极值乘积在 `Int64` 内是精确的:`(2^31-1)^2 = 4611686014132420609`,`(-2^31)^2 = 2^62 = 4611686018427387904`。
- 不修改入参。
- **panic 条件**:`a.length() != b.length()` 时 panic,消息文本固定为 `rvv: dot length mismatch`;不截断、不返回部分结果。

## 5. panic 行为

| 函数 | 是否 panic | 条件 |
|---|---|---|
| `sum` | 否 | — |
| `count_ge` | 否 | — |
| `prefix_sum` | 否 | — |
| `filter` | 否 | — |
| `dot` | **是** | `a.length() != b.length()`,消息 `rvv: dot length mismatch` |

M1 的验证口径:`dot` 的长度不等 panic 未纳入 `src/tests/api_test.mbt`(按 M1 任务约定,不写只验证“发生了 panic”的用例),以**代码审查**(`src/scalar/impl.mbt` 中唯一 `abort` 点)+ **手工运行**验证:native 打印 `rvv: dot length mismatch` 并以 `PanicError` 退出(exit 134),wasm-gc 以 `RuntimeError: unreachable` 退出(exit 1)。工具链本身支持核心库使用的 `test "panic …"` 约定,后续里程碑可补成回归用例。

## 6. 非目标(v0.1.0 明确不做)

- 不含浮点原语(不提供 `f32`/`f64` 的 `sum` / `dot` / `filter` 等)。
- 不含 `@v128` 或任何 SIMD 向量类型参数;元素类型固定为 32 位有符号整数。
- 不做运行时 CPU 探测;后端在编译期按 target 选择(M1 全后端同一标量实现,M2 起 native 换 C 内核)。
- 不提供 in-place `filter`、stride/offset/视图版本、错误码返回值或 `Result` 版本。
- 不承诺 RVV/LMUL/尾部处理策略(属 M2 实现自由),只承诺本文件描述的输入输出行为。
- 不承诺性能数字;性能只认 M3 的 spike 退休指令数口径。
