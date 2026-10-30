#+build !windows
package teststack

// Nothing to reserve: macOS and Linux give an executable 8 MiB of stack. This
// file only lets `import _ "../engine/teststack"` build on those systems.
