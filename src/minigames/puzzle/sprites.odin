package puzzle

import rl "vendor:raylib"
import gfx "../../engine/gfx"

// Pixel art for the crypt, 16 px per cell. One shared palette: each letter
// belongs to a single material so frames can be read at a glance.
//   floor  m h b n s k q      ice    I J K L M      sigil  v w
//   plate  P Q R S T U        gate   G H E F        wall   A B C D X Y
//   relic  1 2 3 4 5 6 7      hero   r t u f e g z  flame  y 8 9 0

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
	hero:       gfx.Sprite, // down, down step, up, up step, side, side step
	flame:      gfx.Sprite, // 3 frames
	ok:         bool,
}

@(private)
crypt_palette :: proc() -> gfx.Pixel_Palette {
	p: gfx.Pixel_Palette
	set :: gfx.palette_set
	// Flagstones.
	set(&p, 'm', {22, 20, 30, 255})
	set(&p, 'h', {86, 81, 103, 255})
	set(&p, 'b', {64, 60, 79, 255})
	set(&p, 'n', {57, 53, 71, 255})
	set(&p, 's', {47, 44, 60, 255})
	set(&p, 'k', {30, 28, 40, 255})
	set(&p, 'q', {54, 74, 58, 255})
	// Ice.
	set(&p, 'I', {92, 148, 198, 255})
	set(&p, 'J', {142, 198, 234, 255})
	set(&p, 'K', {226, 246, 255, 255})
	set(&p, 'L', {66, 112, 164, 255})
	set(&p, 'M', {44, 74, 116, 255})
	// Sigil grooves.
	set(&p, 'v', {88, 70, 160, 255})
	set(&p, 'w', {132, 110, 226, 255})
	// Bronze plate.
	set(&p, 'P', {150, 118, 70, 255})
	set(&p, 'Q', {200, 164, 100, 255})
	set(&p, 'R', {98, 74, 44, 255})
	set(&p, 'S', {34, 28, 26, 255})
	set(&p, 'T', {62, 84, 96, 255})
	set(&p, 'U', {130, 255, 210, 255})
	// Iron gate.
	set(&p, 'G', {72, 76, 92, 255})
	set(&p, 'H', {140, 146, 166, 255})
	set(&p, 'E', {36, 38, 50, 255})
	set(&p, 'F', {120, 74, 52, 255})
	// Walls.
	set(&p, 'A', {66, 61, 80, 255})
	set(&p, 'B', {84, 79, 100, 255})
	set(&p, 'C', {54, 50, 66, 255})
	set(&p, 'D', {62, 55, 72, 255})
	set(&p, 'X', {38, 34, 48, 255})
	set(&p, 'Y', {98, 90, 112, 255})
	// Sandstone relic.
	set(&p, '1', {214, 186, 134, 255})
	set(&p, '2', {176, 146, 98, 255})
	set(&p, '3', {124, 98, 64, 255})
	set(&p, '4', {58, 42, 32, 255})
	set(&p, '5', {104, 80, 52, 255})
	set(&p, '6', {255, 208, 110, 255})
	set(&p, '7', {255, 248, 214, 255})
	// Hooded acolyte.
	set(&p, 'r', {156, 34, 50, 255})
	set(&p, 't', {204, 62, 70, 255})
	set(&p, 'u', {96, 20, 36, 255})
	set(&p, 'f', {236, 210, 178, 255})
	set(&p, 'e', {34, 22, 28, 255})
	set(&p, 'g', {228, 184, 92, 255})
	set(&p, 'z', {18, 12, 20, 255})
	// Torch.
	set(&p, 'y', {255, 236, 150, 255})
	set(&p, '8', {236, 104, 44, 255})
	set(&p, '9', {255, 252, 226, 255})
	set(&p, '0', {92, 62, 40, 255})
	return p
}

@(private, rodata)
FLOOR_ROWS := [3]gfx.Frame_Rows{
	{
		"hhhhhhhhhhhhhhhm",
		"hbbbbbbbbbbbbbsm",
		"hbbnbbbbbbbbbbsm",
		"hbbbbbbbbbnbbbsm",
		"hbbbbbbbbbbbbbsm",
		"hbbbbbnbbbbbbbsm",
		"hbbbbbbbbbbbbbsm",
		"hbnbbbbbbbbbnbsm",
		"hbbbbbbbbbbbbbsm",
		"hbbbbbbbnbbbbbsm",
		"hbbbbbbbbbbbbbsm",
		"hbbbnbbbbbbbbbsm",
		"hbbbbbbbbbbnbbsm",
		"hbbbbbbbbbbbbbsm",
		"hsssssssssssssss",
		"mmmmmmmmmmmmmmmm",
	},
	{
		"hhhhhhhhhhhhhhhm",
		"hbbbbbbbbbbbbbsm",
		"hbbbbbbbbbbbbbsm",
		"hbbnbbbbbbbbbbsm",
		"hbbbbbbbbbbbbbsm",
		"hbbbbbbbbbnnbbsm",
		"hbbbbbbbbbsnbbsm",
		"hbbbbbbbbbbbbbsm",
		"hbbbbnbbbbbbbbsm",
		"hbbbbbbbbbbbbbsm",
		"hbbbbbbbbbbbbbsm",
		"hbnnbbbbbbbbnbsm",
		"hbsnbbbbbbbbbbsm",
		"hbbbbbbbbbbbbbsm",
		"hsssssssssssssss",
		"mmmmmmmmmmmmmmmm",
	},
	{
		"hhhhhhhmhhhhhhhm",
		"hbbbbbsmhbbbbbsm",
		"hbnbbbsmhbbbbbsm",
		"hbbbbbsmhbbbnbsm",
		"hbbbbbsmhbbbbbsm",
		"hbbbnbsmhbbbbbsm",
		"hssssssmhbbbbbsm",
		"mmmmmmmmhbbbbbsm",
		"hhhhhhhmhbbnbbsm",
		"hbbbbbsmhbbbbbsm",
		"hbbbbbsmhbbbbbsm",
		"hbqbbbsmhbbbbbsm",
		"hbqqbbsmhbbbbbsm",
		"hbbbbbsmhbbbbbsm",
		"hssssssmhsssssss",
		"mmmmmmmmmmmmmmmm",
	},
}

@(private, rodata)
ICE_ROWS := [2]gfx.Frame_Rows{
	{
		"JJJJJJJJJJJJJJJM",
		"JIIIIIIIIIIIIILM",
		"JIKIIIIIIIIIIILM",
		"JIIKIIIIIIIJIILM",
		"JIIIKIIIIIJIIILM",
		"JIIIIIIIIJIIIILM",
		"JIIIIIIIIIIIIILM",
		"JIIIIIIJIIIIIILM",
		"JIIIIIJIIIIIKILM",
		"JIIIIJIIIIIIIKLM",
		"JIIIIIIIIIIIIILM",
		"JIIIIIIIIIIIIILM",
		"JIIKKIIIIIIIIILM",
		"JIIIIIIIIIIIIILM",
		"JLLLLLLLLLLLLLLL",
		"MMMMMMMMMMMMMMMM",
	},
	{
		"JJJJJJJJJJJJJJJM",
		"JIIIIIIIIIIIIILM",
		"JIIIIIIIIIKIIILM",
		"JIIIIIIIIKIIIILM",
		"JIIJIIIIKIIIIILM",
		"JIJIIIIIIIIIIILM",
		"JJIIIIIIIIIIIILM",
		"JIIIIIIIIIIIIILM",
		"JIIIIIIIIIIIIILM",
		"JIIIIIIIIIIJIILM",
		"JIIKIIIIIIJIIILM",
		"JIIIKIIIIJIIIILM",
		"JIIIIIIIIIIIIILM",
		"JIIIIIIIIIIIIILM",
		"JLLLLLLLLLLLLLLL",
		"MMMMMMMMMMMMMMMM",
	},
}

@(private, rodata)
SIGIL_ROWS := [1]gfx.Frame_Rows{
	{
		"hhhhhhhhhhhhhhhm",
		"hbbbbbbbbbbbbbsm",
		"hbbbbvvvvvbbbbsm",
		"hbbbvbbbbbvbbbsm",
		"hbbvbbbwbbbvbbsm",
		"hbvbbbwbwbbbvbsm",
		"hbvbbwbbbwbbvbsm",
		"hbvbwbbbbbwbvbsm",
		"hbvbbwbbbwbbvbsm",
		"hbvbbbwbwbbbvbsm",
		"hbbvbbbwbbbvbbsm",
		"hbbbvbbbbbvbbbsm",
		"hbbbbvvvvvbbbbsm",
		"hbbbbbbbbbbbbbsm",
		"hsssssssssssssss",
		"mmmmmmmmmmmmmmmm",
	},
}

@(private, rodata)
PLATE_ROWS := [2]gfx.Frame_Rows{
	{
		"hhhhhhhhhhhhhhhm",
		"hbbbbbbbbbbbbbsm",
		"hbSSSSSSSSSSSbsm",
		"hbSQQQQQQQQQRbsm",
		"hbSQPPPPPPPPRbsm",
		"hbSQPPPPPPPPRbsm",
		"hbSQPPPTTPPPRbsm",
		"hbSQPPTTTTPPRbsm",
		"hbSQPPTTTTPPRbsm",
		"hbSQPPPTTPPPRbsm",
		"hbSQPPPPPPPPRbsm",
		"hbSQPPPPPPPPRbsm",
		"hbSRRRRRRRRRRbsm",
		"hbbbbbbbbbbbbbsm",
		"hsssssssssssssss",
		"mmmmmmmmmmmmmmmm",
	},
	{
		"hhhhhhhhhhhhhhhm",
		"hbbbbbbbbbbbbbsm",
		"hbSSSSSSSSSSSbsm",
		"hbSSSSSSSSSSSbsm",
		"hbSRPPPPPPPPRbsm",
		"hbSRPPPPPPPPRbsm",
		"hbSRPPPPPPPPRbsm",
		"hbSRPPPUUPPPRbsm",
		"hbSRPPUUUUPPRbsm",
		"hbSRPPUUUUPPRbsm",
		"hbSRPPPUUPPPRbsm",
		"hbSRPPPPPPPPRbsm",
		"hbSRRRRRRRRRRbsm",
		"hbbbbbbbbbbbbbsm",
		"hsssssssssssssss",
		"mmmmmmmmmmmmmmmm",
	},
}

@(private, rodata)
GATE_SLOT_ROWS := [1]gfx.Frame_Rows{
	{
		"hhhhhhhhhhhhhhhm",
		"hbbbbbbbbbbbbbsm",
		"hbbbbbbbbbbbbbsm",
		"hbbnbbbbbbbbbbsm",
		"hbbbbbbbbbbbbbsm",
		"hbbbbbbbbbbbbbsm",
		"hEEEEEEEEEEEEEEm",
		"hEkEEkEEkEEkEEEm",
		"hGGGGGGGGGGGGGGm",
		"hbbbbbbbbbbbbbsm",
		"hbbbbbbbbbbbbbsm",
		"hbbbbbbbbbbnbbsm",
		"hbbbbbbbbbbbbbsm",
		"hbbbbbbbbbbbbbsm",
		"hsssssssssssssss",
		"mmmmmmmmmmmmmmmm",
	},
}

@(private, rodata)
GATE_BARS_ROWS := [1]gfx.Frame_Rows{
	{
		"EEEEEEEEEEEEEEEE",
		"EHHHHHHHHHHHHHHE",
		"EGGGGFGGGGGGFGGE",
		"EEEEEEEEEEEEEEEE",
		".HG.HG.HG.HG.HG.",
		".HG.HG.HG.HG.HG.",
		".HG.HF.HG.HG.HG.",
		".HG.HG.HG.HG.HG.",
		".HG.HG.HG.HG.HG.",
		"EHHHHHHHHHHHHHHE",
		"EEEEEEEEEEEEEEEE",
		".HG.HG.HG.HG.HG.",
		".HG.HG.HG.HF.HG.",
		".HG.HG.HG.HG.HG.",
		".HG.HG.HG.HG.HG.",
		".HG.HG.HG.HG.HG.",
		".HG.HG.HG.HG.HG.",
		".HE.HE.HE.HE.HE.",
		".E..E..E..E..E..",
		"................",
	},
}

@(private, rodata)
WALL_TOP_ROWS := [2]gfx.Frame_Rows{
	{
		"BAAAAAACBAAAAAAC",
		"AAAAAAACAAAAACAC",
		"AACAAAACAAAAAAAC",
		"AAAAAAACAAAAAAAC",
		"AAAAAAACAABAAAAC",
		"AAAAACACAAAAAAAC",
		"AAAAAAACAAAAAAAC",
		"CCCCCCCCCCCCCCCC",
		"AAACBAAAAAACBAAA",
		"AAACAAAAAAACAAAA",
		"AAACAAAACAACAAAA",
		"ACACAAAAAAACAAAA",
		"AAACAAAAAAACAACA",
		"AAACAAABAAACAAAA",
		"AAACAAAAAAACAAAA",
		"CCCCCCCCCCCCCCCC",
	},
	{
		"BAAAAAAAAAACBAAA",
		"AAAACAAAAAACAAAA",
		"AAAAAAAAAAACAACA",
		"AAAAAAAABAACAAAA",
		"AACAAAAAAAACAAAA",
		"AAAAAAAAAAACAAAA",
		"AAAAAAAAAAACAAAA",
		"CCCCCCCCCCCCCCCC",
		"BAAAAACBAAAAAAAC",
		"AAAAAACAAAACAAAC",
		"AAACAACAAAAAAAAC",
		"AAAAAACAAAAAAAAC",
		"AAAAAACAAAAAACAC",
		"ABAAAACAAAAAAAAC",
		"AAAAAACAAAAAAAAC",
		"CCCCCCCCCCCCCCCC",
	},
}

@(private, rodata)
WALL_FRONT_ROWS := [2]gfx.Frame_Rows{
	{
		"YYYYYYYYYYYYYYYY",
		"DDDDDDXDDDDDDDXD",
		"DDDDDDXDDDDDDDXD",
		"XXXXXXXXXXXXXXXX",
		"DDXDDDDDDDXDDDDD",
		"XXXXXXXXXXXXXXXX",
	},
	{
		"YYYYYYYYYYYYYYYY",
		"DDDXDDDDDDDXDDDD",
		"DDDXDDDDDDDXDDDD",
		"XXXXXXXXXXXXXXXX",
		"DDDDDDXDDDDDDDXD",
		"XXXXXXXXXXXXXXXX",
	},
}

@(private, rodata)
CRATE_ROWS := [2]gfx.Frame_Rows{
	{
		"..444444444444..",
		".41111111111114.",
		".41222222222234.",
		".41225555552234.",
		".41252222225234.",
		".41252255225234.",
		".41252255225234.",
		".41252222225234.",
		".41225555552234.",
		".41222222222234.",
		".43333333333334.",
		".44444444444444.",
		".42222222222224.",
		".42332233223324.",
		".42222222222224.",
		".43333333333334.",
		".44444444444444.",
		"................",
	},
	{
		"..444444444444..",
		".41111111111114.",
		".41222222222234.",
		".41226666662234.",
		".41262222226234.",
		".41262277226234.",
		".41262277226234.",
		".41262222226234.",
		".41226666662234.",
		".41222222222234.",
		".43333333333334.",
		".44444444444444.",
		".42222222222224.",
		".42662266226624.",
		".42222222222224.",
		".43333333333334.",
		".44444444444444.",
		"................",
	},
}

@(private, rodata)
HERO_ROWS := [6]gfx.Frame_Rows{
	{ // facing down
		"......zzzz......",
		".....zrttrz.....",
		"....zrttttrz....",
		"....zrffffrz....",
		"....zfeffefz....",
		"....zrffffrz....",
		"...zurrrrrruz...",
		"..zurrtggtrruz..",
		"..zurrrggrrruz..",
		"..zuurrrrrruuz..",
		"..zuurrrrrruuz..",
		"..zuuurrrruuuz..",
		"...zuurrrruuz...",
		"...zuuurruuuz...",
		"...zzuuuuuuzz...",
		"....zz....zz....",
	},
	{ // facing down, step
		"......zzzz......",
		".....zrttrz.....",
		"....zrttttrz....",
		"....zrffffrz....",
		"....zfeffefz....",
		"....zrffffrz....",
		"...zurrrrrruz...",
		"..zurrtggtrruz..",
		"..zurrrggrrruz..",
		"..zuurrrrrruuz..",
		"..zuurrrrrruuz..",
		"..zuuurrrruuuz..",
		"...zuurrrruuz...",
		"...zuuurruuuz...",
		"...zzuuuuuuzz...",
		"...zz......zz...",
	},
	{ // facing up
		"......zzzz......",
		".....zrttrz.....",
		"....zrttttrz....",
		"....zrttttrz....",
		"....zrrttrrz....",
		"....zurrrruz....",
		"...zurrrrrruz...",
		"..zurrrrrrrruz..",
		"..zurrrrrrrruz..",
		"..zuurrrrrruuz..",
		"..zuurrrrrruuz..",
		"..zuuurrrruuuz..",
		"...zuurrrruuz...",
		"...zuuurruuuz...",
		"...zzuuuuuuzz...",
		"....zz....zz....",
	},
	{ // facing up, step
		"......zzzz......",
		".....zrttrz.....",
		"....zrttttrz....",
		"....zrttttrz....",
		"....zrrttrrz....",
		"....zurrrruz....",
		"...zurrrrrruz...",
		"..zurrrrrrrruz..",
		"..zurrrrrrrruz..",
		"..zuurrrrrruuz..",
		"..zuurrrrrruuz..",
		"..zuuurrrruuuz..",
		"...zuurrrruuz...",
		"...zuuurruuuz...",
		"...zzuuuuuuzz...",
		"...zz......zz...",
	},
	{ // facing left
		".....zzzz.......",
		"....zrttrz......",
		"...zrttttrz.....",
		"...zfftttrz.....",
		"..zeffttttrz....",
		"...zffrrrrz.....",
		"...zurrrrruz....",
		"..zurrtrrrruz...",
		"..zugrrrrrruz...",
		"..zurrrrrrruz...",
		"..zuurrrrrruz...",
		"...zuurrrruuz...",
		"...zuurrrruuz...",
		"...zuuurruuuz...",
		"...zzuuuuuuzz...",
		"....zz...zz.....",
	},
	{ // facing left, step
		".....zzzz.......",
		"....zrttrz......",
		"...zrttttrz.....",
		"...zfftttrz.....",
		"..zeffttttrz....",
		"...zffrrrrz.....",
		"...zurrrrruz....",
		"..zurrtrrrruz...",
		"..zugrrrrrruz...",
		"..zurrrrrrruz...",
		"..zuurrrrrruz...",
		"...zuurrrruuz...",
		"...zuurrrruuz...",
		"...zuuurruuuz...",
		"...zzuuuuuuzz...",
		"...zz.....zz....",
	},
}

@(private, rodata)
FLAME_ROWS := [3]gfx.Frame_Rows{
	{
		"..y...",
		"..yy..",
		".y99y.",
		".y99y.",
		"y8998y",
		"y8888y",
		".8888.",
		"..00..",
	},
	{
		"...y..",
		"..yy..",
		".yy9y.",
		".y99y.",
		"y8998y",
		".8888y",
		".8888.",
		"..00..",
	},
	{
		"......",
		"..y...",
		".yy9..",
		".y99y.",
		"y8999y",
		"y8888y",
		".8888.",
		"..00..",
	},
}

sprites_create :: proc() -> Sprites {
	palette := crypt_palette()
	s: Sprites
	ok := true
	make_one :: proc(frames: []gfx.Frame_Rows, palette: ^gfx.Pixel_Palette, ok: ^bool) -> gfx.Sprite {
		sprite, good := gfx.sprite_create(frames, palette)
		if !good {
			ok^ = false
		}
		return sprite
	}
	s.floor = make_one(FLOOR_ROWS[:], &palette, &ok)
	s.ice = make_one(ICE_ROWS[:], &palette, &ok)
	s.sigil = make_one(SIGIL_ROWS[:], &palette, &ok)
	s.plate = make_one(PLATE_ROWS[:], &palette, &ok)
	s.gate_slot = make_one(GATE_SLOT_ROWS[:], &palette, &ok)
	s.gate_bars = make_one(GATE_BARS_ROWS[:], &palette, &ok)
	s.wall_top = make_one(WALL_TOP_ROWS[:], &palette, &ok)
	s.wall_front = make_one(WALL_FRONT_ROWS[:], &palette, &ok)
	s.crate = make_one(CRATE_ROWS[:], &palette, &ok)
	s.hero = make_one(HERO_ROWS[:], &palette, &ok)
	s.flame = make_one(FLAME_ROWS[:], &palette, &ok)
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
