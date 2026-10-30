#+build windows
package main

// Laptops with two graphics cards hand an unknown program the weaker, built-in
// one. These two exported values are the drivers' documented way for a game to
// ask for the dedicated card: NVIDIA Optimus reads the first, AMD PowerXpress
// the second. Asked for by the user on 25 October 2026 (Fase 0 of
// docs/piano-profondita.md), when the game turned out to draw on Intel graphics
// beside an RTX 3060. A machine with one card ignores both.
@(export, link_name = "NvOptimusEnablement")
nv_optimus_enablement: u32 = 1

@(export, link_name = "AmdPowerXpressRequestHighPerformance")
amd_power_xpress_request_high_performance: i32 = 1
