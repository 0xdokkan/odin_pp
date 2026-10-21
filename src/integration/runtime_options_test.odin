package integration
import application "../application"
import render "../render"

import "core:testing"

@(test)
test_tactical_larger_visibility_and_camera_options :: proc(t: ^testing.T) {
	options := application.DEFAULT_RUNTIME_OPTIONS
	testing.expect_value(t, options.tactical.vision_size, 7)
	testing.expect(t, options.perspective)
	for argument in ([?]string{"--m7", "--m8", "--m9", "--vision=5", "--vision=7", "--orthographic"}) {
		handled, ok := application.apply_runtime_option(&options, argument)
		testing.expect(t, handled && ok)
	}
	testing.expect_value(t, options.tactical.vision_size, 7)
	testing.expect(t, !options.perspective)
	handled, valid := application.apply_runtime_option(&options, "--vision=9")
	testing.expect(t, handled && valid)
	testing.expect_value(t, options.tactical.vision_size, 9)
}

@(test)
test_runtime_options_accept_reproducible_seed_speed_and_report_path :: proc(t: ^testing.T) {
	options := application.DEFAULT_RUNTIME_OPTIONS
	testing.expect(t, !options.debug_abilities)
	testing.expect(t, !options.spell_lab)
	arguments := [?]string{
		"--seed=0xC0FFEE", "--animation-speed=2.5", "--playtest-output=/tmp/my report.json",
		"--sprites=/tmp/my sprites/pack.json",
	}
	for argument in arguments {
		handled, ok := application.apply_runtime_option(&options, argument)
		testing.expect(t, handled && ok)
	}
	testing.expect_value(t, options.seed, u64(0xC0FFEE))
	testing.expect_value(t, options.animation_speed, f32(2.5))
	testing.expect_value(t, options.playtest_output, "/tmp/my report.json")
	testing.expect_value(t, options.sprite_manifest, "/tmp/my sprites/pack.json")
	handled, ok := application.apply_runtime_option(&options, "--fast")
	testing.expect(t, handled && ok)
	testing.expect_value(t, options.animation_speed, f32(4))
	handled, ok = application.apply_runtime_option(&options, "--debug-abilities")
	testing.expect(t, handled && ok && options.debug_abilities)
	handled, ok = application.apply_runtime_option(&options, "--spell-lab")
	testing.expect(t, handled && ok && options.spell_lab)
	handled, ok = application.apply_runtime_option(&options, "--dice-lab")
	testing.expect(t, handled && ok && options.spell_lab && options.dice_lab)
	handled, ok = application.apply_runtime_option(&options, "--spell-lab")
	testing.expect(t, handled && ok && options.spell_lab && !options.dice_lab)
	seed, seed_ok := application.parse_run_seed("18446744073709551615")
	testing.expect(t, seed_ok)
	testing.expect_value(t, seed, max(u64))
}

@(test)
test_runtime_options_reject_invalid_values_without_mutation :: proc(t: ^testing.T) {
	options := application.DEFAULT_RUNTIME_OPTIONS
	invalid := [?]string{
		"--classic", "--flat",
		"--seed=", "--seed=-1", "--seed=0x", "--seed=18446744073709551616", "--seed=12xyz",
		"--animation-speed=0", "--animation-speed=5", "--animation-speed=NaN",
		"--animation-speed=Inf", "--animation-speed=2junk", "--playtest-output=", "--sprites=",
		"--decision-time=0", "--decision-time=61", "--decision-time=NaN",
		"--vision=1", "--vision=4", "--qte-time=NaN", "--qte-time=0", "--qte-time=6",
	}
	for argument in invalid {
		handled, ok := application.apply_runtime_option(&options, argument)
		testing.expect(t, handled && !ok)
		testing.expect_value(t, options, application.DEFAULT_RUNTIME_OPTIONS)
	}
}

@(test)
test_runtime_options_choose_the_environment_theme :: proc(t: ^testing.T) {
	options := application.DEFAULT_RUNTIME_OPTIONS
	// The neon world is the default; the gothic look is a hidden option.
	testing.expect_value(t, options.environment_theme, render.Environment_Theme.Neon)
	handled, ok := application.apply_runtime_option(&options, "--theme=gothic")
	testing.expect(t, handled && ok)
	testing.expect_value(t, options.environment_theme, render.Environment_Theme.Gothic)
	handled, ok = application.apply_runtime_option(&options, "--theme=neon")
	testing.expect(t, handled && ok)
	testing.expect_value(t, options.environment_theme, render.Environment_Theme.Neon)
	// The theme combines with every other option and parses like them.
	application.roguelike_parse_arguments(&options, []string{"--seed=7", "--theme=gothic", "--vision=5"})
	testing.expect_value(t, options.environment_theme, render.Environment_Theme.Gothic)
	testing.expect_value(t, options.seed, u64(7))
	testing.expect_value(t, options.tactical.vision_size, 5)
	// Parsing alone never changes what renderers start with: the application
	// sets that when it starts.
	testing.expect_value(t, render.startup_environment_theme_choice(), render.Environment_Theme.Neon)
	for argument in ([?]string{"--theme=", "--theme=Gothic", "--theme=sepia", "--theme=neon "}) {
		fresh := application.DEFAULT_RUNTIME_OPTIONS
		handled, ok = application.apply_runtime_option(&fresh, argument)
		testing.expectf(t, handled && !ok, "%q", argument)
		testing.expect_value(t, fresh, application.DEFAULT_RUNTIME_OPTIONS)
	}
}
