package platform2d

import rl "vendor:raylib"
import gfx "../../engine/gfx"

Player_Frame :: enum u8 {
	Idle,
	Blink,
	Run_A,
	Run_B,
	Run_C,
	Jump,
	Fall,
}

Tile_Frame :: enum u8 {
	Stone,
	Stone_Cracked,
	Stone_Top,
	Ledge,
	Spikes,
	Crumble,
}

@(private)
Sprite_Id :: enum u8 { Player, Ghoul, Bat, Totem, Ember, Brazier, Heart, Tiles }

// Canonical RGBA sheets, embedded so launch directories do not affect assets.
@(private, rodata)
SPRITE_ASSETS := [Sprite_Id]gfx.Sprite_Asset{
	.Player = {#load("../../../assets/minigames/platform2d/player.png"), 7},
	.Ghoul = {#load("../../../assets/minigames/platform2d/ghoul.png"), 2},
	.Bat = {#load("../../../assets/minigames/platform2d/bat.png"), 2},
	.Totem = {#load("../../../assets/minigames/platform2d/totem.png"), 1},
	.Ember = {#load("../../../assets/minigames/platform2d/ember.png"), 2},
	.Brazier = {#load("../../../assets/minigames/platform2d/brazier.png"), 1},
	.Heart = {#load("../../../assets/minigames/platform2d/heart.png"), 2},
	.Tiles = {#load("../../../assets/minigames/platform2d/tiles.png"), 6},
}

Sprites :: struct {
	player:  gfx.Sprite,
	player_paper, ghoul_paper, bat_paper, totem_paper: gfx.Sprite,
	ghoul:   gfx.Sprite,
	bat:     gfx.Sprite,
	totem:   gfx.Sprite,
	ember:   gfx.Sprite,
	brazier: gfx.Sprite,
	heart:   gfx.Sprite,
	tiles:   gfx.Sprite,
	// Smooth radial falloff for additive lights (stacked discs band visibly).
	glow:    rl.Texture2D,
}

sprites_create :: proc() -> Sprites {
	s: Sprites
	s.player, _ = gfx.sprite_load(SPRITE_ASSETS[.Player])
	s.ghoul, _ = gfx.sprite_load(SPRITE_ASSETS[.Ghoul])
	s.bat, _ = gfx.sprite_load(SPRITE_ASSETS[.Bat])
	s.totem, _ = gfx.sprite_load(SPRITE_ASSETS[.Totem])
	s.ember, _ = gfx.sprite_load(SPRITE_ASSETS[.Ember])
	s.brazier, _ = gfx.sprite_load(SPRITE_ASSETS[.Brazier])
	s.heart, _ = gfx.sprite_load(SPRITE_ASSETS[.Heart])
	s.tiles, _ = gfx.sprite_load(SPRITE_ASSETS[.Tiles])
	s.player_paper = gfx.sprite_silhouette_create(s.player)
	s.ghoul_paper = gfx.sprite_silhouette_create(s.ghoul)
	s.bat_paper = gfx.sprite_silhouette_create(s.bat)
	s.totem_paper = gfx.sprite_silhouette_create(s.totem)
	s.glow = glow_texture_create()
	return s
}

sprites_destroy :: proc(s: ^Sprites) {
	gfx.sprite_destroy(&s.player_paper)
	gfx.sprite_destroy(&s.ghoul_paper)
	gfx.sprite_destroy(&s.bat_paper)
	gfx.sprite_destroy(&s.totem_paper)
	gfx.sprite_destroy(&s.player)
	gfx.sprite_destroy(&s.ghoul)
	gfx.sprite_destroy(&s.bat)
	gfx.sprite_destroy(&s.totem)
	gfx.sprite_destroy(&s.ember)
	gfx.sprite_destroy(&s.brazier)
	gfx.sprite_destroy(&s.heart)
	gfx.sprite_destroy(&s.tiles)
	if s.glow.id != 0 {
		rl.UnloadTexture(s.glow)
	}
	s.glow = {}
}

GLOW_SIZE :: 64

@(private)
glow_texture_create :: proc() -> rl.Texture2D {
	img := rl.GenImageColor(GLOW_SIZE, GLOW_SIZE, rl.BLANK)
	half := f32(GLOW_SIZE) * 0.5
	for y in 0..<GLOW_SIZE {
		for x in 0..<GLOW_SIZE {
			dx := (f32(x) + 0.5 - half) / half
			dy := (f32(y) + 0.5 - half) / half
			t := max(1 - (dx*dx + dy*dy), 0)
			// Squared falloff: bright core, long soft tail.
			a := u8(255 * t * t)
			rl.ImageDrawPixel(&img, i32(x), i32(y), {255, 255, 255, a})
		}
	}
	texture := rl.LoadTextureFromImage(img)
	rl.UnloadImage(img)
	rl.SetTextureFilter(texture, .BILINEAR)
	return texture
}

// Additive light of the given radius; call inside an additive blend.
soft_glow :: proc(s: ^Sprites, center: Vec2, radius: f32, color: rl.Color) {
	if s.glow.id == 0 {
		return
	}
	src := rl.Rectangle{0, 0, GLOW_SIZE, GLOW_SIZE}
	rl.DrawTexturePro(s.glow, src, {center.x - radius, center.y - radius, radius * 2, radius * 2}, {}, 0, color)
}

// Source rectangle of one tile frame, optionally upside down (ceiling spikes).
tile_source :: proc(s: gfx.Sprite, frame: Tile_Frame, flip_y := false) -> rl.Rectangle {
	r := gfx.sprite_source(s, int(frame))
	if flip_y {
		r.height = -r.height
	}
	return r
}
