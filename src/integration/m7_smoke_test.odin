package integration
import devtools "../devtools"

import "core:testing"

@(test)
test_m7_headless_route_with_large_encounters_reaches_a_deterministic_terminal_state :: proc(t: ^testing.T) {
	// This route reached the expanded boss but spent its 10,000-iteration
	// budget mostly counting cast frames, with only 2,543 commands executed.
	first, ok := devtools.tactical_route_sample(0xC0FFEE)
	second, repeated := devtools.tactical_route_sample(0xC0FFEE)
	testing.expect(t, ok && repeated)
	testing.expect_value(t, first, second)
	testing.expect(t, first.outcome == "Victory" || first.outcome == "Defeat")
	testing.expect(t, first.commands > 0 && first.commands < 10000)
}
