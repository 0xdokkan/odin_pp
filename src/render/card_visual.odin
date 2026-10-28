package render

import rl "vendor:raylib"
import audio "../engine/audio"
import game "../game"

// Presentation-only metadata. Gameplay numbers and upgrade descriptions still
// come from game.Card_Definition; unique artwork and animations stay in their
// own draw routines. Enum-keyed tables reject a missing card at compile time.
@(private = "file")
Card_Accent :: enum { Red, Green, Purple, Blue, Gold, Electric }
@(private = "file", rodata)
CARD_ACCENTS := [Card_Accent]rl.Color{
	.Red = {130, 43, 45, 255}, .Green = {72, 92, 42, 255},
	.Purple = {98, 57, 122, 255}, .Blue = {60, 84, 93, 255},
	.Gold = {122, 88, 34, 255}, .Electric = {42, 93, 125, 255},
}

@(private = "file")
Card_Visual :: struct {
	icon: int,
	short_name, narrow_name: cstring,
	accent: Card_Accent,
	fill, outline: rl.Color,
	sound: audio.Lab_Sfx,
}

@(private = "file", rodata)
CARD_VISUALS := [game.Card_Id]Card_Visual{
	.Strike = {icon = 0, short_name = "STRIKE", accent = .Red, sound = .Card_Strike,
		fill = {74, 39, 42, 245}, outline = {224, 99, 86, 255}},
	.Arc_Bolt = {icon = 4, short_name = "ARC", accent = .Purple, sound = .Card_Arc_Bolt,
		fill = {31, 52, 67, 245}, outline = {90, 204, 227, 255}},
	.Piercing_Ray = {icon = 4, short_name = "RAY", accent = .Purple, sound = .Card_Piercing_Ray,
		fill = {28, 57, 61, 245}, outline = {91, 214, 204, 255}},
	.Cross_Slash = {icon = 0, short_name = "CROSS", accent = .Red, sound = .Card_Cross_Slash,
		fill = {66, 39, 51, 245}, outline = {232, 119, 162, 255}},
	.Firebomb = {icon = 6, short_name = "BOMB", accent = .Red, sound = .Card_Firebomb,
		fill = {75, 43, 27, 245}, outline = {246, 146, 72, 255}},
	.Guard = {icon = 1, short_name = "GUARD", accent = .Blue, sound = .Card_Guard,
		fill = {34, 55, 69, 245}, outline = {101, 174, 218, 255}},
	.Toxic_Wave = {icon = 2, short_name = "TOXIC", accent = .Green, sound = .Card_Toxic_Wave,
		fill = {35, 62, 43, 245}, outline = {113, 190, 91, 255}},
	.Thorn_Coat = {icon = 7, short_name = "THORNS", accent = .Green, sound = .Card_Thorn_Coat,
		fill = {67, 50, 29, 245}, outline = {238, 174, 73, 255}},
	.Afterimage = {icon = 5, short_name = "AFTER", accent = .Blue, sound = .Card_Afterimage,
		fill = {53, 46, 70, 245}, outline = {194, 184, 226, 255}},
	.Counter_Rune = {icon = 8, short_name = "RUNE", accent = .Red, sound = .Card_Counter_Rune,
		fill = {68, 59, 30, 245}, outline = {246, 207, 92, 255}},
	.Battle_Focus = {icon = 9, short_name = "FOCUS", accent = .Red, sound = .Card_Battle_Focus,
		fill = {31, 61, 56, 245}, outline = {91, 214, 176, 255}},
	.Calculated_Risk = {icon = 9, short_name = "RISK", accent = .Red, sound = .Card_Calculated_Risk,
		fill = {67, 43, 34, 245}, outline = {238, 174, 73, 255}},
	.Spark_Forge = {icon = 10, short_name = "FORGE", accent = .Gold, sound = .Card_Spark_Forge,
		fill = {55, 45, 66, 245}, outline = {209, 151, 236, 255}},
	.Spark = {icon = 10, short_name = "SPARK", accent = .Gold, sound = .Card_Spark,
		fill = {57, 54, 31, 245}, outline = {246, 207, 92, 255}},
	.Shove = {icon = 3, short_name = "SHOVE", accent = .Gold, sound = .Card_Shove,
		fill = {66, 42, 35, 245}, outline = {236, 137, 91, 255}},
	.Dash = {icon = 5, short_name = "DASH", accent = .Blue, sound = .Card_Dash,
		fill = {27, 58, 65, 245}, outline = {80, 206, 213, 255}},
	.Grappling_Hook = {icon = 11, short_name = "HOOK", accent = .Gold, sound = .Card_Grappling_Hook,
		fill = {48, 48, 54, 245}, outline = {187, 190, 197, 255}},
	.Heavy_Blow = {icon = 12, short_name = "HEAVY", accent = .Red, sound = .Card_Heavy_Blow,
		fill = {70, 36, 31, 245}, outline = {244, 126, 75, 255}},
	.Venom_Needle = {icon = 2, short_name = "NEEDLE", accent = .Green, sound = .Card_Venom_Needle,
		fill = {27, 56, 50, 245}, outline = {126, 218, 132, 255}},
	.Caustic_Bloom = {icon = 2, short_name = "BLOOM", accent = .Green, sound = .Card_Caustic_Bloom,
		fill = {56, 59, 27, 245}, outline = {205, 220, 83, 255}},
	.Purifying_Guard = {icon = 15, short_name = "PURIFY", accent = .Blue, sound = .Card_Purifying_Guard,
		fill = {33, 53, 60, 245}, outline = {151, 222, 215, 255}},
	.Volatile_Study = {icon = 9, short_name = "STUDY", accent = .Red, sound = .Card_Volatile_Study,
		fill = {62, 36, 63, 245}, outline = {238, 133, 201, 255}},
	.Fate_Strike = {icon = 13, short_name = "FATE", accent = .Red, sound = .Card_Fate_Strike,
		fill = {61, 42, 77, 245}, outline = {230, 180, 255, 255}},
	.Chain_Lightning = {icon = 14, short_name = "CHAIN", accent = .Purple, sound = .Card_Chain_Lightning,
		fill = {25, 52, 73, 245}, outline = {119, 224, 255, 255}},
	.Sundering_Blow = {icon = 12, short_name = "SUNDER", accent = .Red, sound = .Card_Sundering_Blow,
		fill = {74, 29, 34, 245}, outline = {245, 94, 100, 255}},
	.Prismatic_Barrage = {icon = 13, short_name = "BARRAGE", accent = .Red, sound = .Card_Prismatic_Barrage,
		fill = {65, 48, 75, 245}, outline = {247, 198, 112, 255}},
	.Twin_Venom = {icon = 2, short_name = "VENOM", accent = .Green, sound = .Card_Twin_Venom,
		fill = {40, 58, 31, 245}, outline = {179, 237, 111, 255}},
	.Shock_Floor = {icon = 14, short_name = "FLOOR", accent = .Electric, sound = .Card_Shock_Floor,
		fill = {25, 52, 73, 245}, outline = {119, 224, 255, 255}},
	.Tesla_Coil = {icon = 14, short_name = "TESLA", accent = .Electric, sound = .Card_Tesla_Coil,
		fill = {25, 52, 73, 245}, outline = {119, 224, 255, 255}},
	.Titan_Grip = {icon = 12, short_name = "TITAN", accent = .Red, sound = .Card_Titan_Grip,
		fill = {70, 36, 31, 245}, outline = {244, 126, 75, 255}},
	.Storm_Crown = {icon = 14, short_name = "CROWN", accent = .Electric, sound = .Card_Storm_Crown,
		fill = {25, 52, 73, 245}, outline = {119, 224, 255, 255}},
	.Sei_Denari = {icon = 9, short_name = "6 ORO", accent = .Red, sound = .Card_Sei_Denari,
		fill = {72, 54, 24, 245}, outline = {236, 196, 96, 255}},
	.Sette_Denari = {icon = 9, short_name = "7 ORO", accent = .Red, sound = .Card_Sette_Denari,
		fill = {72, 54, 24, 245}, outline = {236, 196, 96, 255}},
	.Shadow_Step = {icon = 16, short_name = "OMBRA", accent = .Purple, sound = .Card_Shadow_Step, narrow_name = "Ombra",
		fill = {33, 26, 48, 245}, outline = {164, 144, 183, 255}},
	.Poison_Pool = {icon = 17, short_name = "POZZA", accent = .Green, sound = .Card_Poison_Pool, narrow_name = "Pozza",
		fill = {28, 58, 40, 245}, outline = {126, 206, 104, 255}},
	.Wildfire = {icon = 18, short_name = "FUOCO", accent = .Red, sound = .Card_Wildfire,
		fill = {78, 36, 22, 245}, outline = {250, 136, 60, 255}},
	.Deflect = {icon = 19, short_name = "RIFLESSO", accent = .Blue, sound = .Card_Deflect,
		fill = {30, 50, 66, 245}, outline = {150, 196, 228, 255}},
	.Coffin = {icon = 20, short_name = "FERETRO", accent = .Gold, sound = .Card_Coffin,
		fill = {60, 46, 30, 245}, outline = {226, 186, 120, 255}},
	.Fate_Dice = {icon = 21, short_name = "DESTINO", accent = .Purple, sound = .Card_Fate_Dice, narrow_name = "Dado",
		fill = {52, 34, 70, 245}, outline = {214, 170, 250, 255}},
	.Venom_Blade = {icon = 22, short_name = "LAMA", accent = .Green, sound = .Card_Venom_Blade, narrow_name = "Lama",
		fill = {30, 56, 40, 245}, outline = {150, 226, 110, 255}},
	.Lasso = {icon = 23, short_name = "LAZZO", accent = .Gold, sound = .Card_Lasso,
		fill = {70, 52, 30, 245}, outline = {222, 178, 110, 255}},
	.Fishing_Rod = {icon = 24, short_name = "CANNA", accent = .Blue, sound = .Card_Fishing_Rod, narrow_name = "Canna",
		fill = {26, 48, 72, 245}, outline = {118, 186, 236, 255}},
	.Pinball = {icon = 25, short_name = "PINBALL", accent = .Blue, sound = LAB_PINBALL_CARD,
		fill = {44, 50, 60, 245}, outline = {196, 206, 220, 255}},
	.First_Person = {icon = 26, short_name = "FPS", accent = .Red, sound = LAB_FIRST_PERSON_CARD, narrow_name = "FPS",
		fill = {40, 46, 38, 245}, outline = {176, 186, 132, 255}},
	// The provisional tag, glove and sound until Fase 3 (docs/piano-prima-persona.md).
	.First_Person_Brawler = {icon = 33, short_name = "FPB", accent = .Red, sound = .Card_First_Person_Brawler, narrow_name = "FPB",
		fill = {64, 30, 30, 245}, outline = {232, 120, 112, 255}},
	.Cannon = {icon = 4, short_name = "CANNONE", accent = .Electric, sound = .World_Barrel_Explosion,
		fill = {27, 56, 72, 245}, outline = {105, 215, 255, 255}},
	.Flood = {icon = 4, short_name = "ONDA", accent = .Blue, sound = .World_Pool_Splash,
		fill = {22, 48, 75, 245}, outline = {100, 185, 250, 255}},
	.Black_Hole = {icon = 13, short_name = "BUCO NERO", accent = .Purple, sound = .World_Tesla_Ring,
		fill = {37, 23, 60, 245}, outline = {198, 120, 255, 255}},
	.Bomb_Marley = {icon = 6, short_name = "BOMB MARLEY", accent = .Red, sound = .World_Bomb_Fuse,
		fill = {68, 37, 24, 245}, outline = {255, 155, 68, 255}},
	.Dinosaur = {icon = 12, short_name = "DINOSAURO", accent = .Green, sound = .Brute_Charge,
		fill = {28, 59, 36, 245}, outline = {164, 224, 105, 255}},
	.Marley_Party = {icon = 27, short_name = "MARLEY", accent = .Gold, sound = .Card_Bomb_Marley, narrow_name = "Marley",
		fill = {46, 50, 28, 245}, outline = {240, 196, 64, 255}},
	.Flood_Wave = {icon = 28, short_name = "ONDA", accent = .Blue, sound = .Card_Flood, narrow_name = "Onda",
		fill = {22, 50, 76, 245}, outline = {96, 176, 240, 255}},
	.Field_Cannon = {icon = 29, short_name = "CANNONE", accent = .Gold, sound = .Card_Cannon, narrow_name = "Cannone",
		fill = {52, 46, 34, 245}, outline = {222, 178, 110, 255}},
	.Laser_Cannon = {icon = 30, short_name = "LASER", accent = .Red, sound = .Card_Laser_Cannon, narrow_name = "Laser",
		fill = {62, 28, 36, 245}, outline = {255, 96, 96, 255}},
	.Devouring_Hole = {icon = 31, short_name = "BUCO", accent = .Purple, sound = .Card_Black_Hole, narrow_name = "Buco",
		fill = {24, 20, 40, 245}, outline = {160, 120, 240, 255}},
	.Dino_Ride = {icon = 32, short_name = "DINO", accent = .Green, sound = .Card_Dinosaur, narrow_name = "Dino",
		fill = {34, 56, 36, 245}, outline = {124, 206, 96, 255}},
	.Count = {icon = 0, short_name = "", accent = .Red,
		fill = {45, 49, 52, 245}, outline = {105, 116, 116, 255}},
}

@(private = "file")
card_visual :: proc(id: game.Card_Id) -> Card_Visual {
	if id < .Strike || id > .Count { return {short_name = ""} }
	return CARD_VISUALS[id]
}

@(private)
card_colors :: proc(id: game.Card_Id, affordable: bool) -> (fill, outline: rl.Color) {
	if !affordable { return {39, 42, 45, 245}, {91, 96, 98, 255} }
	visual := card_visual(id)
	return visual.fill, visual.outline
}

@(private)
card_short_name :: proc(id: game.Card_Id) -> cstring { return card_visual(id).short_name }
@(private)
gothic_card_icon :: proc(id: game.Card_Id) -> int { return card_visual(id).icon }
@(private)
gothic_card_accent :: proc(id: game.Card_Id) -> rl.Color { return CARD_ACCENTS[card_visual(id).accent] }

// Narrow faces may abbreviate a name; the inspector keeps its full catalog name.
@(private)
gothic_card_narrow_name :: proc(id: game.Card_Id) -> (name: cstring, found: bool) {
	name = card_visual(id).narrow_name
	return name, name != nil
}

lab_card_sfx :: proc(id: game.Card_Id) -> (sfx: audio.Lab_Sfx, ok: bool) {
	return card_visual(id).sound, id >= .Strike && id < .Count
}
