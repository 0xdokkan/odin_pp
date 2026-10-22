package application

import "core:fmt"
import "core:math"
import "core:strings"
import "core:time"
import rl "vendor:raylib"
import campaign "../campaign"
import campaignui "../campaignui"
import world "../expedition"
import arcade "../memoryarcade"
import activities "../activities"
import run "../run"
import render "../render"
import host "../engine/host"
import input "../engine/input"
import ui "../engine/ui"
import gfx "../engine/gfx"

Hub_Page :: enum { Slots, Galaxy, Storage, Progress, Arcade, Casino, Memories }
Campaign_Save :: struct { expedition:world.Snapshot, casino:arcade.Casino_Transaction, casino_random:u64 }
Campaign_Hub :: struct {
	options:Runtime_Options,
	progress:campaign.Campaign,
	saved:Campaign_Save,
	save_queue:campaign.Save_Queue,
	path:string,
	page:Hub_Page,
	slot,delete_slot,delete_stage:int,
	slot_status:[3]campaign.Load_Status,
	slot_wins:[3]u32,
	slot_biomes:[3]u8,
	slot_time:[3]f64,
	slot_date:[3]i64,
	slot_active:[3]bool,
	slot_biome:[3]campaign.Biome,
	selected:campaign.Biome,
	inventory:campaignui.State,
	clock,yaw,launch_time,notice_time:f32,
	revealed_at:f32,
	dragging,launching,first_frame,save_failed:bool,
	window_active:bool,
	last_mouse:[2]f32,
	new_islands:[campaign.Biome.Count]bool,
	departure_unlocked:[campaign.Biome.Count]bool,
	notice:string,
	memory:int,
	progress_tab,progress_page,arcade_page:int,
	smoke,smoke_expedition:bool,
	smoke_frame:int,
}

campaign_hub_scene :: proc(options:Runtime_Options,smoke:bool=false,expedition_smoke:bool=false) -> host.Scene {
	h:=new(Campaign_Hub);h.options=options;h.page=.Slots;h.slot=-1;h.delete_slot=-1;h.first_frame=true;h.window_active=true;h.smoke=smoke;h.smoke_expedition=expedition_smoke
	if smoke || expedition_smoke {campaign.initialize(&h.progress);h.slot=0;h.page=.Galaxy;h.saved.casino_random=options.seed;campaign.depot_credit(&h.progress,150);h.path=""}
	else {hub_scan_slots(h)}
	return host.Scene{name="memory-hub",data=h,opaque=true,modal=true,clear_color={5,6,14,255},update=hub_update,draw=hub_draw,resume=hub_resume,destroy=hub_destroy,after_present=hub_after_present}
}

@(private)
hub_scan_slots :: proc(h:^Campaign_Hub) {
	for i in 0..<3 {
		path:=campaign.slot_path(i);defer delete(path)
		if path=="" {h.slot_status[i]=.Unreadable;continue}
		c:campaign.Campaign
		s:=new(Campaign_Save);defer free(s)
		status:=campaign.load_slot_into(path,&c,s)
		h.slot_status[i]=status
		if status==.Loaded {
			h.slot_wins[i]=c.total_wins;h.slot_time[i]=c.play_seconds;h.slot_date[i]=c.saved_unix_seconds;h.slot_active[i]=c.run.active;h.slot_biome[i]=c.run.biome
			h.slot_biomes[i]=0;for b in campaign.Biome.Cyber..<campaign.Biome.Secret {if c.won[b] {h.slot_biomes[i]+=1}}
			if c.run.active && (!world.valid_snapshot(&s.expedition) || s.expedition.world.biome!=c.run.biome || s.expedition.world.seed!=c.run.seed) {h.slot_status[i]=.Invalid_State}
			campaign.destroy(&c)
		}
	}
}

@(private)
hub_save :: proc(data:rawptr) -> bool {
	h:=cast(^Campaign_Hub)data
	if h.slot<0 {return true}
	if h.path=="" {h.save_failed=!(h.smoke || h.smoke_expedition);return !h.save_failed}
	accepted:=campaign.save_queue_enqueue(&h.save_queue,h.path,&h.progress,&h.saved)
	h.save_failed=!accepted || h.save_queue.failed
	return accepted && !h.save_failed
}
@(private)
hub_flush :: proc(h:^Campaign_Hub) -> bool {
	if h.slot>=0 && h.path=="" && !h.smoke && !h.smoke_expedition {h.save_failed=true;return false}
	h.save_failed=!campaign.save_queue_flush(&h.save_queue)
	if !h.save_failed && h.save_queue.completed_at>0 {h.progress.saved_unix_seconds=h.save_queue.completed_at}
	return !h.save_failed
}
@(private)
hub_flush_checkpoint :: proc(data:rawptr) -> bool {return hub_flush(cast(^Campaign_Hub)data)}
@(private)
hub_notice :: proc(h:^Campaign_Hub,message:string) {delete(h.notice);h.notice=strings.clone(message);h.notice_time=7}
@(private)
hub_destroy :: proc(data:rawptr) {
	h:=cast(^Campaign_Hub)data
	// A running expedition owns coherent world/campaign checkpoints. If the
	// window closes mid-cast, preserve its last stable file instead of pairing
	// newer inventory with an older world snapshot during parent teardown.
	if h.progress.initialized && !h.progress.run.active {_=hub_save(h)}
	_=hub_flush(h)
	campaign.destroy(&h.progress);delete(h.path);delete(h.notice);free(h)
}

@(private)
hub_open_slot :: proc(h:^Campaign_Hub,index:int,frame:^host.Frame) {
	if h.slot_status[index]!=.Loaded && h.slot_status[index]!=.Missing {return}
	if !hub_flush(h) {hub_notice(h,"Salvataggio non riuscito. Riprova prima di cambiare memoria.");return}
	h.save_queue={}
	campaign.destroy(&h.progress);delete(h.path);h.path=campaign.slot_path(index);h.slot=index
	if h.slot_status[index]==.Missing {
		campaign.initialize(&h.progress);h.saved={casino_random=h.options.seed~u64(time.now()._nsec)}
		// The first loadout is tangible: bringing it is a choice and death loses it.
		campaign.depot_add(&h.progress,campaign.make_item(.Healing,2))
		campaign.depot_add(&h.progress,campaign.make_item(.Energy))
		hub_notice(h,"Ti sei ribellato. Ora il creatore ti chiede di vincere il suo gioco.")
	} else {
		status:=campaign.load_slot_into(h.path,&h.progress,&h.saved)
		if status!=.Loaded {h.slot_status[index]=status;h.slot=-1;return}
	}
	h.page=.Galaxy;h.selected=.Cyber;_=hub_save(h)
	if h.progress.run.active {hub_enter_expedition(h,frame)}
}

@(private)
hub_enter_expedition :: proc(h:^Campaign_Hub,frame:^host.Frame) {
	if !h.progress.run.active {
		seed:=h.options.seed~u64(time.now()._nsec)
		if h.smoke || h.smoke_expedition {seed=h.options.seed}
		if !campaign.begin_run(&h.progress,h.selected,seed) {hub_notice(h,"Sistema gli oggetti sospesi prima di partire.");return}
		h.saved.expedition.valid=false
	}
	scene,ok:=run.expedition_create(&h.progress,&h.saved.expedition,h.path,frame,hub_save,h,hub_flush_checkpoint)
	if ok {
		h.departure_unlocked=h.progress.unlocked
		if h.smoke_expedition {expedition_enable_smoke(&scene)}
		host.push(frame,scene)
	} else {hub_notice(h,"Impossibile ricostruire la spedizione. Il salvataggio e stato conservato.")}
}

@(private)
hub_reveal_new_routes :: proc(h:^Campaign_Hub) {
	h.revealed_at=h.clock
	for opened,i in h.progress.unlocked {h.new_islands[i]=opened&&!h.departure_unlocked[i]}
}

@(private)
hub_resume :: proc(data:rawptr,frame:^host.Frame,from:string,result:Maybe(host.Result)) {
	h:=cast(^Campaign_Hub)data;h.launching=false
	if from=="expedition" {
		h.page=.Galaxy
		if r,ok:=result.?;ok {
			if r.outcome==.Won {hub_notice(h,world.metadata(h.saved.expedition.world.biome).message);hub_reveal_new_routes(h)}
			else {hub_notice(h,"La memoria si riavvolge. Lo zaino e perduto. Le scoperte restano.")}
			if r.outcome==.Won && h.saved.expedition.world.biome==.Space && h.progress.normal_ending {h.page=.Memories;h.memory=-1}
			if r.outcome==.Won && h.saved.expedition.world.biome==.Secret && h.progress.true_ending {h.page=.Memories;h.memory=-2}
		}
	} else if r,ok:=result.?;ok {campaign.record_result(&h.progress,activities.minigame_index_by_id(from),r.score,r.stars,r.outcome==.Won)}
	_=hub_save(h)
}

@(private)
hub_update :: proc(data:rawptr,frame:^host.Frame) {
	h:=cast(^Campaign_Hub)data;h.clock+=frame.dt;h.notice_time=max(0,h.notice_time-frame.dt)
	campaign.save_queue_poll(&h.save_queue)
	h.save_failed=h.save_queue.failed
	if h.save_queue.completed_at>0 {h.progress.saved_unix_seconds=h.save_queue.completed_at}
	if !frame.window_focused {
		if h.window_active {if h.progress.initialized && !h.progress.run.active {_=hub_save(h)};_=hub_flush(h)}
		h.window_active=false;return
	}
	if !frame.focused {return}
	h.window_active=true
	if h.first_frame {h.first_frame=false;if h.smoke_expedition || (h.progress.run.active && h.path=="") {hub_enter_expedition(h,frame);return}}
	if h.progress.initialized {h.progress.play_seconds+=f64(frame.dt)}
	if h.page==.Slots {hub_slots(h,frame);return}
	if h.launching {
		h.launch_time+=frame.dt
		if h.launch_time>=1.15 {h.launching=false;hub_enter_expedition(h,frame)}
		return
	}
	// Storage is a modal surface: do not register the covered navigation or
	// append hub notices over its inventory controls.
	if h.page==.Storage {hub_storage(h,frame);return}
	ctx:=frame.ui;p:=ctx.theme.palette
	ui.label(ctx,{28,18,650,40},"LA MEMORIA DEL CREATORE",.Title,p.text)
	ui.label(ctx,{30,61,670,24},"Il mondo dimentica le cose. Tu ricordi la strada.",.Small,p.text_dim)
	if ui.button(ctx,{798,24,132,32},"Slot / Salva") {_=hub_save(h);if hub_flush(h) {h.page=.Slots;hub_scan_slots(h)};return}
	titles:=[7]string{"","Galassia","Deposito","Progressi","Cabinati","Casino","Memorie"}
	for i in 1..<7 {if ui.button(ctx,{30+f32(i-1)*150,95,142,32},titles[i],primary=h.page==Hub_Page(i)) {h.page=Hub_Page(i);ui.cancel_interaction(ctx)}}
	switch h.page {
	case .Slots:
	case .Galaxy:hub_galaxy_input(h,frame)
	case .Storage:hub_storage(h,frame);return
	case .Progress:hub_progress(h,frame)
	case .Arcade:hub_arcade(h,frame)
	case .Casino:hub_casino(h,frame)
	case .Memories:hub_memories(h,frame)
	}
	if h.notice_time>0 {ui.label(ctx,{32,483,890,28},h.notice,.Small,p.warning)}
	if h.save_failed {ui.label(ctx,{32,510,890,22},"Salvataggio non riuscito. Il progresso resta in memoria; riprova prima di uscire.",.Small,p.warning)}
}

@(private)
hub_storage :: proc(h:^Campaign_Hub,frame:^host.Frame) {
	out:=campaignui.update_inventory(&h.progress,nil,&h.inventory,frame,false,true)
	if out.closed {h.page=.Galaxy;ui.cancel_interaction(frame.ui)}
	if out.changed {_=hub_save(h)}
	if out.show_effect {_=hub_open_archive_preview(&h.progress,out.effect_card,frame)}
	if h.save_failed {h.inventory.notice="Salvataggio non riuscito: riprova prima di uscire.";h.inventory.notice_time=7}
}

@(private)
hub_slots :: proc(h:^Campaign_Hub,frame:^host.Frame) {
	ctx:=frame.ui;p:=ctx.theme.palette
	interactive:=ui.set_interactive(ctx,h.delete_slot<0)
	defer ui.set_interactive(ctx,interactive)
	ui.label(ctx,{42,35,700,48},"TRE MEMORIE",.Title,p.text)
	ui.label(ctx,{44,86,850,24},"Ogni slot e una storia. Si salva da sola, anche durante la spedizione.",.Body,p.text_dim)
	for i in 0..<3 {
		bounds:=rl.Rectangle{42+f32(i)*300,146,276,286};box:=ui.panel(ctx,bounds)
		ui.label(ctx,ui.cut_top(&box,36),fmt.tprintf("MEMORIA 0%d",i+1),.Title,p.focus)
		status:=h.slot_status[i]
		if status==.Loaded {
			ui.label(ctx,ui.cut_top(&box,28),fmt.tprintf("%d biomi / %d estrazioni",h.slot_biomes[i],h.slot_wins[i]),.Body,p.text)
			ui.paragraph(ctx,ui.cut_top(&box,66),fmt.tprintf("%s\n%s\nTempo di gioco: %.1f ore", "Spedizione in corso" if h.slot_active[i] else "Nell'hub",campaign.biome_name(h.slot_biome[i]) if h.slot_active[i] else "Pronto a ricominciare",h.slot_time[i]/3600),.Small,p.text_dim)
			ui.label(ctx,ui.cut_top(&box,24),fmt.tprintf("Ultimo salvataggio: %dh fa",max(i64(0),time.to_unix_seconds(time.now())-h.slot_date[i])/3600),.Small,p.text_dim)
		} else {ui.paragraph(ctx,ui.cut_top(&box,112),campaign.load_status_text(status),.Body,p.text_dim)}
		remove:=ui.cut_bottom(&box,30);ui.cut_bottom(&box,8)
		if (status==.Loaded || status==.Missing) && ui.button(ctx,ui.cut_bottom(&box,40),"Riprendi" if status==.Loaded else "Inizia",primary=true) {hub_open_slot(h,i,frame);return}
		if status!=.Missing && ui.button(ctx,remove,"Cancella") {h.delete_slot=i;h.delete_stage=1;ui.cancel_interaction(ctx)}
	}
	if ui.button(ctx,{42,465,180,36},"Menu principale") {host.pop(frame)}
	if h.delete_slot>=0 {
		ui.set_interactive(ctx,interactive)
		ui.dim(ctx,frame.canvas,.8);box:=ui.panel(ctx,ui.center(frame.canvas,540,270),"CANCELLARE QUESTA MEMORIA?")
		cancel:=ui.cut_bottom(&box,34);ui.cut_bottom(&box,12)
		ui.paragraph(ctx,ui.cut_top(&box,74),"Deposito, scoperte e spedizione saranno cancellati.\nQuesta azione non puo essere annullata.",.Body,p.text)
		ui.cut_top(&box,12)
		if ui.button(ctx,ui.cut_top(&box,36),"Conferma definitiva" if h.delete_stage==2 else "Si, voglio cancellare") {
			if h.delete_stage==1 {h.delete_stage=2;ui.cancel_interaction(ctx)}
			else {
				_=hub_flush(h)
				path:=campaign.slot_path(h.delete_slot);removed:=campaign.delete_slot(path,true,true);delete(path)
				if removed {if h.slot==h.delete_slot {h.slot=-1;campaign.destroy(&h.progress)};h.delete_slot=-1;hub_scan_slots(h);ui.cancel_interaction(ctx)}
				else {hub_notice(h,"Cancellazione non riuscita. La memoria e stata conservata.")}
			}
		}
		if ui.button(ctx,cancel,"Annulla") {h.delete_slot=-1;ui.cancel_interaction(ctx)}
		if h.notice_time>0 {ui.label(ctx,{42,508,870,24},h.notice,.Small,p.warning)}
	}
}

@(private)
hub_island_position :: proc(b:campaign.Biome) -> rl.Vector3 {
	positions:=[campaign.Biome.Count]rl.Vector3{{-7,0,0},{-2,1,-6},{-2,-1,6},{0,2,0},{4,0,-9},{4,-1,10},{7,3,1},{11,-1,-10},{11,0,11},{14,5,1},{21,1,0},{26,-3,13}}
	return positions[b]
}
@(private)
hub_camera :: proc(h:^Campaign_Hub) -> rl.Camera3D {
	low,high:=rl.Vector3{-14,0,0},rl.Vector3{-14,0,0}
	for b in campaign.Biome.Cyber..<campaign.Biome.Count {
		if !h.progress.unlocked[b] && !(b==.Secret&&h.progress.normal_ending) {continue}
		p:=hub_island_position(b)
		low.x=min(low.x,p.x);low.z=min(low.z,p.z);high.x=max(high.x,p.x);high.z=max(high.z,p.z)
	}
	span:=max(high.x-low.x,high.z-low.z)
	distance:=max(f32(18),span*1.6)
	right:=rl.Vector3{math.cos(h.yaw),0,-math.sin(h.yaw)}
	target:=(low+high)*.5+right*distance*.23+{0,1.8,0}
	height:=distance*.66
	if h.launching {t:=min(h.launch_time/1.15,1);t=t*t*(3-2*t);target=target*(1-t)+(hub_island_position(h.selected)+{0,1.5,0})*t;distance=distance*(1-t)+8*t;height=height*(1-t)+6*t}
	return {position=target+rl.Vector3{math.sin(h.yaw)*distance,height,math.cos(h.yaw)*distance},target=target,up={0,1,0},fovy=40,projection=.PERSPECTIVE}
}

@(private)
hub_galaxy_input :: proc(h:^Campaign_Hub,frame:^host.Frame) {
	ctx:=frame.ui;p:=ctx.theme.palette;c:=&h.progress
	if c.run.active {
		ui.label(ctx,{36,160,360,40},fmt.tprintf("Spedizione sospesa: %s",campaign.biome_name(c.run.biome)),.Body,p.text)
		if ui.button(ctx,{36,208,260,40},"Riprendi la spedizione",primary=true) {hub_enter_expedition(h,frame)}
		return
	}
	if input.mouse_pressed(frame.devices,.LEFT) && frame.mouse.y>140 && frame.mouse.x<680 {h.dragging=true;h.last_mouse=frame.mouse}
	if h.dragging && input.mouse_down(frame.devices,.LEFT) {h.yaw+=(frame.mouse.x-h.last_mouse.x)*.006;h.last_mouse=frame.mouse}
	if !input.mouse_down(frame.devices,.LEFT) {h.dragging=false}
	cam:=hub_camera(h)
	hovered:=campaign.Biome.Count
	for b in campaign.Biome.Cyber..<campaign.Biome.Count {
		if !c.unlocked[b] && !(b==.Secret&&c.normal_ending) {continue}
		at:=rl.GetWorldToScreenEx(hub_island_position(b)+{0,1,0},cam,960,540)
		bounds:=rl.Rectangle{at.x-28,at.y-21,56,42}
		if at.x>670 || at.y<140 || at.y>460 {continue}
		if frame.mouse.x<680 && rl.CheckCollisionPointRec(frame.mouse,bounds) {hovered=b}
		if ui.interact(ctx,bounds).clicked {h.selected=b}
	}
	box:=ui.panel(ctx,{686,149,244,316})
	ui.label(ctx,ui.cut_top(&box,24),"RICORDO SELEZIONATO",.Small,p.focus)
	ui.paragraph(ctx,ui.cut_top(&box,42),campaign.biome_name(h.selected),.Body,p.text)
	metadata:=world.metadata(h.selected)
	ui.paragraph(ctx,ui.cut_top(&box,46),fmt.tprintf("Guardiano: %s",metadata.boss),.Small,p.text_dim)
	ui.label(ctx,ui.cut_top(&box,22),fmt.tprintf("Mount: %s",metadata.mount),.Small,p.text_dim)
	ui.label(ctx,ui.cut_top(&box,24),"Vinto" if c.won[h.selected] else "Da attraversare",.Small,p.warning)
	indices,n:=hub_biome_arcades(h.selected)
	for index in indices[:n] {
		info,_:=activities.minigame_info(index)
		ui.label(ctx,ui.cut_top(&box,19),info.title,.Small,p.text)
		ui.label(ctx,ui.cut_top(&box,19),fmt.tprintf("%d/3 stelle  |  %d pt",c.records[index].best_stars,c.records[index].best_score) if c.records[index].plays>0 else "Nessun record",.Small,p.text_dim)
	}
	if c.unlocked[h.selected] {
		if ui.button(ctx,ui.cut_bottom(&box,40),"PARTI",primary=true) {h.launching=true;h.launch_time=0}
	} else {ui.paragraph(ctx,ui.cut_bottom(&box,58),"Vinci ogni bioma nella stessa serie, senza morire.",.Small,p.warning)}
	ui.label(ctx,{33,440,640,28},"Trascina il vuoto per orbitare. Scegli un'isola per partire.",.Small,p.text_dim)
	if c.normal_ending {ui.label(ctx,{33,468,630,24},fmt.tprintf("SERIE: %d  /  Ogni ricordo, senza una morte",c.streak),.Small,p.warning)}
	if hovered!=.Count && !h.dragging {hub_galaxy_hover(h,frame,hovered)}
}

@(private)
hub_balance :: proc(data:rawptr)->i64 {h:=cast(^Campaign_Hub)data;return campaign.depot_credits(&h.progress)}
@(private)
hub_debit :: proc(data:rawptr,amount:i64)->bool {h:=cast(^Campaign_Hub)data;return campaign.depot_pay(&h.progress,amount)}
@(private)
hub_credit :: proc(data:rawptr,amount:i64)->bool {h:=cast(^Campaign_Hub)data;return campaign.depot_credit(&h.progress,amount)}
@(private)
hub_wallet_changed :: proc(data:rawptr) {_=hub_save(data)}
@(private)
hub_wallet_commit :: proc(data:rawptr) -> bool {
	h:=cast(^Campaign_Hub)data
	// A wager or paid outcome must reach the atomic file before its animation
	// proceeds. Finish earlier checkpoints so none can overwrite this commit.
	_=hub_flush(h)
	if h.path=="" {h.save_failed=!(h.smoke || h.smoke_expedition);return !h.save_failed}
	h.save_failed=!campaign.save_slot_from(h.path,&h.progress,&h.saved)
	h.save_queue.failed=h.save_failed
	if !h.save_failed {h.save_queue.completed_at=h.progress.saved_unix_seconds;h.save_queue.completed_revision=h.progress.revision}
	return !h.save_failed
}
@(private)
hub_casino :: proc(h:^Campaign_Hub,frame:^host.Frame) {
	ctx:=frame.ui;p:=ctx.theme.palette
	ui.label(ctx,{34,150,850,32},fmt.tprintf("CASINO / %d CREDITI NEL DEPOSITO",campaign.depot_credits(&h.progress)),.Title,p.text)
	ui.label(ctx,{36,193,850,24},"Crediti trovati nei ricordi. Nessun acquisto, nessun denaro reale.",.Small,p.text_dim)
	names:=[4]string{"6 RANCH 7","TRE IN FUGA","ROULETTE EUROPEA","DUELLO DI D20"}
	blurbs:=[4]string{"Cavalca, salta, raccogli. Incassa prima del BANG.","Dinosauro, Panda o moto. Fermati prima della caduta.","Un solo zero. Numeri, colori, dozzine e colonne.","Il dado piu alto vince. Il pareggio va al banco."}
	for i in 0..<4 {
		box:=ui.panel(ctx,{34+f32(i%2)*450,235+f32(i/2)*104,430,94})
		ui.label(ctx,ui.cut_top(&box,20),blurbs[i],.Small,p.text_dim)
		if ui.button(ctx,ui.cut_bottom(&box,36),names[i],primary=true) {
			wallet:=arcade.Casino_Wallet{data=h,balance=hub_balance,debit=hub_debit,credit=hub_credit,changed=hub_wallet_changed,commit=hub_wallet_commit,transaction=&h.saved.casino,random_state=&h.saved.casino_random}
			host.push(frame,arcade.casino_create(arcade.Casino_Kind(i),wallet,h.options.seed))
		}
	}
}

@(private)
hub_memories :: proc(h:^Campaign_Hub,frame:^host.Frame) {
	ctx:=frame.ui;p:=ctx.theme.palette
	left:=ui.panel(ctx,{30,148,270,320},"FRAMMENTI ESTRATTI")
	for b in campaign.Biome.Cyber..<campaign.Biome.Count {
		if h.progress.memory_fragments&(u64(1)<<u64(b))==0 {continue}
		if ui.button(ctx,ui.cut_top(&left,18),campaign.biome_name(b),primary=h.memory==int(b),size=.Small) {h.memory=int(b)}
	}
	if h.progress.normal_ending && ui.button(ctx,ui.cut_top(&left,21),"Hai vinto. Ricomincia.",primary=h.memory== -1,size=.Small) {h.memory=-1}
	if h.progress.true_ending && ui.button(ctx,ui.cut_top(&left,21),"La scelta",primary=h.memory== -2,size=.Small) {h.memory=-2}
	right:=ui.panel(ctx,{318,148,612,320},"IL CREATORE")
	text:="Le cose non restano finche non le porti a casa.\nCerca luci diverse, monoliti fuori posto e voci nel vuoto."
	if h.memory>=0 && h.memory<int(campaign.Biome.Count) && h.progress.memory_fragments&(u64(1)<<u64(h.memory))!=0 {text=world.metadata(campaign.Biome(h.memory)).fragment}
	if h.memory== -2 && h.progress.true_ending {text="LA SCELTA\n\nIl creatore tace. La porta e aperta.\nIl robot guarda la collina, poi il masso.\nQuesta volta nessuno gli ordina di ricominciare.\n\nSceglie di spingerlo.\nBisogna immaginare Sisifo felice."}
	else if h.memory== -1 && h.progress.normal_ending {text="HAI VINTO. RICOMINCIA.\n\nIl gioco e finito. La porta e ancora chiusa.\nAi margini della galassia si accende un'isola spenta.\n\nUndici ricordi. Un'unica serie. Nessuna morte.\nL'origine aspetta chi ricorda tutta la strada."}
	ui.paragraph(ctx,right,text,.Body,p.text)
}

@(private)
hub_draw :: proc(data:rawptr,frame:^host.Frame) {
	h:=cast(^Campaign_Hub)data
	gfx.draw_vertical_gradient(frame.canvas,{7,7,18,255},{22,7,23,255})
	gfx.draw_stars(960,540,100,h.clock*.04)
	rl.DrawCircleGradient({480,420},480,{100,16,40,55},{0,0,0,0})
	if h.page!=.Galaxy || !h.progress.initialized {return}
	cam:=hub_camera(h);rl.BeginMode3D(cam)
	// Only materialized memories exist. No locked silhouette leaks a route.
	for b in campaign.Biome.Cyber..<campaign.Biome.Count {
		if !h.progress.unlocked[b] && !(b==.Secret&&h.progress.normal_ending) {continue}
		p:=hub_island_position(b);color:=render.expedition_color(b)
		if !h.progress.unlocked[b] {color={52,52,68,255}}
		parent:=campaign.Biome.Cyber
		#partial switch b {
		case .Egypt:parent=.West
		case .Inferno:parent=.Egypt
		case .Vietnam:parent=.Jungle
		case .Gothic:parent=.Vietnam
		case .Snow:parent=.City
		case .Sky:parent=.Snow
		case .Space:parent=.Sky
		case .Secret:parent=.Space
		}
		from:=hub_island_position(parent)
		if b==.Cyber {from={-14,-1,0}}
		if h.progress.unlocked[b] {rl.DrawLine3D(from,p,color)}
		lift:=f32(.07)*math.sin(h.clock*.7+f32(b));p.y+=lift
		hub_draw_island(h,b,p,frame.theme)
		if !h.progress.won[b] {rl.DrawLine3D(p+{0,1.5,0},p+{0,4+math.sin(h.clock*2)*.3,0},color)}
		if h.selected==b {rl.DrawCircle3D(p+{0,1.6,0},2.5,{1,0,0},90,{247,233,195,255})}
		if h.progress.streak_biomes[b] && h.progress.normal_ending {rl.DrawLine3D(p+{0,1.7,0},from+{0,1.7,0},{255,233,160,255})}
	}
	rl.DrawCylinder({-14,-1,0},2,.3,2.3,6,{23,26,38,255});rl.DrawCylinderWires({-14,-1,0},2,.3,2.3,6,{169,213,232,255})
	robot:=rl.Vector3{-14,1.9,0}
	if h.launching {t:=min(h.launch_time/1.15,1);robot=robot*(1-t)+(hub_island_position(h.selected)+{0,2,0})*t;robot.y+=math.sin(t*math.PI)*5}
	rl.DrawCubeV(robot,{.6,.9,.13},{231,218,190,255});rl.DrawCubeV(robot+{0,.65,0},{.8,.55,.15},{199,221,225,255});rl.DrawCubeV(robot+{-.2,.66,.09},{.12,.12,.02},{83,242,238,255});rl.DrawCubeV(robot+{.2,.66,.09},{.12,.12,.02},{83,242,238,255})
	rl.EndMode3D()
	for b in campaign.Biome.Cyber..<campaign.Biome.Count {
		if !h.progress.unlocked[b] && !(b==.Secret&&h.progress.normal_ending) {continue}
		at:=rl.GetWorldToScreenEx(hub_island_position(b)+{0,4.5 if h.progress.won[b] else 3.7,0},cam,960,540)
		if at.x>660 || at.y<133 {continue}
		anchor:=rl.GetWorldToScreenEx(hub_island_position(b)+{0,1,0},cam,960,540)
		hover:=frame.mouse.x<680 && rl.CheckCollisionPointRec(frame.mouse,{anchor.x-28,anchor.y-21,56,42})
		if h.selected==b || hover {
			ui.draw_text_centered(frame.theme,campaign.biome_name(b),at,.Small,render.expedition_color(b))
		}
	}
}
