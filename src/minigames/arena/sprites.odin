package arena

import gfx "../../engine/gfx"

Sprite_Id :: enum u8 {
	Player,
	Chaser,
	Caster,
	Charger,
	Splitter,
	Shard,
	Boss,
	Heart,
	Gem,
}

// Canonical RGBA sheets, embedded so launch directories do not affect assets.
@(private, rodata)
SPRITE_ASSETS := [Sprite_Id]gfx.Sprite_Asset{
	.Player = {#load("../../../assets/minigames/arena/player.png"), 2},
	.Chaser = {#load("../../../assets/minigames/arena/chaser.png"), 2},
	.Caster = {#load("../../../assets/minigames/arena/caster.png"), 2},
	.Charger = {#load("../../../assets/minigames/arena/charger.png"), 2},
	.Splitter = {#load("../../../assets/minigames/arena/splitter.png"), 1},
	.Shard = {#load("../../../assets/minigames/arena/shard.png"), 1},
	.Boss = {#load("../../../assets/minigames/arena/boss.png"), 2},
	.Heart = {#load("../../../assets/minigames/arena/heart.png"), 1},
	.Gem = {#load("../../../assets/minigames/arena/gem.png"), 1},
}

sprite_frame_count :: proc(id: Sprite_Id) -> int {
	return SPRITE_ASSETS[id].frames
}

@(private)
sprites_create :: proc(sprites, white: ^[Sprite_Id]gfx.Sprite) {
	for id in Sprite_Id {
		sprites[id], _ = gfx.sprite_load(SPRITE_ASSETS[id])
		white[id], _ = gfx.sprite_load(SPRITE_ASSETS[id], silhouette = true)
	}
}

@(private)
sprites_destroy :: proc(sprites, white: ^[Sprite_Id]gfx.Sprite) {
	for id in Sprite_Id {
		gfx.sprite_destroy(&sprites[id])
		gfx.sprite_destroy(&white[id])
	}
}
