# Axiom on Windows — build, run, and troubleshooting guide

This is the complete guide to building and running Axiom on Windows: the
quick path, the theory of *why* the build is shaped this way, a configuration
reference, and a troubleshooting Q&A covering every failure mode encountered
or anticipated during the port. If you only want to play, read
[Quick start](#2-quick-start) and stop.

Status: the full acceptance suite passes on Windows and the game runs
windowed with correct rendering, audio, saves, and high-DPI layout.

---

## Contents

1. [Prerequisites](#1-prerequisites)
2. [Quick start](#2-quick-start)
3. [How the build works — and why](#3-how-the-build-works--and-why)
4. [Configuration reference](#4-configuration-reference)
5. [Runtime behavior on Windows](#5-runtime-behavior-on-windows)
6. [Verification checklist](#6-verification-checklist)
7. [Troubleshooting Q&A](#7-troubleshooting-qa)
8. [Design decisions FAQ](#8-design-decisions-faq)
9. [Known limitations and future work](#9-known-limitations-and-future-work)

---

## 1. Prerequisites

| Requirement | Purpose | Install |
|---|---|---|
| **elan** (Lean version manager) | Fetches the exact Lean toolchain pinned in `lean-toolchain` | Download `elan-x86_64-pc-windows-msvc.zip` from the [elan releases](https://github.com/leanprover/elan/releases) and run `elan-init.exe -y --default-toolchain none` — works everywhere. (`winget install leanprover.elan` also works *where winget exists*; note that Windows LTSC/Server editions ship without winget, and chocolatey carries no elan package.) |
| **MSYS2 with the UCRT64 toolchain** | C compiler for raylib and the binding's FFI shim | Install [MSYS2](https://www.msys2.org/), then `pacman -S mingw-w64-ucrt-x86_64-toolchain` |
| **CMake ≥ 3.11 and Ninja** | Builds raylib's C library | `pacman -S mingw-w64-ucrt-x86_64-cmake mingw-w64-ucrt-x86_64-ninja`, or any standalone install on PATH |
| **Git for Windows** (git-bash) | Runs the `scripts/*-windows.sh` scripts; submodule fetch | [git-scm.com](https://git-scm.com/) |

Notes:

- **Use the UCRT64 environment**, not MINGW64, not MSYS. §3.2 explains why the
  C runtime must be UCRT — that is a hard requirement, not a preference. MSVC
  is not part of this build; it can compile the C dependencies, but only with
  shims and at a net loss (§8).
- elan's zip is named `elan-x86_64-pc-windows-msvc.zip`. That is a **Rust
  target triple** describing how the elan binary itself was built — elan is
  written in Rust, a fork of rustup, and Rust offers `-pc-windows-msvc` and
  `-pc-windows-gnu` flavors of its own toolchain. It is an accurate name for
  elan and says nothing about the Lean toolchain elan downloads, which is
  `x86_64-w64-windows-gnu`. Irrelevant here; ignore it.
- No Visual Studio and no vcpkg needed. Lean bundles its own clang; you never
  invoke it directly.

## 2. Quick start

From git-bash, in the repository root:

```bash
./scripts/check-windows.sh    # preflight: verify every requirement, with remedies
./scripts/setup-windows.sh    # one-time: fetch deps, build raylib C library
./scripts/build-windows.sh    # build the game and the test suite
./scripts/run-windows.sh      # build if needed, then launch the game
./scripts/package-windows.sh  # optional: distributable zip in dist/
```

The preflight is read-only and reports each requirement as ok/FAIL with the
fix; `setup`/`build` also fail fast with pointers rather than dying deep in
a compile.

Run the acceptance suite:

```bash
./scripts/build-windows.sh axiom_tests
./.lake/build/bin/axiom_tests.exe
```

If MSYS2 is installed somewhere non-standard, set `MINGW_UCRT_ROOT` first
(see [Configuration reference](#4-configuration-reference)).

## 3. How the build works — and why

### 3.1 The pieces

Four kinds of code end up in `axiom.exe`:

1. **Lean code** (the game) — compiled by Lean to C, then to objects.
2. **The binding's FFI shim** — C glue in `Raylib.lean`'s package that
   bridges Lean values to raylib calls.
3. **raylib itself** — a static C library (`libraylib.a`) built from the
   pinned submodule source with CMake.
4. **Lean's runtime** and the support libraries its distribution bundles
   (`libc++`, `libc++abi`, `libuv`, `libunwind`, …) — statically linked, so
   the final exe imports only Windows system DLLs (verified with
   `objdump -p`: `ucrtbase.dll`, `icu.dll`, kernel/user/GDI, …) and runs
   without any toolchain on PATH.

Three different compiler roles are involved, and getting them right is the
entire trick of the port:

| Role | Who does it | Why |
|---|---|---|
| Compile Lean-generated C | Lean's bundled clang (via `leanc`) | It only needs Lean's own headers; the bundled compiler always has those |
| Compile raylib + FFI shim | **UCRT64 gcc** (set as the binding's `cc` option in `lakefile.lean`) | These need real platform SDK headers (Win32, OpenGL), which Lean's trimmed toolchain does not ship |
| **Link the executable** | **`leanc`** (Lean's bundled clang) — *never* an externally set `LEAN_CC` | Only leanc knows where Lean's bundled runtime companions live; see 3.3 |

### 3.2 Why UCRT64 specifically (the ABI story)

Lean's Windows toolchain identifies itself as
**`x86_64-w64-windows-gnu`** (run `lean --version` and look at the triple)
and is built in MSYS2's CLANG64 environment, which targets the
**Universal C Runtime (UCRT)**. Every object linked into the final exe must
agree on two things:

- **C runtime**: UCRT, not the legacy MSVCRT. This rules out MSVCRT-era
  MinGW distributions (e.g. TDM-GCC). *Modern* mingw-w64-builds releases
  target UCRT and do qualify — the env script's signature check (§4) tests the
  property, not the brand. MSVC's `/MD` also targets UCRT, so this criterion
  alone does not exclude MSVC (§8).
- **Link-time ABI**: the final image must be `windows-gnu`, because Lean's
  runtime ships as a MinGW-GNU library set — `libc++.a`, `libc++abi.a`,
  `libunwind.a`, `libmingwex.a`, `libmoldname.a`, `crt2.o` under
  `~/.elan/toolchains/<name>/lib/`. `leanc` produces such an image (§3.3).
  MSVC's `link.exe` cannot: it rejects Lean's C++ runtime objects outright with
  `LNK1143: no symbol for COMDAT section`, because clang emits GNU-style
  COMDATs for the `windows-gnu` target (§8). Note this is a limit on the
  *linker*, not on tooling availability — Lean bundles a complete linker of its
  own, so you never need an external one (§8).

MSYS2's **UCRT64** environment is the recommended distribution: it satisfies
the CRT requirement out of the box, and its objects enter the `leanc` link with
no massaging.
raylib is pure C99, so the usual C++ cross-toolchain hazards (name mangling,
exception models) don't apply — matching the CRT and object format is
sufficient. Compiled C is broadly link-compatible across Windows toolchains.

### 3.3 The linking trap (read this before "improving" the build)

The macOS build sets `LEAN_CC=/usr/bin/clang` globally. Copying that pattern
to Windows (`LEAN_CC=gcc`) **breaks the link**, in two stages:

1. First failure: `cannot find -lc++ -lc++abi -luv`. Lean's runtime is built
   against LLVM's libc++ (not GCC's libstdc++) and needs libuv; those
   libraries live inside the Lean toolchain
   (`~/.elan/toolchains/<name>/lib/`), and gcc has no idea to look there.
2. Adding `-L<toolchain>/lib` gets further but fails with undefined
   `operator delete` / `write` — gcc's linker driver now mixes *its own*
   CRT startup pieces with *Lean's* bundled MinGW pieces, and the two
   halves disagree.

The resolution is to split the roles as in 3.1: **do not set `LEAN_CC` at
all** on Windows. `lake` then invokes `leanc` to link; leanc's bundled clang
resolves Lean's runtime from its own sysroot correctly.

What that sysroot does *not* carry is three of the Win32 import libraries the
game needs. `~/.elan/toolchains/<name>/lib/` ships `libkernel32.a`,
`libuser32.a`, `libshell32.a`, `libadvapi32.a`, `libws2_32.a` and more, but
**not** `libopengl32.a`, `libgdi32.a`, or `libwinmm.a`. The lakefile adds one
`-L{MINGW_UCRT_ROOT}/lib` to supply those three (the link line names all five,
harmlessly — the other two resolve from Lean's own sysroot either way).

(Aside: this is also why the macOS lakefile computes `-L{leanSystemLibDir}`
— on macOS `LEAN_CC` *is* set, so the system clang needs to be told where
Lean's libraries are. The two platforms solve the same problem from
opposite ends.)

### 3.4 What happens in `setup-windows.sh`

1. `lake update` — fetches the Lean packages at their pinned SHAs
   (`Raylib.lean` binding, `pod`, transitively `LSpec`).
2. `git submodule update --init` inside the binding — fetches the pinned
   **raylib C source** (the binding tracks upstream raylib as a submodule).
3. CMake configure + build with UCRT64 gcc and Ninja:
   Release, `BUILD_EXAMPLES=OFF`, `PLATFORM=Desktop` — producing
   `libraylib.a` and headers under
   `.lake/packages/raylib/raylib/build/raylib/`, the exact paths the
   lakefile's `cflags`/link args reference.
   - `SUPPORT_WINMM_HIGHRES_TIMER=ON` deliberately diverges from the
     binding's own build script, which turns it OFF to avoid the winmm
     dependency. We link `-lwinmm` anyway, and without the high-resolution
     timer raylib paces frames with ~15.6 ms sleep granularity — a 60 FPS
     target quantizes to ~30 FPS. Measured on this port: ~6 ms/frame
     improvement from turning it back on.
4. The macOS HiDPI patch in `patches/` is **not applied and not needed**:
   every hunk is guarded by `#if defined(__APPLE__)`.

### 3.5 What happens in `lake build`

Lean compiles ~100 modules (the binding is most of them), the binding's shim
is compiled by UCRT64 gcc (via the `cc` option the lakefile passes), and
leanc links everything with the Windows link set from `nativeLinkArgs`:

```
-L.lake/packages/raylib/raylib/build/raylib   raylib itself
-L{MINGW_UCRT_ROOT}/lib                       opengl32, gdi32, winmm (§3.3)
-lraylib -lopengl32 -lgdi32 -lwinmm -lshell32 -luser32
```

(`shell32` and `user32` resolve from Lean's own sysroot; only the first three
need the added `-L`.)

Renderer: OpenGL 3.3 core via WGL — raylib's desktop default. There is no
DirectX, ANGLE, or Vulkan anywhere; any GPU driver from the last decade
provides GL 3.3.

## 4. Configuration reference

| Variable | Meaning | Default |
|---|---|---|
| `MINGW_UCRT_ROOT` | Root of a UCRT-targeting MinGW toolchain, Windows-style path (e.g. `C:/msys64/ucrt64`) | Detected by `scripts/env-windows.sh`: (1) this variable if set — validated, fails loudly if not viable; (2) the standard MSYS2 location `C:/msys64/ucrt64`; (3) whatever `gcc` is on PATH, if it passes the viability signature below. Building without the script assumes (2) |
| `MINGW_UCRT_CC` | Full path to the validated gcc | Exported by the env script; lakefile falls back to `{MINGW_UCRT_ROOT}/bin/gcc.exe` |
| `MINGW_UCRT_LIBDIR` | Directory containing the Win32 import libraries (`libopengl32.a`, …) | Exported by the env script via `gcc -print-file-name` (handles MinGW layouts where this is not `<root>/lib`); lakefile falls back to `{MINGW_UCRT_ROOT}/lib` |
| `LEAN_CC` | **Must be unset on Windows** (the env script unsets it) | — |
| `PATH` | Must contain the toolchain's `bin` during builds (MSYS2 tools silently fail off-PATH). Not needed to *run* the built exe — it is self-contained | Handled by the scripts |
| `ELAN_HOME` | elan's install/data directory (elan binary, toolchains, settings) | `%USERPROFILE%\.elan`. Fully relocatable: set `ELAN_HOME` before installing/using elan and everything (including toolchain downloads) lives there — verified empirically. The scripts respect it |
| `AXIOM_QA_CAPTURE`, `AXIOM_QA_PLAY`, `AXIOM_QA_HOLD` | QA harness controls (see `Main.lean`) | unset |

**The viability signature.** A candidate gcc is accepted if and only if:

1. `gcc -dumpmachine` prints `x86_64-w64-mingw32` — right ABI family
   (rejects MSVC and MSYS's own gcc);
2. compiling `#include <stdio.h>` defines `_UCRT` — right C runtime,
   matching Lean's (rejects MSVCRT-era MinGW such as TDM-GCC; note that
   modern mingw-w64-builds distributions target UCRT and *are* accepted —
   the signature tests properties, not install locations);
3. `gcc -print-file-name=libopengl32.a` resolves to an existing file —
   the Win32 import libraries the link needs are present, and this lookup
   also yields the correct `-L` directory for any lib layout.

The scripts are thin: everything meaningful lives in
`scripts/env-windows.sh` (single source of truth for toolchain discovery)
and `lakefile.lean` (single source of truth for compiler/linker
configuration).

## 5. Runtime behavior on Windows

- **Saves** live at `%APPDATA%\Axiom\first-light.axm`
  (e.g. `C:\Users\you\AppData\Roaming\Axiom`). Corrupt or incompatible
  saves are renamed to `first-light.corrupt-<ms>.axm` alongside, never
  deleted or overwritten.
- **QA artifacts** (screenshots, metrics, perf) go to `%TEMP%` instead of
  `/tmp`: `axiom-play.png`, `axiom-window-metrics.txt`,
  `axiom-qa-perf.txt`, etc.
- **High-DPI**: with display scaling (125 %, 150 %, …), raylib reports the
  logical size as `screen`, the pixel size as `render`, and the scale via
  `GetWindowScaleDPI` — the same relationship as macOS Retina, so the HUD
  layout code works unchanged. Verified via `--qa-resize`:
  `screen=944x576 render=1180x720 scale=1.25`.
- **The exe is self-contained.** Lean's runtime is statically linked; the
  only imports are Windows system DLLs (verified with `objdump -p` and a
  PATH-stripped run). `axiom.exe` can be run, copied, or zipped on its own
  with no toolchain present.

## 6. Verification checklist

After any toolchain or build change, in order:

1. `./scripts/build-windows.sh axiom_tests` builds with zero errors.
2. `axiom_tests.exe` prints all-✓ lines and
   `All Axiom checks passed.` — this exercises worldgen determinism,
   physics, meshing, the save codec, on-disk save persistence and
   quarantine, audio synthesis: the pure core plus the save I/O path.
3. `axiom.exe --qa-play` opens a window, renders ~130 frames, writes
   `%TEMP%\axiom-play.png` + `%TEMP%\axiom-qa-perf.txt`, and exits by
   itself. Inspect the PNG: island terrain, hotbar centered at the bottom,
   status chip top-left, crosshair centered.
4. `axiom.exe --qa-resize` writes `%TEMP%\axiom-window-metrics.txt`;
   `render` should equal `layout × scale` per axis.
5. Interactive smoke test: title screen → Enter → walk (WASD), mine
   (left-click; sound plays), place (right-click), Esc → pause, Q → title,
   window close → relaunch and confirm the world persisted.

## 7. Troubleshooting Q&A

### Build-time

**Q: `gcc.exe` (or any UCRT64 tool) exits with code 1 and *no output at all*.**
PATH problem. UCRT64 programs resolve their sub-processes (`cc1`, `ld`) and
runtime DLLs (`libstdc++-6.dll`, `libgcc_s_seh-1.dll`, …) via a discoverable
install location, not the literal path you invoked. Invoking
`C:\...\ucrt64\bin\gcc.exe` by full path *without* that directory on PATH
fails silently. Fix: `source scripts/env-windows.sh` (it prepends the bin
dir), or prepend it yourself. If PATH is definitely correct and you still
see silent failures, rule out antivirus/EDR blocking a freshly-installed
unsigned `cc1.exe`/`ld.exe` child process.

**Q: Link fails: `cannot find -lc++: No such file or directory` (also
`-lc++abi`, `-luv`).**
You linked with something other than leanc — almost always because
`LEAN_CC` is set in the environment. Those libraries are Lean's bundled
runtime companions, private to its toolchain directory. Fix: `unset
LEAN_CC` and rebuild. Do **not** "fix" it by adding
`-L~/.elan/toolchains/<...>/lib` and keeping gcc as linker — see the next
question for what happens.

**Q: Link fails: undefined reference to `operator delete(void*)` /
`operator delete[]` / `write` from `libc++abi.a` / `libmingwex.a`.**
The second stage of the same mistake: gcc-as-linker found Lean's libraries
(you added the `-L`) but is now mixing its own CRT startup/runtime halves
with Lean's bundled MinGW pieces, and they disagree. There is no reliable
flag-level fix. Link with leanc: `unset LEAN_CC`.

**Q: Link fails: `cannot find -lopengl32` (or `-lgdi32`, `-lwinmm`).**
Exactly these three import libraries are absent from leanc's sysroot (§3.3);
`kernel32`, `user32` and `shell32` are present there, which is why you never
see this error for them. The lakefile passes `-L{MINGW_UCRT_ROOT}/lib` to
supply the missing three; if you see this error, `MINGW_UCRT_ROOT` is wrong or
points at a non-UCRT64 environment. Check
`ls $MINGW_UCRT_ROOT/lib/libopengl32.a`.

**Q: Compiling the binding's shim fails with missing standard headers
(`stdio.h: No such file or directory` or similar).**
The shim is being compiled by Lean's bundled clang, which has no platform
SDK headers. The lakefile normally prevents this by passing UCRT64 gcc as
the binding's `cc` option — this error means that option didn't reach the
binding (lakefile edited? option renamed upstream?). Verify the `require
raylib ... |>.insert \`cc raylibCc` block in `lakefile.lean`.

**Q: `lake update` warns: `toolchain not updated; multiple toolchain
candidates`.**
Harmless. The raylib binding's own repo declares a different Lean toolchain
than this project; Lake is saying it kept ours (from `lean-toolchain`).
Pinned SHAs make the resolution deterministic either way.

**Q: CMake configure fails to find a compiler / picks MSVC.**
You ran it outside the env script's PATH, so CMake auto-detected whatever else
was installed. Use `setup-windows.sh`, which passes
`-DCMAKE_C_COMPILER="$MINGW_UCRT_CC"` explicitly. An MSVC-built `raylib.lib`
does not link as-is: it hits the `libOLDNAMES.a` / `_fltused` /
`__security_cookie` sequence described in §8.

**Q: Does the `patches/raylib-macos-hidpi-resize.patch` need applying?**
No. Every hunk is `#if defined(__APPLE__)`-guarded; on Windows the patched
and unpatched sources compile identically. `setup-windows.sh` skips it.

### Run-time

**Q: The game runs at ~30 FPS instead of 60 with plenty of GPU headroom.**
raylib was built with `SUPPORT_WINMM_HIGHRES_TIMER=OFF` (the binding's
default on Windows). Without the winmm high-resolution timer, frame pacing
sleeps have ~15.6 ms granularity and a 16.6 ms frame target rounds up to
~31 ms. Rebuild raylib with `-DSUPPORT_WINMM_HIGHRES_TIMER=ON` (what
`setup-windows.sh` does) and relink.

**Q: Frame time is uneven / slow on a laptop or over Remote Desktop.**
Old/integrated GPUs and RDP's software GL path both inflate frame times;
the game is modest (static meshes, no shaders) but does clear + draw the
full island every frame at native resolution. Check
`%TEMP%\axiom-qa-perf.txt` from a `--qa-play` run: `avg_ms` near your
display's refresh interval is healthy; a large `max_ms` at frame 120 is
just the QA screenshot readback, not a real hitch. On hybrid-GPU laptops,
force the dGPU via Windows Settings → Display → Graphics if needed.

**Q: Startup shows the loading screen, then the window freezes /
"Not Responding" for several seconds before the title appears.**
Fixed: initial world meshing previously hit an accidental quadratic and
could take 10+ seconds on slower machines; it now completes in well under
a second. If you still see a multi-second freeze on a current build,
that's a bug worth reporting (include `lake exe axiom_bench` output).

**Q: Mining/placing makes no sound.**
The audio device failed to initialize (the game degrades silently by
design — sounds are `Option`s). Check the console for miniaudio/WASAPI
errors; exclusive-mode audio apps and some USB DACs can block device init.
Sound synthesis itself is covered by the test suite, so the failure is
always at the device layer.

**Q: Where did my world go / how do I reset it?**
`%APPDATA%\Axiom\first-light.axm`. Delete it for a fresh island; the game
also quarantines (never deletes) any save it can't validate, as
`first-light.corrupt-<timestamp>.axm` in the same folder.

**Q: The window is tiny / huge / blurry at 150 % display scaling.**
Report it with `%TEMP%\axiom-window-metrics.txt` from `--qa-resize`. The
invariant that must hold: `render = layout × scale` per axis. It held at
125 % in port testing; a violation at another scale factor would be a real
bug in the `layoutSize` logic, not your setup.

### Environment

**Q: Can I build from PowerShell/cmd instead of git-bash?**
The lakefile and `lake` work anywhere; the convenience scripts are bash.
Minimum PowerShell equivalent:
`$env:PATH = "C:\msys64\ucrt64\bin;$env:USERPROFILE\.elan\bin;$env:PATH"`,
ensure `LEAN_CC` is not set (`Remove-Item Env:LEAN_CC` if it is), then
`lake build`. The one-time raylib CMake build mirrors `setup-windows.sh`.

**Q: Antivirus flagged/quarantined `axiom.exe` or a build tool.**
Freshly-compiled unsigned executables trip heuristics, and this project
compiles both its own exe and (once) a compiler-driven C build. Restore
from quarantine and add the repo + `%USERPROFILE%\.elan` to exclusions, or
sign the binary. Nothing in the build phones home; the only network access
in any script is `lake update`/git fetching pinned dependencies.

## 8. Design decisions FAQ

**Why not MSVC?** Not because it is impossible — because it costs shims and
buys nothing. Everything below was verified against the pinned toolchain with
Visual Studio 2022 and the Windows SDK present.

*MSVC can compile the C dependencies.* `cl /MD` targets the same UCRT as Lean,
both compilers emit COFF, and raylib is pure C, so there is no name mangling or
exception model to reconcile. What differs is MSVC's CRT glue, and each piece
costs a shim:

| Link-time symptom | Cause | Shim |
|---|---|---|
| `could not open 'libOLDNAMES.a'` | MSVC writes `/DEFAULTLIB:"MSVCRT" /DEFAULTLIB:"OLDNAMES"` into every object's `.drectve` section | strip it (`objcopy --remove-section=.drectve`), or satisfy it with empty stub archives |
| `undefined symbol: _fltused` | MSVC's "this TU uses floating point" marker | `int _fltused = 0x9875;` |
| `undefined symbol: __security_cookie`, `__GSHandlerCheck`, … | stack-protector machinery, resident in `libcmt`/`msvcrt.lib` | compile with `/GS- /guard:cf-` |
| `undefined symbol: __chkstk` | stack probes, emitted for frames over ~4 KB — raylib has them | none that is safe |

`__chkstk` is decisive. It cannot be written in C. Suppressing it with `/Gs<n>`
links cleanly and yields a **crashing binary** — verified with a 32 KB frame:
clean link, then a segfault, because the guard-page probes were load-bearing.
The only honest fix is hand-written assembly.

Beyond the shims, Lake passes gcc-style flags (`-c -o out.o -I…`) to the
binding's `cc`, which `cl.exe` does not accept — the C role would also need a
flag-translating wrapper, or LLVM's `clang.exe`. And the list is open-ended:
raylib is far larger than these probes, and every further CRT-glue symbol is one
more shim. UCRT64 gcc needs none of it; its objects link as-is.

*MSVC cannot link.* `link.exe` fed Lean's runtime fails at parse time —
`libleanrt.a(object.cpp.obj) : fatal error LNK1143: no symbol for COMDAT
section` — because clang emits GNU-style COMDATs for the `windows-gnu` target
and MSVC's linker will not read them. It parses leanc's *C* objects fine,
reaching ordinary `LNK2019` symbol resolution; Lean's *C++* runtime is the wall.
Fixing that means rebuilding Lean's runtime for an MSVC target, i.e. the
MSVC-ABI Lean upstream does not ship.

*No external linker is needed regardless.* Lean bundles `clang`, `ld.lld` and
`llvm-ar`. The only thing MinGW supplies that Lean's toolchain lacks is the
three missing import libraries (§3.3) — and the Windows SDK carries those in
`.Lib` form, which `ld.lld` consumes directly (`-lopengl32` resolves
`OpenGL32.Lib` case-insensitively, so the lakefile's link args need no change).
An MSVC-only machine can therefore compile *and* link, with `leanc` linking and
no MinGW installed at all. The obstacle to MSVC is never the linker; it is the
compile-side shims above.

**Why gcc for C but leanc for linking, instead of one compiler for both?**
Because the two jobs have disjoint requirements: compiling raylib needs
platform SDK headers (which only the system toolchain has), linking needs
Lean's private runtime layout (which only leanc knows). Splitting the roles
means each tool does the part it's authoritative for. See §3.3 for what
happens with a single-compiler approach.

**Why MSYS2 UCRT64 and not some other mingw-w64 build or the TDM-GCC that may
already be installed?** A CRT mismatch is what disqualifies a toolchain: Lean
targets UCRT, and an MSVCRT-era distribution (TDM-GCC, older mingw-w64
packagings) mixes C runtimes — the class of bug that surfaces at 2 a.m. as heap
corruption. The requirement is a property, not a brand. A modern
mingw-w64-builds release targets UCRT, qualifies, and passes the env script's
signature check (§4). MSYS2 UCRT64 is the recommendation because it satisfies
the check by construction and is trivial to install, not because it is the only
accepted toolchain.

**Why OpenGL and not something newer?** raylib's desktop backend is GL 3.3
and the game uses no advanced GPU features — vertex-colored static meshes
and the default material. There is nothing a newer API would buy except a
port cost.

**Why is raylib built by an external CMake step instead of by Lake?** It
mirrors the macOS build's structure (the binding's "custom" mode). A
cleaner future model is pinning a patched raylib fork and using the
binding's `submodule` mode — tracked as future work.

## 9. Known limitations and future work

Each item is labeled honestly: **[deferred]** means nothing blocks it — it
was scoped out of the port and is a bounded, known-shape task; **[blocked]**
means it has a real external dependency or unknown.

- **No Windows CI** [deferred, one real unknown]. A `windows-latest` GitHub
  Actions job running the preflight + setup + tests + `--qa-play` is
  mechanical; MSYS2 is installable in CI (`msys2/setup-msys2` action). The
  genuine unknown is whether the hosted runner's display-less GL context
  lets the `--qa-*` window modes run (the headless test suite is
  unaffected). Worst case: CI covers build + tests only.
- **Packaged distribution** [done]. `./scripts/package-windows.sh` builds
  `dist/Axiom-First-Light-v<version>-windows-x86_64.zip` (self-contained
  exe + license bundle, version from `packaging/Info.plist`, spec-conforming
  zip via Windows' built-in bsdtar, SHA-256 alongside). Verified by
  extracting to a fresh directory and running the exe with a system-only
  PATH. Code signing remains optional future work (requires a certificate).
- **Icon / version resource** [deferred]. The `windres` compile itself is
  trivial; what is *not* trivial is linking the resource object cleanly —
  a lakefile link-arg conditional on file existence reintroduces the
  configure-time fragility this build was just audited for. Do it together
  with a proper build step, not as a quick patch.
- **Unify raylib build through the binding (`enableWindowsMingw`) /
  fork-and-pin** [blocked on upstream coordination]. Replacing this repo's
  cmake step (and macOS's patch-in-`.lake` step) with the binding's
  `submodule` mode pointed at a patched raylib fork requires either
  upstreaming the HiDPI patch to raylib or maintaining a fork — a
  cross-repo decision for the maintainer, not a local edit.
- **Frame pacing on old/integrated GPUs** [external]. ~26 ms frames were
  measured on a dated laptop GPU after the timer fix; the residual is
  hardware/driver, not port work. No action unless it reproduces on
  capable hardware.
- **High-DPI beyond 125 %** [needs hardware]. The `render = layout × scale`
  invariant is verified at 100 %/125 % on one machine; 150 %+ and
  multi-monitor mixed-DPI setups are untested — report metrics from
  `--qa-resize` if you see layout issues.
