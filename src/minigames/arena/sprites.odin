// Pixel art for the arena, authored as character rows (no image files).
// Every sprite also gets a white silhouette twin for hit flashes, since a
// raylib tint can only darken a texture.
package arena

import rl "vendor:raylib"
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

// Facing right; the renderer flips toward the target.
@(private = "file")
player_rows := [2][14]string{
	{
		"....kkkkk.....",
		"...kSSSSSk....",
		"..kSsssssSk...",
		"..kSsskkkkk...",
		"..kSskccyck...",
		"..kSskcccck...",
		"..krrrrrrrk...",
		".kiirrrrrrik..",
		".kiiiiiiiiik..",
		".kIiiiiiiiIk..",
		".kIIiiiiiIIk..",
		"..kIIIIIIIk...",
		"...kSk.kSk....",
		"...kk...kk....",
	},
	{
		"..............",
		"....kkkkk.....",
		"...kSSSSSk....",
		"..kSsssssSk...",
		"..kSsskkkkk...",
		"..kSskccyck...",
		"..kSskcccck...",
		"..krrrrrrrk...",
		".kiirrrrrrik..",
		".kiiiiiiiiik..",
		".kIiiiiiiiIk..",
		"..kIIiiiIIk...",
		"...kSkkSk.....",
		"....kk.kk.....",
	},
}

@(private = "file")
chaser_rows := [2][10]string{
	{
		".k......k.",
		".ok....ko.",
		"..kkkkkk..",
		".kooooook.",
		"kooyooyook",
		"korrrrrrok",
		"kooooooook",
		".kooooook.",
		"..kokkok..",
		"..kk..kk..",
	},
	{
		"..........",
		".k......k.",
		".ok....ko.",
		".kkkkkkkk.",
		"kooyooyook",
		"korrrrrrok",
		"kooooooook",
		".kooooook.",
		".kok..kok.",
		".kk....kk.",
	},
}

@(private = "file")
caster_rows := [2][14]string{
	{
		".....kk.....",
		"....kPPk....",
		"....kPPPk...",
		"...kPPPPPk..",
		"kkPPPPPPPPkk",
		"...kbbbbk...",
		"...kbvbvk...",
		"...kbbbbk...",
		"..kppppppk..",
		".kpppPppppk.",
		".kppPpppPpk.",
		"kpppPppppPpk",
		"kPPPPPPPPPPk",
		".kkkkkkkkkk.",
	},
	{
		"......kk....",
		".....kPPk...",
		"....kPPPk...",
		"...kPPPPPk..",
		"kkPPPPPPPPkk",
		"...kbbbbk...",
		"...kbvbvk...",
		"...kbbbbk...",
		"..kppppppk..",
		".kppPppppPk.",
		".kpppPppppk.",
		"kppPppppPppk",
		".kPPPPPPPPPk",
		"..kkkkkkkkk.",
	},
}

@(private = "file")
charger_rows := [2][16]string{
	{
		"..k..........k..",
		".kbk........kbk.",
		".kbbk......kbbk.",
		"..kbkkkkkkkkbk..",
		"...kcccccccck...",
		"..kccyccccycck..",
		"..kcccooooccck..",
		".kcccccccccccck.",
		"kccocccccccccock",
		"kcccoccccccoccck",
		"kccccoooooocccck",
		".kcccccccccccck.",
		"..kcccccccccck..",
		"..kcck....kcck..",
		"..kcck....kcck..",
		".kkkk......kkkk.",
	},
	{
		"..k..........k..",
		".kbk........kbk.",
		".kbbk......kbbk.",
		"..kbkkkkkkkkbk..",
		"...kcccccccck...",
		"..kccyccccycck..",
		"..kcccooooccck..",
		".kcccccccccccck.",
		"kccocccccccccock",
		"kcccoccccccoccck",
		"kccccoooooocccck",
		".kcccccccccccck.",
		"..kcccccccccck..",
		"...kcck..kcck...",
		"...kcck..kcck...",
		"..kkkk....kkkk..",
	},
}

@(private = "file")
splitter_rows := [1][12]string{
	{
		"....kkkkkk....",
		"...kmmmmmmk...",
		"..kmmyymmmmk..",
		".kmmyymmmmmmk.",
		".kmmmmmmmmmmk.",
		"kmmmkmmmmkmmmk",
		"kmmmkmmmmkmmmk",
		"kmmmmmmmmmmmmk",
		"kMmmmmmmmmmmMk",
		"kMMmmmmmmmmMMk",
		".kMMMMMMMMMMk.",
		"..kkkkkkkkkk..",
	},
}

@(private = "file")
shard_rows := [1][7]string{
	{
		"..kkkk..",
		".kmymmk.",
		"kmyymmmk",
		"kmmkmkmk",
		"kmmmmmmk",
		"kMmmmmMk",
		".kkkkkk.",
	},
}

@(private = "file")
boss_rows := [2][22]string{
	{
		"..k...k...kk...k...k..",
		".kgk.kgk.kggk.kgk.kgk.",
		".kggkgggkggggkgggkggk.",
		".kggggggggrrggggggggk.",
		"..kkkkkkkkkkkkkkkkkk..",
		"...kbbbbbbbbbbbbbbk...",
		"..kbbbbbbbbbbbbbbbbk..",
		"..kbbbkkkbbbbkkkbbbk..",
		"..kbbkyykbbbbkyykbbk..",
		"..kbbkkkkbbbbkkkkbbk..",
		"..kbbbbbbkkkkbbbbbbk..",
		"...kbbbbbbkkbbbbbbk...",
		"...kbkbkbkbbkbkbkbk...",
		"....kbbbbbbbbbbbbk....",
		"..kkrkkkkkkkkkkkkrkk..",
		".krrrrrrrrRRrrrrrrrrk.",
		"krrrrrrrRooooRrrrrrrrk",
		"krRrrrrrRoyyoRrrrrrRrk",
		"kRrrrrrrrRooRrrrrrrrRk",
		"kRRrrrrrrrRRrrrrrrrRRk",
		".kRRRRRRRRRRRRRRRRRRk.",
		"..kkkkkkkkkkkkkkkkkk..",
	},
	{
		"..k...k...kk...k...k..",
		".kgk.kgk.kggk.kgk.kgk.",
		".kggkgggkggggkgggkggk.",
		".kggggggggrrggggggggk.",
		"..kkkkkkkkkkkkkkkkkk..",
		"...kbbbbbbbbbbbbbbk...",
		"..kbbbbbbbbbbbbbbbbk..",
		"..kbbbkkkbbbbkkkbbbk..",
		"..kbbkywkbbbbkwykbbk..",
		"..kbbkkkkbbbbkkkkbbk..",
		"..kbbbbbbkkkkbbbbbbk..",
		"...kbbbbbbkkbbbbbbk...",
		"...kbkbkbkbbkbkbkbk...",
		"....kbbbbbbbbbbbbk....",
		"..kkrkkkkkkkkkkkkrkk..",
		".krrrrrrrrRRrrrrrrrrk.",
		"krrrrrrrRRooRRrrrrrrrk",
		"krRrrrrrRooooRrrrrrRrk",
		"kRrrrrrrrRRRRrrrrrrrRk",
		"kRRrrrrrrrRRrrrrrrrRRk",
		".kRRRRRRRRRRRRRRRRRRk.",
		"..kkkkkkkkkkkkkkkkkk..",
	},
}

@(private = "file")
heart_rows := [1][8]string{
	{
		".kk...kk.",
		"krrk.krrk",
		"krwrkrrrk",
		"krrrrrrrk",
		".krrrrRk.",
		"..krrRk..",
		"...kRk...",
		"....k....",
	},
}

// Pale so a tint can colour it per power-up.
@(private = "file")
gem_rows := [1][9]string{
	{
		"....k....",
		"...kwk...",
		"..kwiik..",
		".kwiiiIk.",
		"kwiiiiIIk",
		".kiiiIIk.",
		"..kiIIk..",
		"...kIk...",
		"....k....",
	},
}

sprite_frame_count :: proc(id: Sprite_Id) -> int {
	switch id {
	case .Player, .Chaser, .Caster, .Charger, .Boss:
		return 2
	case .Splitter, .Shard, .Heart, .Gem:
		return 1
	}
	return 1
}

sprite_rows :: proc(id: Sprite_Id, frame: int) -> []string {
	f := clamp(frame, 0, sprite_frame_count(id)-1)
	switch id {
	case .Player:
		return player_rows[f][:]
	case .Chaser:
		return chaser_rows[f][:]
	case .Caster:
		return caster_rows[f][:]
	case .Charger:
		return charger_rows[f][:]
	case .Splitter:
		return splitter_rows[f][:]
	case .Shard:
		return shard_rows[f][:]
	case .Boss:
		return boss_rows[f][:]
	case .Heart:
		return heart_rows[f][:]
	case .Gem:
		return gem_rows[f][:]
	}
	return nil
}

sprite_palette :: proc() -> gfx.Pixel_Palette {
	p: gfx.Pixel_Palette
	gfx.palette_set(&p, 'k', {16, 12, 20, 255})
	gfx.palette_set(&p, 'S', {44, 48, 66, 255})
	gfx.palette_set(&p, 's', {72, 78, 102, 255})
	gfx.palette_set(&p, 'c', {58, 52, 68, 255})
	gfx.palette_set(&p, 'y', {255, 214, 110, 255})
	gfx.palette_set(&p, 'w', {255, 252, 240, 255})
	gfx.palette_set(&p, 'r', {178, 38, 52, 255})
	gfx.palette_set(&p, 'R', {112, 22, 36, 255})
	gfx.palette_set(&p, 'i', {236, 226, 204, 255})
	gfx.palette_set(&p, 'I', {184, 172, 150, 255})
	gfx.palette_set(&p, 'o', {240, 126, 46, 255})
	gfx.palette_set(&p, 'g', {232, 196, 112, 255})
	gfx.palette_set(&p, 'b', {214, 204, 180, 255})
	gfx.palette_set(&p, 'p', {76, 111, 146, 255})
	gfx.palette_set(&p, 'P', {36, 61, 87, 255})
	gfx.palette_set(&p, 'v', {158, 211, 246, 255})
	gfx.palette_set(&p, 'm', {246, 112, 42, 255})
	gfx.palette_set(&p, 'M', {168, 48, 30, 255})
	return p
}

// Every pixel of the art turned white, for hit flashes.
@(private)
silhouette_palette :: proc(p: gfx.Pixel_Palette) -> gfx.Pixel_Palette {
	out := p
	for &c in out {
		if c.a > 0 {
			c = rl.WHITE
		}
	}
	return out
}

@(private)
sprites_create :: proc(sprites, white: ^[Sprite_Id]gfx.Sprite) {
	palette := sprite_palette()
	blank := silhouette_palette(palette)
	for id in Sprite_Id {
		frames: [2]gfx.Frame_Rows
		count := sprite_frame_count(id)
		for f in 0..<count {
			frames[f] = sprite_rows(id, f)
		}
		actor_palette := palette
		if id == .Player {
			gfx.palette_set(&actor_palette, 'S', {180, 169, 147, 255})
			gfx.palette_set(&actor_palette, 's', {238, 228, 206, 255})
			gfx.palette_set(&actor_palette, 'y', {147, 219, 250, 255})
			gfx.palette_set(&actor_palette, 'i', {44, 56, 74, 255})
			gfx.palette_set(&actor_palette, 'I', {24, 34, 49, 255})
			gfx.palette_set(&actor_palette, 'c', {12, 21, 30, 255})
		}
		sprites[id], _ = gfx.sprite_create(frames[:count], &actor_palette)
		white[id], _ = gfx.sprite_create(frames[:count], &blank)
	}
}

@(private)
sprites_destroy :: proc(sprites, white: ^[Sprite_Id]gfx.Sprite) {
	for id in Sprite_Id {
		gfx.sprite_destroy(&sprites[id])
		gfx.sprite_destroy(&white[id])
	}
}
