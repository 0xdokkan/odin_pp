package run

import game "../game"

Options :: struct {
	seed: u64,
	tactical: game.Tactical_Config,
	perspective: bool,
	animation_speed: f32,
	debug_abilities: bool,
	playtest_output, sprite_manifest: string,
	spell_lab, dice_lab, mechanics_lab: bool,
	playtest_report: bool,
	procedural_rooms, persist_profile: bool,
}

DEFAULT_OPTIONS :: Options{
	seed = 0xC0FFEE,
	animation_speed = 1,
	tactical = game.GAME_TACTICAL_CONFIG,
	perspective = true,
	procedural_rooms = true,
	persist_profile = true,
}
