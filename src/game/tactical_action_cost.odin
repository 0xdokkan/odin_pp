package game

// M7 charges time only after a valid action. These prices are also consumed by
// the hand and inspector; classic combat keeps its action-per-pulse economy.
TACTICAL_MOVE_SECONDS :: f32(1)
TACTICAL_ATTACK_SECONDS :: f32(1)
TACTICAL_DODGE_SECONDS :: f32(1)
TACTICAL_REFOCUS_SECONDS :: f32(2)

tactical_card_time_cost :: proc(id: Card_Id) -> f32 {
	switch id {
	case .Guard, .Thorn_Coat, .Afterimage, .Counter_Rune, .Battle_Focus,
	     .Calculated_Risk, .Spark_Forge, .Spark, .Purifying_Guard, .Volatile_Study, .Sei_Denari, .Sette_Denari:
		return 1
	case .Strike, .Arc_Bolt, .Shove, .Dash, .Grappling_Hook, .Venom_Needle, .Fate_Strike, .Tesla_Coil:
		return 2
	case .Piercing_Ray, .Cross_Slash, .Heavy_Blow, .Sundering_Blow, .Twin_Venom, .Shock_Floor, .Titan_Grip:
		return 3
	case .Firebomb, .Toxic_Wave, .Caustic_Bloom, .Chain_Lightning, .Prismatic_Barrage, .Storm_Crown:
		return 4
	// Movimento Ombra takes no window time: its four seconds stand outside it.
	case .Shadow_Step, .Count:
		return 0
	}
	return 0
}
