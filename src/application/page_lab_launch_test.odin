package application

import "core:testing"

@(test)
test_page_lab_launch_is_selected_and_keeps_runtime_arguments :: proc(t: ^testing.T) {
	options := DEFAULT_RUNTIME_OPTIONS
	for argument in ([2]string{"--page-lab", "--smoke-page-lab"}) {
		launch, rest := split_launch_arguments({argument, "--seed=42"})
		defer delete(rest)
		testing.expect(t, launch.page_lab)
		testing.expect_value(t, launch.smoke_page_lab, argument == "--smoke-page-lab")
		testing.expect_value(t, len(rest), 1)
		if len(rest) == 1 { testing.expect_value(t, rest[0], "--seed=42") }
		testing.expect_value(t, page_lab_launch_error(launch, &options), "")
	}
	// Both spellings select the same workshop; smoke still implies its scene.
	launch, rest := split_launch_arguments({"--page-lab", "--smoke-page-lab"})
	defer delete(rest)
	testing.expect(t, launch.page_lab && launch.smoke_page_lab && len(rest) == 0)
	testing.expect_value(t, page_lab_launch_error(launch, &options), "")
}

@(test)
test_page_lab_rejects_conflicting_launcher_modes_in_either_order :: proc(t: ^testing.T) {
	options := DEFAULT_RUNTIME_OPTIONS
	for other in ([?]string{"--run", "--expedition", "--smoke-expedition", "--smoke-hub", "--smoke-hub-world",
		"--editor-mappe", "--smoke-editor-mappe", "--smoke-menu", "--minigame=arena", "--smoke-minigame=arena", "--minigame="}) {
		for first in ([2]bool{false, true}) {
			args := [2]string{"--smoke-page-lab", other}
			if first { args = {other, "--smoke-page-lab"} }
			launch, rest := split_launch_arguments(args[:])
			defer delete(rest)
			testing.expect(t, len(rest) == 0)
			testing.expect(t, page_lab_launch_error(launch, &options) != "", other)
		}
	}
}

@(test)
test_page_lab_cannot_be_ignored_by_direct_runtime_routing :: proc(t: ^testing.T) {
	launch, rest := split_launch_arguments({"--page-lab"})
	defer delete(rest)
	for argument in ([?]string{"--mechanics-lab", "--spell-lab", "--dice-lab", "--dice-set-lab",
		"--engine-lab", "--ring-lab", "--fps-lab", "--playtest-output=report.json"}) {
		options := DEFAULT_RUNTIME_OPTIONS
		roguelike_parse_arguments(&options, {argument})
		testing.expect(t, page_lab_launch_error(launch, &options) != "", argument)
	}
	options := DEFAULT_RUNTIME_OPTIONS
	roguelike_parse_arguments(&options, {"--smoke-mechanics-lab"})
	testing.expect(t, page_lab_launch_error(launch, &options) != "")
	// No new restriction is imposed on invocations that do not select this lab.
	testing.expect_value(t, page_lab_launch_error({}, &options), "")
}
