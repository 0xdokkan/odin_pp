package game

import "core:testing"
import grid "../engine/grid"
import level "../level"

@(test)
test_expedition_clock_has_no_deadline_and_draws_on_four_world_beats :: proc(t: ^testing.T) {
	data: level.Level
	player: Player
	room := tactical_clock_test_room(t, &data, &player)
	defer level.destroy(&data)
	defer destroy_room(&room)
	testing.expect(t, configure_expedition_combat(&room))
	room.enemies[0].tactical_cooldown = 1000
	player.deck.energy = 0
	for beat in 1..=32 {
		testing.expect(t, !tactical_tick(&room, 1, true, false))
		drain_tactical_test_pulse(t, &room, false)
		testing.expect(t, !tactical_expire_window(&room))
		testing.expect_value(t, player.tactical.phase, Tactical_Phase.Decision)
		testing.expect_value(t, player.deck.hand_count, min(MAX_HAND_CARDS, STARTING_HAND_SIZE+beat/4))
	}
	testing.expect_value(t, player.deck.energy, EXPEDITION_MAX_ENERGY)
	testing.expect_value(t, player.tactical.encounter_beats, u64(32))
	testing.expect_value(t, player.tactical.metrics.timeouts, u64(0))
	testing.expect_value(t, player.tactical.stuns, 0)
	testing.expect(t, tactical_allows_cards(&room))
}

@(test)
test_expedition_mana_tracks_only_world_time_and_has_no_banked_overflow :: proc(t: ^testing.T) {
	data: level.Level
	player: Player
	room := tactical_clock_test_room(t, &data, &player)
	defer level.destroy(&data)
	defer destroy_room(&room)
	testing.expect(t, configure_expedition_combat(&room))
	player.deck.energy = 30
	tactical_tick(&room, 0.125, true, false)
	testing.expect_value(t, player.deck.energy, i32(31))
	tactical_tick(&room, 10, false, false)
	testing.expect_value(t, player.deck.energy, i32(31))
	tactical_begin_card_cast(&room, 2)
	tactical_tick(&room, 2, true, false)
	testing.expect_value(t, player.deck.energy, i32(31))
	testing.expect_value(t, player.tactical.clock_fraction, f32(0.125))
	player.deck.energy = 99
	tactical_tick(&room, 0.2, true, false)
	testing.expect_value(t, player.deck.energy, i32(100))
	player.deck.energy = 0
	tactical_tick(&room, 0.05, true, false)
	testing.expect_value(t, player.deck.energy, i32(0))
	testing.expect(t, abs(player.tactical.energy_fraction-0.4) < 0.001)
}

@(test)
test_expedition_encounters_reset_hand_mana_and_legacy_activities_stay_closed :: proc(t: ^testing.T) {
	data: level.Level
	player: Player
	room := tactical_clock_test_room(t, &data, &player)
	defer level.destroy(&data)
	defer destroy_room(&room)
	testing.expect(t, configure_expedition_combat(&room))
	end_expedition_encounter(&room)
	testing.expect_value(t, room.phase, Room_Phase.Loot)
	testing.expect_value(t, player.deck.hand_count, 0)
	testing.expect(t, begin_expedition_encounter(&room))
	testing.expect_value(t, player.deck.energy, i32(100))
	testing.expect_value(t, player.deck.hand_count, STARTING_HAND_SIZE)
	testing.expect(t, !western_ranch_can_start(&room))
	_, ring := query_tesla_ring(&room)
	testing.expect(t, !ring)
	for id in Card_Id {
		if id == .Count { continue }
		cost := card_energy_cost(&room, id)
		testing.expect(t, cost >= 10 && cost <= 70)
	}
	testing.expect_value(t, card_energy_cost(&room, .Strike), i32(15))
	testing.expect_value(t, card_energy_cost(&room, .Bomb_Marley), i32(70))
}

@(test)
test_expedition_play_spends_full_price_without_immediate_replacement :: proc(t: ^testing.T) {
	data: level.Level
	player: Player
	room := tactical_clock_test_room(t, &data, &player)
	defer level.destroy(&data)
	defer destroy_room(&room)
	testing.expect(t, configure_expedition_combat(&room))
	card := player.deck.hand[0]
	// Keep ownership and hand coherent while selecting a predictable self card.
	for &owned in player.deck.owned[:player.deck.owned_count] { if owned.id == card.id { owned.definition_id = .Guard } }
	player.deck.hand[0].definition_id = .Guard
	player.deck.energy = 14
	testing.expect_value(t, play_card(&room, card.id, entity_target(PLAYER_ENTITY)).result, Card_Play_Result.Not_Enough_Energy)
	testing.expect_value(t, player.deck.hand_count, STARTING_HAND_SIZE)
	player.deck.energy = 15
	played := play_card(&room, card.id, entity_target(PLAYER_ENTITY))
	testing.expect(t, card_play_was_committed(played.result))
	testing.expect_value(t, player.deck.energy, i32(0))
	tactical_tick(&room, 10, true, false)
	testing.expect_value(t, player.deck.hand_count, STARTING_HAND_SIZE-1)
	testing.expect_value(t, player.deck.energy, i32(0))
}

@(test)
test_memory_cannon_orientation_and_laser_upgrade_hit_the_expected_lane :: proc(t: ^testing.T) {
	data: level.Level
	player: Player
	room := tactical_clock_test_room(t, &data, &player)
	defer level.destroy(&data)
	defer destroy_room(&room)
	testing.expect(t, configure_expedition_combat(&room))
	room.enemies[0].position = {7, 3}
	room.enemies[0].tactical_cooldown = 1000
	player.tactical.placement_direction = .East
	testing.expect(t, deploy_board_device(&room, .Cannon, {4, 3}, 5, 2, room.recent_events))
	if len(room.objects) == 0 { return }
	object := room.objects[len(room.objects)-1]
	testing.expect_value(t, object.device_direction, Move_Direction.East)
	testing.expect(t, memory_device_contains(&room, object, {7, 3}))
	testing.expect(t, !memory_device_contains(&room, object, {4, 6}))
	before := room.enemies[0].health
	for _ in 0..<3 {
		tactical_tick(&room, 1, true, false)
		drain_tactical_test_pulse(t, &room, false)
	}
	testing.expect_value(t, room.enemies[0].health, before-5)
	testing.expect_value(t, room.objects[len(room.objects)-1].device_charges, i32(3))
}

@(test)
test_expedition_gravity_ice_and_bridge_movement_use_real_collision :: proc(t:^testing.T) {
	data:level.Level;player:Player;room:=tactical_clock_test_room(t,&data,&player)
	defer level.destroy(&data);defer destroy_room(&room)
	configure_expedition_combat(&room)
	player.tactical.config.low_gravity=true
	room.enemies[0].position={5,3}
	ref:=enemy_entity(room.enemies[0].id)
	action:=make_action(.Trigger,PLAYER_ENTITY,entity_target(ref),.Entity)
	add_effect(&action,move_effect(ref,{6,3}))
	hit:=resolve_action(&room,&action);testing.expect(t,hit.accepted)
	testing.expect_value(t,room.enemies[0].position,level_position(7,3))
	// A blocked extra cell preserves the original one-cell push.
	room.enemies[0].position={5,3};_=level.set_tile(&data,{7,3},{.Wall})
	hit=resolve_action(&room,&action);testing.expect(t,hit.accepted)
	testing.expect_value(t,room.enemies[0].position,level_position(6,3))
	player.tactical.config.low_gravity=false;player.tactical.config.expedition_biome=6
	player.position={1,2};_=level.set_tile(&data,{2,2},{.Floor});_=level.set_tile(&data,{3,2},{.Floor})
	// (2,2) is a stable ice cell in the Snow biome.
	testing.expect_value(t,expedition_terrain(6,{2,2}),Expedition_Terrain.Ice)
	action=make_action(.Move,PLAYER_ENTITY,cell_target({2,2}),.Walkable_Cell)
	add_effect(&action,move_effect(PLAYER_ENTITY,{2,2}))
	hit=resolve_action(&room,&action);testing.expect(t,hit.accepted)
	testing.expect_value(t,player.position,level_position(3,2))
	player.tactical.config.expedition_biome=9;player.tactical.environment_beat=0
	testing.expect(t,expedition_bridge_open(&room,{21,10}))
	player.tactical.environment_beat=2;testing.expect(t,!expedition_bridge_open(&room,{21,10}))
}

@(private)
level_position :: proc(x,y:int)->grid.Position {return {x,y}}

@(test)
test_expedition_dinosaur_boost_ends_only_on_world_time :: proc(t:^testing.T) {
	data:level.Level;player:Player;room:=tactical_clock_test_room(t,&data,&player)
	defer level.destroy(&data);defer destroy_room(&room)
	configure_expedition_combat(&room)
	base:=player_basic_attack_damage(&player)
	player.tactical.dinosaur_remaining=2;player.tactical.dinosaur_power=3
	testing.expect_value(t,player_basic_attack_damage(&player),base+3)
	tactical_tick(&room,5,false,false);testing.expect_value(t,player.tactical.dinosaur_remaining,f32(2))
	tactical_tick(&room,1,true,false);drain_tactical_test_pulse(t,&room,false)
	tactical_tick(&room,1,true,false);drain_tactical_test_pulse(t,&room,false)
	testing.expect_value(t,player.tactical.dinosaur_remaining,f32(0));testing.expect_value(t,player_basic_attack_damage(&player),base)
}

@(test)
test_expedition_boss_patterns_are_distinct_and_fully_telegraphed :: proc(t:^testing.T) {
	data:level.Level;player:Player;room:=tactical_clock_test_room(t,&data,&player,.Demolitionist)
	defer level.destroy(&data);defer destroy_room(&room)
	configure_expedition_combat(&room);player.position={4,4};room.enemies[0].position={7,4}
	enemy:=&room.enemies[0];positions:[MAX_ENEMIES_PER_ROOM]grid.Position;positions[0]=enemy.position
	cyber:=plan_expedition_boss(&room,enemy,enemy.position,&positions,1,0,nil)
	testing.expect_value(t,cyber.kind,Enemy_Intent_Kind.Attack);testing.expect(t,cyber.windup && cyber.threatened_cell_count>4)
	player.tactical.config.expedition_biome=2
	jungle:=plan_expedition_boss(&room,enemy,enemy.position,&positions,1,0,nil)
	testing.expect_value(t,jungle.kind,Enemy_Intent_Kind.Charge)
	player.tactical.config.expedition_biome=4
	egypt:=plan_expedition_boss(&room,enemy,enemy.position,&positions,1,0,nil)
	testing.expect_value(t,egypt.kind,Enemy_Intent_Kind.Attack);testing.expect(t,egypt.windup)
	for cell in egypt.threatened_cells[:egypt.threatened_cell_count] {testing.expect_value(t,max(abs(cell.x-enemy.position.x),abs(cell.y-enemy.position.y)),2)}
}

@(test)
test_expedition_gravity_wells_pull_with_collision_and_do_not_affect_other_biomes :: proc(t:^testing.T) {
	data:level.Level;player:Player;room:=tactical_clock_test_room(t,&data,&player)
	defer level.destroy(&data);defer destroy_room(&room)
	configure_expedition_combat(&room)
	player.position={5,4};player.tactical.config.expedition_biome=10;player.tactical.config.low_gravity=true
	_=level.set_tile(&data,{5,5},{.Floor});_=level.set_tile(&data,{5,6},{.Floor})
	origin:=player.position
	expedition_gravity_pulse(&room,room.recent_events)
	testing.expect(t,player.position!=origin)
	testing.expect(t,!cell_blocks_movement(&room,player.position))
	player.position=origin;player.tactical.config.expedition_biome=0
	expedition_gravity_pulse(&room,room.recent_events);testing.expect_value(t,player.position,origin)
}

@(test)
test_memory_wave_pull_and_timed_bomb_resolve_and_expire :: proc(t:^testing.T) {
	for kind in ([3]Grid_Object_Kind{.Flood,.Black_Hole,.Bomb_Marley}) {
		data:level.Level;player:Player;room:=tactical_clock_test_room(t,&data,&player)
		configure_expedition_combat(&room)
		room.enemies[0].position={6,3};player.tactical.placement_direction=.East;player.tactical.config.expedition_biome=1
		damage:i32=12 if kind==.Bomb_Marley else 2
		testing.expect(t,deploy_board_device(&room,kind,{4,3},damage,1,room.recent_events))
		pulse:Pulse_Report
		for _ in 0..<(3 if kind==.Bomb_Marley else 2) {tick_memory_devices(&room,&pulse)}
		testing.expect_value(t,room.enemies[0].health,i32(100)-damage)
		if kind==.Flood {
			testing.expect_value(t,room.enemies[0].position,level_position(7,3))
			_,slow:=status_for_entity(&room,enemy_entity(room.enemies[0].id),.Slow);testing.expect(t,slow)
		} else if kind==.Black_Hole {testing.expect_value(t,room.enemies[0].position,level_position(5,3))}
		else {testing.expect_value(t,len(room.objects),0)}
		destroy_room(&room);level.destroy(&data)
	}
}

@(test)
test_expedition_gothic_chaser_phases_through_cover_to_clear_landing :: proc(t:^testing.T) {
	data:level.Level;player:Player;room:=tactical_clock_test_room(t,&data,&player)
	defer level.destroy(&data);defer destroy_room(&room)
	configure_expedition_combat(&room);player.tactical.config.expedition_biome=8;player.position={4,4}
	room.enemies[0].position={7,4};room.enemies[0].intent={}
	_=level.set_tile(&data,{6,4},{.Wall});_=level.set_tile(&data,{5,4},{.Floor})
	plan_enemy_intents(&room)
	testing.expect(t,room.enemies[0].intent.phase_through)
	testing.expect_value(t,room.enemies[0].intent.destination,level_position(5,4))
	room.enemies[0].tactical_cooldown=1
	tactical_tick(&room,1,true,false);drain_tactical_test_pulse(t,&room,false)
	testing.expect_value(t,room.enemies[0].position,level_position(5,4))
}

@(test)
test_expedition_biome_archers_apply_status_only_after_unblocked_hits :: proc(t:^testing.T) {
	for biome in ([2]u8{2,7}) {
		data:level.Level;player:Player;room:=tactical_clock_test_room(t,&data,&player,.Archer)
		defer level.destroy(&data);defer destroy_room(&room)
		configure_expedition_combat(&room);player.tactical.config.expedition_biome=biome
		enemy:=&room.enemies[0];intent:=make_attack_intent(&room,enemy.position,player.position,3)
		kind:=Status_Kind.Poison if biome==2 else Status_Kind.Burn
		shielded,_:=apply_status(&room,PLAYER_ENTITY,.Shield,50,3);testing.expect(t,shielded)
		pulse:Pulse_Report;_=resolve_enemy_blow(&room,enemy,&intent,true,&pulse)
		_,present:=status_for_entity(&room,PLAYER_ENTITY,kind);testing.expect(t,!present)
		_,_=remove_status(&room,PLAYER_ENTITY,.Shield)
		pulse={};_=resolve_enemy_blow(&room,enemy,&intent,true,&pulse)
		status,applied:=status_for_entity(&room,PLAYER_ENTITY,kind);testing.expect(t,applied);testing.expect_value(t,status.potency,i32(1))
	}
}

@(test)
test_expedition_wind_checks_occupancy_walls_and_records_real_move :: proc(t:^testing.T) {
	data:level.Level;player:Player;room:=tactical_clock_test_room(t,&data,&player)
	defer level.destroy(&data);defer destroy_room(&room)
	configure_expedition_combat(&room);player.tactical.config.expedition_biome=9
	player.position={4,4};room.enemies[0].position={5,4}
	testing.expect(t,!expedition_wind_push(&room,PLAYER_ENTITY,{1,0}));testing.expect_value(t,player.position,level_position(4,4))
	room.enemies[0].position={7,4};_=level.set_tile(&data,{5,4},{.Wall})
	testing.expect(t,!expedition_wind_push(&room,PLAYER_ENTITY,{1,0}));testing.expect_value(t,player.position,level_position(4,4))
	_=level.set_tile(&data,{5,4},{.Floor});testing.expect(t,expedition_wind_push(&room,PLAYER_ENTITY,{1,0}))
	testing.expect_value(t,player.position,level_position(5,4))
	room.enemies[0].archetype=.Chaser;room.enemies[0].intent=make_wait_intent(&room,room.enemies[0].position)
	tactical_schedule_enemy(&room,&room.enemies[0]);testing.expect_value(t,room.enemies[0].tactical_cooldown,f32(2))
	player.tactical.config.expedition_biome=4;tactical_schedule_enemy(&room,&room.enemies[0]);testing.expect_value(t,room.enemies[0].tactical_cooldown,f32(4))
}

@(test)
test_expedition_large_map_paths_keep_flanking_routes_with_bounded_search :: proc(t:^testing.T) {
	data,created:=level.create(224,224,{.Floor});testing.expect(t,created);defer level.destroy(&data)
	data.player_spawn={112,112};data.has_player_spawn=true;_=level.set_tile(&data,{112,112},{.Player_Spawn});_=level.set_tile(&data,{204,112},{.Exit})
	player:=create_test_player(t);room,ok:=create_room(&data,&player,{});testing.expect(t,ok);defer destroy_room(&room)
	configure_expedition_combat(&room)
	for y in 100..=124 {_=level.set_tile(&data,{118,y},{.Wall})}
	rebuild_tactical_enemy_distances(&room,room.enemy_path_distances,.Melee)
	near:=room.enemy_path_distances[112*224+124];testing.expect(t,near>12 && near<50)
	testing.expect_value(t,room.enemy_path_distances[112*224+170],-1)
	// Moving the active encounter updates the bounded window on the next plan.
	player.position={180,112};rebuild_tactical_enemy_distances(&room,room.enemy_path_distances,.Melee)
	testing.expect_value(t,room.enemy_path_distances[112*224+170],10)
	testing.expect_value(t,room.enemy_path_distances[112*224+112],-1)
}
