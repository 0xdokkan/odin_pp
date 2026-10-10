package fps

import rl "vendor:raylib"
import gfx "../../engine/gfx"

// Pixel art authored as rows of characters; each sprite has its own
// palette. Enemy sheets get an extra all-white frame for the hit flash.
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

GHOUL_ART :: [4][20]string{
	{
		"......kkkk......",
		".....kgGGgdk....",
		"....kGggggdk....",
		"....krrggrrk....",
		"....kgmwwmdk....",
		".....kdmmdk.....",
		"...kkkkddkkkk...",
		"..kdgGGgggggdk..",
		".kdgkgGgggggkgdk",
		".kgdkgggggggkdgk",
		".kgdkdgggggdkdgk",
		".kgdkkdgggdkkdgk",
		".kwdk.kcCck.kdwk",
		".kwk..kcccck.kwk",
		"..k...kcCcCk..k.",
		"......kdkkdk....",
		".....kdgk.kgdk..",
		".....kggk..kgk..",
		"....kddk...kgdk.",
		"....kkkk...kkkk.",
	},
	{
		"......kkkk......",
		".....kgGGgdk....",
		"....kGggggdk....",
		"....krrggrrk....",
		"....kgmwwmdk....",
		".....kdmmdk.....",
		"...kkkkddkkkk...",
		"..kdgGGgggggdk..",
		".kdgkgGgggggkgdk",
		".kgdkgggggggkdgk",
		".kgdkdgggggdkdgk",
		".kgdkkdgggdkkdgk",
		".kgdk.kcCck.kdwk",
		".kdwk.kcccck.kwk",
		".kwk..kcCcCk..k.",
		"......kdkkdk....",
		"......kgdk.kdgk.",
		"......kgk..kggk.",
		".....kdgk...kddk",
		".....kkkk...kkkk",
	},
	{
		"kwk...kkkk...kwk",
		"kgk..kGGgdk..kgk",
		"kgdkkGggggdkkdgk",
		".kgdkrrggrrkdgk.",
		".kgdkgmmmmdkdgk.",
		"..kdkkdmmdkkdk..",
		"...kkkkddkkkk...",
		"...kdgGgggggk...",
		"...kgGgggggdk...",
		"...kdgggggggk...",
		"...kdgggggggk...",
		"....kdgggggk....",
		"....kkcCcckk....",
		"....kcccccck....",
		"....kcCcCcCk....",
		"......kdkkdk....",
		".....kdgk.kgdk..",
		".....kggk..kgk..",
		"....kddk...kgdk.",
		"....kkkk...kkkk.",
	},
	{
		"................",
		"................",
		"................",
		"................",
		"................",
		"................",
		"................",
		"................",
		"................",
		"................",
		"................",
		"................",
		"................",
		"................",
		"................",
		"................",
		"......kkkk......",
		"..kkkkGgrgkkkk..",
		".kdgwgdgggcCwdk.",
		"kkkkkkkkkkkkkkkk",
	},
}

WRAITH_ART :: [4][20]string{
	{
		"......kkkk......",
		".....kPPPpk.....",
		"....kPPpppphk...",
		"....kPhbbbhpk...",
		"...kPhbebebhpk..",
		"...kphbbbbbhpk..",
		"...kpphbbbhppk..",
		"..kpPpphhhpppk..",
		".kpPppppppppppk.",
		"kpPkpppppppppkpk",
		"kpk.kpPpppppk.kp",
		"kPk.kppppppppk.k",
		".k..kpPppppppk..",
		"....kppppppppk..",
		"....ktpppppptk..",
		"....kttppppttk..",
		".....ktpptpttk..",
		".....kt.ttt.tk..",
		"......t..t...t..",
		"......t......t..",
	},
	{
		"......kkkk......",
		".....kPPPpk.....",
		"....kPPpppphk...",
		"....kPhbbbhpk...",
		"...kPhbebebhpk..",
		"...kphbbbbbhpk..",
		"...kpphbbbhppk..",
		"..kpPpphhhpppk..",
		".kpPppppppppppk.",
		"kpPkpppppppppkpk",
		"kpk.kpPpppppk.kp",
		"kPk.kppppppppk.k",
		".k..kpPppppppk..",
		"....kppppppppk..",
		"....kppppppptk..",
		"....ktppppptk...",
		"....ktptpptk....",
		"....kt.ttt.k....",
		"....t..t..t.....",
		".....t....t.....",
	},
	{
		"......kkkk......",
		".....kPPPpk.....",
		"....kPPpppphk...",
		"....kPhbbbhpk...",
		"...kPhbeeebhpk..",
		"...kphbbbbbhpk..",
		"kk.kpphbbbhppk.k",
		"kPkpPpphhhpppkPk",
		"kPPpPppppppppPPk",
		".kppppppppppppk.",
		"..kppPpppppppk..",
		"...kpppppppppk..",
		"....kpPppppppk..",
		"....kppppppppk..",
		"....ktpppppptk..",
		"....kttppppttk..",
		".....ktpptpttk..",
		".....kt.ttt.tk..",
		"......t..t...t..",
		"......t......t..",
	},
	{
		"................",
		"................",
		"................",
		"................",
		"................",
		"................",
		"................",
		"................",
		"................",
		"................",
		"................",
		"................",
		"................",
		"................",
		"................",
		"................",
		"................",
		".....tttttt.....",
		"...tpPppppPpt...",
		"..ttpppppppptt..",
	},
}

CULTIST_ART :: [4][20]string{
	{
		"......kkkk......",
		".....kRrrrk.....",
		"....kRrrrrDk....",
		"....kRffffDk....",
		"....krfefefk....",
		"....krffffDk....",
		"...kRrrffrrDk...",
		"..kRrrorrorrDk..",
		"..kRrrrorrrrDk..",
		".kRrkrrorrrkrDk.",
		".kRrkrrorrrkrDk.",
		".ksskrrorrrkssk.",
		"..kk.krorrrk.kk.",
		".....kRrorrDk...",
		"....kRrrorrrDk..",
		"....kRrrorrrDk..",
		"...kRrrrorrrrDk.",
		"...kRrrrorrrrDk.",
		"...kRrrrrrrrrDk.",
		"...kkkkkkkkkkkk.",
	},
	{
		"......kkkk......",
		".....kRrrrk.....",
		"....kRrrrrDk....",
		"....kRffffDk....",
		"....krfefefk....",
		"....krffffDk....",
		"...kRrrffrrDk...",
		"..kRrrorrorrDk..",
		"..kRrrrorrrrDk..",
		".kRrkrrorrrkrDk.",
		".kRrkrrorrrkrDk.",
		".ksskrrorrrkssk.",
		"..kk.krorrrk.kk.",
		".....kRrorrDk...",
		"....kRrrorrrDk..",
		"....kRrrorrrDk..",
		"..kRrrrorrrrDk..",
		"..kRrrrorrrrDk..",
		"..kRrrrrrrrrDk..",
		"..kkkkkkkkkkkk..",
	},
	{
		".......hh.......",
		"......hHHh......",
		"..ks..hHHh..sk..",
		"..ksk..hh..ksk..",
		"...kRkkkkkkRk...",
		"...kRkRrrrkRk...",
		"...kRkRffDkRk...",
		"...kRkfefekRk...",
		"....kRrffrrDk...",
		"...kRrrorrorDk..",
		"...kRrrorrrrDk..",
		"...kRrrorrrrDk..",
		"...kRrrorrrrDk..",
		"...kRrrorrrrDk..",
		"...kRrrrorrrrDk.",
		"...kRrrrorrrrDk.",
		"...kRrrrorrrrDk.",
		"...kRrrrorrrrDk.",
		"...kRrrrrrrrrDk.",
		"...kkkkkkkkkkkk.",
	},
	{
		"................",
		"................",
		"................",
		"................",
		"................",
		"................",
		"................",
		"................",
		"................",
		"................",
		"................",
		"................",
		"................",
		"................",
		"................",
		"................",
		"................",
		"....kkkkkkkk....",
		"..kRrrorrrrrDk..",
		".kkkkkkkkkkkkkk.",
	},
}

RUNE_ART :: [2][16]string{
	{
		"...kkkkkk...",
		"..kSSSSssk..",
		".kSSsssssdk.",
		".kSsGGGGsdk.",
		".kSssGgssdk.",
		".kSsgsGsgdk.",
		".kSsgGGGgdk.",
		".kSssGgssdk.",
		".kSsgsGsgdk.",
		".kSssGgssdk.",
		".kSsGGGGsdk.",
		".kSssssssdk.",
		".kSsssssddk.",
		".kssssssddk.",
		"..kddddddk..",
		"...kkkkkk...",
	},
	{
		"...kkkkkk...",
		"..kdddddsk..",
		".kddddddsdk.",
		".kdsssssddk.",
		".kdsddddsdk.",
		".kdsdssdsdk.",
		".kdsdssdsdk.",
		".kdsddddsdk.",
		".kdsssssddk.",
		".kddddddddk.",
		".kdsddddsdk.",
		".kddddddddk.",
		".kdddddddkk.",
		".kddddddddk.",
		"..kddddddk..",
		"...kkkkkk...",
	},
}

HEALTH_ART :: [1][12]string{
	{
		"...kkkk...",
		"...kcck...",
		"...kcck...",
		"...kggk...",
		"..kgggggk.",
		".kgwRRRrgk",
		".kgwRRrrdk",
		".kgRRrrrdk",
		".kgRrrrddk",
		".kgrrrrddk",
		"..kgddddk.",
		"...kkkkk..",
	},
}

MANA_ART :: [1][12]string{
	{
		"....kk....",
		"...kBwk...",
		"..kBBbvk..",
		"..kBwbvk..",
		".kBBbbvdk.",
		".kBwbbvdk.",
		".kBbbbvdk.",
		".kbbbvvdk.",
		"..kbbvdk..",
		"..kbvvdk..",
		"...kvdk...",
		"....kk....",
	},
}

STAFF_ART :: [2][32]string{
	{
		"....kkkk....",
		"...kHHCck...",
		"..kHCCCcck..",
		"..kCCCccck..",
		"..kCCcccck..",
		".okCcccccko.",
		".oOkcccckOo.",
		"..oOkcckOo..",
		"...oOkkOo...",
		"....oOOo....",
		"....kWwk....",
		"....kWwk....",
		"....oOOo....",
		"....kWwk....",
		"....kWdk....",
		"....kWwk....",
		"....kwdk....",
		"....kWwk....",
		"....kWdk....",
		"....oOOo....",
		"..kkkWwkkk..",
		".kGGgWwgGGk.",
		"kGgggWwgggGk",
		"kGgggkkgggGk",
		"kGGgggggggGk",
		"kgGGggggGGgk",
		".kgggggggggk",
		".kllllllllk.",
		".kllllllllk.",
		"..kllllllk..",
		"..kllllllk..",
		"..kllllllk..",
	},
	{
		"....kHHk....",
		"...kHHHHk...",
		"..kHHHHCHk..",
		"..kHHHCCCk..",
		"..kHHCCCCk..",
		".okHCCCCCko.",
		".oOkCCCCkOo.",
		"..oOkCCkOo..",
		"...oOkkOo...",
		"....oOOo....",
		"....kWwk....",
		"....kWwk....",
		"....oOOo....",
		"....kWwk....",
		"....kWdk....",
		"....kWwk....",
		"....kwdk....",
		"....kWwk....",
		"....kWdk....",
		"....oOOo....",
		"..kkkWwkkk..",
		".kGGgWwgGGk.",
		"kGgggWwgggGk",
		"kGgggkkgggGk",
		"kGGgggggggGk",
		"kgGGggggGGgk",
		".kgggggggggk",
		".kllllllllk.",
		".kllllllllk.",
		"..kllllllk..",
		"..kllllllk..",
		"..kllllllk..",
	},
}

CANDLE_ART :: [1][8]string{
	{
		"......",
		"..kk..",
		".kwWk.",
		".kwWk.",
		".kwWk.",
		".kwWk.",
		"kwwwWk",
		"kkkkkk",
	},
}

FLAME_ART :: [2][8]string{
	{
		"..f..",
		"..f..",
		".fFf.",
		".fFf.",
		"fFHFf",
		"fFHFf",
		".fFf.",
		"..f..",
	},
	{
		"...f.",
		"..f..",
		".fFf.",
		"fFFf.",
		"fFHFf",
		".FHFf",
		".fFf.",
		"..f..",
	},
}

SKULL_ART :: [1][7]string{
	{
		"..kkkk..",
		".kwwwwk.",
		"kwwwwwwk",
		"kwbwwbwk",
		"kwwkkwwk",
		".kwwwwk.",
		"..kwkwk.",
	},
}

BONES_ART :: [1][5]string{
	{
		"..k......k..",
		".kwk....kwk.",
		"kwwwwwwwwwwk",
		".kwk....kwk.",
		"..k......k..",
	},
}

BRAZIER_ART :: [1][12]string{
	{
		"kkkkkkkkkk",
		"kiIIIIIIik",
		".kiiiiiik.",
		"..kiiiik..",
		"...kiik...",
		"....kk....",
		"....ik....",
		"....ki....",
		"....ik....",
		"...kiik...",
		"..kiiiik..",
		".kkkkkkkk.",
	},
}

@(private)
palette_for :: proc(id: Sprite_Id) -> gfx.Pixel_Palette {
	p: gfx.Pixel_Palette
	set :: gfx.palette_set
	set(&p, 'W', rl.WHITE)
	switch id {
	case .Ghoul:
		set(&p, 'k', {16, 18, 16, 255})
		set(&p, 'd', {62, 80, 58, 255})
		set(&p, 'g', {104, 126, 92, 255})
		set(&p, 'G', {150, 168, 124, 255})
		set(&p, 'r', {255, 70, 40, 255})
		set(&p, 'm', {46, 12, 14, 255})
		set(&p, 'w', {226, 214, 182, 255})
		set(&p, 'c', {92, 62, 46, 255})
		set(&p, 'C', {60, 40, 30, 255})
	case .Wraith:
		set(&p, 'k', {26, 36, 56, 220})
		set(&p, 'p', {128, 170, 198, 200})
		set(&p, 'P', {200, 230, 244, 215})
		set(&p, 'h', {58, 78, 106, 225})
		set(&p, 'b', {8, 10, 22, 240})
		set(&p, 'e', {140, 255, 230, 255})
		set(&p, 't', {96, 132, 164, 150})
	case .Cultist:
		set(&p, 'k', {14, 8, 10, 255})
		set(&p, 'D', {82, 14, 22, 255})
		set(&p, 'r', {138, 26, 36, 255})
		set(&p, 'R', {186, 48, 52, 255})
		set(&p, 'f', {24, 16, 18, 255})
		set(&p, 'e', {255, 196, 96, 255})
		set(&p, 'o', {226, 186, 96, 255})
		set(&p, 's', {200, 164, 132, 255})
		set(&p, 'h', {214, 92, 255, 255})
		set(&p, 'H', {250, 220, 255, 255})
	case .Rune:
		set(&p, 'k', {20, 16, 24, 255})
		set(&p, 's', {80, 72, 94, 255})
		set(&p, 'S', {116, 106, 132, 255})
		set(&p, 'd', {50, 44, 62, 255})
		set(&p, 'g', {255, 190, 80, 255})
		set(&p, 'G', {255, 240, 190, 255})
	case .Health:
		set(&p, 'k', {24, 12, 14, 255})
		set(&p, 'r', {200, 30, 40, 255})
		set(&p, 'R', {250, 96, 96, 255})
		set(&p, 'd', {120, 16, 24, 255})
		set(&p, 'c', {150, 108, 64, 255})
		set(&p, 'w', {255, 236, 236, 255})
		set(&p, 'g', {170, 190, 200, 210})
	case .Mana:
		set(&p, 'k', {16, 14, 34, 255})
		set(&p, 'b', {74, 112, 232, 255})
		set(&p, 'B', {150, 192, 255, 255})
		set(&p, 'v', {124, 72, 206, 255})
		set(&p, 'w', {240, 242, 255, 255})
		set(&p, 'd', {40, 40, 112, 255})
	case .Staff:
		set(&p, 'k', {16, 10, 8, 255})
		set(&p, 'w', {49, 61, 76, 255})
		set(&p, 'W', {88, 105, 126, 255})
		set(&p, 'd', {26, 35, 49, 255})
		set(&p, 'o', {200, 156, 72, 255})
		set(&p, 'O', {255, 222, 140, 255})
		set(&p, 'c', {47, 127, 188, 255})
		set(&p, 'C', {116, 202, 251, 255})
		set(&p, 'H', {217, 243, 255, 255})
		set(&p, 'g', {72, 74, 88, 255})
		set(&p, 'G', {136, 140, 158, 255})
		set(&p, 'l', {92, 60, 40, 255})
	case .Candle:
		set(&p, 'k', {44, 34, 26, 255})
		set(&p, 'w', {232, 222, 192, 255})
		set(&p, 'W', {178, 166, 136, 255})
	case .Flame:
		set(&p, 'f', {240, 110, 36, 255})
		set(&p, 'F', {255, 200, 96, 255})
		set(&p, 'H', {255, 252, 230, 255})
	case .Skull:
		set(&p, 'k', {40, 34, 30, 255})
		set(&p, 'w', {214, 204, 176, 255})
		set(&p, 'b', {20, 16, 16, 255})
	case .Bones:
		set(&p, 'k', {40, 34, 30, 255})
		set(&p, 'w', {200, 190, 160, 255})
	case .Brazier:
		set(&p, 'k', {16, 14, 16, 255})
		set(&p, 'i', {72, 66, 72, 255})
		set(&p, 'I', {124, 116, 122, 255})
	}
	return p
}

// White silhouette of a frame, for the hit flash.
@(private)
flash_rows :: proc(rows: []string, allocator := context.temp_allocator) -> []string {
	out := make([]string, len(rows), allocator)
	for row, i in rows {
		b := make([]u8, len(row), allocator)
		for j in 0..<len(row) {
			b[j] = '.' if row[j] == '.' else 'W'
		}
		out[i] = string(b)
	}
	return out
}

// Frame lists for each sprite. Slices point into `storage`, which the caller
// keeps alive until the sprites are built.
Sprite_Art :: struct {
	ghoul:   [4][20]string,
	wraith:  [4][20]string,
	cultist: [4][20]string,
	rune:    [2][16]string,
	health:  [1][12]string,
	mana:    [1][12]string,
	staff:   [2][32]string,
	candle:  [1][8]string,
	flame:   [2][8]string,
	skull:   [1][7]string,
	bones:   [1][5]string,
	brazier: [1][12]string,
}

sprite_art :: proc() -> Sprite_Art {
	return Sprite_Art{
		ghoul = GHOUL_ART, wraith = WRAITH_ART, cultist = CULTIST_ART, rune = RUNE_ART,
		health = HEALTH_ART, mana = MANA_ART, staff = STAFF_ART, candle = CANDLE_ART,
		flame = FLAME_ART, skull = SKULL_ART, bones = BONES_ART, brazier = BRAZIER_ART,
	}
}

// Fills `out` with the frames of one sprite (plus the flash frame for
// enemies) and returns how many were written.
sprite_frames :: proc(art: ^Sprite_Art, id: Sprite_Id, out: []gfx.Frame_Rows) -> int {
	n := 0
	add :: proc(out: []gfx.Frame_Rows, n: ^int, rows: []string) {
		if n^ < len(out) {
			out[n^] = rows
			n^ += 1
		}
	}
	switch id {
	case .Ghoul:
		for &f in art.ghoul {
			add(out, &n, f[:])
		}
		add(out, &n, flash_rows(art.ghoul[0][:]))
	case .Wraith:
		for &f in art.wraith {
			add(out, &n, f[:])
		}
		add(out, &n, flash_rows(art.wraith[0][:]))
	case .Cultist:
		for &f in art.cultist {
			add(out, &n, f[:])
		}
		add(out, &n, flash_rows(art.cultist[0][:]))
	case .Rune:
		for &f in art.rune {
			add(out, &n, f[:])
		}
	case .Health:
		add(out, &n, art.health[0][:])
	case .Mana:
		add(out, &n, art.mana[0][:])
	case .Staff:
		for &f in art.staff {
			add(out, &n, f[:])
		}
	case .Candle:
		add(out, &n, art.candle[0][:])
	case .Flame:
		for &f in art.flame {
			add(out, &n, f[:])
		}
	case .Skull:
		add(out, &n, art.skull[0][:])
	case .Bones:
		add(out, &n, art.bones[0][:])
	case .Brazier:
		add(out, &n, art.brazier[0][:])
	}
	return n
}
