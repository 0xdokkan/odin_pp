package run

import "core:fmt"
import "core:math"
import "core:strings"
import rl "vendor:raylib"
import campaign "../campaign"
import campaignui "../campaignui"
import world "../expedition"
import activities "../activities"
import host "../engine/host"
import input "../engine/input"
import rng "../engine/rng"
import ui "../engine/ui"
import game "../game"
import render "../render"

Expedition_Scene_Timing :: struct {view_ms,world_ms,hud_hand_ms,map_ms,effect_ms:f64}

// The hub owns campaign and last stable snapshot for the lifetime of this
// scene. Closing a window saves it; only the explicit abandon action loses it.
Expedition_Session :: struct {
	rs:^Roguelike_Session,
	progress:^campaign.Campaign,
	checkpoint:^world.Snapshot,
	// Exploration glides; the room keeps the cell under the robot's center.
	roam:world.Roam,
	world:world.World,
	path:string,
	save:proc(rawptr)->bool,
	flush:proc(rawptr)->bool,
	save_data:rawptr,
	inventory:campaignui.State,
	inventory_open,character_open,map_open,paused,abandon_confirm:bool,
	site:int,
	workshop_remove:int,
	save_timer,message_timer:f32,
	message:string,
	last_revision,last_pulse:u64,
	mirrored_gold:i32,
	save_failed,finished,extracting:bool,
	window_active:bool,
	smoke:bool,
	smoke_step:int,
	draw_timing:Expedition_Scene_Timing,
}

expedition_create :: proc(c:^campaign.Campaign,checkpoint:^world.Snapshot,path:string,frame:^host.Frame,save:proc(rawptr)->bool=nil,save_data:rawptr=nil,flush:proc(rawptr)->bool=nil) -> (host.Scene,bool) {
	if c==nil || !c.run.active {return {},false}
	e:=new(Expedition_Session);e.progress=c;e.checkpoint=checkpoint;e.path=strings.clone(path);e.site=-1;e.save=save;e.flush=flush;e.save_data=save_data;e.window_active=true
	rs:=roguelike_session_new();e.rs=rs
	rs.options.tactical=game.EXPEDITION_TACTICAL_CONFIG;rs.options.persist_profile=false;rs.options.seed=c.run.seed
	rs.run_seed=c.run.seed;rs.run_state.phase=.In_Room
	if checkpoint!=nil && checkpoint.valid {
		if !world.restore(checkpoint,&e.world,&rs.level_data,&rs.run_state.player,&rs.room) {roguelike_destroy(rs);delete(e.path);free(e);return {},false}
	} else {
		player,ok:=game.create_player({max_health=32,attack=2,defense=1})
		if !ok || !world.generate(&e.world,&rs.level_data,c.run.biome,c.run.seed) {roguelike_destroy(rs);delete(e.path);free(e);return {},false}
		rs.run_state.player=player
		room,ready:=game.create_room(&rs.level_data,&rs.run_state.player,{room_seed=c.run.seed})
		if !ready {roguelike_destroy(rs);delete(e.path);free(e);return {},false}
		rs.room=room;rs.room.phase=.Loot
		_=game.configure_expedition_combat(&rs.room)
		game.end_expedition_encounter(&rs.room)
		world.prepare_room(&e.world,&rs.room)
		campaign.apply_equipment(&c.backpack,&rs.run_state.player)
	}
	rs.room.player.tactical.config.low_gravity = e.world.biome == .Space
	rs.room.player.tactical.config.expedition_biome = u8(e.world.biome)
	rs.room_created=true;rs.run_created=true
	if roguelike_attach(rs,frame.window)!=.Ready {roguelike_destroy(rs);delete(e.path);free(e);return {},false}
	for &site,i in e.world.sites[:e.world.site_count] {if site.secret && campaign.secret_known(c,e.world.biome,i) && site.state==.Unvisited {site.state=.Discovered}}
	e.world.last_health=rs.room.player.health
	// The inventory owns credits; this baseline detects direct card effects
	// without mistaking inventory purchases or drops for a fresh award.
	e.mirrored_gold=rs.room.player.gold
	expedition_message(e,"La memoria resta. Il resto devi portarlo a casa.")
	_=expedition_save(e)
	return host.Scene{name="expedition",data=e,opaque=true,modal=true,clear_color={5,7,14,255},update=expedition_update,draw=expedition_draw,draw_window=expedition_draw_window,resume=expedition_resume,suspend=expedition_suspend,destroy=expedition_destroy},true
}

@(private)
expedition_message :: proc(e:^Expedition_Session,message:string) {delete(e.message);e.message=strings.clone(message);e.message_timer=5}

// Free movement reads the screen: W climbs it even though the grid's axes
// run diagonally under the fixed camera. Encounters keep the grid's keys.
@(private)
expedition_walk_wish :: proc(rs:^Roguelike_Session,frame:^host.Frame)->[2]f32 {
	side:=f32(int(input.key_down(frame.devices,.D))-int(input.key_down(frame.devices,.A)))
	ahead:=f32(int(input.key_down(frame.devices,.W))-int(input.key_down(frame.devices,.S)))
	if side==0 && ahead==0 {return {}}
	camera:=rs.iso_renderer.tactical.camera
	forward:=[2]f32{camera.target.x-camera.position.x,camera.target.z-camera.position.z}
	length:=math.sqrt(forward.x*forward.x+forward.y*forward.y);if length<.0001 {return {}}
	forward/=length
	wish:=[2]f32{-forward.y,forward.x}*side+forward*ahead
	norm:=math.sqrt(wish.x*wish.x+wish.y*wish.y)
	return wish/norm if norm>1 else wish
}

expedition_save :: proc(e:^Expedition_Session,durable:bool=false) -> bool {
	if e.checkpoint!=nil && e.progress.run.active && !e.extracting {
		if !world.capture(&e.world,&e.rs.room,e.checkpoint) {
			// A cast cannot become a checkpoint. Closing or losing focus must
			// still finish the preceding coherent checkpoint already in flight.
			if durable && e.flush!=nil {e.save_failed=!e.flush(e.save_data)}
			return false
		}
	}
	if !e.progress.run.active && e.checkpoint!=nil {e.checkpoint.valid=false}
	if e.save!=nil {e.save_failed=!e.save(e.save_data)}
	else if e.path!="" && e.checkpoint!=nil {e.save_failed=!campaign.save_slot_from(e.path,e.progress,e.checkpoint)}
	if durable && e.flush!=nil {
		submitted:=!e.save_failed
		flushed:=e.flush(e.save_data)
		e.save_failed=!submitted || !flushed
	}
	e.save_timer=0;e.last_revision=e.progress.revision;e.last_pulse=e.rs.room.pulse_count
	return !e.save_failed
}

@(private)
expedition_suspend :: proc(data:rawptr) {e:=cast(^Expedition_Session)data;_=expedition_save(e,true);roguelike_suspend_input(e.rs)}
@(private)
expedition_destroy :: proc(data:rawptr) {e:=cast(^Expedition_Session)data;_=expedition_save(e,true);roguelike_destroy(e.rs);delete(e.path);delete(e.message);free(e)}
@(private)
expedition_draw_window :: proc(data:rawptr,frame:^host.Frame) {e:=cast(^Expedition_Session)data;roguelike_draw_window(e.rs,frame)}

@(private)
expedition_resume :: proc(data:rawptr,frame:^host.Frame,from:string,result:Maybe(host.Result)) {
	e:=cast(^Expedition_Session)data;roguelike_suspend_input(e.rs)
	if !e.extracting {return}
	stars:u8
	if r,ok:=result.?;ok {stars=r.stars;campaign.record_result(e.progress,activities.minigame_index_by_id(from),r.score,r.stars,r.outcome==.Won);if from=="ring" && r.outcome==.Won {campaign.discover(e.progress,.Titan_Grip);campaign.discover(e.progress,.Storm_Crown)}}
	_=campaign.finish_run(e.progress,true,stars);e.finished=true;_=expedition_save(e)
	host.pop(frame,host.Result{minigame="expedition",outcome=.Won,stars=stars})
}

@(private)
expedition_extract :: proc(e:^Expedition_Session,frame:^host.Frame) {
	if !e.world.boss_defeated || e.extracting {return}
	e.world.extracting=true;e.progress.run.boss_defeated=true
	_=expedition_save(e);e.extracting=true
	id:=world.metadata(e.world.biome).arcade
	if e.world.biome==.City && e.world.seed%2==0 {id="ring"}
	info,ok:=activities.minigame_info(activities.minigame_index_by_id(id))
	if ok {host.push(frame,info.create({seed=e.world.seed,challenge=true}))}
	else {expedition_resume(e,frame,"",nil)}
}

@(private)
expedition_collect :: proc(e:^Expedition_Session,manual:bool=false) {
	w:=&e.world;room:=&e.rs.room;c:=e.progress
	for event in room.recent_events.events[:room.recent_events.count] {
		if event.kind==.Fish_Caught && event.card_definition!=.Fishing_Rod {campaign.discover(c,event.card_definition)}
	}
	if room.player.gold>e.mirrored_gold {
		append(&room.loot,game.Loot{position=room.player.position,kind=.Gold,amount=room.player.gold-e.mirrored_gold})
	}
	// The legacy room only produces loot; the backpack is its sole consumer.
	loot_index:=0
	for loot_index<len(room.loot) {
		item:=room.loot[loot_index]
		made:campaign.Item
		switch item.kind {
		case .Gold:made=campaign.make_item(.Credits,min(item.amount,99))
		case .Healing:made=campaign.make_item(.Healing,1,item.healing_amount)
		case .Weapon:made=campaign.make_item(.Weapon,1,i32(item.weapon_id));made.uses=item.amount
		}
		if !world.add_drop(w,item.position,made) {break}
		if item.kind==.Gold && item.amount>99 {room.loot[loot_index].amount-=99;continue}
		ordered_remove(&room.loot,loot_index)
	}
	i:=0
	for i<w.drop_count {
		drop:=w.drops[i]
		if drop.manual_only && !manual {i+=1;continue}
		if world.distance(room.player.position,drop.position)> (2 if manual else 3) {i+=1;continue}
		taken:=false
		if drop.xp>0 {levels:=campaign.add_xp(c,drop.xp);taken=true;if levels>0 {expedition_message(e,fmt.tprintf("LIVELLO %d  /  +%d punto potenziamento",c.run.level,levels))}}
		else {
			if drop.item.kind==.Credits && !manual {
				accepted:=campaign.backpack_credit(&c.backpack,drop.item.quantity)
				if accepted>0 {w.drops[i].item.quantity-=accepted;c.revision+=1;taken=w.drops[i].item.quantity==0}
			} else {result:=campaign.pickup(&c.backpack,drop.item,manual);taken=result!=.Rejected;if result==.Pending {e.inventory_open=true;expedition_message(e,"Oggetto in sospeso: trova un posto nello zaino.")}}
		}
		if taken {w.drop_count-=1;w.drops[i]=w.drops[w.drop_count];c.revision+=1}
		else {i+=1}
	}
	room.player.gold=campaign.backpack_credits(&c.backpack)
	e.mirrored_gold=room.player.gold
}

@(private)
expedition_drop_inventory_item :: proc(e:^Expedition_Session,item:campaign.Item) -> bool {
	room:=&e.rs.room;bag:=&e.progress.backpack
	if world.add_drop(&e.world,room.player.position,item,manual_only=true) {return true}
	// Grid/pending drops leave their own free space. An equipped item instead
	// leaves an equipment slot; a completely full backpack cannot receive it.
	restored:=campaign.pickup(bag,item,true)!=.Rejected
	if !restored && item.kind==.Weapon && bag.weapon.kind==.None {bag.weapon=item;restored=true}
	if !restored && item.kind==.Relic {
		for &slot in bag.relics {if slot.kind==.None {slot=item;restored=true;break}}
	}
	assert(restored,"An inventory drop must leave a slot where it can be restored")
	campaign.apply_equipment(bag,room.player)
	e.inventory_open=true
	expedition_message(e,"Il terreno e pieno: l'oggetto e rimasto nel tuo equipaggiamento.")
	return false
}

@(private)
expedition_reward :: proc(e:^Expedition_Session,index:int) {
	w:=&e.world;if w.reward_count>0 {return}
	if w.sites[index].kind==.Trial && w.drop_count>=world.MAX_DROPS {return}
	w.reward_site=index
	r:=rng.create(w.sites[index].seed~0xAE1A)
	excluded:=game.card_offer_exclusions(&e.rs.room.player.deck)
	for id in game.Card_Id.Strike..<game.Card_Id.Count {if !campaign.card_in_pool(e.progress,id) {excluded+={id}}}
	node:=game.Run_Node{kind=.Elite if w.sites[index].kind==.Trial else .Combat,depth=world.rank(w.biome)*3}
	// Campaign discovery replaces the old ring profile gate; the explicit pool
	// exclusions above still keep unknown cards out until the following run.
	profile:=game.M8_Profile{ring_wins=3}
	if !game.generate_weighted_card_choices(&r.state,&node,w.reward_cards[:],&profile,excluded) {return}
	w.reward_count=3
	w.sites[index].reward_pending=false
	if w.sites[index].kind==.Trial {_=world.add_drop(w,w.sites[index].position,campaign.make_item(.Relic,1,1+i32(rng.next_u64(&r)%(u64(game.Relic_Id.Count)-1))))}
	_=campaign.add_xp(e.progress,4+i32(world.rank(w.biome))*2)
	e.progress.revision+=1
}

@(private)
expedition_interact :: proc(e:^Expedition_Session,frame:^host.Frame) {
	w:=&e.world;c:=e.progress;room:=&e.rs.room
	if w.mounted {expedition_message(e,"Scendi dalla mount con M per interagire.");return}
	if room.phase==.Combat {return}
	expedition_collect(e,true)
	if w.boss_defeated && world.distance(room.player.position,room.exit_position)<=3 {expedition_extract(e,frame);return}
	index:=world.nearest_site(w,room.player.position);if index<0 {return}
	s:=&w.sites[index]
	if s.group>=0 {for m in w.groups[s.group].members[:w.groups[s.group].count] {if m.alive {_=world.engage(w,room,s.group);if s.kind==.Boss {w.boss_announced=true};expedition_message(e,world.metadata(w.biome).entry if s.kind==.Boss else "La memoria si difende.");return}}}
	s.state=.Discovered
	switch s.kind {
	case .Nest,.Trial: if s.reward_pending {expedition_reward(e,index)}
	case .Boss: if w.boss_defeated {expedition_extract(e,frame)}
	case .Cache:
		if w.drop_count>world.MAX_DROPS-2 {expedition_message(e,"Raccogli un oggetto a terra prima di aprire questa cache.");return}
		r:=rng.create(s.seed)
		_=world.add_drop(w,s.position,campaign.make_item(.Credits,15+i32(rng.next_u64(&r)%35)))
		kind:=campaign.Item_Kind.Healing
		roll:=rng.next_u64(&r)%8
		if roll==0 {kind=.Backpack};if roll==1 {kind=.Relic};if roll==2 {kind=.Energy};if roll==3 {kind=.Weapon};if roll==4 {kind=.Decoy};if roll==5 {kind=.Upgrade};if roll==6 {kind=.Temporary_Card}
		variant:i32
		if kind==.Relic {variant=1+i32(rng.next_u64(&r)%(u64(game.Relic_Id.Count)-1))}
		if kind==.Weapon {variant=i32(game.Weapon_Id.Iron_Cleaver)}
		if kind==.Temporary_Card {variant=i32(game.Card_Id.Strike)}
		if kind==.Backpack {variant=min(i32(campaign.GRID_MAX_WIDTH-campaign.BACKPACK_WIDTH),1+i32(world.rank(w.biome)))}
		_=world.add_drop(w,s.position,campaign.make_item(kind,1,variant));s.state=.Resolved;expedition_collect(e,true)
	case .Archive:
		id,found:=expedition_discovery(c,w.biome,s.seed)
		if found {campaign.discover(c,id);definition,_:=game.card_definition_by_id(id);expedition_message(e,fmt.tprintf("SCOPERTA: %s. Disponibile dalle prossime spedizioni.",definition.name))}
		else {expedition_message(e,"Archivio completo. La memoria non ha piu segreti.")}
		s.state=.Resolved
	case .Spring:room.player.health=min(room.player.stats.max_health,room.player.health+16);s.state=.Resolved;expedition_message(e,"Fonte esaurita. +16 vita.")
	case .Workshop:e.site=index
	case .Memory:
		if !world.add_drop(w,s.position,campaign.make_item(.Memory,1,i32(w.biome))) {expedition_message(e,"Raccogli un oggetto a terra prima di recuperare il frammento.");return}
		s.state=.Resolved;expedition_collect(e,true);expedition_message(e,"Frammento recuperato. Estrai per ascoltarlo nell'hub.")
	case .Tunnel:
		position,safe:=world.tunnel_destination(w,room)
		if !safe {expedition_message(e,"L'uscita del tunnel e ostruita. Riprova piu tardi.");return}
		room.player.position=position;s.state=.Resolved;expedition_message(e,"Il tunnel riemerge oltre le risaie.")
	}
	c.revision+=1
}

expedition_discovery :: proc(c:^campaign.Campaign,b:campaign.Biome,seed:u64) -> (game.Card_Id,bool) {
	home:[4]game.Card_Id
	switch b {
	case .Cyber:home={.Cannon,.Tesla_Coil,.Shock_Floor,.Flood}
	case .West:home={.Lasso,.Sei_Denari,.Sette_Denari,.Coffin}
	case .Jungle:home={.Dinosaur,.Poison_Pool,.Venom_Blade,.Caustic_Bloom}
	case .City:home={.Bomb_Marley,.Pinball,.Shove,.Storm_Crown}
	case .Egypt:home={.Fate_Dice,.Fate_Strike,.Calculated_Risk,.Prismatic_Barrage}
	case .Vietnam:home={.First_Person,.Wildfire,.Firebomb,.Cannon}
	case .Snow:home={.Deflect,.Guard,.Dash,.Purifying_Guard}
	case .Inferno:home={.Wildfire,.Firebomb,.Thorn_Coat,.Bomb_Marley}
	case .Gothic:home={.Shadow_Step,.Coffin,.Lasso,.Counter_Rune}
	case .Sky:home={.Afterimage,.Purifying_Guard,.Dash,.Grappling_Hook}
	case .Space:home={.Black_Hole,.Cannon,.Prismatic_Barrage,.Chain_Lightning}
	case .Secret:home={.Black_Hole,.Titan_Grip,.Storm_Crown,.Fate_Dice}
	case .Count:return {},false
	}
	for i in 0..<4 {id:=home[(i+int(seed%4))%4];if !c.discovered[id] {return id,true}}
	for i in 0..<int(game.Card_Id.Count) {id:=game.Card_Id((i+int(seed%u64(game.Card_Id.Count)))%int(game.Card_Id.Count));if !c.discovered[id] && !game.card_is_lab_only(id) {return id,true}}
	return {},false
}

@(private)
expedition_update :: proc(data:rawptr,frame:^host.Frame) {
	e:=cast(^Expedition_Session)data;rs:=e.rs;room:=&rs.room;c:=e.progress;w:=&e.world
	if e.finished {return}
	rs.frame_input=map_run_input(&rs.actions,frame.devices,frame.focused&&frame.window_focused,&rs.input_history)
	rs.frame_time=frame.dt;rs.mouse_canvas={frame.mouse.x,frame.mouse.y};rs.mouse_inside=frame.mouse_inside
	if !frame.window_focused {
		if e.window_active {_=expedition_save(e,true);e.window_active=false}
		roguelike_suspend_input(rs);return
	}
	e.window_active=true
	if !frame.focused {roguelike_suspend_input(rs);return}
	if rs.effect_window.open {update_effect_window_in_run(rs,frame);return}
	if w.extracting && !e.extracting {expedition_extract(e,frame);return}
	e.message_timer=max(0,e.message_timer-frame.dt);e.save_timer+=frame.dt;c.play_seconds+=f64(frame.dt)
	if input.key_pressed(frame.devices,.F10) {
		if expedition_save(e,true) {host.pop(frame)} else {expedition_message(e,"Attendi la fine dell'azione prima di tornare all'hub.")}
		return
	}
	if input.key_pressed(frame.devices,.P) || (input.key_pressed(frame.devices,.ESCAPE) && !e.inventory_open && !e.map_open && e.site<0 && w.reward_count==0) {e.paused=!e.paused;clear_card_interaction(&rs.card_interaction)}
	if e.paused {
		ctx:=frame.ui;p:=ctx.theme.palette
		ui.dim(ctx,frame.canvas,.65);box:=ui.panel(ctx,ui.center(frame.canvas,430,280),"MEMORIA SOSPESA")
		ui.paragraph(ctx,ui.cut_top(&box,55),"Puoi chiudere il gioco: riprenderai da qui.\nAbbandonare perde lo zaino e azzera la serie.",.Small,p.text_dim)
		if ui.button(ctx,ui.cut_top(&box,42),"Riprendi",primary=true) {e.paused=false}
		ui.cut_top(&box,10)
		if ui.button(ctx,ui.cut_top(&box,38),"Salva e torna agli slot") {if expedition_save(e,true) {host.pop(frame)};return}
		ui.cut_top(&box,10)
		if ui.button(ctx,ui.cut_top(&box,38),"Conferma: perdi lo zaino" if e.abandon_confirm else "Abbandona la spedizione") {
			if e.abandon_confirm {_=campaign.finish_run(c,false);e.finished=true;_=expedition_save(e);host.pop(frame,host.Result{outcome=.Abandoned});return}
			e.abandon_confirm=true
		}
		return
	}
	if !e.inventory_open && !e.map_open && e.site<0 && w.reward_count==0 && rs.frame_input.left_pressed {
		layout:=render.tactical_hud_layout(&rs.iso_renderer)
		if rl.CheckCollisionPointRec(frame.mouse,layout.map_button) {e.map_open=true;rs.frame_input.left_pressed=false}
		else if render.m8_control_at_point(&rs.iso_renderer,room,rs.mouse_canvas)==.Character {e.inventory_open=true;e.inventory.panel=.Character;rs.frame_input.left_pressed=false}
	}
	if input.key_pressed(frame.devices,.Z) && !e.inventory_open {e.inventory_open=true;e.inventory.panel=.Inventory}
	if input.key_pressed(frame.devices,.U) && !e.inventory_open {e.inventory_open=true;e.inventory.panel=.Character}
	if input.key_pressed(frame.devices,.TAB) && !e.inventory_open {e.map_open=!e.map_open;clear_card_interaction(&rs.card_interaction)}
	if e.map_open && input.key_pressed(frame.devices,.ESCAPE) {e.map_open=false}
	if input.key_pressed(frame.devices,.M) && room.phase==.Loot && !e.inventory_open {w.mounted=!w.mounted;expedition_message(e,world.metadata(w.biome).mount if w.mounted else "A piedi")}
	if !e.inventory_open && !e.map_open && e.site<0 && w.reward_count==0 && render.tactical_inspector_effect_ready(&rs.iso_renderer,room) {
		cards:=&rs.card_interaction
		card,effect:=render.tactical_inspector_effect(&rs.iso_renderer,room,cards.hovered_card_id,cards.selected_card_id,cards.dragged_card_id)
		if effect!=.None && (run_pressed(rs.frame_input,.Inspect) || effect==.Button && rs.frame_input.left_pressed && render.point_in_rectangle(rs.mouse_canvas,render.tactical_inspector_effect_bounds())) {
			if open_effect_window_in_run(rs,card,.Inspector) {return}
		}
	}
	character_pause:=e.inventory_open && e.inventory.panel!=.Inventory
	if !character_pause {
		_=render.update_renderer_frame_timeline(&rs.iso_renderer,frame.dt)
		render.advance_sprite_assets(&rs.iso_renderer.sprite_assets,frame.dt)
		render.update_tactical_atmosphere(&rs.iso_renderer,frame.dt)
		render.set_living_cards(&rs.iso_renderer,true)
		render.update_tactical_view(&rs.iso_renderer,room,rs.mouse_canvas,rs.mouse_inside&&!e.inventory_open&&!e.map_open,input={wheel=0})
		controls:=rs.frame_input
		controls.actions.pressed-={.Pause,.Map,.Cancel,.Route_Map,.Restart}
		if e.inventory_open || e.map_open || e.site>=0 || w.reward_count>0 {controls.left_pressed=false;controls.right_pressed=false;controls.wheel=0;controls.actions.pressed={};controls.actions.down={}}
		blocked:=update_tactical_controller(&rs.tactical_controller,room,&rs.iso_renderer,&rs.card_interaction,&rs.gameplay_buffer,frame.dt,true,rs.mouse_canvas,!e.inventory_open&&!e.map_open&&rs.mouse_inside,nil,controls)
		world_runs:=!game.tactical_is_casting(room) && room.qte.kind==.None && !game.tactical_shadow_active(room) && render.presentation_time_policy(&rs.iso_renderer.timeline)!=.Cinematic
		if world_runs {
			_=world.sync(w,room)
			world.tick(w,room,frame.dt)
			for site,i in w.sites[:w.site_count] {
				if site.secret && site.state!=.Unvisited {if campaign.discover_secret(c,w.biome,i) {expedition_message(e,"SEGRETO TROVATO / Un luogo che non dimenticherai.")}}
				if site.reward_pending && room.phase==.Loot {expedition_reward(e,i);break}
			}
		}
		// Exploration glides freely; encounters bring the cell steps back.
		walking:=!blocked && !e.inventory_open && !e.map_open && e.site<0 && w.reward_count==0 && room.phase==.Loot
		world.roam_step(w,room,&e.roam,expedition_walk_wish(rs,frame) if walking else {},frame.dt if world_runs else 0)
		if !blocked && !e.inventory_open && !e.map_open && e.site<0 && w.reward_count==0 {
			if room.phase==.Loot {
				if input.key_pressed(frame.devices,.E) {expedition_interact(e,frame)}
				if !w.mounted {
					fishing_controls:=controls;fishing_controls.actions.pressed={};fishing_controls.actions.down={}
					command,has:=poll_gameplay_command(room,&rs.iso_renderer,&rs.card_interaction,rs.mouse_canvas,rs.mouse_inside,!render.renderer_blocks_player_input(&rs.iso_renderer),false,fishing_controls)
					if has&&command.kind==.Fish {_=commit_gameplay_command(room,&rs.iso_renderer,&rs.card_interaction,command)}
				}
				// A deliberate click on a resting enemy starts an encounter.
				if controls.left_pressed && rs.iso_renderer.has_hovered_cell {for &g,i in w.groups[:w.group_count] {for m in g.members[:g.count] {if m.alive && world.distance(m.enemy.position,rs.iso_renderer.hovered_cell)<=1 && world.distance(room.player.position,m.enemy.position)<=8 {_=world.engage(w,room,i);w.mounted=false;break}}}}
			} else if room.phase==.Combat {
				busy:=render.renderer_blocks_player_input(&rs.iso_renderer)||game.tactical_player_busy(room)
				command,has:=poll_gameplay_command(room,&rs.iso_renderer,&rs.card_interaction,rs.mouse_canvas,rs.mouse_inside,!busy,false,controls)
				if ready,ok:=route_gameplay_command(&rs.gameplay_buffer,room,busy,command,has,frame.dt,game.MOVEMENT_KEY_DIRECTIONS,controls);ok {_=commit_gameplay_command(room,&rs.iso_renderer,&rs.card_interaction,ready)}
			}
		}
		_=world.sync(w,room);expedition_collect(e)
		// Tunnels and forced moves this frame are adopted before drawing.
		world.roam_sync(&e.roam,room)
		r:=&e.roam
		render.set_expedition_walker(&rs.iso_renderer,room.phase==.Loot,{r.position.x+r.offset.x-.5,r.position.y+r.offset.y-.5},{r.velocity.x,r.velocity.y},r.stride,frame.dt)
		if !w.boss_announced {for group in w.groups[:w.group_count] {if group.boss && group.active {w.boss_announced=true;expedition_message(e,world.metadata(w.biome).entry);break}}}
		campaign.sync_weapon(&c.backpack,room.player)
		update_run_dice_overlay(rs)
		roguelike_lab_sounds(rs,frame)
	}
	if room.phase==.Defeat || room.player.health<=0 {
		_=campaign.finish_run(c,false);e.finished=true;_=expedition_save(e);host.pop(frame,host.Result{minigame="expedition",outcome=.Lost});return
	}
	if e.inventory_open {
		can_use:=room.phase!=.Combat || (game.tactical_allows_action(room) && !render.renderer_blocks_player_input(&rs.iso_renderer))
		out:=campaignui.update_inventory(c,room.player,&e.inventory,frame,room.phase==.Combat,false,can_use)
		if out.closed {e.inventory_open=false;clear_card_interaction(&rs.card_interaction)}
		for item in out.drops[:out.drop_count] {
			_=expedition_drop_inventory_item(e,item)
		}
		if out.action_seconds>0 {game.finish_player_combat_command(room,out.action_seconds)}
		if out.decoy {
			if world.lure_patrol(w,room,room.player.position) {expedition_message(e,"Esca attiva. La pattuglia vicina sta seguendo il segnale.")}
			else {expedition_message(e,"Nessuna pattuglia libera ha raccolto il segnale dell'esca.")}
		}
		if out.show_effect {_=open_effect_window_in_run(rs,{id=1,definition_id=out.effect_card},.Sheet)}
	}
	if w.reward_count>0 && !e.inventory_open {expedition_reward_ui(e,frame)}
	if e.site>=0 && !e.inventory_open {expedition_workshop_ui(e,frame)}
	if !e.inventory_open && !e.map_open && room.phase==.Loot {
		if ui.button(frame.ui,{788,450,150,28},"ZAINO  [Z]") {e.inventory_open=true;e.inventory.panel=.Inventory}
	}
	if e.save_timer>=10 || c.revision!=e.last_revision || room.pulse_count!=e.last_pulse {if world.stable(room) && !render.renderer_timeline_is_busy(&rs.iso_renderer) {_=expedition_save(e)}}
}

@(private)
expedition_reward_ui :: proc(e:^Expedition_Session,frame:^host.Frame) {
	ctx:=frame.ui;p:=ctx.theme.palette;w:=&e.world
	ui.dim(ctx,frame.canvas,.64);box:=ui.panel(ctx,ui.center(frame.canvas,760,285),"RICORDO RECUPERATO / SCEGLI UNA CARTA")
	ui.label(ctx,ui.cut_top(&box,22),"La carta restera con te fino alla fine della spedizione.",.Small,p.text_dim)
	row:=ui.cut_top(&box,150)
	for id,i in w.reward_cards[:w.reward_count] {
		definition,_:=game.card_definition_by_id(id);cell:=ui.column(row,3,i,12);inside:=ui.panel(ctx,cell)
		ui.label(ctx,ui.cut_top(&inside,28),definition.name,.Body,p.text)
		ui.label(ctx,ui.cut_top(&inside,26),fmt.tprintf("ENERGIA %d",game.expedition_card_energy_cost(id)),.Small,p.focus)
		if ui.button(ctx,ui.cut_top(&inside,32),"Mostra effetto") {_=open_effect_window_in_run(e.rs,{id=1,definition_id=id},.Reward)}
		if ui.button(ctx,ui.cut_bottom(&inside,30),"Prendi",primary=true) {
			_,result:=game.add_owned_card(&e.rs.room.player.deck,id)
			if result {w.reward_count=0;e.progress.revision+=1;break}
			expedition_message(e,"Mazzo pieno: rimuovi una carta in officina o salta il premio.")
		}
	}
	if ui.button(ctx,ui.cut_bottom(&box,30),"Salta") {w.reward_count=0;e.progress.revision+=1}
}

@(private)
expedition_workshop_card :: proc(e:^Expedition_Session) -> (game.Card_Id,bool) {
	if e.site<0 || e.site>=e.world.site_count {return {},false}
	random:=rng.create(e.world.sites[e.site].seed~0x5A09)
	excluded:=game.card_offer_exclusions(&e.rs.room.player.deck)
	for id in game.Card_Id.Strike..<game.Card_Id.Count {if !campaign.card_in_pool(e.progress,id) {excluded+={id}}}
	node:=game.Run_Node{kind=.Shop,depth=world.rank(e.world.biome)*3}
	profile:=game.M8_Profile{ring_wins=3}
	choice:[1]game.Card_Id
	if !game.generate_weighted_card_choices(&random.state,&node,choice[:],&profile,excluded) {return {},false}
	return choice[0],true
}

@(private)
expedition_buy_consumable :: proc(c:^campaign.Campaign,item:campaign.Item,price:i32) -> bool {
	if c==nil || price<=0 || !campaign.item_valid(item) {return false}
	// Paying can empty a credit stack and free the very cell being purchased.
	// Stage both mutations so a refused placement never charges the player.
	bag:=c.backpack
	if !campaign.backpack_pay(&bag,price) || !campaign.grid_add(&bag.grid,item) {return false}
	c.backpack=bag;c.revision+=1
	return true
}

@(private)
expedition_workshop_ui :: proc(e:^Expedition_Session,frame:^host.Frame) {
	ctx:=frame.ui;p:=ctx.theme.palette;c:=e.progress;room:=&e.rs.room
	ui.dim(ctx,frame.canvas,.64);box:=ui.panel(ctx,ui.center(frame.canvas,640,454),"OFFICINA / CREDITI NELLO ZAINO")
	ui.label(ctx,ui.cut_top(&box,28),fmt.tprintf("Disponibili: %d crediti",campaign.backpack_credits(&c.backpack)),.Body,p.focus)
	footer:=ui.cut_bottom(&box,34);ui.cut_bottom(&box,8)
	id,found:=expedition_workshop_card(e)
	definition,_:=game.card_definition_by_id(id)
	row:=ui.cut_top(&box,40);inspect:=ui.cut_right(&row,136);ui.cut_right(&row,8)
	if ui.button(ctx,row,fmt.tprintf("%s  /  20 crediti",definition.name),found && room.player.deck.owned_count<game.MAX_OWNED_CARDS && campaign.backpack_credits(&c.backpack)>=20) {
		if campaign.backpack_credits(&c.backpack)>=20 {_,result:=game.add_owned_card(&room.player.deck,id);if result {campaign.backpack_pay(&c.backpack,20);c.revision+=1}}
	}
	if ui.button(ctx,inspect,"MOSTRA EFFETTO",found,false,.Small) {_=open_effect_window_in_run(e.rs,{id=1,definition_id=id},.Shop_Offer)}
	ui.cut_top(&box,8)
	if ui.button(ctx,ui.cut_top(&box,36),"Kit di riparazione  /  10 crediti",campaign.backpack_credits(&c.backpack)>=10) {
		if !expedition_buy_consumable(c,campaign.make_item(.Healing),10) {expedition_message(e,"Fai spazio nello zaino prima di comprare il kit.")}
	}
	ui.cut_top(&box,14)
	if room.player.deck.owned_count>0 {
		e.workshop_remove=clamp(e.workshop_remove,0,room.player.deck.owned_count-1)
		card:=room.player.deck.owned[e.workshop_remove];selected,_:=game.card_definition_by_id(card.definition_id)
		row=ui.cut_top(&box,30);previous:=ui.cut_left(&row,34);next:=ui.cut_right(&row,34)
		if ui.button(ctx,previous,"<",true,false,.Small) {e.workshop_remove=(e.workshop_remove+room.player.deck.owned_count-1)%room.player.deck.owned_count}
		ui.label(ctx,row,fmt.tprintf("%d/%d  %s",e.workshop_remove+1,room.player.deck.owned_count,selected.name),.Small,p.text,.Center)
		if ui.button(ctx,next,">",true,false,.Small) {e.workshop_remove=(e.workshop_remove+1)%room.player.deck.owned_count}
		ui.cut_top(&box,6)
		if ui.button(ctx,ui.cut_top(&box,34),"Rimuovi la carta selezionata  /  15 crediti",room.player.deck.owned_count>game.MIN_OWNED_CARDS && campaign.backpack_credits(&c.backpack)>=15) {
			if game.expedition_remove_card(&room.player.deck,card.id)==.Removed {campaign.backpack_pay(&c.backpack,15);c.revision+=1}
		}
	}
	ui.cut_top(&box,10)
	ui.paragraph(ctx,box,"I potenziamenti richiedono punti esperienza. Apri PERSONAGGIO fuori dagli scontri per spenderli.",.Small,p.text_dim)
	if ui.button(ctx,footer,"Torna al bioma") || input.key_pressed(frame.devices,.ESCAPE) {e.site=-1}
}

@(private)
expedition_draw :: proc(data:rawptr,frame:^host.Frame) {
	e:=cast(^Expedition_Session)data;rs:=e.rs;room:=&rs.room
	when render.EXPEDITION_BENCHMARK {
		e.draw_timing={};rs.iso_renderer.tactical.draw_timing={}
		if surface:=rs.iso_renderer.tactical.surface;surface!=nil && surface.post!=nil {surface.post.timing={}}
		stamp:=rl.GetTime();now:f64
	}
	if rs.effect_window.open && rs.effect_window.backdrop_ready {
		draw_effect_window_backdrop(&rs.effect_window,frame.canvas.width,frame.canvas.height);draw_effect_window(&rs.effect_window,&rs.iso_renderer,frame.canvas.width,frame.canvas.height)
		when render.EXPEDITION_BENCHMARK {e.draw_timing.effect_ms=(rl.GetTime()-stamp)*1000}
		return
	}
	render.update_tactical_view(&rs.iso_renderer,room,rs.mouse_canvas,false,true)
	when render.EXPEDITION_BENCHMARK {now=rl.GetTime();e.draw_timing.view_ms=(now-stamp)*1000;stamp=now}
	render.draw_tactical_world(&rs.iso_renderer,room,active_targeting_card_id(rs.card_interaction),&e.world)
	when render.EXPEDITION_BENCHMARK {now=rl.GetTime();e.draw_timing.world_ms=(now-stamp)*1000;stamp=now}
	render.draw_status(&rs.iso_renderer,room,rs.window.scale_mode)
	render.draw_tactical_hud(&rs.iso_renderer,room,false,false)
	if room.phase==.Combat {render.draw_hand(&rs.iso_renderer,room,rs.card_interaction.hovered_card_id,rs.card_interaction.selected_card_id,rs.card_interaction.dragged_card_id,rs.mouse_canvas)}
	else {
		rl.DrawRectangleRec({0,440,960,100},{8,10,18,240})
		ui.draw_text(frame.theme,campaign.biome_name(e.world.biome),{26,450},.Title,render.expedition_color(e.world.biome))
		ui.draw_text(frame.theme,"WASD  esplora    M  mount    E  interagisci    Z  zaino    U  personaggio    TAB  ologramma",{27,492},.Small,{191,196,211,255})
		ui.draw_text(frame.theme,fmt.tprintf("LIV %d   XP %d / %d   PUNTI %d   CREDITI %d",e.progress.run.level,e.progress.run.xp,campaign.xp_for_level(e.progress.run.level),e.progress.run.points,campaign.backpack_credits(&e.progress.backpack)),{27,516},.Small,{132,181,211,255})
	}
	if e.message_timer>0 {ui.draw_text_centered(frame.theme,e.message,{480,130 if room.phase==.Combat else 408},.Body,{239,218,160,255})}
	if e.save_failed {ui.draw_text(frame.theme,"SALVATAGGIO NON RIUSCITO / Riprovo al prossimo stato stabile",{22,420},.Small,{255,125,115,255})}
	if e.world.lane_warning {ui.draw_text_centered(frame.theme,world.metadata(e.world.biome).lane,{480,158 if e.message_timer>0 else 132},.Body,{255,126,91,255})}
	when render.EXPEDITION_BENCHMARK {now=rl.GetTime();e.draw_timing.hud_hand_ms=(now-stamp)*1000;stamp=now}
	if e.map_open {draw_expedition_hologram(e,frame)}
	when render.EXPEDITION_BENCHMARK {now=rl.GetTime();e.draw_timing.map_ms=(now-stamp)*1000;stamp=now}
	if rs.effect_window.open {draw_effect_window(&rs.effect_window,&rs.iso_renderer,frame.canvas.width,frame.canvas.height)}
	when render.EXPEDITION_BENCHMARK {e.draw_timing.effect_ms=(rl.GetTime()-stamp)*1000}
}
