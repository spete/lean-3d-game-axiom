import Lake

open Lake DSL

require raylib from git
  "https://github.com/KislyjKisel/Raylib.lean" @ "054884afbc8bc65e1df438db2b2ffdabcad427c8"
  with NameMap.empty.insert `cc "/usr/bin/clang"

package "axiom" {
  leanOptions := #[⟨`autoImplicit, false⟩]
}

lean_lib Axiom

def leanSystemLibDir := run_io
  (Option.map (·.systemLibDir)) <$> Lake.findLeanInstall?

def nativeLinkArgs : Array String :=
  (match leanSystemLibDir with
   | none => #[]
   | some libDir => #[s!"-L{libDir}"])
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
