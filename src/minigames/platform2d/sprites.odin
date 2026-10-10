package platform2d

// Pixel art as rows of characters; every sprite's palette is set up in
// `sprites_create`. Characters face right; draw them flipped to face left.

import rl "vendor:raylib"
import gfx "../../engine/gfx"

PLAYER_UPPER :: [13]string{
	"................",
	"......kkkkk.....",
	".....kHHHhhk....",
	"....kHHhhhhhk...",
	"....kHhhkkkkk...",
	"....khhkffefk...",
	"....khhkfffk....",
	"...kssssssskk...",
	"...kcCsscccck...",
	"..kcCcccccccck..",
	"..kdCccccccck...",
	"..kdcCcccccck...",
	"...kdcccccck....",
}

// Leg rows per pose, appended under the shared upper body.
PLAYER_LEGS :: [6][3]string{
	{"....kkcccckk....", ".....kbbkbbk....", ".....kbk.kbk...."}, // idle
	{"....kkcccckk....", "....kbbk..kbk...", "...kbk.....kbk.."}, // stride A
	{"....kkcccckk....", "......kbbk......", "......kbbk......"}, // passing
	{"....kkcccckk....", "....kbk..kbbk...", "..kbk.....kbk..."}, // stride B
	{"....kkcccckk....", ".....kbbbbk.....", "......kkkk......"}, // tucked (jump)
	{"...kkccccckk....", "...kc.kbbk.ck...", "......kbbk......"}, // dangling (fall)
}

Player_Frame :: enum u8 {
	Idle,
	Blink,
	Run_A,
	Run_B,
	Run_C,
	Jump,
	Fall,
}

GHOUL_FRAMES :: [2][16]string{
	{
		"................",
		"................",
		"................",
		"................",
		".....kkkkk......",
		"....kGGggdk.....",
		"...kGgggggdk....",
		"...kgekgegdk....",
		"...kgggggggk....",
		"...kgtktktgk....",
		"..kdgggggggdk...",
		"..kgkgggggkgk...",
		"..kk.kgggk.kk...",
		".....kdgdk......",
		"....kdk.kdk.....",
		"....kk...kk.....",
	},
	{
		"................",
		"................",
		"................",
		"................",
		"................",
		".....kkkkk......",
		"....kGGggdk.....",
		"...kGgggggdk....",
		"...kgekgegdk....",
		"...kgggggggk....",
		"...kgtktktgk....",
		"..kdgggggggdk...",
		"..kgkgggggkgk...",
		"..kk.kgggk.kk...",
		".....kdkdk......",
		"....kk..kk......",
	},
}

BAT_FRAMES :: [2][8]string{
	{
		"kk............kk",
		"kPk...k..k...kPk",
		"kPPk..kkkk..kPPk",
		".kPPkkppppkkPPk.",
		"..kkkpeppepkkk..",
		"....kppppppk....",
		".....kppppk.....",
		"......kkkk......",
	},
	{
		"......k..k......",
		"......kkkk......",
		"....kkppppkk....",
		"..kkkpeppepkkk..",
		".kPPkppppppkPPk.",
		"kPPk.kppppk.kPPk",
		"kPk...kkkk...kPk",
		"kk............kk",
	},
}

TOTEM_ROWS :: [16]string{
	"................",
	"................",
	"....kkkkkkkk....",
	"...kWWwwwwwsk...",
	"..kWwwwwwwwwsk..",
	"..kweekwweeksk..",
	"..kweekwweeksk..",
	"..kwwwwkkwwwsk..",
	"...kwwwwwwwsk...",
	"...kwkwkwkwsk...",
	"....kkkkkkkk....",
	"....kPpppppk....",
	"....kPpkkppk....",
	"....kPpppppk....",
	"...kPPppppppk...",
	"...kkkkkkkkkk...",
}

EMBER_FRAMES :: [2][8]string{
	{
		"...oo...",
		"..oyyo..",
		".oyYYyo.",
		"oyYYYYyo",
		"oyYYYYyo",
		".oyYYyo.",
		"..oyyo..",
		"...oo...",
	},
	{
		"...oo...",
		"...yo...",
		"..oYyo..",
		"..yYYo..",
		"..oYYy..",
		"..oyYo..",
		"...oy...",
		"...oo...",
	},
}

BRAZIER_ROWS :: [16]string{
	"................",
	"................",
	"................",
	"................",
	"................",
	"................",
	"................",
	"..kkkkkkkkkkkk..",
	"..kIiiiiiiiiik..",
	"...kIccrccrck...",
	"....kIiiiiik....",
	".....kkIikk.....",
	"......kIik......",
	"......kIik......",
	".....kkIikk.....",
	"....kkkkkkkk....",
}

HEART_FRAMES :: [2][8]string{
	{
		".kk...kk.",
		"kRrk.krrk",
		"kRrrkrrrk",
		"krrrrrrrk",
		".krrrrrk.",
		"..krrrk..",
		"...krk...",
		"....k....",
	},
	{
		".kk...kk.",
		"kddk.kddk",
		"kdddkdddk",
		"kdddddddk",
		".kdddddk.",
		"..kdddk..",
		"...kdk...",
		"....k....",
	},
}

Tile_Frame :: enum u8 {
	Stone,
	Stone_Cracked,
	Stone_Top,
	Ledge,
	Spikes,
	Crumble,
}

TILE_FRAMES :: [6][16]string{
	{
		"cccccccaccccccca",
		"cbbbbbbacbbbbbba",
		"cbbbbbbacbbdbbba",
		"cbbdbbbacbbbbbba",
		"cbbbbbbacbbbbbba",
		"cbbbbbbacbbbbbba",
		"bbbbbbbabbbbbbba",
		"aaaaaaaaaaaaaaaa",
		"cccacccccccacccc",
		"bbbacbbbbbbacbbb",
		"bbbacbbbbdbacbbb",
		"bbbacbbbbbbacbbb",
		"bdbacbbbbbbacbdb",
		"bbbacbbbbbbacbbb",
		"bbbabbbbbbbabbbb",
		"aaaaaaaaaaaaaaaa",
	},
	{
		"cccccccaccccccca",
		"cbbbbbbacbbbbbba",
		"cbbbabbacbbbbbba",
		"cbbbbabacbbbbbba",
		"cbbbbbaacbbbbbba",
		"cbbbbbbacbbmbbba",
		"bbbbbbbabbmmbbba",
		"aaaaaaaaaaaaaaaa",
		"cccacccccccacccc",
		"bbbacbbbbbbacbbb",
		"bbbacbbabbbacbbb",
		"bmbacbbbabbacbbb",
		"bmmacbbbbabacbbb",
		"bbbacbbbbbbacbbb",
		"bbbabbbbbbbabbbb",
		"aaaaaaaaaaaaaaaa",
	},
	{
		"ttTTtttTTTttTttt",
		"dtttdttttdtttdtt",
		"cdcccdccccdcccdc",
		"cbbbbbbacbbbbbba",
		"cbbbbbbacbbbbbba",
		"cbbbbbbacbbbbbba",
		"bbbbbbbabbbbbbba",
		"aaaaaaaaaaaaaaaa",
		"cccacccccccacccc",
		"bbbacbbbbbbacbbb",
		"bbbacbbbbdbacbbb",
		"bbbacbbbbbbacbbb",
		"bdbacbbbbbbacbdb",
		"bbbacbbbbbbacbbb",
		"bbbabbbbbbbabbbb",
		"aaaaaaaaaaaaaaaa",
	},
	{
		"WWWWWWWWWWWWWWWW",
		"wwnwwwwwwwwwwnww",
		"wwwwwwwwwwwwwwww",
		"xxxxxxxxxxxxxxxx",
		".x............x.",
		"..x..........x..",
		"...x........x...",
		"................",
		"................",
		"................",
		"................",
		"................",
		"................",
		"................",
		"................",
		"................",
	},
	{
		"................",
		"................",
		"................",
		"................",
		"................",
		".r...r...r...r..",
		".r...r...r...r..",
		".S...S...S...S..",
		".Sh..Sh..Sh..Sh.",
		".Sh..Sh..Sh..Sh.",
		"SSh.SSh.SSh.SSh.",
		"SSh.SSh.SSh.SSh.",
		"SShhSShhSShhSShh",
		"SShhSShhSShhSShh",
		"kkkkkkkkkkkkkkkk",
		"kkkkkkkkkkkkkkkk",
	},
	{
		"QQQQQQQQQQQQQQQy",
		"Qqqqqzqqqqqqqqqy",
		"Qqqqqzqqqqqqqqqy",
		"Qqqqzzqqqqqzqqqy",
		"Qqqzqqqqqqzqqqqy",
		"Qqqqqqqqqzqqqqqy",
		"Qzzqqqqqzqqqqqqy",
		"Qqqzzqqzqqqqqqqy",
		"Qqqqqzzqqqqzzzqy",
		"Qqqqqqzqqqzqqqqy",
		"Qqqqqqqzqzqqqqqy",
		"Qqqzqqqqzqqqqqqy",
		"Qqqqzqqqzqqqqqqy",
		"Qqqqqzqqqzqqqqqy",
		"Qqqqqqqqqqqqqqqy",
		"yyyyyyyyyyyyyyyy",
	},
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

// Player frames assembled from the shared body and the per-pose legs.
player_frame_rows :: proc(frame: Player_Frame) -> [16]string {
	upper := PLAYER_UPPER
	legs := PLAYER_LEGS
	rows: [16]string
	for i in 0..<13 {
		rows[i] = upper[i]
	}
	if frame == .Blink {
		rows[5] = "....khhkffffk..."
	}
	pose := 0
	switch frame {
	case .Idle, .Blink:
		pose = 0
	case .Run_A:
		pose = 1
	case .Run_B:
		pose = 2
	case .Run_C:
		pose = 3
	case .Jump:
		pose = 4
	case .Fall:
		pose = 5
	}
	for i in 0..<3 {
		rows[13+i] = legs[pose][i]
	}
	return rows
}

sprites_create :: proc() -> Sprites {
	s: Sprites
	pal: gfx.Pixel_Palette

	pal = {}
	gfx.palette_set(&pal, 'k', {20, 16, 26, 255})
	gfx.palette_set(&pal, 'h', {177, 166, 144, 255})
	gfx.palette_set(&pal, 'H', {234, 225, 204, 255})
	gfx.palette_set(&pal, 'f', {26, 20, 32, 255})
	gfx.palette_set(&pal, 'e', {146, 220, 255, 255})
	gfx.palette_set(&pal, 'c', {39, 49, 65, 255})
	gfx.palette_set(&pal, 'C', {81, 100, 120, 255})
	gfx.palette_set(&pal, 'd', {22, 31, 44, 255})
	gfx.palette_set(&pal, 's', {236, 226, 204, 255})
	gfx.palette_set(&pal, 'b', {46, 42, 56, 255})
	player_rows: [len(Player_Frame)][16]string
	player_frames: [len(Player_Frame)]gfx.Frame_Rows
	for f in Player_Frame {
		player_rows[f] = player_frame_rows(f)
		player_frames[f] = player_rows[f][:]
	}
	s.player, _ = gfx.sprite_create(player_frames[:], &pal)

	pal = {}
	// Pale and sickly, so it reads against the red-lit slate.
	gfx.palette_set(&pal, 'k', {14, 16, 12, 255})
	gfx.palette_set(&pal, 'g', {152, 69, 72, 255})
	gfx.palette_set(&pal, 'G', {211, 102, 96, 255})
	gfx.palette_set(&pal, 'd', {91, 38, 47, 255})
	gfx.palette_set(&pal, 'e', {255, 128, 64, 255})
	gfx.palette_set(&pal, 't', {222, 212, 192, 255})
	ghoul := GHOUL_FRAMES
	s.ghoul, _ = gfx.sprite_create({ghoul[0][:], ghoul[1][:]}, &pal)

	pal = {}
	gfx.palette_set(&pal, 'k', {16, 12, 20, 255})
	gfx.palette_set(&pal, 'p', {40, 62, 82, 255})
	gfx.palette_set(&pal, 'P', {83, 115, 145, 255})
	gfx.palette_set(&pal, 'e', {255, 84, 64, 255})
	bat := BAT_FRAMES
	s.bat, _ = gfx.sprite_create({bat[0][:], bat[1][:]}, &pal)

	pal = {}
	gfx.palette_set(&pal, 'k', {18, 14, 20, 255})
	gfx.palette_set(&pal, 'w', {214, 204, 184, 255})
	gfx.palette_set(&pal, 'W', {242, 234, 216, 255})
	gfx.palette_set(&pal, 's', {150, 140, 128, 255})
	gfx.palette_set(&pal, 'e', {34, 22, 26, 255})
	gfx.palette_set(&pal, 'p', {70, 64, 82, 255})
	gfx.palette_set(&pal, 'P', {100, 94, 112, 255})
	totem := TOTEM_ROWS
	s.totem, _ = gfx.sprite_create({totem[:]}, &pal)

	pal = {}
	gfx.palette_set(&pal, 'o', {236, 112, 40, 255})
	gfx.palette_set(&pal, 'y', {255, 198, 88, 255})
	gfx.palette_set(&pal, 'Y', {255, 248, 214, 255})
	ember := EMBER_FRAMES
	s.ember, _ = gfx.sprite_create({ember[0][:], ember[1][:]}, &pal)

	pal = {}
	gfx.palette_set(&pal, 'k', {16, 14, 20, 255})
	gfx.palette_set(&pal, 'i', {72, 72, 86, 255})
	gfx.palette_set(&pal, 'I', {112, 112, 130, 255})
	gfx.palette_set(&pal, 'c', {40, 36, 48, 255})
	gfx.palette_set(&pal, 'r', {200, 72, 40, 255})
	brazier := BRAZIER_ROWS
	s.brazier, _ = gfx.sprite_create({brazier[:]}, &pal)

	pal = {}
	gfx.palette_set(&pal, 'k', {28, 10, 16, 255})
	gfx.palette_set(&pal, 'r', {214, 48, 60, 255})
	gfx.palette_set(&pal, 'R', {255, 136, 130, 255})
	gfx.palette_set(&pal, 'd', {58, 38, 48, 255})
	heart := HEART_FRAMES
	s.heart, _ = gfx.sprite_create({heart[0][:], heart[1][:]}, &pal)

	pal = {}
	// Stone
	gfx.palette_set(&pal, 'a', {26, 27, 38, 255})
	gfx.palette_set(&pal, 'b', {48, 50, 66, 255})
	gfx.palette_set(&pal, 'c', {64, 66, 86, 255})
	gfx.palette_set(&pal, 'd', {86, 88, 110, 255})
	gfx.palette_set(&pal, 't', {113, 145, 170, 255})
	gfx.palette_set(&pal, 'T', {166, 196, 216, 255})
	gfx.palette_set(&pal, 'm', {65, 97, 122, 255})
	// Ledge planks
	gfx.palette_set(&pal, 'w', {120, 88, 64, 255})
	gfx.palette_set(&pal, 'W', {164, 126, 90, 255})
	gfx.palette_set(&pal, 'x', {66, 46, 38, 255})
	gfx.palette_set(&pal, 'n', {204, 194, 172, 255})
	// Bone spikes
	gfx.palette_set(&pal, 'S', {206, 194, 174, 255})
	gfx.palette_set(&pal, 'h', {120, 108, 102, 255})
	gfx.palette_set(&pal, 'r', {176, 40, 46, 255})
	gfx.palette_set(&pal, 'k', {36, 28, 34, 255})
	// Crumbling sandstone
	gfx.palette_set(&pal, 'q', {128, 100, 76, 255})
	gfx.palette_set(&pal, 'Q', {164, 132, 98, 255})
	gfx.palette_set(&pal, 'z', {84, 62, 50, 255})
	gfx.palette_set(&pal, 'y', {62, 46, 40, 255})
	tiles := TILE_FRAMES
	tile_frames: [len(Tile_Frame)]gfx.Frame_Rows
	for i in 0..<len(Tile_Frame) {
		tile_frames[i] = tiles[i][:]
	}
	s.tiles, _ = gfx.sprite_create(tile_frames[:], &pal)
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
