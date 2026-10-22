package render

import rl "vendor:raylib"
import campaign "../campaign"

// Physical loot is another printed cutout in the world. Distinct silhouettes
// let a full-backpack player recognize what remains on the ground.
@(private)
expedition_loot_art :: proc(item:campaign.Item)->(m:Expedition_Paper) {
	m.cutout=true
	cream:=EXPEDITION_PAPER_EDGE;ink:=EXPEDITION_PAPER_INK
	gold:=rl.Color{234,185,79,255};teal:=rl.Color{111,206,200,255};red:=rl.Color{214,87,76,255}
	switch item.kind {
	case .Healing:
		if item.variant>0 {
			paper_disc(&m,0,.3,.29,.15,teal)
			paper_tri(&m,{.2,.3},{.39,.46},{.39,.14},teal)
			paper_box(&m,-.18,.31,.05,.05,ink,false)
		} else {
			paper_box(&m,-.26,.08,.52,.43,red);paper_box(&m,-.12,.51,.24,.07,cream)
			paper_box(&m,-.045,.16,.09,.27,cream,false);paper_box(&m,-.135,.25,.27,.09,cream,false)
		}
	case .Energy:
		paper_box(&m,-.19,.08,.38,.48,teal);paper_box(&m,-.08,.56,.16,.06,gold)
		paper_tri(&m,{.03,.49},{-.11,.28},{.04,.28},cream,false)
		paper_tri(&m,{-.03,.17},{.11,.38},{-.04,.38},cream,false)
	case .Credits:
		for i in 0..<3 {paper_disc(&m,-.12+f32(i)*.11,.22+f32(i%2)*.12,.18,.19,gold)}
		paper_box(&m,.06,.16,.07,.17,cream,false)
	case .Temporary_Card,.Memory:
		paper_box(&m,-.23,.06,.46,.56,teal if item.kind==.Temporary_Card else gold)
		paper_box(&m,-.16,.14,.32,.32,ink,false)
		if item.kind==.Memory {
			paper_disc(&m,0,.31,.09,.1,red,false)
			paper_tri(&m,{-.09,.31},{.09,.31},{0,.17},red,false)
		} else {paper_box(&m,-.09,.23,.18,.15,teal,false)}
		paper_box(&m,-.12,.51,.24,.035,cream,false)
	case .Weapon:
		paper_limb(&m,{-.23,.08},{.19,.62},.095,{140,105,70,255})
		paper_tri(&m,{.01,.43},{.09,.7},{.37,.56},{185,210,218,255})
	case .Relic:
		paper_disc(&m,0,.34,.26,.27,gold)
		paper_disc(&m,0,.34,.17,.18,ink,false)
		paper_tri(&m,{0,.49},{-.12,.29},{.12,.29},teal,false)
	case .Upgrade:
		paper_tri(&m,{0,.66},{-.28,.32},{.28,.32},teal)
		paper_tri(&m,{0,.06},{.28,.32},{-.28,.32},teal)
		paper_limb(&m,{0,.2},{0,.48},.06,cream,false)
	case .Decoy:
		paper_disc(&m,0,.29,.23,.19,teal)
		paper_limb(&m,{0,.45},{.09,.64},.04,gold)
		for side in ([2]f32{-1,1}) {paper_box(&m,side*.095-.035,.29,.07,.065,cream,false)}
	case .Backpack:
		paper_box(&m,-.14,.48,.28,.12,{119,82,52,255})
		paper_box(&m,-.27,.06,.54,.48,{191,135,69,255})
		paper_box(&m,-.18,.1,.36,.2,gold);paper_box(&m,-.04,.35,.08,.12,cream,false)
	case .None:
	}
	return
}
