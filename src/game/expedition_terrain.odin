package game

import grid "../engine/grid"
import level "../level"

Expedition_Terrain :: enum u8 { Plain, Electric, Sand, Grass, Water, Ice, Snow, Lava, Swamp, Bridge, Gravity }

// Fixed irregular patches leave open plains between hazards. Adjacent cells
// share a patch, instead of the former modulo pattern's dense checkerboard.
@(private)
expedition_patch_distance :: proc(b:u8,p:grid.Position)->(best,variation:int) {
	best=10000
	for gy in p.y/12-1..=p.y/12+1 {for gx in p.x/12-1..=p.x/12+1 {
		h:=u32(gx+4096)*0x9e3779b9 ~ u32(gy+4096)*0x85ebca6b ~ u32(b)*0xc2b2ae35
		h~=h>>16
		x,y:=gx*12+3+int(h%7),gy*12+3+int((h>>8)%7)
		if gx==0 && gy==0 {x,y=2,2}
		d:=(p.x-x)*(p.x-x)+(p.y-y)*(p.y-y)
		if d<best {best=d;variation=int((h>>16)%3)}
	}}
	return
}

// Biome IDs are serialized values shared with campaign.Biome. Exploration,
// combat, previews and presentation all query this same fixed geography.
expedition_terrain :: proc(b: u8, p: grid.Position) -> Expedition_Terrain {
	// The biome's ground is the open map's: a cave under the rock has none (Fase 5 of docs/piano-profondita.md).
	if p.layer != grid.GROUND_LAYER { return .Plain }
	n := (p.x*13+p.y*7+int(b)*19)%37
	switch b {
	case 0: if n < 2 { return .Electric }
	case 2: d,v:=expedition_patch_distance(b,p);if d<=7+v*3 {return .Grass}
	case 4: d,v:=expedition_patch_distance(b,p);if d<=8+v*4 {return .Sand}
	case 5: if p.y%19 < 4 { return .Water }
	case 6:
		// The spiral mountain's path is packed snow, with two stretches of ice (level/mountain.odin).
		offset:=grid.offset(p, -level.MOUNTAIN_CENTER.x, -level.MOUNTAIN_CENTER.y)
		if abs(offset.x)<=level.MOUNTAIN_HALF && abs(offset.y)<=level.MOUNTAIN_HALF {return .Ice if level.mountain_icy(offset) else .Plain}
		d,v:=expedition_patch_distance(b,p);if d<=6+v*2 {return .Ice};if d<=17+v*3 {return .Snow}
	case 7: if (p.x+p.y/2)%23 < 3 { return .Lava }
	case 8: d,v:=expedition_patch_distance(b,p);if d<=9+v*3 {return .Swamp}
	case 9: if p.x%24 >= 21 || p.y%24 >= 21 { return .Bridge }
	case 10: if n < 3 { return .Gravity }
	}
	return .Plain
}

// Open Inferno maps do not contain doors. Their walkable Door tile is the
// persistent marker for a floor plate fractured by an eruption. Keeping the
// marker in the level makes it survive the ordinary complete tile snapshot.
expedition_ground :: proc(room: ^Room, p: grid.Position) -> Expedition_Terrain {
	if room==nil || room.player==nil {return .Plain}
	biome:=room.player.tactical.config.expedition_biome
	if biome==7 && room.level_data!=nil {
		if tile,ok:=level.tile_at(room.level_data,p);ok && tile.kind==.Door {return .Lava}
	}
	return expedition_terrain(biome,p)
}

expedition_fracture_floor :: proc(room: ^Room,p: grid.Position) -> bool {
	if room==nil || room.player==nil || room.level_data==nil || !room.player.tactical.config.expedition ||
		room.player.tactical.config.expedition_biome!=7 {return false}
	tile,ok:=level.tile_at(room.level_data,p)
	if !ok || tile.kind!=.Floor || expedition_terrain(7,p)==.Lava {return false}
	return level.set_tile(room.level_data,p,{.Door})
}

@(private)
expedition_bridge_open :: proc(room: ^Room, position: grid.Position) -> bool {
	return room == nil || room.player == nil || !room.player.tactical.config.expedition ||
		expedition_terrain(room.player.tactical.config.expedition_biome, position) != .Bridge ||
		room.player.tactical.environment_beat%4 < 2
}

@(private)
expedition_step_seconds :: proc(room: ^Room) -> f32 {
	if room == nil || room.player == nil {return TACTICAL_MOVE_SECONDS}
	// Riding the lab's Velociraptor steps faster (dinosaur.odin).
	seconds := player_move_seconds(room)
	if room.player.tactical.dinosaur_remaining > 0 {seconds *= 0.75}
	if !room.player.tactical.config.expedition {return seconds}
	ground := expedition_terrain(room.player.tactical.config.expedition_biome, room.player.position)
	if ground == .Sand || ground == .Water || ground == .Snow || ground == .Swamp {seconds *= 2}
	return seconds
}

@(private)
expedition_terrain_entry :: proc(room: ^Room, target: Entity_Ref, report: ^Action_Report) {
	if room == nil || room.player == nil || !room.player.tactical.config.expedition || !entity_exists(room, target) {return}
	position, found := entity_position(room, target)
	if !found {return}
	ground := expedition_ground(room, position)
	action := make_action(.Trigger, SYSTEM_ENTITY, entity_target(target), .Entity)
	if ground == .Lava {
		if target == PLAYER_ENTITY { add_effect(&action, damage_effect(target, 2+room.player.stats.defense)) }
		else if target.kind == .Enemy { add_effect(&action, apply_status_effect(target, .Burn, 1, 0)) }
	} else if ground == .Electric && room.player.tactical.environment_beat%4 == 0 {
		add_effect(&action, damage_effect(target, 1))
	}
	if action.effect_count > 0 {
		hit := resolve_action(room, &action)
		merge_spell_hit_report(report, &hit)
	}
}

@(private)
expedition_terrain_beat :: proc(room: ^Room, pulse: ^Pulse_Report) {
	if room.phase != .Combat {return}
	s := &room.player.tactical
	if s.encounter_beats%4==0 {expedition_gravity_pulse(room,&pulse.events)}
	if expedition_ground(room, room.player.position) == .Lava {
		action := make_action(.Trigger, SYSTEM_ENTITY, entity_target(PLAYER_ENTITY), .Player)
		add_effect(&action, damage_effect(PLAYER_ENTITY, 1+room.player.stats.defense))
		hit := resolve_action(room, &action)
		merge_action_report(pulse, &hit)
	}
}

// The same persistent lava remains dangerous while exploring. Combat owns
// its pulse separately, so world.tick calls this only outside an encounter.
expedition_exploration_terrain_beat :: proc(room: ^Room) {
	if room==nil || room.player==nil || room.phase!=.Loot || !room.player.tactical.config.expedition ||
		expedition_ground(room,room.player.position)!=.Lava {return}
	action:=make_action(.Trigger,SYSTEM_ENTITY,entity_target(PLAYER_ENTITY),.Player)
	add_effect(&action,damage_effect(PLAYER_ENTITY,1+room.player.stats.defense))
	report:=resolve_action(room,&action)
	append_event_log(room.recent_events,&report.events)
}

// Gravity wells are fixed geography, so both exploration and combat query
// the same attractor. Blockers prevent the pull instead of teleporting actors.
expedition_gravity_pulse :: proc(room:^Room,events:^Event_Log) {
	if room==nil || room.player==nil || room.player.tactical.config.expedition_biome!=10 || !room.player.tactical.config.expedition {return}
	targets:[MAX_ENEMIES_PER_ROOM+1]Entity_Ref;targets[0]=PLAYER_ENTITY;count:=1
	for enemy in room.enemies {targets[count]=enemy_entity(enemy.id);count+=1}
	for target in targets[:count] {
		position,found:=entity_position(room,target);if !found {continue}
		well:=position;best:=3
		for y in -2..=2 {for x in -2..=2 {
			p:=grid.offset(position, x, y);distance:=max(abs(x),abs(y))
			if distance>=best || expedition_terrain(10,p)!=.Gravity || !base_cell_is_walkable(room,p) || !shape_cell_has_clear_path(room,position,p) {continue}
			well,best=p,distance
		}}
		if best==0 || best==3 {continue}
		step:=grid.Position{x = sign(well.x-position.x), y = sign(well.y-position.y)}
		action:=make_action(.Trigger,SYSTEM_ENTITY,entity_target(target),.Entity)
		add_effect(&action,move_effect(target,add_position(position,step)))
		report:=resolve_action(room,&action)
		if report.accepted {append_event_log(events,&report.events)}
	}
}

// Exploration moves without spending a combat action, but entering a cell
// still uses the exact trap and elemental hazard pipeline.
expedition_enter_cell :: proc(room:^Room) {
	if room==nil || room.player==nil {return}
	report:Action_Report
	trigger_cell_entry(room,PLAYER_ENTITY,&report)
	append_event_log(room.recent_events,&report.events)
}

// Wind is a real forced move, so occupied cells, walls, closed bridges,
// traps and entry effects all use the same rules as a card's shove.
expedition_wind_push :: proc(room:^Room,target:Entity_Ref,step:grid.Position)->bool {
	if room==nil || room.player==nil || !room.player.tactical.config.expedition || step=={} {return false}
	position,ok:=entity_position(room,target);if !ok {return false}
	action:=make_action(.Trigger,SYSTEM_ENTITY,entity_target(target),.Entity)
	add_effect(&action,move_effect(target,add_position(position,step)))
	report:=resolve_action(room,&action);append_event_log(room.recent_events,&report.events)
	after,exists:=entity_position(room,target)
	return report.accepted && exists && position!=after
}
