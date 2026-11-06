package application

import "core:fmt"
import "core:os"
import rl "vendor:raylib"
import artifacts "../devtools/artifacts"
import host "../engine/host"
import grid "../engine/grid"
import input "../engine/input"
import game "../game"
import level "../level"
import render "../render"
import run "../run"

// Native inputs exercise the real expedition, on the smoke's unsaved campaign.
// Only the initial hand and encounter are staged. No card result is injected.
@(private)
Expedition_Cards_Capture :: struct {
	wrapped: host.Scene,
	stage, frames, total: int,
	anchor, far: grid.Position,
	foe: u32,
	spell: u32,
	cancelled: u32,
	complete, raised, damage_captured: bool,
}

@(private)
expedition_enable_cards_smoke :: proc(scene: ^host.Scene, raised: bool = false) {
	s := new(Expedition_Cards_Capture)
	s.wrapped = scene^
	s.raised = raised
	e := cast(^run.Expedition_Session)scene.data
	expedition_smoke_workshop(e,.West)
	room := &e.rs.room
	if raised {
		// A reproducible plateau tests the existing ground-height renderer.
		// No height or actor position changes after the encounter starts.
		for y in -6..=6 { for x in -6..=6 {
			cell := grid.offset(room.player.position,x,y)
			changed := level.set_height(room.level_data,cell,20)
			expedition_polish_require(changed,"native plateau setup failed")
		} }
	}
	deck := &room.player.deck
	rules, mana := deck.rules, deck.mana
	rules.hand_size = 7
	initialized := game.initialize_empty_deck(deck,rules,e.rs.run_seed)
	expedition_polish_require(initialized,"cards smoke deck initialization failed")
	deck.mana = mana
	for id in ([7]game.Card_Id{.Cannon,.Firebomb,.Guard,.Arc_Bolt,.Dash,.Heavy_Blow,.Thorn_Coat}) {
		_, added := game.add_owned_card(deck,id)
		expedition_polish_require(added,"cards smoke could not build its hand")
	}
	started := game.begin_expedition_encounter(room)
	expedition_polish_require(started,"cards smoke did not enter combat")
	// Choose an empty legal cannon anchor near the hero, before spawning a foe.
	cannon: game.Card_Instance
	for card in deck.hand[:deck.hand_count] { if card.definition_id == .Cannon { cannon = card } }
	expedition_polish_require(cannon.id != 0,"cards smoke has no Cannon in its initial hand")
	placed := false
	for offset in ([6]grid.Position{{x=1,y=1},{x=-1,y=1},{x=1},{x=-1},{y=1},{y=-1}}) {
		cell := game.add_position(room.player.position,offset)
		if _,valid := game.card_drop_target(room,cannon,cell);valid { s.anchor=cell;placed=true;break }
	}
	expedition_polish_require(placed,"cards smoke has no legal cannon anchor")
	s.far = grid.offset(room.player.position,5,0)
	for offset in ([4]grid.Position{{y=2},{x=2},{x=-2},{y=-2}}) {
		cell := game.add_position(room.player.position,offset)
		if cell == s.anchor || game.cell_blocks_movement(room,cell) { continue }
		if id,ok := game.spawn_enemy(room,{position=cell,health=20,attack=1,archetype=.Chaser});ok { s.foe=id;break }
	}
	expedition_polish_require(s.foe != 0,"cards smoke has no enemy")
	for card in deck.hand[:deck.hand_count] {
		if card.definition_id == .Firebomb { s.spell=card.id }
		if card.definition_id == .Thorn_Coat { s.cancelled=card.id }
	}
	expedition_polish_require(s.spell != 0 && s.cancelled != 0,"cards smoke is missing a required card")
	rl.SetWindowSize(1280,720)
	scene^ = {name="expedition-smoke",data=s,opaque=true,modal=true,
		update=expedition_cards_update,draw=expedition_cards_draw,
		after_present=expedition_cards_present,destroy=expedition_cards_destroy}
}

@(private)
expedition_cards_key :: proc(room: ^game.Room, id: game.Card_Id, devices: ^input.Device_Snapshot) {
	keys := [10]rl.KeyboardKey{.ONE,.TWO,.THREE,.FOUR,.FIVE,.SIX,.SEVEN,.EIGHT,.NINE,.ZERO}
	for card,i in room.player.deck.hand[:room.player.deck.hand_count] {
		if card.definition_id == id { devices.keys_pressed[keys[i]],devices.keys_down[keys[i]]=true,true;return }
	}
	expedition_polish_require(false,"native smoke requested a card absent from the hand")
}

@(private)
expedition_cards_update :: proc(data: rawptr, frame: ^host.Frame) {
	s := cast(^Expedition_Cards_Capture)data
	e := cast(^run.Expedition_Session)s.wrapped.data
	room,r := &e.rs.room,&e.rs.iso_renderer
	f := frame^
	devices := input.Device_Snapshot{focused=true}
	f.devices,f.dt,f.focused,f.window_focused=&devices,1.0/60,true,true
	f.mouse,f.mouse_inside={-1,-1},false
	point := s.anchor
	pointing,click := false,false
	if s.frames == 0 {
		switch s.stage {
		case 1: expedition_cards_key(room,.Cannon,&devices)
		case 2: pointing,click=true,true
		case 3: devices.wheel=1
		case 4,11: expedition_cards_key(room,.Firebomb,&devices)
		case 7: expedition_cards_key(room,.Thorn_Coat,&devices)
		case 6: expedition_cards_key(room,.Guard,&devices)
		case 12: pointing,click=true,true
		case 9: devices.buttons_pressed[.RIGHT],devices.buttons_down[.RIGHT]=true,true
		}
	}
	if s.stage == 5 { point,pointing=s.far,true }
	if s.stage == 12 {
		index,found := game.enemy_index_by_id(room,s.foe)
		expedition_polish_require(found,"native cards target disappeared")
		point=room.enemies[index].position
	}
	if pointing {
		height:=f32(game.cell_height(room,point)-room.level_data.base)*game.HEIGHT_STEP_DRAWN
		p:=render.tactical_project(r,{f32(point.x)+.5,f32(point.y)+.5},height)
		f.mouse,f.mouse_inside={p.x,p.y},true
		devices.mouse_position=f.mouse
		if click { devices.buttons_pressed[.LEFT],devices.buttons_down[.LEFT]=true,true }
	}
	s.wrapped.update(s.wrapped.data,&f)
	if s.frames == 0 {
		switch s.stage {
		case 2: expedition_polish_require(e.rs.card_interaction.placing,"cannon did not enter orientation")
		case 4:
			expedition_polish_require(!e.rs.card_interaction.placing && !r.tactical.expedition_placement,"changing cards retained cannon orientation")
		case 6: expedition_polish_require(game.tactical_is_casting(room) || game.tactical_player_busy(room),"guard did not start a real player action")
		case 7,8:
			expedition_polish_require(e.rs.gameplay_buffer.has_pending && e.rs.gameplay_buffer.pending.card_id==s.cancelled,"card was not queued during the real action")
		case 9:
			expedition_polish_require(!e.rs.gameplay_buffer.has_pending && e.rs.card_interaction.selected_card_id==0,"right click did not cancel the queued card")
		}
	}
}

@(private)
expedition_cards_draw :: proc(data: rawptr, frame: ^host.Frame) {
	s:=cast(^Expedition_Cards_Capture)data
	s.wrapped.draw(s.wrapped.data,frame)
}

@(private)
expedition_cards_present :: proc(data: rawptr, frame: ^host.Frame) {
	s:=cast(^Expedition_Cards_Capture)data
	e:=cast(^run.Expedition_Session)s.wrapped.data
	room,r:=&e.rs.room,&e.rs.iso_renderer
	s.frames+=1;s.total+=1
	done:=s.frames>=2
	if s.stage==0 { done=s.frames>=20 }
	if s.stage==5 && s.frames==2 {
		index,found:=game.hand_card_index_by_id(&room.player.deck,s.spell)
		expedition_polish_require(found && r.has_hovered_cell,"invalid target probe is not on the board")
		definition,_:=game.card_definition_by_id(.Firebomb)
		evaluation:=game.evaluate_card_targeting(room,room.player.deck.hand[index],game.card_target_request_at(definition,r.hovered_cell))
		expedition_polish_require(evaluation.error!=.None,"invalid target probe is unexpectedly legal")
		fmt.printf("CARDS POLISH invalid target: %v at %v\n",evaluation.error,r.hovered_cell)
		artifacts.screenshot(fmt.ctprintf("odin_pp_polish_cards_%s_invalid.png","raised" if s.raised else "flat"))
	}
	if s.stage==4 && s.frames==2 { artifacts.screenshot(fmt.ctprintf("odin_pp_polish_cards_%s_switched.png","raised" if s.raised else "flat")) }
	if s.stage==6 && done { artifacts.screenshot(fmt.ctprintf("odin_pp_polish_cards_%s_guard.png","raised" if s.raised else "flat")) }
	if s.stage==10 {
		done=s.frames>60 && !game.tactical_is_casting(room) && !game.tactical_player_busy(room) && !render.renderer_blocks_player_input(r)
		_,present:=game.hand_card_index_by_id(&room.player.deck,s.cancelled)
		expedition_polish_require(present,"cancelled Thorn Coat left the hand")
	}
	if s.stage==13 {
		if !s.damage_captured {
			for i in 0..<render.renderer_active_cue_count(r) {
				cue,found:=render.renderer_active_cue_at(r,i)
				if !found || !cue.started || cue.kind!=.Damage || cue.event.target!=game.enemy_entity(s.foe) { continue }
				if render.presentation_cue_progress(cue)<.2 { continue }
				artifacts.screenshot(fmt.ctprintf("odin_pp_polish_cards_%s_damage.png","raised" if s.raised else "flat"))
				s.damage_captured=true
				break
			}
		}
		_,present:=game.hand_card_index_by_id(&room.player.deck,s.spell)
		index,found:=game.enemy_index_by_id(room,s.foe)
		done=!present && found && room.enemies[index].health<20 && s.damage_captured
	}
	if done {
		fmt.printf("CARDS POLISH stage=%d frames=%d pending=%v selected=%d\n",s.stage,s.frames,e.rs.gameplay_buffer.has_pending,e.rs.card_interaction.selected_card_id)
		s.stage+=1;s.frames=0
	}
	if s.stage>13 {
		s.complete=true
		fmt.printf("CARDS POLISH COMPLETE: orientation, refused target, queued cancel and a real cast; raised=%v\n",s.raised)
		host.quit(frame)
	} else if s.total>=1500 { expedition_polish_require(false,"native cards smoke timed out") }
}

@(private)
expedition_cards_destroy :: proc(data: rawptr) {
	s:=cast(^Expedition_Cards_Capture)data
	complete:=s.complete
	s.wrapped.destroy(s.wrapped.data)
	free(s)
	if !complete { fmt.eprintln("CARDS POLISH INCOMPLETE");os.exit(2) }
}
