#+build windows
package main

// Windows reserves 1 MiB for the main thread, macOS 8 MiB. The unoptimised
// build keeps every branch-local Room/report value in its own stack slot, so
// startup and card plays need more than 1 MiB. The linker flag travels with the
// package, so plain `odin run src -o:none` works without extra arguments.
// A foreign import is linked only when one of its procedures is referenced.
@(extra_linker_flags = "/STACK:16777216")
foreign import windows_stack_reserve "system:kernel32.lib"

@(default_calling_convention = "system")
foreign windows_stack_reserve {
	GetCurrentThreadId :: proc() -> u32 ---
}

@(init, private = "file")
reference_windows_stack_reserve :: proc "contextless" () {
	_ = GetCurrentThreadId()
}
