# NATIVE_ABI — MoonBit ↔ C ABI(v0.1.0)

> **本文件是 native 后端 `extern "C"` 边界的唯一真源**:类型映射、数组布局、长度、所有权/借用、对齐、修改入参的规则与验证方法。
> API 语义只在 [SPEC.md](SPEC.md);交叉构建步骤只在 [CROSS_COMPILE.md](CROSS_COMPILE.md);本文件不重复它们。

## 1. 适用范围

- 只覆盖 **native** target:`src/dispatch_native.mbt` 的 5 个 `extern "C"` 声明 ↔ `src/native/kernel.c` 的 5 个导出符号,外加仅供探针使用的 `rvv_selftest`。
- wasm / wasm-gc / js 没有 C 边界,走 `src/scalar/impl.mbt`(`src/dispatch_wasm.mbt`)。
- `kernel.c` 内部还有编译期分支:`__riscv_vector`(clang + `-march=rv64gcv`)选 RVV intrinsics,否则选 C 标量。**该分支不影响 ABI**,两条分支的 C 原型完全相同。

## 2. 调用链

```
@rvv.sum (src/lib.mbt,公开 API)
  └─ sum_impl (src/dispatch_native.mbt;仅 native target)
       └─ extern "C" c_sum ──► kernel.c: int64_t rvv_sum(const int32_t *a, int32_t n)
```

其余 target 的同名 `*_impl` 在 `src/dispatch_wasm.mbt` 里转发 `@scalar`,不经过 C。

## 3. 类型映射

| MoonBit 侧 | C 侧 | 说明 |
|---|---|---|
| `Int32`(源码里也可能写作 `Int`) | `int32_t` | 32 位二进制补码;本工具链中 `Int` 是 `#alias(Int32)`,两者同一类型 |
| `Int64` | `int64_t` | 64 位二进制补码;只用于 `sum` / `dot` 的累加器与返回值 |
| `FixedArray[Int32]` 入参 | `int32_t *` | **指向第 0 个元素的数据指针**,不是对象头;C 不复制该数组 |
| 数组长度 | 单独的 `int32_t` 参数 | MoonBit 传 `xs.length()`,C 以该参数为唯一长度权威 |
| `Unit` 返回值 | `void` | 仅 `prefix_sum` |
| `FixedArray[Int32]` 输出(filter) | `int32_t *` | 由 MoonBit 预分配长度,C 只写入 |

导出的 6 个 C 符号(前 5 个是公开原语,第 6 个只给 native 探针自检):

| C 符号 | C 原型 |
|---|---|
| `rvv_sum` | `int64_t rvv_sum(const int32_t *a, int32_t n)` |
| `rvv_count_ge` | `int32_t rvv_count_ge(const int32_t *a, int32_t n, int32_t thr)` |
| `rvv_prefix_sum` | `void rvv_prefix_sum(int32_t *a, int32_t n)` |
| `rvv_filter` | `int32_t rvv_filter(const int32_t *a, int32_t n, int32_t thr, int32_t *out)` |
| `rvv_dot` | `int64_t rvv_dot(const int32_t *a, const int32_t *b, int32_t n)` |
| `rvv_selftest` | `int32_t rvv_selftest(void)` |

对应的 MoonBit 声明(节选,`#borrow` 是借用标注):

```moonbit
#borrow(xs)
extern "C" fn c_sum(xs : FixedArray[Int32], n : Int32) -> Int64 = "rvv_sum"

#borrow(xs, out)
extern "C" fn c_filter(
  xs : FixedArray[Int32],
  n : Int32,
  thr : Int32,
  out : FixedArray[Int32],
) -> Int32 = "rvv_filter"
```

## 4. 数组布局与对齐

`FixedArray[Int32]` 在 C 侧看到的布局(数据指针 `p` 即传给 C 的地址):

```
p-8:  int32_t rc | uint32_t meta        <- 8 字节对象头
p  :  a[0] a[1] a[2] ...                <- 4 字节步长,元素间无 padding
```

- `meta` 的低 32 位是元素个数。`moonbit.h` 提供 `Moonbit_array_length(obj)`,等价于 `(int32_t)header->meta`。**C 内核不依赖这个宏**:长度由 MoonBit 作为单独参数传入,C 只使用显式 `n`。宏只在验证/调试时使用(见 §8.1)。
- 元素步长固定 4 字节,数据区至少 4 字节对齐(MoonBit 分配对齐不小于 8),所以 `int32_t *` 访问是安全的。
- native 运行时用引用计数、不移动对象;C 调用期间数组地址稳定。
- `filter` 的输出数组与输入数组布局相同,长度由 MoonBit 先算好再交给 C。

## 5. 所有权与借用

- `#borrow(...)` 表示 **MoonBit 保留所有权**:C 不得 `free`、不得 `moonbit_incref/decref`、不得把指针保存到本次调用之后。
- 输入数组:`sum` / `count_ge` / `dot` 只读;`prefix_sum` 允许原地改写(所有权仍在调用方);`filter` 读 `xs`、写 `out`。
- `filter` 的 `out` 长度 = `count_ge(xs, thr)`。C 返回实际写入个数,必须等于该长度,且不得写到第 `n` 个元素之后。
- C 不分配任何 MoonBit 对象、不调用 `moonbit_malloc`,只返回标量。
- 空数组:`n == 0` 合法,C 的循环不执行、不解引用指针。

## 6. 修改入参的规则

| 函数 | 是否修改入参 | 规则 |
|---|---|---|
| `rvv_sum` / `rvv_count_ge` / `rvv_dot` | 否 | 只读 `n` 个元素 |
| `rvv_prefix_sum` | **是** | 覆盖 `a[0..n)`,元素值按 2^32 回绕 |
| `rvv_filter` | 否(读 `a`,写 `out`) | `out` 由调用方持有,写入 `count` 个元素 |

`dot` 长度不等的情况在 **MoonBit 侧**处理,不会进入 C:见 `src/dispatch_native.mbt` 的 `dot_impl`。panic 文案与唯一 abort 点仍归 `src/scalar/impl.mbt`(`docs/SPEC.md` §5)。

## 7. 编译期分支(不影响 ABI)

```c
#if defined(__riscv_vector)
#include <riscv_vector.h>
#define RVV_KERNEL 1
#else
#define RVV_KERNEL 0
#endif
```

- RVV 分支用 intrinsics(`vsetvl` / `vle32` / `vwadd` / `vwmacc` / `vmsge` / `vcpop` / `vcompress` / `vslideup` / `vredsum`)。
- GNU `riscv64-linux-gnu-gcc` 11.4 没有 `riscv_vector.h`、也不定义 `__riscv_vector`,永远走 C 标量;RVV 分支必须用 clang-19 交叉编译(见 [CROSS_COMPILE.md](CROSS_COMPILE.md))。
- 两条分支的 C 原型、所有权、边界与返回值约定完全一致;切换分支不改变本文件的任何规则。

## 8. 验证方法(可复现)

### 8.1 数组布局探针

在一个临时 MoonBit 包里声明 `#borrow` 的数组参数(包需 `options("native-stub": ["native/k.c"])` 与 `pkgtype(kind: "executable")`),C 端打印 `Moonbit_array_length`、对象头大小与首元素:

```c
#include <moonbit.h>
#include <stdint.h>
#include <stdio.h>
int64_t t_sum(int32_t *a, int32_t n) {
  printf("[C] n=%d len_macro=%d sizeof_hdr=%zu a[0]=%d\n",
         n, Moonbit_array_length(a), sizeof(struct moonbit_object), a[0]);
  int64_t s = 0;
  for (int i = 0; i < n; i++) s += a[i];
  return s;
}
```

```moonbit
#borrow(xs)
extern "C" fn extern_sum(xs : FixedArray[Int32], n : Int32) -> Int64 = "t_sum"
pub fn sum(xs : FixedArray[Int32]) -> Int64 { extern_sum(xs, xs.length()) }
fn main { println(sum([1, 2, 3]).to_string()) }
```

`MOON_CC=... moon build --target native` 后运行,实测输出:

```text
[C] n=3 len_macro=3 sizeof_hdr=8 a[0]=1
6
```

解读:`a[0] == 1` 证明指针指向元素数据而非对象头(否则 `a[0]` 是 rc 字);`len_macro == 3` 证明 `p-8` 处的对象头 meta 就是长度;`sizeof_hdr == 8` 与 §4 的布局一致。该探针只用于验证,不进入仓库。

### 8.2 黑盒测试(native,40 例)

```bash
moon test --target native
```

覆盖长度 0/1/2/3/5/7/8、全相同、严格递增、`Int32::max/min`、非 4 倍数等。指针偏移、元素步长或长度传递只要有错,这些用例就会失败。

### 8.3 符号证据(native 测试确实链接了 C 内核)

```bash
nm _build/native/debug/test/tests/tests.blackbox_test.exe | grep ' T rvv_'
```

```text
0000000000041675 T rvv_sum
000000000004167f T rvv_count_ge
0000000000041689 T rvv_prefix_sum
0000000000041693 T rvv_filter
000000000004169d T rvv_dot
```

`dispatch_native.mbt` 的 `extern "C"` 声明编译成对上述符号的调用;host native 测试因此走 **C 标量分支**,不再是纯 MoonBit 标量。

### 8.4 RVV 双分支

`rvv_selftest`(§9)在 RV64 构建里逐元素比较 C 标量与 RVV 分支:`bash scripts/cross-riscv.sh` 输出 `SELFTEST_PASS`。构建与运行细节见 [CROSS_COMPILE.md](CROSS_COMPILE.md)。

## 9. `rvv_selftest` 契约

- 仅由 native 探针调用(`src/probe/main_native.mbt` 的 `extern "C"` 声明),**不是包的公开 API**。
- 在 `__riscv_vector` 构建中,对 `n = 0, 1, 2, 3, 5, 7, 17, 1024` 生成确定性数据(首元素钉 `INT32_MAX`、次元素钉 `INT32_MIN`),对 5 个原语逐元素比较标量与 RVV 分支;同时检查 RVV 入口确实被执行(执行计数)。
- 返回值:0 = 通过;非 0 = 首个失败码,编码为 `100 * primitive + (case_index + 1)`:
  `1xx` sum、`2xx` count_ge、`3xx` prefix_sum、`4xx` filter、`5xx` dot;`600` = 编译了 RVV 分支但没有执行。
- 没有 `__riscv_vector` 的构建里不存在 RVV 分支,函数直接返回 0;此时 C 标量分支由 §8.2 的 40 个 native 用例覆盖。

## 10. 变更规则

改动 `extern "C"` 声明、C 原型、数组布局、所有权或 `rvv_selftest` 返回值,必须同时更新本文件,并重新跑:`moon check`、`moon test --target native`、`bash scripts/cross-riscv.sh`。
