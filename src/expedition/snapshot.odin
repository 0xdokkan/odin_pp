package expedition

import "core:mem"
import grid "../engine/grid"
import game "../game"
import level "../level"

// Legacy presentation capacity is deliberately unchanged; saves own their buffers.
MAX_CELLS :: 224*224
MAX_SNAPSHOT_SIDE :: 8*224
MAX_SNAPSHOT_CELLS :: MAX_SNAPSHOT_SIDE*MAX_SNAPSHOT_SIDE
MAX_SNAPSHOT_BYTES :: 256*mem.Megabyte
SNAPSHOT_LAYERS_V1 :: u32(1)
SNAPSHOT_LAYERS :: u32(2)

// The six dynamic buffers are owned, never borrowed from a live room. JSON
// serializes their elements, not their pointers or allocators. Destroy explicitly.
Snapshot :: struct {
	valid: bool,
	layers_version: u32,
	width, height: int,
	world: World,
	player: game.Player,
	phase: game.Room_Phase,
	tiles: [dynamic]level.Tile,
	// The height of every cell in steps (all zero: a flat map, which is every save from before the
	// expeditions had a relief: the key is simply missing there).
	heights: [dynamic]u8,
	// The cells of the other layers (layer_cell_pack), and the pools on them (pool index, amount).
	layer_cells: [dynamic]u64,
	layer_cell_count: int,
	layer_pools: [dynamic][2]i32,
	layer_pool_count: int,
	obstacles: [dynamic]game.Obstacle,
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
	ground_pool:[dynamic]i32,
	fires:[game.MAX_GROUND_FIRES]game.Ground_Fire,
	fire_count:int,
	next_fire_id:u32,
	fishing:game.Fishing_State,
	pinball:game.Pinball_State,
	pinball_random:u64,
	lasso:game.Lasso_State,
	// The view behind the player's eyes, each weapon's own under its key (game.First_Person_Save).
	first_person:game.First_Person_Save,
	reactions:game.Reaction_Binding_Set,
	// Where the lifts' platforms rest (game/lift.odin): a save is never made with one carrying someone (stable), and one
	// going empty is saved at its end. A save from before has none, and its map no lifts.
	lifts:game.Lift_State,
}

// V2: index(32), layer slot(2), kind(3), height(8). V1 values are decoded
// separately, so their old high index bits cannot silently become layer bits.
@(private)
layer_cell_pack :: proc(index, slot: int, kind: level.Tile_Kind, height: u8) -> u64 {
	return u64(index)|u64(slot)<<32|u64(kind)<<34|u64(height)<<37
}

@(private)
layer_cell_unpack :: proc(cell: u64, version: u32 = SNAPSHOT_LAYERS) -> (index, slot: int, kind: level.Tile_Kind, height: u8) {
	if version == SNAPSHOT_LAYERS_V1 {
		return int(cell&0xFFFF), int((cell>>16)&3), level.Tile_Kind((cell>>18)&7), u8((cell>>21)&0xFF)
	}
	return int(cell&0xFFFFFFFF), int((cell>>32)&3), level.Tile_Kind((cell>>34)&7), u8((cell>>37)&0xFF)
}

stable :: proc(room:^game.Room) -> bool {
	return room!=nil && room.player!=nil && !room.tactical_pulse.pending && room.qte.kind==.None &&
		!game.tactical_is_casting(room) && !room.player.deck.has_resolving_card && !game.lifts_carrying(room)
}

capture :: proc(w: ^World, room: ^game.Room, out: ^Snapshot) -> bool {
	if w == nil || out == nil || !stable(room) || room.level_data == nil || w.biome >= .Count ||
		len(room.traps) > len(out.traps) || len(room.enemies) > len(out.enemies) ||
		len(room.objects) > len(out.objects) || len(room.loot) > len(out.loot) { return false }
	side := size(w)
	if side <= 0 || side > MAX_SNAPSHOT_SIDE { return false }
	cells := side*side
	data := room.level_data
	if data.tiles.width != side || data.tiles.height != side || len(data.tiles.cells) != cells ||
		len(room.obstacles) > cells || len(room.ground.pool) != game.room_table_cells(data) ||
		(len(data.heights) != 0 && len(data.heights) != cells) { return false }
	layer_cells, layer_pools := 0, 0
	for plane, slot in data.planes {
		if len(plane.tiles) == 0 { continue }
		if slot == level.layer_slot(grid.GROUND_LAYER) || len(plane.tiles) != cells ||
			(len(plane.heights) != 0 && len(plane.heights) != cells) { return false }
		for tile in plane.tiles { if tile.kind != .Void { layer_cells += 1 } }
	}
	for amount in room.ground.pool[cells:] { if amount != 0 { layer_pools += 1 } }
	if !snapshot_capacity_allowed(cells, len(room.obstacles), layer_cells, layer_pools) { return false }
	// Reserve every buffer before touching saved values or lengths. A failed
	// allocation may enlarge capacity, but preserves the previous checkpoint.
	if reserve(&out.tiles, cells) != nil || reserve(&out.heights, cells) != nil ||
		reserve(&out.obstacles, len(room.obstacles)) != nil || reserve(&out.ground_pool, cells) != nil ||
		reserve(&out.layer_cells, layer_cells) != nil || reserve(&out.layer_pools, layer_pools) != nil { return false }
	tiles, heights, obstacles := out.tiles, out.heights, out.obstacles
	ground_pool, saved_layers, saved_pools := out.ground_pool, out.layer_cells, out.layer_pools
	out^ = {}
	out.tiles, out.heights, out.obstacles = tiles, heights, obstacles
	out.ground_pool, out.layer_cells, out.layer_pools = ground_pool, saved_layers, saved_pools
	resize(&out.tiles, cells); resize(&out.heights, cells); resize(&out.obstacles, len(room.obstacles))
	resize(&out.ground_pool, cells); resize(&out.layer_cells, layer_cells); resize(&out.layer_pools, layer_pools)
	sync_structures(w, data)
	out.valid=true;out.layers_version=SNAPSHOT_LAYERS;out.width=side;out.height=side
	out.world=w^;out.player=room.player^;out.phase=room.phase
	out.enemy_count=len(room.enemies);out.trap_count=len(room.traps);out.object_count=len(room.objects);out.loot_count=len(room.loot)
	out.next_enemy_id=room.next_enemy_id;out.next_trap_id=room.next_trap_id;out.next_object_id=room.next_object_id;out.pulse_count=room.pulse_count
	out.fires=room.ground.fires;out.fire_count=room.ground.fire_count;out.next_fire_id=room.ground.next_fire_id
	out.fishing=room.fishing;out.pinball=room.pinball;out.pinball_random=room.pinball_random;out.lasso=room.lasso;out.first_person=game.first_person_save(room.first_person);out.reactions=room.reaction_bindings
	out.lifts=room.lifts
	for &platform in out.lifts.platforms[:out.lifts.count] {platform={at=platform.at}}
	out.family=room.family;out.encounter_kind=room.encounter_kind;out.modifier=room.modifier;out.exit_position=room.exit_position;out.endless=room.endless
	out.tactical_pulse=room.tactical_pulse;out.obstacle_count=len(room.obstacles)
	copy(out.tiles[:],data.tiles.cells[:]);copy(out.obstacles[:],room.obstacles[:])
	for &height in out.heights { height = 0 }
	copy(out.heights[:],data.heights[:])
	copy(out.enemies[:],room.enemies[:]);copy(out.traps[:],room.traps[:]);copy(out.objects[:],room.objects[:]);copy(out.loot[:],room.loot[:])
	copy(out.ground_pool[:],room.ground.pool[:cells])
	for plane, slot in data.planes {
		for tile, index in plane.tiles {
			if tile.kind == .Void { continue }
			height := plane.heights[index] if index < len(plane.heights) else 0
			out.layer_cells[out.layer_cell_count] = layer_cell_pack(index, slot, tile.kind, height); out.layer_cell_count += 1
		}
	}
	for amount, index in room.ground.pool[cells:] {
		if amount == 0 { continue }
		out.layer_pools[out.layer_pool_count] = {i32(cells+index), amount}; out.layer_pool_count += 1
	}
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
	if s==nil || !s.valid || (s.layers_version!=SNAPSHOT_LAYERS && s.layers_version!=SNAPSHOT_LAYERS_V1) || s.phase<.Combat || s.phase>.Defeat || s.obstacle_count<0 || s.obstacle_count>len(s.obstacles) || s.world.biome>=.Count || s.enemy_count<0 || s.enemy_count>len(s.enemies) || s.trap_count<0 || s.trap_count>len(s.traps) || s.object_count<0 || s.object_count>len(s.objects) || s.loot_count<0 || s.loot_count>len(s.loot) || s.fire_count<0 || s.fire_count>len(s.fires) {return false}
	w:=&s.world
	if w.cave_count<0 || w.cave_count>MAX_CAVES || w.in_cave<0 || w.in_cave>w.cave_count {return false}
	if w.site_count<0 || w.site_count>MAX_SITES || w.group_count<0 || w.group_count>MAX_GROUPS || w.drop_count<0 || w.drop_count>MAX_DROPS || w.reward_count<0 || w.reward_count>3 || w.reward_site < -1 || w.reward_site>=w.site_count {return false}
	size:=size(w)
	if size <= 0 || size > MAX_SNAPSHOT_SIDE { return false }
	cells := size*size
	if s.obstacle_count > cells { return false }
	if s.layers_version == SNAPSHOT_LAYERS_V1 {
		if len(s.tiles) > MAX_CELLS || len(s.heights) > MAX_CELLS || len(s.ground_pool) > MAX_CELLS ||
			len(s.obstacles) > MAX_CELLS || len(s.layer_cells) > 4096 || len(s.layer_pools) > 1024 { return false }
		if size != legacy_map_size(w.biome) && size != map_size(w.biome) { return false }
		if (s.width != 0 || s.height != 0) && (s.width != size || s.height != size) { return false }
		if len(s.tiles) < cells || len(s.ground_pool) < cells || (len(s.heights) != 0 && len(s.heights) < cells) { return false }
	} else {
		if s.width != size || s.height != size || len(s.tiles) != cells || len(s.heights) != cells ||
			len(s.ground_pool) != cells || len(s.obstacles) != s.obstacle_count ||
			len(s.layer_cells) != s.layer_cell_count || len(s.layer_pools) != s.layer_pool_count { return false }
	}
	if !snapshot_capacity_allowed(cells, len(s.obstacles), len(s.layer_cells), len(s.layer_pools)) { return false }
	inside :: proc(p:grid.Position,n:int)->bool {return p.x>=0 && p.y>=0 && p.x<n && p.y<n && level.layer_in_range(p.layer)}
	if w.pending_xp<0 || (w.pending_xp>0 && !inside(w.pending_xp_position,size)) || !inside(s.exit_position,size) || !game.expedition_player_valid(&s.player) || !valid_statuses(s.player.statuses) ||
	   s.player.stats.max_health<=0 || s.player.stats.attack<=0 || s.player.stats.defense<0 || s.player.gold<0 ||
	   !game.weapon_slot_valid(s.player.equipment.weapon) || !game.weapon_slot_valid(s.player.equipment.reserve) ||
	   !game.m8_profile_valid(s.player.m8_profile) || s.player.deck.has_resolving_card || s.tactical_pulse.pending ||
	   s.tactical_pulse.count<0 || s.tactical_pulse.count>game.MAX_ENEMIES_PER_ROOM ||
	   s.reactions.count<0 || s.reactions.count>game.MAX_REACTION_BINDINGS_PER_ROOM {return false}
	spawn_count, exit_count := 0, 0
	for tile, index in s.tiles[:cells] {
		if tile.kind > .Fence { return false }
		if tile.kind == .Player_Spawn { spawn_count += 1 }
		if tile.kind == .Exit {
			exit_count += 1
			if s.exit_position != (grid.Position{x = index%size, y = index/size}) { return false }
		}
	}
	if spawn_count == 0 || exit_count != 1 { return false }
	if s.layer_cell_count<0 || s.layer_cell_count>len(s.layer_cells) || s.layer_pool_count<0 || s.layer_pool_count>len(s.layer_pools) {return false}
	previous_layer := -1
	for packed in s.layer_cells[:s.layer_cell_count] {
		if (s.layers_version == SNAPSHOT_LAYERS_V1 && packed>>29 != 0) || (s.layers_version == SNAPSHOT_LAYERS && packed>>45 != 0) { return false }
		index, slot, kind, _ := layer_cell_unpack(packed, s.layers_version)
		if index >= cells || slot >= level.LAYER_COUNT || slot == level.layer_slot(grid.GROUND_LAYER) || kind == .Void || kind > .Fence { return false }
		key := slot*cells+index
		if key <= previous_layer { return false }
		previous_layer = key
	}
	previous_pool := cells-1
	for pool in s.layer_pools[:s.layer_pool_count] {
		if int(pool[0]) <= previous_pool || int(pool[0]) >= cells*level.LAYER_COUNT || pool[1] < 0 { return false }
		layer := game.room_slot_layer(int(pool[0])/cells)
		if !snapshot_has_layer_cell(s, int(pool[0])%cells, level.layer_slot(layer), cells) { return false }
		previous_pool = int(pool[0])
	}
	for amount in s.ground_pool[:cells] { if amount < 0 { return false } }
	for cave in w.caves[:w.cave_count] {if cave.site<0 || cave.site>=w.site_count || w.sites[cave.site].kind!=.Cave || cave.state>.Looted {return false}}
	if w.complex_count<0 || w.complex_count>MAX_COMPLEXES || w.lift_count<0 || w.lift_count>MAX_WORLD_LIFTS || w.gate_count<0 || w.gate_count>MAX_WORLD_GATES || w.base<0 || w.base>level.LAYER_SPACING*4 {return false}
	for c in w.complexes[:w.complex_count] {if c.kind==.None || c.kind>max(Complex_Kind) || !inside(c.origin,size) {return false}}
	for lift in w.lifts[:w.lift_count] {if !inside(lift.ends[0],size) || !inside(lift.ends[1],size) || lift.rest>1 {return false}}
	for gate in w.gates[:w.gate_count] {if !inside(gate.cell,size) || !inside(gate.lever,size) {return false}}
	if s.lifts.count!=w.lift_count {return false}
	for platform in s.lifts.platforms[:s.lifts.count] {if platform.at>1 || platform.moving || platform.has_rider {return false}}
	if _,known:=game.first_person_load(s.first_person);!known {return false}
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
	for drop in w.drops[:w.drop_count] {if !inside(drop.position,size) || drop.xp<0 || int(drop.cave)>w.cave_count {return false}}
	if s.player.position.x<0 || s.player.position.y<0 || s.player.position.x>=size || s.player.position.y>=size || s.player.health<0 || s.player.health>s.player.stats.max_health || !game.validate_deck_state(&s.player.deck) {return false}
	for &g in w.groups[:w.group_count] {
		if g.count<0 || g.count>MAX_MEMBERS || int(g.cave)>w.cave_count || g.site < -1 || g.site>=w.site_count || !inside(g.anchor,size) || g.lure_phase>.Returning || (g.lure_phase!=.None && (!inside(g.lure_target,size) || g.lure_until<0 || g.lure_wait_until<0)) {return false}
		for m in g.members[:g.count] {if !valid_statuses(m.enemy.statuses) || !inside(m.enemy.position,size) || m.enemy.archetype<.Chaser || m.enemy.archetype>=.Count || (m.alive && (m.enemy.health<=0 || m.enemy.health>m.enemy.max_health)) {return false}}
	}
	for site in w.sites[:w.site_count] {if !inside(site.position,size) || site.wave<0 || site.waves<0 || site.wave>site.waves || site.kind>.Cave || site.state>.Resolved || site.group < -1 || site.group>=w.group_count || site.orientation>=4 || site.layout_version>SITE_LAYOUT_VERSION {return false}}
	return true
}

@(private)
snapshot_restore_into_empty :: proc(s:^Snapshot,w:^World,data:^level.Level,player:^game.Player,room:^game.Room) -> bool {
	if w==nil || data==nil || player==nil || room==nil || !valid_snapshot(s) {return false}
	side:=size(&s.world)
	created,allocated:=level.create(side,side,{.Void})
	if !allocated {return false}
	data^=created
	// The base the world's ground was raised by (0 in a save from before there was one, whose ground is not raised).
	data.base=s.world.base
	copy(data.tiles.cells[:],s.tiles[:side*side])
	if len(s.heights) > 0 && !level.set_height_table(data,s.heights[:side*side]) { level.destroy(data); return false }
	// The other layers before the room, whose tables are made for them; a map that breaks their rule is not one.
	for packed in s.layer_cells[:s.layer_cell_count] {
		index,slot,kind,height:=layer_cell_unpack(packed, s.layers_version)
		cell:=grid.Position{x = index%side, y = index/side, layer = i8(slot+grid.LOWEST_LAYER)}
		if !level.set_tile(data,cell,{kind=kind}) || !level.set_height(data,cell,i32(height)) {level.destroy(data);return false}
	}
	// The lifts and the gates, as the map had them; a gate's cell says if it is open (level.add_gate would shut it).
	for lift in s.world.lifts[:s.world.lift_count] {if !level.add_lift(data,lift.ends[0],lift.ends[1],int(lift.rest)) {level.destroy(data);return false}}
	append(&data.gates,..s.world.gates[:s.world.gate_count])
	if error,_:=level.check_layers(data);error!=.None {level.destroy(data);return false}
	for tile,i in data.tiles.cells {
		if tile.kind==.Player_Spawn {data.player_spawn={x = i%side, y = i/side};data.has_player_spawn=true;break}
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
	copy(room.ground.pool,s.ground_pool[:side*side])
	for pool in s.layer_pools[:s.layer_pool_count] { room.ground.pool[pool[0]] = pool[1] }
	room.ground.fires=s.fires;room.ground.fire_count=s.fire_count;room.ground.next_fire_id=s.next_fire_id
	room.fishing=s.fishing;room.pinball=s.pinball;room.pinball_random=s.pinball_random;room.lasso=s.lasso;room.first_person,_=game.first_person_load(s.first_person);room.reaction_bindings=s.reactions
	if s.lifts.count==room.lifts.count {room.lifts=s.lifts}
	room.player=player;room.level_data=data
	return true
}
