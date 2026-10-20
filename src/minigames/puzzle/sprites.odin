package puzzle

import rl "vendor:raylib"
import gfx "../../engine/gfx"

TILE_PX :: 16
WALL_FRONT_PX :: 6 // height of a wall's lit front face

Sprites :: struct {
	floor:      gfx.Sprite, // 3 variants
	ice:        gfx.Sprite, // 2 variants
	sigil:      gfx.Sprite,
	plate:      gfx.Sprite, // raised, pressed
	gate_slot:  gfx.Sprite,
	gate_bars:  gfx.Sprite,
	wall_top:   gfx.Sprite, // 2 variants
	wall_front: gfx.Sprite, // 2 variants
	crate:      gfx.Sprite, // dormant, lit
	hero_paper: gfx.Sprite,
	hero:       gfx.Sprite, // down, down step, up, up step, side, side step
	flame:      gfx.Sprite, // 3 frames
	ok:         bool,
}

@(private)
Sprite_Id :: enum u8 { Floor, Ice, Sigil, Plate, Gate_Slot, Gate_Bars, Wall_Top, Wall_Front, Crate, Hero, Flame }

// Canonical RGBA sheets, embedded so launch directories do not affect assets.
@(private, rodata)
SPRITE_ASSETS := [Sprite_Id]gfx.Sprite_Asset{
	.Floor = {#load("../../../assets/minigames/puzzle/floor.png"), 3},
	.Ice = {#load("../../../assets/minigames/puzzle/ice.png"), 2},
	.Sigil = {#load("../../../assets/minigames/puzzle/sigil.png"), 1},
	.Plate = {#load("../../../assets/minigames/puzzle/plate.png"), 2},
	.Gate_Slot = {#load("../../../assets/minigames/puzzle/gate_slot.png"), 1},
	.Gate_Bars = {#load("../../../assets/minigames/puzzle/gate_bars.png"), 1},
	.Wall_Top = {#load("../../../assets/minigames/puzzle/wall_top.png"), 2},
	.Wall_Front = {#load("../../../assets/minigames/puzzle/wall_front.png"), 2},
	.Crate = {#load("../../../assets/minigames/puzzle/crate.png"), 2},
	.Hero = {#load("../../../assets/minigames/puzzle/hero.png"), 6},
	.Flame = {#load("../../../assets/minigames/puzzle/flame.png"), 3},
}

sprites_create :: proc() -> Sprites {
	s: Sprites
	ok := true
	make_one :: proc(asset: gfx.Sprite_Asset, ok: ^bool) -> gfx.Sprite {
		sprite, good := gfx.sprite_load(asset)
		if !good { ok^ = false }
		return sprite
	}
	s.floor = make_one(SPRITE_ASSETS[.Floor], &ok)
	s.ice = make_one(SPRITE_ASSETS[.Ice], &ok)
	s.sigil = make_one(SPRITE_ASSETS[.Sigil], &ok)
	s.plate = make_one(SPRITE_ASSETS[.Plate], &ok)
	s.gate_slot = make_one(SPRITE_ASSETS[.Gate_Slot], &ok)
	s.gate_bars = make_one(SPRITE_ASSETS[.Gate_Bars], &ok)
	s.wall_top = make_one(SPRITE_ASSETS[.Wall_Top], &ok)
	s.wall_front = make_one(SPRITE_ASSETS[.Wall_Front], &ok)
	s.crate = make_one(SPRITE_ASSETS[.Crate], &ok)
	s.hero = make_one(SPRITE_ASSETS[.Hero], &ok)
	s.hero_paper = gfx.sprite_silhouette_create(s.hero)
	s.flame = make_one(SPRITE_ASSETS[.Flame], &ok)
	s.ok = ok
	return s
}

sprites_destroy :: proc(s: ^Sprites) {
	gfx.sprite_destroy(&s.floor)
	gfx.sprite_destroy(&s.ice)
	gfx.sprite_destroy(&s.sigil)
	gfx.sprite_destroy(&s.plate)
	gfx.sprite_destroy(&s.gate_slot)
	gfx.sprite_destroy(&s.gate_bars)
	gfx.sprite_destroy(&s.wall_top)
	gfx.sprite_destroy(&s.wall_front)
	gfx.sprite_destroy(&s.crate)
	gfx.sprite_destroy(&s.hero)
	gfx.sprite_destroy(&s.hero_paper)
	gfx.sprite_destroy(&s.flame)
	s^ = {}
}

// Draws one sprite frame into a destination rectangle (top-left anchored).
@(private)
blit :: proc(s: gfx.Sprite, frame: int, dest: rl.Rectangle, tint := rl.WHITE, flip_x := false) {
	if s.texture.id == 0 {
		return
	}
	rl.DrawTexturePro(s.texture, gfx.sprite_source(s, frame, flip_x), dest, {0, 0}, 0, tint)
}
