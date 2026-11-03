package advisor

import game "../game"

// WHAT THE IA KNOWS OF EVERY FOE (docs/piano-ia.md, Fase 2; the rule for ever: «La regola per sempre»). The switch has
// no default: a new archetype does not build until it has its line here.
//
// - danger: how much the threat of its blow, still to come past the horizon, weighs in the evaluation (1 is a blow's
//   own damage, at the weight of the life it takes);
// - kill: what killing it is worth (the user's +10 for every foe; the room's guardians, which end the fight, 20).
Enemy_Knowledge :: struct {
	danger: f32,
	kill: f32,
}

enemy_knowledge :: proc(archetype: game.Enemy_Archetype) -> Enemy_Knowledge {
	switch archetype {
	case .Chaser: return {danger = 1, kill = KILL_VALUE}
	// Its arrow flies along a line: out of the line it misses.
	case .Archer: return {danger = 1, kill = KILL_VALUE}
	// The cleave over three cells and the charge: the heaviest blows of the four.
	case .Brute: return {danger = 1.2, kill = KILL_VALUE}
	// The bomb lands on a cell said beforehand and burns around it.
	case .Bomber: return {danger = 1, kill = KILL_VALUE}
	case .Custodian: return {danger = 1.2, kill = 2*KILL_VALUE}
	case .Demolitionist: return {danger = 1.2, kill = 2*KILL_VALUE}
	case .Count:
	}
	return {danger = 1, kill = KILL_VALUE}
}

// The user's weights (docs/piano-ia.md, «La valutazione»).
// A point of life lost weighs three points of damage done.
LIFE_WEIGHT :: f32(3)
DAMAGE_WEIGHT :: f32(1)
KILL_VALUE :: f32(10)
// Death is the worst branch of all, always: below any count of life, damage and kills.
DEATH_VALUE :: f32(-1e6)
// A fight won is worth its kills, and the rest of the run: a little more.
WIN_VALUE :: f32(5)

// The position's few points (an influence map's idea): a blow still to land past the horizon on the player's cell
// counts half its life; every way out of the cell, a little; a step from the weakest foe, a little; in line with an
// archer's clear line, a little less.
THREAT_WEIGHT :: f32(0.5)
EXIT_VALUE :: f32(0.1)
CLOSE_VALUE :: f32(0.05)
ARCHER_LINE_VALUE :: f32(-0.5)
// A real hand may miss the defence keys: once in four (a proposal), and then the blow lands; a step out of the blow
// risks nothing. The diagonal's two keys: a little, so a straight step is advised when it is enough.
MISS_CHANCE :: f32(0.25)
// A blow struck at once is worth a fifth more than the same at the horizon (search.odin, «the tempo»).
TEMPO_WEIGHT :: f32(0.2)
DIAGONAL_RISK :: f32(0.2)
// What a refocus as the first move costs a branch that sets a device down, at most (search.odin, play_path).
REFOCUS_PRICE :: f32(2)
