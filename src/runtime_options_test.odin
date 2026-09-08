package main

import "core:testing"

@(test)
test_runtime_options_accept_reproducible_seed_speed_and_report_path :: proc(t: ^testing.T) {
	options := DEFAULT_RUNTIME_OPTIONS
	testing.expect(t, !options.debug_abilities)
	testing.expect(t, !options.spell_lab)
	arguments := [?]string{
		"--seed=0xC0FFEE", "--animation-speed=2.5", "--playtest-output=/tmp/my report.json",
		"--sprites=/tmp/my sprites/pack.json",
	}
	for argument in arguments {
		handled, ok := apply_runtime_option(&options, argument)
		testing.expect(t, handled && ok)
	}
	testing.expect_value(t, options.seed, u64(0xC0FFEE))
	testing.expect_value(t, options.animation_speed, f32(2.5))
	testing.expect_value(t, options.playtest_output, "/tmp/my report.json")
	testing.expect_value(t, options.sprite_manifest, "/tmp/my sprites/pack.json")
	handled, ok := apply_runtime_option(&options, "--fast")
	testing.expect(t, handled && ok)
	testing.expect_value(t, options.animation_speed, f32(4))
	handled, ok = apply_runtime_option(&options, "--debug-abilities")
	testing.expect(t, handled && ok && options.debug_abilities)
	handled, ok = apply_runtime_option(&options, "--spell-lab")
	testing.expect(t, handled && ok && options.spell_lab)
	handled, ok = apply_runtime_option(&options, "--dice-lab")
	testing.expect(t, handled && ok && options.spell_lab && options.dice_lab)
	handled, ok = apply_runtime_option(&options, "--spell-lab")
	testing.expect(t, handled && ok && options.spell_lab && !options.dice_lab)
	seed, seed_ok := parse_run_seed("18446744073709551615")
	testing.expect(t, seed_ok)
	testing.expect_value(t, seed, max(u64))
}

@(test)
test_runtime_options_reject_invalid_values_without_mutation :: proc(t: ^testing.T) {
	options := DEFAULT_RUNTIME_OPTIONS
	invalid := [?]string{
		"--seed=", "--seed=-1", "--seed=0x", "--seed=18446744073709551616", "--seed=12xyz",
		"--animation-speed=0", "--animation-speed=5", "--animation-speed=NaN",
		"--animation-speed=Inf", "--animation-speed=2junk", "--playtest-output=", "--sprites=",
	}
	for argument in invalid {
		handled, ok := apply_runtime_option(&options, argument)
		testing.expect(t, handled && !ok)
		testing.expect_value(t, options, DEFAULT_RUNTIME_OPTIONS)
	}
}
