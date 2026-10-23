package expedition

import grid "../engine/grid"
import game "../game"
import level "../level"

MAX_CELLS :: 224*224

// No address, allocator, GPU handle or borrowed slice is serialized. Dynamic
// room storage is reconstructed after validating every active prefix.
Snapshot :: struct {
	valid: bool,
	width, height: int,
	world: World,
	player: game.Player,
	phase: game.Room_Phase,
	tiles: [MAX_CELLS]level.Tile,
	// The height of every cell in steps (all zero: a flat map, which is every save from before the
	// expeditions had a relief: the key is simply missing there).
	heights: [MAX_CELLS]u8,
	obstacles: [MAX_CELLS]game.Obstacle,
	obstacle_count: int,
	family: level.Room_Family,
	encounter_kind: game.Encounter_Kind,
	modifier: game.Room_Modifier,
	exit_position: grid.Position,
	endless: bool,
	tactical_pulse: game.Tactical_Pulse,
	enemies: [game.MAX_ENEMIES_PER_ROOM]game.Enemy,
	enemy_count: int,
	traps: [game.MAX_TRAPS_PER_ROOM]game.Trap,
	trap_count: int,
	objects: [game.MAX_GRID_OBJECTS_PER_ROOM]game.Grid_Object,
	object_count: int,
	loot: [MAX_DROPS]game.Loot,
	loot_count: int,
	next_enemy_id,next_trap_id,next_object_id:u32,
	pulse_count:u64,
	ground_pool:[MAX_CELLS]i32,
	fires:[game.MAX_GROUND_FIRES]game.Ground_Fire,
	fire_count:int,
	next_fire_id:u32,
	fishing:game.Fishing_State,
	pinball:game.Pinball_State,
	pinball_random:u64,
	lasso:game.Lasso_State,
	first_person:game.First_Person_State,
	reactions:game.Reaction_Binding_Set,
}

stable :: proc(room:^game.Room) -> bool {
	return room!=nil && room.player!=nil && !room.tactical_pulse.pending && room.qte.kind==.None &&
		!game.tactical_is_casting(room) && !room.player.deck.has_resolving_card
}

capture :: proc(w:^World,room:^game.Room,out:^Snapshot) -> bool {
	if w==nil || out==nil || !stable(room) || room.level_data==nil || len(room.traps)>len(out.traps) || len(room.obstacles)>len(out.obstacles) || len(room.ground.pool)>MAX_CELLS || len(room.level_data.tiles.cells)>MAX_CELLS || len(room.enemies)>len(out.enemies) || len(room.objects)>len(out.objects) || len(room.loot)>len(out.loot) {return false}
	side:=size(w)
	if side!=legacy_map_size(w.biome) && side!=map_size(w.biome) {return false}
	if room.level_data.tiles.width!=side || room.level_data.tiles.height!=side || len(room.level_data.tiles.cells)!=side*side || len(room.ground.pool)!=side*side {return false}
	// Zero in place, then copy into the caller's heap snapshot. A large compound
	// literal here would put the expanded tile and obstacle arrays on the stack.
	out^={}
	out.valid=true;out.width=side;out.height=side
	out.world=w^;out.player=room.player^;out.phase=room.phase
	out.enemy_count=len(room.enemies);out.trap_count=len(room.traps);out.object_count=len(room.objects);out.loot_count=len(room.loot)
	out.next_enemy_id=room.next_enemy_id;out.next_trap_id=room.next_trap_id;out.next_object_id=room.next_object_id;out.pulse_count=room.pulse_count
	out.fires=room.ground.fires;out.fire_count=room.ground.fire_count;out.next_fire_id=room.ground.next_fire_id
	out.fishing=room.fishing;out.pinball=room.pinball;out.pinball_random=room.pinball_random;out.lasso=room.lasso;out.first_person=room.first_person;out.reactions=room.reaction_bindings
	out.family=room.family;out.encounter_kind=room.encounter_kind;out.modifier=room.modifier;out.exit_position=room.exit_position;out.endless=room.endless
	out.tactical_pulse=room.tactical_pulse;out.obstacle_count=len(room.obstacles)
	copy(out.tiles[:],room.level_data.tiles.cells[:]);copy(out.heights[:],room.level_data.heights[:]);copy(out.obstacles[:],room.obstacles[:])
	copy(out.enemies[:],room.enemies[:]);copy(out.traps[:],room.traps[:]);copy(out.objects[:],room.objects[:]);copy(out.loot[:],room.loot[:]);copy(out.ground_pool[:],room.ground.pool)
	return true
}

@(private)
valid_statuses :: proc(value:game.Status_Set)->bool {
	statuses:=value
	if statuses.count<0 || statuses.count>game.MAX_STATUSES_PER_ENTITY {return false}
	for status,i in statuses.items[:statuses.count] {
		if !game.status_kind_is_valid(status.kind) || status.potency<=0 || status.remaining_pulses<0 {return false}
		for previous in statuses.items[:i] {if previous.kind==status.kind {return false}}
	}
	return true
}

valid_snapshot :: proc(s:^Snapshot) -> bool {
	if s==nil || !s.valid || s.phase<.Combat || s.phase>.Defeat || s.obstacle_count<0 || s.obstacle_count>MAX_CELLS || s.world.biome>=.Count || s.enemy_count<0 || s.enemy_count>len(s.enemies) || s.trap_count<0 || s.trap_count>len(s.traps) || s.object_count<0 || s.object_count>len(s.objects) || s.loot_count<0 || s.loot_count>len(s.loot) || s.fire_count<0 || s.fire_count>len(s.fires) {return false}
	w:=&s.world
	if w.site_count<0 || w.site_count>MAX_SITES || w.group_count<0 || w.group_count>MAX_GROUPS || w.drop_count<0 || w.drop_count>MAX_DROPS || w.reward_count<0 || w.reward_count>3 || w.reward_site < -1 || w.reward_site>=w.site_count {return false}
	size:=size(w)
	if size!=legacy_map_size(w.biome) && size!=map_size(w.biome) {return false}
	// Version 1 omitted dimensions; its World.side_length also defaults to 0.
	if (s.width!=0 || s.height!=0) && (s.width!=size || s.height!=size) {return false}
	if size<=0 || size*size>MAX_CELLS || s.obstacle_count>size*size {return false}
	inside :: proc(p:grid.Position,n:int)->bool {return p.x>=0 && p.y>=0 && p.x<n && p.y<n}
	if w.pending_xp<0 || (w.pending_xp>0 && !inside(w.pending_xp_position,size)) || !inside(s.exit_position,size) || !game.expedition_player_valid(&s.player) || !valid_statuses(s.player.statuses) ||
	   s.player.stats.max_health<=0 || s.player.stats.attack<=0 || s.player.stats.defense<0 || s.player.gold<0 ||
	   !game.weapon_slot_valid(s.player.equipment.weapon) || !game.weapon_slot_valid(s.player.equipment.reserve) ||
	   !game.m8_profile_valid(s.player.m8_profile) || s.player.deck.has_resolving_card || s.tactical_pulse.pending ||
	   s.tactical_pulse.count<0 || s.tactical_pulse.count>game.MAX_ENEMIES_PER_ROOM ||
	   s.reactions.count<0 || s.reactions.count>game.MAX_REACTION_BINDINGS_PER_ROOM {return false}
	for tile in s.tiles[:size*size] {if tile.kind>.Fence {return false}}
	if w.structure_count<0 || w.structure_count>MAX_WORLD_STRUCTURES {return false}
	for placed in w.structures[:w.structure_count] {if placed.id>=.Count || placed.rotation>=4 || !inside(placed.origin,size) {return false}}
	for e,i in s.enemies[:s.enemy_count] {
		if !valid_statuses(e.statuses) || e.intent.path_count<0 || e.intent.path_count>game.MAX_ENEMY_INTENT_PATH_CELLS || e.intent.threatened_cell_count<0 || e.intent.threatened_cell_count>game.MAX_ENEMY_INTENT_THREAT_CELLS || e.id==0 || e.id>=s.next_enemy_id || e.archetype<.Chaser || e.archetype>=.Count || e.health<=0 || e.health>e.max_health || e.attack<=0 || !inside(e.position,size) {return false}
		for previous in s.enemies[:i] {if e.id==previous.id {return false}}
	}
	for trap in s.traps[:s.trap_count] {if trap.id==0 || trap.id>=s.next_trap_id || !inside(trap.position,size) {return false}}
	for object in s.objects[:s.object_count] {_,ok:=game.grid_object_definition(object.kind);if !ok || object.id==0 || object.id>=s.next_object_id || !inside(object.position,size) {return false}}
	for loot in s.loot[:s.loot_count] {if loot.kind<.Gold || loot.kind>.Weapon || loot.amount<0 || loot.healing_amount<0 || loot.healing_amount>4 || !inside(loot.position,size) {return false}}
	for obstacle in s.obstacles[:s.obstacle_count] {if !inside(obstacle.position,size) {return false}}
	for fire in s.fires[:s.fire_count] {if !inside(fire.center,size) || fire.id==0 || fire.stage<0 || fire.stage>game.GROUND_FIRE_STAGES {return false}}
	for drop in w.drops[:w.drop_count] {if !inside(drop.position,size) || drop.xp<0 {return false}}
	if s.player.position.x<0 || s.player.position.y<0 || s.player.position.x>=size || s.player.position.y>=size || s.player.health<0 || s.player.health>s.player.stats.max_health || !game.validate_deck_state(&s.player.deck) {return false}
	for &g in w.groups[:w.group_count] {
		if g.count<0 || g.count>MAX_MEMBERS || g.site < -1 || g.site>=w.site_count || !inside(g.anchor,size) || g.lure_phase>.Returning || (g.lure_phase!=.None && (!inside(g.lure_target,size) || g.lure_until<0 || g.lure_wait_until<0)) {return false}
		for m in g.members[:g.count] {if !valid_statuses(m.enemy.statuses) || !inside(m.enemy.position,size) || m.enemy.archetype<.Chaser || m.enemy.archetype>=.Count || (m.alive && (m.enemy.health<=0 || m.enemy.health>m.enemy.max_health)) {return false}}
	}
	for site in w.sites[:w.site_count] {if !inside(site.position,size) || site.wave<0 || site.waves<0 || site.wave>site.waves || site.kind>.Tunnel || site.state>.Resolved || site.group < -1 || site.group>=w.group_count || site.orientation>=4 || site.layout_version>SITE_LAYOUT_VERSION {return false}}
	return true
}

restore :: proc(s:^Snapshot,w:^World,data:^level.Level,player:^game.Player,room:^game.Room) -> bool {
	if w==nil || data==nil || player==nil || room==nil || !valid_snapshot(s) {return false}
	side:=size(&s.world)
	created,allocated:=level.create(side,side,{.Void})
	if !allocated {return false}
	data^=created
	copy(data.tiles.cells[:],s.tiles[:side*side])
	_=level.set_height_table(data,s.heights[:side*side])
	for tile,i in data.tiles.cells {
		if tile.kind==.Player_Spawn {data.player_spawn={i%side,i/side};data.has_player_spawn=true;break}
	}
	if !data.has_player_spawn {level.destroy(data);return false}
	// The structures' records are in the world; their tiles came with the map.
	if !level.set_structures(data,s.world.structures[:max(0,s.world.structure_count)]) {level.destroy(data);return false}
	player^=s.player
	player.health=max(i32(1),player.health) // Allocation also supports a stable defeated snapshot.
	r,ok:=game.create_room(data,player,{room_seed=s.world.seed})
	if !ok {level.destroy(data);return false}
	room^=r;player^=s.player;w^=s.world;w.side_length=side
	room.phase=s.phase
	room.family=s.family;room.encounter_kind=s.encounter_kind;room.modifier=s.modifier;room.exit_position=s.exit_position;room.endless=s.endless;room.tactical_pulse=s.tactical_pulse
	clear(&room.obstacles);append(&room.obstacles,..s.obstacles[:s.obstacle_count])
	clear(&room.enemies);clear(&room.traps);clear(&room.objects);clear(&room.loot)
	append(&room.enemies,..s.enemies[:s.enemy_count]);append(&room.traps,..s.traps[:s.trap_count]);append(&room.objects,..s.objects[:s.object_count]);append(&room.loot,..s.loot[:s.loot_count])
	room.next_enemy_id=s.next_enemy_id;room.next_trap_id=s.next_trap_id;room.next_object_id=s.next_object_id;room.pulse_count=s.pulse_count
	copy(room.ground.pool,s.ground_pool[:]);room.ground.fires=s.fires;room.ground.fire_count=s.fire_count;room.ground.next_fire_id=s.next_fire_id
	room.fishing=s.fishing;room.pinball=s.pinball;room.pinball_random=s.pinball_random;room.lasso=s.lasso;room.first_person=s.first_person;room.reaction_bindings=s.reactions
	room.player=player;room.level_data=data
	return true
}
