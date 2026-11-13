# CROSS_COMPILE — RV64 交叉构建与 qemu 验证(v0.1.0)

> **本文件是 RV64 交叉配方的唯一真源**:从零复现的完整步骤、clang/gcc 分工、`MOON_CC` 包装器、`-march`、sysroot、qemu 命令、预期输出与已知限制。
> 脚本实现见 `scripts/cross-riscv.sh`;ABI 规则见 [NATIVE_ABI.md](NATIVE_ABI.md);API 语义见 [SPEC.md](SPEC.md)。

## 1. 这份配方能证明什么

把 native 探针交叉编译成 RV64 ELF 并在 qemu 8.2 上运行,验证:

1. `src/native/kernel.c` 的 RVV intrinsics 分支能被 clang-19 编译(而不是被静默替换成标量);
2. 产物里确实有 RVV 指令(`vsetvli` / `vle32`);
3. `rvv_selftest` 在 qemu 里通过:C 标量分支与 RVV 分支对 5 个原语 × 8 个规模逐元素相等;
4. MoonBit 公开 API 在 RV64 上的冒烟输出与 wasm-gc 一致(`15,3,35,325`)。

没有 RISC-V 硬件;所有 RVV 结论来自 qemu(spike 用于 M3 的指令数,不在本文件范围)。

## 2. 环境依赖

WSL Ubuntu 22.04 下的实测版本:

| 组件 | 版本 | 用途 |
|---|---|---|
| MoonBit | `moon 0.1.20261104 (940aa18)` | 构建 native 包与探针 |
| clang | `Ubuntu clang 19.1.7` | **只编译** `kernel.c`(提供 `riscv_vector.h` 与 RVV intrinsics) |
| riscv64-linux-gnu-gcc | `11.4.0` | 编译 MoonBit 生成的 C 与运行时、**链接** |
| riscv64-linux-gnu binutils | `2.38` | `ar` / `ranlib` / `objdump` / `readelf` |
| qemu-user | `8.2.2`(`~/qemu82/bin/qemu-riscv64`) | 执行 RVV 产物 |

安装:

```bash
sudo apt-get update
sudo apt-get install -y clang-19 gcc-riscv64-linux-gnu binutils-riscv64-linux-gnu \
                        qemu-user file binutils
# qemu-user 6.2(22.04 默认)没有 RVV;需要 8.x,例如自建到 ~/qemu82。
# MoonBit 装到 ~/.moon,使用时 export PATH=$HOME/.moon/bin:$PATH
```

`scripts/run-qemu.sh` 优先使用 `~/qemu82/bin/qemu-riscv64`,也可用环境变量 `QEMU_RISCV64` 指定;版本低于 8 会直接报错而不是给出误导性的 SIGILL。

## 3. 为什么是 clang 编 `kernel.c`、gcc 链接

这三条都实测过(命令可复跑):

1. **gcc 11.4 没有 RVV 头文件、也不定义 `__riscv_vector`**:

   ```bash
   find /usr -name riscv_vector.h            # 只在 /usr/lib/llvm-19/... 下
   printf '#ifdef __riscv_vector\nyes\n#else\nno\n#endif\n' > /tmp/m.c
   riscv64-linux-gnu-gcc -march=rv64gcv -mabi=lp64d -E -P /tmp/m.c   # no
   clang-19 --target=riscv64-linux-gnu --sysroot=/usr/riscv64-linux-gnu \
            -march=rv64gcv -mabi=lp64d -E -P /tmp/m.c                # yes
   ```

2. **clang-19 能编译 RVV intrinsics**(`kernel.c` 用的就是这套):

   ```bash
   clang-19 --target=riscv64-linux-gnu --sysroot=/usr/riscv64-linux-gnu \
            -march=rv64gcv -mabi=lp64d -O2 -c src/native/kernel.c -o /tmp/kernel.o
   ```

3. **clang 不能负责链接**(加了 `--sysroot` 后找不到 crt/libgcc/libc_nonshared):

   ```text
   /usr/bin/riscv64-linux-gnu-ld: cannot find crtbeginS.o: No such file or directory
   /usr/bin/riscv64-linux-gnu-ld: cannot find -lgcc: No such file or directory
   /usr/bin/riscv64-linux-gnu-ld: cannot find /usr/riscv64-linux-gnu/lib/libc.so.6 ...
   ```

   因此 **链接交给 `riscv64-linux-gnu-gcc`**,并且不要给它 `--sysroot`(它的默认 sysroot 就是 `/usr/riscv64-linux-gnu`)。两边生成的 ELF64 LP64D 目标文件可以直接混合链接。

## 4. `MOON_CC` 包装器契约

MoonBit native 后端对 `$MOON_CC` 的调用(实测,来自一个记录 argv 的包装器):

```text
$MOON_CC -dumpmachine
$MOON_CC -o <obj> -I$HOME/.moon/include -g -c -fwrapv -fno-strict-aliasing \
          -ffp-contract=off -O2 ... <src.c>
$MOON_CC -o <exe> <objs...> <archives...> -lm $HOME/.moon/lib/libbacktrace.a
```

另外它要求 **`ar` / `ranlib` 与 `$MOON_CC` 在同一目录**(否则报 `failed to resolve native archiver executable`)。

包装器据此按输入文件名分派:`kernel.c` 交给 clang(`--target` + `--sysroot` + `-march=rv64gcv -mabi=lp64d`),其余(生成的 C、运行时、链接)交给交叉 gcc(`-march=rv64gcv -mabi=lp64d`)。脚本生成的内容:

```bash
#!/usr/bin/env bash
set -euo pipefail
CLANG=${RVV_CLANG:-clang-19}
GCC=${RVV_GCC:-riscv64-linux-gnu-gcc}
SYSROOT=${RVV_SYSROOT:-/usr/riscv64-linux-gnu}
want_clang=0
for arg in "$@"; do
  case "$arg" in */kernel.c|kernel.c) want_clang=1 ;; esac
done
if [ "$want_clang" -eq 1 ]; then
  exec "$CLANG" --target=riscv64-linux-gnu --sysroot="$SYSROOT" \
    -march=rv64gcv -mabi=lp64d -gdwarf-4 "$@"
fi
exec "$GCC" -march=rv64gcv -mabi=lp64d "$@"
```

`-gdwarf-4` 的原因:clang-19 默认生成 DWARF-5,而 Ubuntu 22.04 的 binutils 2.38 读不了其中的 rnglists,会刷 `Unrecognized form: 0x22`;固定 DWARF-4 后 `objdump` / `readelf` 输出干净,且保留调试信息。

## 5. 一键复现

```bash
cd /mnt/c/Users/aurasui/Desktop/moonbit-dev/moonbit-rvv
bash scripts/cross-riscv.sh
echo $?        # 0
```

脚本会:

1. 检查依赖(`moon`、`clang-19`、`riscv64-linux-gnu-gcc/ar/ranlib/objdump`、`file`、`readelf`、sysroot);
2. 生成 `scripts/.toolchain/cc`(上面的包装器)与 `ar` / `ranlib` 符号链接;
3. 清空并重建 `scripts/.toolchain/build`,用 `MOON_CC` 跑 `moon build --target native --target-dir scripts/.toolchain/build`,避免与宿主 `_build/native` 混用;
4. 断言 `kernel.o` 的 `.comment` 里是 clang(证明 RVV 分支由 clang 编译);
5. `file` / `readelf -h` 断言 ELF64 RISC-V;
6. `objdump -d | grep -c vsetvli` 与 `vle32` 断言 ≥ 1;
7. 用 `scripts/run-qemu.sh`(优先 qemu 8.2)运行,断言输出含 `SELFTEST_PASS` 与 `15,3,35,325`。

## 6. 手动逐步复现(不依赖脚本)

```bash
cd /mnt/c/Users/aurasui/Desktop/moonbit-dev/moonbit-rvv
export PATH=$HOME/.moon/bin:$PATH

# 1) 包装器目录
mkdir -p scripts/.toolchain
#    把 §4 的脚本写到 scripts/.toolchain/cc 并 chmod +x
ln -sf "$(command -v riscv64-linux-gnu-ar)"     scripts/.toolchain/ar
ln -sf "$(command -v riscv64-linux-gnu-ranlib)" scripts/.toolchain/ranlib

# 2) 交叉构建(独立 target-dir,不要覆盖宿主构建)
MOON_CC="$PWD/scripts/.toolchain/cc" \
  moon build --target native --target-dir scripts/.toolchain/build

# 3) 产物
B=scripts/.toolchain/build/native/debug/build
EXE=$B/probe/probe.exe
readelf -p .comment $B/kernel.o          # 应出现 clang version 19.1.7
file "$EXE"                              # ELF 64-bit ... UCB RISC-V ... double-float ABI
readelf -h "$EXE" | grep Machine         # Machine: RISC-V
riscv64-linux-gnu-objdump -d "$EXE" | grep -c vsetvli   # 19
riscv64-linux-gnu-objdump -d "$EXE" | grep -c vle32     # 12

# 4) qemu(8.2;system 6.2 不支持 V)
~/qemu82/bin/qemu-riscv64 -cpu rv64,v=true -L /usr/riscv64-linux-gnu "$EXE"
```

第 4 步的预期 stdout:

```text
SELFTEST_PASS
15,3,35,325
```

stderr 会出现 qemu 自己的提示 `vector version is not specified, use the default value v1.0`,说明 V 扩展已启用。

## 7. 实测输出(一次完整运行)

```text
== toolchain
   moon:   moon 0.1.20261104 (940aa18 2026-11-04)
   clang:  Ubuntu clang version 19.1.7 (...)
   gcc:    riscv64-linux-gnu-gcc (Ubuntu 11.4.0-1ubuntu1~22.04) 11.4.0
   qemu:   qemu-riscv64 version 8.2.2
== moon build --target native (MOON_CC=.../scripts/.toolchain/cc)
Finished. moon: ran 35 tasks, now up to date
== kernel object compiler (readelf -p .comment)
String dump of section '.comment':
  [     1]  Ubuntu clang version 19.1.7 (...)
== file
...: ELF 64-bit LSB pie executable, UCB RISC-V, RVC, double-float ABI, ... with debug_info, not stripped
== readelf -h
  Machine:                           RISC-V
  Flags:                             0x5, RVC, double-float ABI
== RVV instructions in artifact (riscv64-linux-gnu-objdump -d)
   vsetvli: 19
   vle32:   12
== qemu run (8.x user-mode, -cpu rv64,v=true)
qemu: qemu-riscv64 version 8.2.2 (/home/aura/qemu82/bin/qemu-riscv64)
vector version is not specified, use the default value v1.0
SELFTEST_PASS
15,3,35,325
== OK: RVV branch present in the artifact and self test passed under qemu
```

## 8. 已知限制

- 无 RISC-V 硬件;RVV 行为只在 qemu 8.2 上验证,qemu 的向量版本提示为 v1.0,默认 VLEN=128。
- 系统 `/usr/bin/qemu-riscv64`(6.2)没有 V,遇到 `vsetvli` 会非法指令;必须用 8.x。
- 宿主 native(x86_64)只编译 C 标量分支;**RVV 分支只能在交叉产物里验证**。
- 不做运行时 CPU 探测:是否走 RVV 由编译期 `__riscv_vector` 决定。
- clang 负责编译、gcc 负责链接与其余 C;clang 单独链接会缺 crt/libgcc(§3)。
- binutils 2.38 读 clang 默认 DWARF-5 会告警,所以 `kernel.c` 固定 `-gdwarf-4`;换成 binutils ≥ 2.40 可去掉该约束。
- Windows/MSVC 的 `native-stub` 不在 v0.1.0 支持范围(见仓库 README)。
- 本配方不产出性能数字;性能口径与结果见 M3 的 `docs/BENCHMARKS.md`。

## 9. 故障排查

| 现象 | 原因 | 处理 |
|---|---|---|
| `fatal error: 'riscv_vector.h' file not found` | 用 gcc 编了 `kernel.c` | 让包装器把 `kernel.c` 分派给 `clang-19` |
| `failed to resolve native archiver executable .../ar` | `MOON_CC` 旁边没有 `ar` | 在包装器同目录放 `ar` / `ranlib` 符号链接 |
| `cannot find crtbeginS.o / -lgcc / libc_nonshared.a` | 用 clang 链接 | 链接交给 `riscv64-linux-gnu-gcc`,且不要传 `--sysroot` |
| qemu 报非法指令 / `Illegal instruction` | 用了 qemu 6.2 | 用 `~/qemu82`(8.2)或设置 `QEMU_RISCV64` |
| `objdump` 刷 `Unrecognized form: 0x22` | clang DWARF-5 与 binutils 2.38 | 保持包装器的 `-gdwarf-4` |
| `vsetvli: 0` | `kernel.c` 没走 clang 或 `-march=rv64gcv` 丢失 | 检查包装器分派与 `readelf -p .comment kernel.o` |
| `SELFTEST_FAIL:600` | 编译了 RVV 但执行计数不符(分支未跑到) | 检查是否真的链接了 clang 编的 `kernel.o` |
