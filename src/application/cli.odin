package application
import "core:fmt"
import "core:os"

roguelike_parse_arguments :: proc(options: ^Runtime_Options, args: []string) {
	for argument in args {
		handled, valid := apply_runtime_option(options, argument)
		if !valid {
			if runtime_option_is_retired(argument) {
				fmt.eprintf("%s: modalità ritirata; il gioco usa il tattico 3D.\n", argument)
			} else {
				fmt.eprintf("invalid option: %s\n", argument)
			}
			os.exit(2)
		}
		if handled {
			continue
		}
		if argument == "--playtest-report" {
			options.playtest_report = true
		} else if argument == "--smoke-playtest" {
			options.smoke_playtest = true
			options.smoke_mode_count += 1
		} else {
			fmt.eprintf("unknown option: %s\n", argument)
			os.exit(2)
		}
	}
	if options.m7_smoke { options.smoke_mode_count += 1 }
	if options.m7_view_smoke { options.smoke_mode_count += 1 }
	if options.m8_view_smoke { options.smoke_mode_count += 1 }
	if options.western_smoke { options.smoke_mode_count += 1 }
	if options.mechanics_lab_smoke { options.smoke_mode_count += 1 }
	if options.effect_window_smoke { options.smoke_mode_count += 1 }
	if options.arena_view_smoke { options.smoke_mode_count += 1 }
	if options.dice_set_smoke { options.smoke_mode_count += 1 }
	if options.m9_smoke { options.smoke_mode_count += 1 }
	if options.m9_lab != .None || options.m9_smoke {
		if options.spell_lab || options.dice_set_lab || options.dice_set_smoke ||
		   (options.m9_lab != .None && options.smoke_mode_count > 0) || options.playtest_report || len(options.playtest_output) > 0 {
			fmt.eprintln("M9 labs cannot be combined with other labs, reports or smoke modes")
			os.exit(2)
		}
	}
	if (options.dice_set_lab || options.dice_set_smoke) &&
	   (options.spell_lab || (options.dice_set_lab && options.smoke_mode_count > 0)) {
		fmt.eprintln("dice set lab cannot be combined with another lab or smoke")
		os.exit(2)
	}
	if options.mechanics_lab && (options.spell_lab || options.dice_set_lab ||
	   options.m9_lab != .None || options.smoke_mode_count > 0 || options.playtest_report) {
		fmt.eprintln("the mechanics lab cannot be combined with another lab, report or smoke")
		os.exit(2)
	}
	if options.smoke_mode_count > 1 {
		fmt.eprintln("choose exactly one --smoke* mode")
		os.exit(2)
	}
	if len(options.playtest_output) > 0 && !options.smoke_playtest {
		options.playtest_report = true
	}
	if options.playtest_report && options.smoke_playtest {
		fmt.eprintln("--playtest-report is interactive; use --smoke-playtest for headless telemetry")
		os.exit(2)
	}
	if options.spell_lab && (options.smoke_mode_count > 0 || options.playtest_report) {
		fmt.eprintln("--spell-lab is a standalone practice arena; run it without smoke or report options")
		os.exit(2)
	}

}

roguelike_requires_direct_start :: proc(options: ^Runtime_Options) -> bool {
	return options.smoke_mode_count > 0 || options.spell_lab || options.dice_set_lab ||
	       options.m9_lab != .None || options.playtest_report || options.mechanics_lab
}
