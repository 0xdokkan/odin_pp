package fps

import gfx "../../engine/gfx"

Sprite_Id :: enum u8 {
	Ghoul,
	Wraith,
	Cultist,
	Rune,
	Health,
	Mana,
	Staff,
	Candle,
	Flame,
	Skull,
	Bones,
	Brazier,
}

// Enemy sheet layout.
FRAME_WALK_A :: 0
FRAME_WALK_B :: 1
FRAME_ATTACK :: 2
FRAME_DEAD :: 3
FRAME_FLASH :: 4

// Canonical RGBA sheets, embedded so launch directories do not affect assets.
@(private, rodata)
SPRITE_ASSETS := [Sprite_Id]gfx.Sprite_Asset{
	.Ghoul = {#load("../../../assets/minigames/fps/ghoul.png"), 5},
	.Wraith = {#load("../../../assets/minigames/fps/wraith.png"), 5},
	.Cultist = {#load("../../../assets/minigames/fps/cultist.png"), 5},
	.Rune = {#load("../../../assets/minigames/fps/rune.png"), 2},
	.Health = {#load("../../../assets/minigames/fps/health.png"), 1},
	.Mana = {#load("../../../assets/minigames/fps/mana.png"), 1},
	.Staff = {#load("../../../assets/minigames/fps/staff.png"), 2},
	.Candle = {#load("../../../assets/minigames/fps/candle.png"), 1},
	.Flame = {#load("../../../assets/minigames/fps/flame.png"), 2},
	.Skull = {#load("../../../assets/minigames/fps/skull.png"), 1},
	.Bones = {#load("../../../assets/minigames/fps/bones.png"), 1},
	.Brazier = {#load("../../../assets/minigames/fps/brazier.png"), 1},
}
