package game

import grid "../engine/grid"

// The guardians share the reliable intent/recovery machinery, with different
// readable attacks. Crosses and rings stay fixed through their windup; moving
// off their highlighted cells is always a valid answer.
@(private)
expedition_boss_area :: proc(room:^Room,enemy:^Enemy,origin:grid.Position,ring:bool,requested_radius:int)->Enemy_Intent {
	radius := min(requested_radius, 2 if ring else 4)
	intent:=make_attack_intent(room,origin,room.player.position,enemy.attack)
	intent.threatened_cell_count=0
	for y in -radius..=radius {for x in -radius..=radius {
		d:=max(abs(x),abs(y))
		if d==0 || (ring && d!=radius) || (!ring && x!=0 && y!=0) {continue}
		p:=grid.Position{origin.x+x,origin.y+y}
		if !grid.contains(&room.level_data.tiles,p) || !enemy_has_lob_line(room,origin,p) {continue}
		if intent.threatened_cell_count<len(intent.threatened_cells) {
			intent.threatened_cells[intent.threatened_cell_count]=p;intent.threatened_cell_count+=1
		}
	}}
	if intent.threatened_cell_count==0 {return make_wait_intent(room,origin)}
	intent.windup=!enemy.aim_ready
	return intent
}

@(private)
plan_expedition_boss :: proc(room:^Room,enemy:^Enemy,origin:grid.Position,
	positions:^[MAX_ENEMIES_PER_ROOM]grid.Position,count,index:int,bombs:[]grid.Position)->Enemy_Intent {
	biome:=room.player.tactical.config.expedition_biome
	if max(abs(origin.x-room.player.position.x),abs(origin.y-room.player.position.y)) > (3 if biome==4 else 6) {
		return plan_chaser_intent(room,enemy,origin,positions,count,index)
	}
	// Outlaw and Seraph aim deliberate shots. Jungle and Snow charge farther;
	// the masked killer and Oyabun force close combat between recoveries.
	switch biome {
	case 1,9:
		if biome==9 && enemy.boss_phase>=2 && enemy.boss_cycle%2==1 {return expedition_boss_area(room,enemy,origin,false,5)}
		return plan_tactical_archer(room,enemy,origin,positions,count,index)
	case 2,6:
		if biome==6 && enemy.boss_cycle%2==0 {return expedition_boss_area(room,enemy,origin,true,2)}
		return plan_brute_intent(room,enemy,origin,positions,count,index,7 if biome==2 else 5)
	case 3,8:
		if biome==3 && enemy.boss_cycle%2==0 {return plan_brute_intent(room,enemy,origin,positions,count,index,3)}
		return plan_chaser_intent(room,enemy,origin,positions,count,index)
	case 4:
		return expedition_boss_area(room,enemy,origin,true,2 if enemy.boss_phase<2 else 3)
	case 5,7,10:
		if biome!=5 && enemy.boss_cycle%2==1 {return expedition_boss_area(room,enemy,origin,biome==7,3 if biome==7 else 6)}
		return plan_tactical_bomber(room,enemy,origin,positions,count,index,bombs)
	case 0:
		return expedition_boss_area(room,enemy,origin,false,5 if enemy.boss_phase<2 else 7)
	case:
		if enemy.boss_cycle%3==0 {return expedition_boss_area(room,enemy,origin,true,3)}
		if enemy.boss_cycle%3==1 {return plan_tactical_bomber(room,enemy,origin,positions,count,index,bombs)}
		return plan_brute_intent(room,enemy,origin,positions,count,index,7)
	}
}
