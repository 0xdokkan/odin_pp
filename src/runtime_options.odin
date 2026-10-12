package main

import "core:strconv"
import "core:strings"
import game "game"
import render "render"

Runtime_Options :: struct {
	seed: u64,
	tactical: game.Tactical_Config,
	scene_3d: bool,
	perspective: bool,
	m7_smoke, m7_view_smoke: bool,
	m8_view_smoke: bool,
	western_smoke: bool,
	// PROVA MECCANICHE: the endless sandbox (mechanics_lab.odin) and its capture.
	mechanics_lab, mechanics_lab_smoke: bool,
	arena_view_smoke: bool,
	animation_speed: f32,
	debug_abilities: bool,
	playtest_output: string,
	sprite_manifest: string,
	spell_lab: bool,
	dice_lab: bool,
	dice_set_lab, dice_set_smoke: bool,
	m9_lab: render.M9_Kind,
	m9_smoke: bool,
}

DEFAULT_RUNTIME_OPTIONS :: Runtime_Options{seed = 0xC0FFEE, animation_speed = 1, tactical = game.DEFAULT_TACTICAL_CONFIG, scene_3d = true, perspective = true}

// Il parser standard della toolchain non segnala overflow degli interi.
parse_run_seed :: proc(value: string) -> (seed: u64, ok: bool) {
	digits := value
	base := u64(10)
	if strings.has_prefix(digits, "0x") {
		digits = digits[2:]
		base = 16
	}
	if len(digits) == 0 {
		return
	}
	for digit in digits {
		amount: u64
		switch {
		case digit >= '0' && digit <= '9':
			amount = u64(digit-'0')
		case digit >= 'a' && digit <= 'f':
			amount = u64(digit-'a')+10
		case digit >= 'A' && digit <= 'F':
			amount = u64(digit-'A')+10
		case:
			return 0, false
		}
		if amount >= base || seed > (max(u64)-amount)/base {
			return 0, false
		}
		seed = seed*base+amount
	}
	return seed, true
}

apply_runtime_option :: proc(options: ^Runtime_Options, argument: string) -> (handled, ok: bool) {
	if options == nil {
		return false, false
	}
	if argument == "--classic" { options.tactical.enabled = false; options.scene_3d = false; return true, true }
	if argument == "--m7" { options.tactical.enabled = true; return true, true }
	if argument == "--m8" { options.tactical.enabled = true; return true, true }
	if argument == "--m9" { options.tactical.enabled = true; return true, true }
	if argument == "--engine-lab" || argument == "--arena-lab" {options.m9_lab=.Arena;return true,true}
	if argument == "--ring-lab" {options.m9_lab=.Ring;return true,true}
	if argument == "--fps-lab" {options.m9_lab=.FPS;return true,true}
	if argument == "--smoke-m9-view" {options.m9_smoke=true;return true,true}
	if argument == "--smoke-m8-view" { options.m8_view_smoke = true; return true, true }
	if argument == "--smoke-western" { options.western_smoke = true; return true, true }
	if argument == "--mechanics-lab" { options.mechanics_lab = true; return true, true }
	if argument == "--smoke-mechanics-lab" { options.mechanics_lab_smoke = true; return true, true }
	if argument == "--smoke-arenas-view" { options.arena_view_smoke = true; return true, true }
	if argument == "--dice-set-lab" { options.dice_set_lab = true; return true, true }
	if argument == "--smoke-dice-set" { options.dice_set_smoke = true; return true, true }
	if argument == "--flat" { options.scene_3d = false; return true, true }
	if argument == "--perspective" { options.perspective = true; return true, true }
	if argument == "--orthographic" { options.perspective = false; return true, true }
	if argument == "--no-fog" { options.tactical.vision_size = 0; return true, true }
	if argument == "--smoke-m7" { options.m7_smoke = true; return true, true }
	if argument == "--smoke-m7-view" { options.m7_view_smoke = true; return true, true }
	if strings.has_prefix(argument, "--decision-time=") {
		value, valid := strconv.parse_int(argument[len("--decision-time="):])
		valid = valid && value >= 1 && value <= 60
		if valid { options.tactical.timer_seconds = value }
		return true, valid
	}
	if strings.has_prefix(argument, "--vision=") {
		value, valid := strconv.parse_int(argument[len("--vision="):])
		valid = valid && value != 0 && game.valid_tactical_vision(value)
		if valid { options.tactical.vision_size = value }
		return true, valid
	}
	if strings.has_prefix(argument, "--qte-time=") {
		value, valid := strconv.parse_f32(argument[len("--qte-time="):])
		valid = valid && value >= 0.2 && value <= 5
		if valid { options.tactical.qte_seconds = value }
		return true, valid
	}
	if strings.has_prefix(argument, "--seed=") {
		seed, valid := parse_run_seed(argument[len("--seed="):])
		if valid {
			options.seed = seed
		}
		return true, valid
	}
	if strings.has_prefix(argument, "--animation-speed=") {
		speed, valid := strconv.parse_f32(argument[len("--animation-speed="):])
		valid = valid && speed >= 0.25 && speed <= 4
		if valid {
			options.animation_speed = speed
		}
		return true, valid
	}
	if argument == "--fast" {
		options.animation_speed = 4
		return true, true
	}
	if argument == "--debug-abilities" {
		options.debug_abilities = true
		return true, true
	}
	if argument == "--spell-lab" {
		options.spell_lab = true
		options.dice_lab = false
		return true, true
	}
	if argument == "--dice-lab" {
		options.spell_lab = true
		options.dice_lab = true
		return true, true
	}
	if strings.has_prefix(argument, "--playtest-output=") {
		path := argument[len("--playtest-output="):]
		if len(path) == 0 {
			return true, false
		}
		options.playtest_output = path
		return true, true
	}
	if strings.has_prefix(argument, "--sprites=") {
		manifest := argument[len("--sprites="):]
		if len(manifest) == 0 { return true, false }
		options.sprite_manifest = manifest
		return true, true
	}
	return false, true
}
