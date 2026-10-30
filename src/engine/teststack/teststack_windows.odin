#+build windows
package teststack

// A test build that decodes the 1.3 MB expedition snapshot overflows the 1 MiB
// stack Windows gives an executable: core:encoding/json reserves on the stack a
// field mask the size of the struct for every key (about 6 MB in all), and the
// unoptimised build adds its own copies. The game is not affected: its main
// package already reserves 16 MiB (src/windows_stack.odin), but that file is not
// part of a test build of a single package. Importing this package from a test
// file gives that test executable 32 MiB, as `import _ "../engine/teststack"`.
// The linker flag travels with the package; a foreign import is linked only when
// one of its procedures is referenced.
@(extra_linker_flags = "/STACK:33554432")
foreign import test_stack_reserve "system:kernel32.lib"

@(default_calling_convention = "system")
foreign test_stack_reserve {
	GetCurrentThreadId :: proc() -> u32 ---
}

@(init, private = "file")
reference_test_stack_reserve :: proc "contextless" () {
	_ = GetCurrentThreadId()
}
