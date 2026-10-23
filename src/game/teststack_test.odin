package game

// Without this the tests of this package hang on Windows when run on their own:
// the unoptimised build overflows the 1 MiB default stack (see engine/teststack).
import _ "../engine/teststack"
