package main

import "core:strconv"
import "core:strings"

Runtime_Options :: struct {
	seed: u64,
	animation_speed: f32,
	debug_abilities: bool,
	playtest_output: string,
}

DEFAULT_RUNTIME_OPTIONS :: Runtime_Options{seed = 0xC0FFEE, animation_speed = 1}

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
	if strings.has_prefix(argument, "--playtest-output=") {
		path := argument[len("--playtest-output="):]
		if len(path) == 0 {
			return true, false
		}
		options.playtest_output = path
		return true, true
	}
	return false, true
}
