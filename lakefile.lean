import Lake

open Lake DSL

/-- Root of a UCRT-targeting MinGW toolchain (Windows only). "UCRT MinGW" is
the requirement — any distribution works whose gcc targets
`x86_64-w64-mingw32` with the Universal C Runtime, matching Lean's
`x86_64-w64-windows-gnu` runtime. `scripts/env-windows.sh` detects and
validates one (standard MSYS2 location, then `gcc` on PATH) and exports
`MINGW_UCRT_ROOT`/`MINGW_UCRT_CC`/`MINGW_UCRT_LIBDIR`; building without the
script assumes the standard MSYS2 install. -/
def mingwUcrtRoot : String := run_io
  ((·.getD "C:/msys64/ucrt64") <$> IO.getEnv "MINGW_UCRT_ROOT")

/-- Full path to the Windows C compiler (validated gcc from the env script,
or the standard layout under `mingwUcrtRoot`). -/
def mingwUcrtCc : String := run_io
  ((·.getD s!"{mingwUcrtRoot}/bin/gcc.exe") <$> IO.getEnv "MINGW_UCRT_CC")

/-- Directory holding the Win32 import libraries (`libopengl32.a`, …). The
env script resolves it via `gcc -print-file-name`, which handles MinGW
distributions whose lib dir is not `<root>/lib`. -/
def mingwUcrtLibDir : String := run_io
  ((·.getD s!"{mingwUcrtRoot}/lib") <$> IO.getEnv "MINGW_UCRT_LIBDIR")

/-- C compiler for the raylib binding's FFI shim. Lean's bundled clang cannot
find the platform SDK headers on either OS, so point at a system toolchain:
Apple clang on macOS, a UCRT-targeting MinGW gcc on Windows (matches Lean's
x86_64-w64-windows-gnu / UCRT runtime). -/
def raylibCc : String :=
  if System.Platform.isWindows then mingwUcrtCc
  else "/usr/bin/clang"

require raylib from git
  "https://github.com/KislyjKisel/Raylib.lean" @ "054884afbc8bc65e1df438db2b2ffdabcad427c8"
  with NameMap.empty
    |>.insert `cc raylibCc
    |>.insert `raylib "custom"
    |>.insert `cflags
      "-I.lake/packages/raylib/raylib/build/raylib/include -I.lake/packages/raylib/raylib/src/external/glfw/include"

package "axiom" {
  leanOptions := #[⟨`autoImplicit, false⟩]
}

lean_lib Axiom

def leanSystemLibDir := run_io
  (Option.map (·.systemLibDir)) <$> Lake.findLeanInstall?

/-- When `LEAN_CC` overrides the linker driver (system clang on macOS, UCRT64
gcc on Windows), it does not know Lean's toolchain lib directory, where Lean's
bundled runtime companions live (`libc++`, `libc++abi`, `libuv`, `libunwind`
on Windows). `leanc` would add this path implicitly; a plain system compiler
needs it spelled out. -/
def leanLibSearch : Array String :=
  match leanSystemLibDir with
  | none => #[]
  | some libDir => #[s!"-L{libDir}"]

/- Windows: link with `leanc` (do NOT set LEAN_CC for `lake build`) so Lean's
bundled clang resolves its own runtime (`libc++`, `libuv`, …) from its own
sysroot. Only the Win32 import libraries come from the MSYS2 UCRT64
distribution, which Lean's trimmed sysroot does not carry. -/
def nativeLinkArgs : Array String :=
  if System.Platform.isWindows then #[
    "-L.lake/packages/raylib/raylib/build/raylib",
    s!"-L{mingwUcrtLibDir}",
    "-lraylib",
    "-lopengl32",
    "-lgdi32",
    "-lwinmm",
    "-lshell32",
    "-luser32"
  ]
  else
    leanLibSearch
    ++ #[
      "-mmacosx-version-min=26.0",
      "-L.lake/packages/raylib/raylib/build/raylib",
      "-lraylib",
      "-framework", "CoreVideo",
      "-framework", "IOKit",
      "-framework", "Cocoa",
      "-framework", "GLUT",
      "-framework", "OpenGL"
    ]

@[default_target]
lean_exe "axiom" {
  root := `Main
  moreLinkArgs := nativeLinkArgs
}

lean_exe "axiom_tests" {
  root := `Tests
  moreLinkArgs := nativeLinkArgs
}
