package devtools

import render "../render"

Tool_Options :: struct {
	m7_smoke, m7_view_smoke, m8_view_smoke, western_smoke: bool,
	mechanics_lab_smoke, effect_window_smoke, arena_view_smoke: bool,
	dice_set_lab, dice_set_smoke: bool,
	m9_lab: render.M9_Kind,
	m9_smoke, smoke_playtest: bool,
	smoke_mode_count: int,
}
