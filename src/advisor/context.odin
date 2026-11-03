package advisor

import game "../game"
import grid "../engine/grid"

// THE GAME'S STATE (docs/piano-ia.md, Fase 6): what the IA knows beyond the room. The run and the expedition fill it
// (run/advisor_context.odin: the advisor imports neither); the lab sets its progress with a key. It goes with every
// snapshot, so the worker reads it on its own thread.
//
// - progress: how near the end of the run (0 at the start, 1 at the boss): the nearer, the less a point of life weighs;
// - heal_outside: the life the nearest real heal outside the fight gives back (the FONTE not yet used within 20 cells,
//   the Kit in the backpack, the Rest on the next node); the heals inside the room the IA finds itself (room_heal);
// - the sleepers: the foes on the map not yet in the fight, where they stand and how near wakes them. The copy does
//   not wake them (the expedition does, outside the room): ending a branch within their reach costs a little, so the
//   IA does not lead the player to them for nothing.

MAX_SLEEPERS :: 32

Sleeper :: struct {
	position: grid.Position,
	archetype: game.Enemy_Archetype,
	health: i32,
	// Within this many cells (the larger of the two axes) it wakes.
	wake: int,
}

Game_Context :: struct {
	// Filled by the run, the expedition or the lab (else: the start of a run, no heal, no sleeper).
	known: bool,
	progress: f32,
	heal_outside: i32,
	sleepers: [MAX_SLEEPERS]Sleeper,
	sleeper_count: int,
	// The foes still to beat: in the room and asleep on the map.
	remaining_foes: int,
}

// THE AGGRESSIVENESS (the user's «leggermente più aggressiva»): a point of life weighs 3 at the start of the run, 2 at its
// end, half a point less with a real heal near, never below 1.5. Death stays the worst branch, always.
LIFE_WEIGHT_START :: f32(3)
LIFE_WEIGHT_END :: f32(2)
HEAL_RELIEF :: f32(0.5)
LIFE_WEIGHT_FLOOR :: f32(1.5)
// A branch ending where a sleeper wakes: this, for each one.
SLEEPER_VALUE :: f32(-1.5)

life_weight :: proc(ctx: Game_Context, healed: bool) -> f32 {
	w := LIFE_WEIGHT_START+(LIFE_WEIGHT_END-LIFE_WEIGHT_START)*clamp(ctx.progress, 0, 1)
	if healed { w -= HEAL_RELIEF }
	return max(w, LIFE_WEIGHT_FLOOR)
}

// The real heals of the room itself: the food the foes dropped (never the fish the rod caught: its food keeps its
// healing in `healing_amount`, the user's exception), the table of Benvenuti a Napoli. The life they give, at most.
room_heal :: proc(room: ^game.Room) -> (life: i32) {
	for loot in room.loot {
		if loot.kind == .Healing && loot.healing_amount == 0 { life += max(loot.amount, 1) }
	}
	for object in room.objects {
		if object.kind == .Napoli_Table { life += 1 }
	}
	return
}

// The sleepers a branch's end stands within reach of.
@(private)
sleepers_woken :: proc(ctx: ^Game_Context, cell: grid.Position) -> (count: int) {
	for sleeper in ctx.sleepers[:ctx.sleeper_count] {
		if sleeper.position.layer != cell.layer { continue }
		if max(abs(sleeper.position.x-cell.x), abs(sleeper.position.y-cell.y)) <= sleeper.wake { count += 1 }
	}
	return
}
