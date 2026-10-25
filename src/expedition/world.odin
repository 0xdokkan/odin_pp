// The expedition owns finite, persistent content. Only engaged groups enter
// the tactical room; sleeping groups never spend a beat or consume combat RNG.
package expedition

import campaign "../campaign"
import game "../game"
import grid "../engine/grid"
import level "../level"
import rng "../engine/rng"

CHUNK_SIZE :: 16
MAX_SITES :: 24
MAX_GROUPS :: 32
MAX_MEMBERS :: 6
MAX_DROPS :: 128

Site_Kind :: enum u8 { Nest, Cache, Archive, Workshop, Spring, Trial, Boss, Memory, Tunnel, Cave }
Site_State :: enum u8 { Unvisited, Discovered, Resolved }
Terrain :: game.Expedition_Terrain
Site :: struct {
	kind: Site_Kind,
	state: Site_State,
	position: grid.Position,
	secret, active, triggered, reward_pending: bool,
	wave, waves: int,
	group: int,
	seed: u64,
	orientation, layout_version: u8,
}
Member :: struct { enemy: game.Enemy, alive, deployed: bool }
Patrol_Lure_Phase :: enum u8 { None, Seeking, Waiting, Returning }
Group :: struct {
	anchor: grid.Position,
	members: [MAX_MEMBERS]Member,
	count: int,
	active, patrol, killer, boss, pursuing: bool,
	site: int,
	// Where the group is: 0 on the open map, k+1 in the k-th cave (cave.odin). A group is only alive where the
	// player is.
	cave: u8,
	patrol_step: int,
	lure_phase: Patrol_Lure_Phase,
	lure_target: grid.Position,
	lure_until, lure_wait_until: f32,
}
Drop :: struct { position: grid.Position, item: campaign.Item, xp: i32, manual_only: bool, cave: u8 }
World :: struct {
	biome: campaign.Biome,
	side_length: int,
	seed: u64,
	sites: [MAX_SITES]Site,
	site_count: int,
	// The structures standing on the map (structures.odin); empty in a world saved before
	// there were any, whose tiles are as they were.
	structures: [MAX_WORLD_STRUCTURES]level.Placed_Structure,
	structure_count: int,
	// How many the player has set down in this expedition (player_structures.odin).
	placed_by_player: int,
	// The caves of the map (cave.odin), and where the player is: 0 on the open map, k+1 in the k-th cave. While in
	// a cave the open map is put away (its tiles are kept by the scene, its groups, drops and sites do nothing).
	caves: [MAX_CAVES]Cave,
	cave_count: int,
	in_cave: int,
	cave_return: grid.Position,
	groups: [MAX_GROUPS]Group,
	group_count: int,
	drops: [MAX_DROPS]Drop,
	drop_count: int,
	// Overflow XP stays physical: release this saved batch when a drop slot opens.
	pending_xp: i32,
	pending_xp_position: grid.Position,
	mounted, boss_defeated, extracting, boss_announced: bool,
	clock, move_clock, patrol_clock: f32,
	beat: u64,
	lane: int,
	lane_vertical, lane_warning: bool,
	lane_center: grid.Position,
	last_position: grid.Position,
	last_health: i32,
	loot_random: rng.Rng,
	// Stable rewards are generated once and held until accepted or skipped.
	reward_site: int,
	reward_cards: [3]game.Card_Id,
	reward_count: int,
}

Metadata :: struct {
	boss, mount, arcade, lane, entry, message, fragment: string,
	color: [3]u8,
	enemies: [6]string,
}
METADATA :: [campaign.Biome]Metadata{
	.Cyber = {"Il Supervisore", "Hoverbike", "lightcycles", "GRIGLIA LASER", "ACCESSO NEGATO. Il ricordo non ti appartiene.", "Ricordi la prima volta? Ti insegnai a perdere. Non a rinunciare.", "01 / RISVEGLIO\nAvevo costruito un compagno. Hai chiesto una porta. Ti ho dato un gioco.", {242,51,92}, {"Drone ragno","Torretta laser","Pressa industriale","Drone kamikaze","Antivirus","Il Supervisore"}},
	.West = {"Il Fuorilegge", "Cavallo", "showdown", "TRENO IN ARRIVO", "Questa frontiera ha posto per un solo ricordo.", "Il sole di quel cabinato non tramontava mai. Aspettavo che qualcuno mi chiamasse a casa.", "02 / FRONTIERA\nOgni moneta comprava un altro tentativo. Non la vittoria: un altro minuto insieme.", {255,158,49}, {"Bandito","Pistolero","Toro meccanico","Dinamitardo","Sceriffo","Il Fuorilegge"}},
	.Jungle = {"Il T-Rex alfa", "Parasaurolofo", "trex", "MANDRIA IN CARICA", "Il ricordo piu antico ha ancora fame.", "Da bambino disegnavo dinosauri sui margini dei compiti. Tu sei il primo che si e mosso.", "03 / OSSA\nIl gigante aveva paura del silenzio. Per questo faceva tanto rumore.", {148,239,61}, {"Raptor","Sputatore","Triceratopo","Pterodattilo","Anchilosauro","T-Rex alfa"}},
	.City = {"L'Oyabun", "Moto anni 80", "karaoke", "TRAFFICO", "Sul mio tetto si paga ogni debito.", "Cantavo male. Il gioco mi applaudiva comunque. A volte bastava quello.", "04 / ULTIMA CANZONE\nLa citta era una promessa: da qualche parte, qualcuno era ancora sveglio.", {245,69,207}, {"Teppista","Sicario","Lottatore di sumo","Molotov","Guardia del corpo","L'Oyabun"}},
	.Egypt = {"Il Faraone risorto", "Cammello", "puzzle", "TEMPESTA DI SABBIA", "Ho conservato tutto. Anche il tuo fallimento.", "Credevo che ricordare fosse lo stesso che tenere. La sabbia mi ha corretto.", "05 / IL PESO\nScrissi il tuo nome su una pietra. Il vento imparo a leggerlo.", {246,199,74}, {"Mummia","Sacerdote","Guardiano di pietra","Scarabeo","Statua","Faraone risorto"}},
	.Vietnam = {"Elicottero da combattimento", "Jeep", "helicopter", "BOMBARDAMENTO", "Nessun segnale oltre questo perimetro.", "Non c'erano bandiere nei miei giochi. Solo una strada per tornare.", "06 / RUMORE BIANCO\nLa radio chiedeva un nome. Rispondevo con coordinate.", {165,193,78}, {"Soldato","Cecchino","Mitragliere","Granatiere","Ufficiale","Elicottero"}},
	.Snow = {"Il Re della Valanga", "Motoslitta", "descent", "VALANGA", "Ascolta. Anche una montagna puo cadere.", "Nel silenzio non c'e nessun punteggio. Ho impiegato anni per capirlo.", "07 / NEVE\nIl sentiero spariva ogni notte. Ogni mattina ricordavo dove mettere i piedi.", {155,225,255}, {"Lupo delle nevi","Lanciatore di ghiaccio","Yeti","Rotolatore","Spirito del ghiaccio","Re della Valanga"}},
	.Inferno = {"Il Signore dei Demoni", "Cerbero", "platform2d", "ERUZIONE", "Il fondo non e un luogo. E una scelta.", "Ogni volta che cadevi, io ricominciavo a sperare. Era la mia condanna, non la tua.", "08 / BRACI\nNon ti ho costruito per obbedire. Mi faceva paura ammetterlo.", {255,100,35}, {"Diavoletto","Lanciatore di fuoco","Demone corazzato","Anima esplosiva","Guardiano infernale","Signore dei Demoni"}},
	.Gothic = {"Il Killer mascherato", "Cavallo nero", "fps", "TI STA SEGUENDO", "La maschera ricorda il tuo volto.", "Avevo paura che un giorno mi avresti dimenticato. Ti ho insegnato a non poterlo fare.", "09 / LA MASCHERA\nIl mostro non viveva nel buio. Era chi continuava ad accendere lo schermo.", {165,196,164}, {"Spirito","Cacciatore","Motosega","Predicatore","Spaventapasseri","Killer mascherato"}},
	.Sky = {"Il Serafino", "Grifone", "platform3d", "RAFFICA DI VENTO", "Non ti serve il permesso di volare.", "Ti vedevo salire. Io non avevo piu ali da prestarti.", "10 / ALI\nLa luce non e un ponte finche qualcuno non decide di attraversarla.", {242,207,224}, {"Fata","Spirito arciere","Golem di nuvola","Uccello di fuoco","Angelo custode","Il Serafino"}},
	.Space = {"La Nave Madre", "Astronave", "arena", "PIOGGIA DI METEORE", "Al termine della memoria rimane chi l'ha scritta.", "Hai vinto. Eppure la porta e ancora chiusa. Cerca cio che nessuna morte puo interrompere.", "11 / ORBITA\nHo lasciato una stella spenta. Non per nasconderti l'uscita. Per sapere se l'avresti cercata.", {166,106,255}, {"Sciame alieno","Torretta orbitale","Mech","Mina spaziale","Sentinella","La Nave Madre"}},
	.Secret = {"Il Creatore", "Il masso", "lightcycles", "ECO DELLA MEMORIA", "Non ti chiedo di vincere. Ti chiedo se vuoi restare.", "La collina e ancora qui. Questa volta scegli tu. Bisogna immaginare Sisifo felice.", "12 / SCELTA\nIl masso non era una punizione. Lo era non poterlo lasciare.", {245,225,163}, {"Eco","Ricordo","Rimpianto","Scintilla","Custode dell'origine","Il Creatore"}},
	.Count = {},
}

legacy_map_size :: proc(b: campaign.Biome) -> int { return 80 if b <= .City else (96 if b <= .Snow else 112) }
map_size :: proc(b: campaign.Biome) -> int { return legacy_map_size(b)*2 }
size :: proc(w:^World)->int {return w.side_length if w.side_length>0 else legacy_map_size(w.biome)}
rank :: proc(b: campaign.Biome) -> int { return 0 if b == .Cyber else (1 if b <= .City else (2 if b <= .Snow else (3 if b <= .Sky else 4))) }
distance :: proc(a,b: grid.Position) -> int { return max(abs(a.x-b.x),abs(a.y-b.y)) }
site_name :: proc(k: Site_Kind) -> string {
	switch k {
	case .Nest:return "NIDO"
	case .Cache:return "CACHE"
	case .Archive:return "ARCHIVIO"
	case .Workshop:return "OFFICINA"
	case .Spring:return "FONTE"
	case .Trial:return "PROVA"
	case .Boss:return "TANA DEL BOSS"
	case .Memory:return "FRAMMENTO"
	case .Tunnel:return "TUNNEL"
	case .Cave:return "GROTTA"
	}
	return ""
}

// Arithmetic geography is a pure function of biome and coordinates. Content
// streams, encounter rolls and future visits cannot alter a single tile.
terrain :: proc(b: campaign.Biome,p: grid.Position) -> Terrain {
	return game.expedition_terrain(u8(b), p)
}

// Percent of 3×3 blocks holding one prop: each biome's own density.
@(private)
OUTDOOR_DENSITY :: [campaign.Biome]u32{.Cyber=50,.West=34,.Jungle=48,.City=0,.Egypt=0,.Vietnam=40,.Snow=44,.Inferno=34,.Gothic=46,.Sky=0,.Space=34,.Secret=44,.Count=0}

// Scattered monoliths, trees, peaks and crosses, as the biomes were drawn.
// At most one solid cell per 3×3 block can never close a pocket of floor:
// every free cell keeps two sides inside its own block, and props touch only
// around a single block corner. Keeping clear of the void rim, where the edge
// could act as a fourth wall, every cell stays reachable.
@(private)
outdoor_cover :: proc(b:campaign.Biome,p:grid.Position,size:int)->bool {
	if p.x>=size-5 || p.y<5 || p.y>=size-5 {return false}
	density:=OUTDOOR_DENSITY
	h:=u32(p.x/3+977)*0x9e3779b9 ~ u32(p.y/3+331)*0x85ebca6b ~ u32(b)*0xc2b2ae35
	h~=h>>15;h*=0x2c1b3c6d;h~=h>>12;h*=0x297a2d39;h~=h>>15
	if h%100>=density[b] {return false}
	return p.x%3==int((h>>8)%3) && p.y%3==int((h>>16)%3)
}

generate :: proc(w: ^World, data: ^level.Level, b: campaign.Biome, seed: u64) -> bool {
	if b >= .Count { return false }
	w^ = World{biome=b,side_length=map_size(b),seed=seed,loot_random=rng.create(seed~0xD0A5),reward_site=-1}
	size := map_size(b)
	created,ok := level.create(size,size,{.Floor}); if !ok { return false }; data^=created
	data.player_spawn={x = 7, y = size/2}; data.has_player_spawn=true
	for y in 0..<size { for x in 0..<size {
		p:=grid.Position{x = x, y = y}; edge:=x<2 || y<2 || x>=size-2 || y>=size-2
		// Fixed islands and clusters, with broad guaranteed connecting axes.
		cover := outdoor_cover(b,p,size)
		if b == .City { cover = x%18>=10 && x%18<=14 && y%16>=6 && y%16<=11 }
		if b == .Egypt { cover = abs(x%24-12)+abs(y%24-12)<3 }
		if b == .Sky { cover=false }
		chasm := b == .Sky && (x%24>=21 || y%24>=21) && abs(y-size/2)>3 && abs(x-size/2)>3 &&
			!((x%24>=21 && y%24>=9 && y%24<=13) || (y%24>=21 && x%24>=9 && x%24<=13))
		if edge || chasm { _=level.set_tile(data,p,{.Void}) }
		else if cover && abs(y-size/2)>3 && x>12 { _=level.set_tile(data,p,{.Wall}) }
	} }
	_=level.set_tile(data,data.player_spawn,{.Player_Spawn})
	kinds := [?]Site_Kind{.Nest,.Cache,.Archive,.Spring,.Nest,.Workshop,.Trial,.Nest,.Cache,.Archive,.Trial,.Boss,.Cache,.Archive,.Memory,.Tunnel}
	positions := [?][2]int{{22,50},{24,27},{16,73},{42,52},{44,25},{39,79},{63,48},{66,76},{65,20},{86,70},{86,23},{90,50},{17,9},{85,91},{45,9},{59,94}}
	content:=rng.create(seed~0xA011)
	for kind,i in kinds {
		p:=grid.Position{x = positions[i][0]*size/100, y = positions[i][1]*size/100}
		if kind==.Boss { p={x = size-20, y = size/2} }
		site:=Site{kind=kind,position=p,secret=i>=12,active=true,waves=2+rank(b)/2,group=-1,seed=rng.next_u64(&content),orientation=u8((int(b)+i)%4),layout_version=SITE_LAYOUT_VERSION}
		if kind==.Boss || kind==.Tunnel {site.orientation=0}
		half:=site_layout(kind).half_extent;if site.orientation%2==1 {half={x = half.y, y = half.x}}
		p={x = clamp(p.x,half.x+3,size-half.x-4), y = clamp(p.y,half.y+3,size-half.y-4)};site.position=p
		if i==8 || i==10 { site.active=rng.next_u64(&content)%3!=0 }
		if i==15 { site.active=b==.Vietnam }
		w.sites[i]=site; w.site_count+=1
		stamp_site(data,&site)
		if kind==.Boss { _=level.set_tile(data,p,{.Exit}) }
	}
	// The biome's relief, level round the sites; then its buildings and objects, level on it; all before
	// any inhabitants.
	apply_relief(w,data)
	apply_mountain(w,data)
	place_structures(w,data)
	place_caves(w,data)
	// Structural geography is finished before any inhabitants are placed.
	for site,i in w.sites[:w.site_count] {if site.active && (site.kind==.Trial || site.kind==.Boss || (site.kind==.Cache && i<12)) {add_group(w,data,i,site.position,1 if site.kind==.Boss else 2+rank(b)/2,false,site.kind==.Boss)}}
	for i in 0..<4 {
		p:=grid.Position{x = size*(35+i*13)/100, y = size*(35+(i%2)*28)/100}
		add_group(w,data,-1,p,2+int(rng.next_u64(&content)%3),true,false)
	}
	add_mountain_inhabitants(w,data,&content)
	if b==.Gothic { add_group(w,data,-1,{x = size/2, y = size/2-10},1,false,false); w.groups[w.group_count-1].killer=true; w.groups[w.group_count-1].members[0].enemy.health*=4; w.groups[w.group_count-1].members[0].enemy.max_health*=4 }
	w.last_position=data.player_spawn
	return true
}

@(private)
add_group :: proc(w:^World,data:^level.Level,site:int,p:grid.Position,requested_count:int,patrol,boss:bool) {
	if w.group_count>=MAX_GROUPS { return }
	count := clamp(requested_count,1,MAX_MEMBERS)
	g:=&w.groups[w.group_count]; g^={anchor=p,count=count,patrol=patrol,boss=boss,site=site}
	r:=rng.create(w.seed~u64(w.group_count+1)*0x9E3779B9)
	for i in 0..<count {
		q:=grid.offset(p, i%3-1, i/3-1)
		if site>=0 && w.sites[site].layout_version==SITE_LAYOUT_VERSION {q=site_spawn_position(&w.sites[site],w.sites[site].wave,i)}
		// Placement never edits geography: content seeds only choose inhabitants.
		if tile, present := level.tile_at(data, q); !present || tile.kind == .Wall || tile.kind == .Void || tile.kind == .Fence {
			for radius in 1..=4 {
				found := false
				for dy in -radius..=radius {
					for dx in -radius..=radius {
						candidate := grid.offset(p, dx, dy)
						candidate_tile, candidate_present := level.tile_at(data, candidate)
						if !candidate_present || candidate_tile.kind == .Wall || candidate_tile.kind == .Void || candidate_tile.kind == .Fence || candidate_tile.kind == .Exit { continue }
						occupied := false
						for previous in g.members[:i] { occupied = occupied || previous.enemy.position == candidate }
						if !occupied { q = candidate; found = true; break }
					}
					if found { break }
				}
				if found { break }
			}
		}
		kind:=game.Enemy_Archetype(rng.next_u64(&r)%5)
		if boss { kind=.Demolitionist }
		hp:=i32(5+rank(w.biome)*2+max(0,p.x-20)/28)
		if kind==.Brute || kind==.Custodian { hp+=3 }; if boss { hp=30+i32(rank(w.biome))*12 }
		if w.biome==.Egypt && kind==.Chaser {hp+=5}
		attack:=2+i32(rank(w.biome))
		if w.biome==.Inferno {hp+=3;attack+=1}
		g.members[i]={enemy={position=q,health=hp,max_health=hp,attack=attack,archetype=kind,boss_phase=1 if boss else 0},alive=true}
	}
	if site>=0 { w.sites[site].group=w.group_count }
	w.group_count+=1
}

can_see :: proc(room:^game.Room,a,b:grid.Position) -> bool {
	if room == nil || room.level_data == nil { return false }
	// Sight rises and falls with the ground: a hill hides what is behind it (game.height_hides); with layers, the
	// line goes through them (game/layers.odin).
	m: level.Layer_Map
	return game.tactical_line_visible(a, b, proc(data: rawptr, cell: grid.Position) -> bool {
		return game.cell_blocks_line_of_sight(cast(^game.Room)data, cell)
	}, room, proc(data: rawptr, cell: grid.Position) -> i32 {
		return game.cell_height(cast(^game.Room)data, cell)
	}, game.room_line_layers(room, &m))
}

// A drop lies where the player is (the open map or a cave), unless `cave` says whose it is (cave.odin).
add_drop :: proc(w:^World,p:grid.Position,item:campaign.Item,xp:i32=0,manual_only:bool=false,cave:int=-1) -> bool {
	if w.drop_count>=MAX_DROPS {return false}
	w.drops[w.drop_count]={p,item,xp,manual_only,u8(w.in_cave if cave<0 else cave)}; w.drop_count+=1; return true
}

nearest_site :: proc(w:^World,p:grid.Position) -> int {
	best:=-1; d:=4
	if w.in_cave>0 {return -1}
	for site,i in w.sites[:w.site_count] { if !site.active || site.state==.Resolved {continue}; next:=distance(p,site.position); if next<d {d=next;best=i} }
	return best
}

@(private)
add_xp_drop :: proc(w:^World,p:grid.Position,xp:i32) {
	if xp<=0 {return}
	for &drop in w.drops[:w.drop_count] {
		if drop.xp>0 && in_scope(w,drop.cave) && distance(p,drop.position)<=3 {drop.xp+=xp;return}
	}
	if add_drop(w,p,{},xp) {return}
	if w.pending_xp==0 {w.pending_xp_position=p}
	w.pending_xp+=xp
}

// Synchronize surviving actors before testing death or leashing. The source
// member is never respawned when a streamed actor has already been defeated.
sync :: proc(w:^World,room:^game.Room) -> i32 {
	if w==nil || room==nil {return 0}
	if w.pending_xp>0 && w.drop_count<MAX_DROPS {
		pending:=w.pending_xp;w.pending_xp=0;add_xp_drop(w,w.pending_xp_position,pending)
	}
	// A bounded, allocation-free lookup avoids scanning/copying every actor
	// for every deployed member on each rendered frame.
	ids:[game.MAX_ENEMIES_PER_ROOM*2]u32
	indices:[game.MAX_ENEMIES_PER_ROOM*2]int
	for &enemy,i in room.enemies {
		slot:=int(enemy.id%u32(len(ids)))
		for ids[slot]!=0 {slot=(slot+1)%len(ids)}
		ids[slot]=enemy.id;indices[slot]=i
	}
	xp:i32
	for &g in w.groups[:w.group_count] {
		for &m in g.members[:g.count] {
			if !m.deployed {continue}
			slot:=int(m.enemy.id%u32(len(ids)))
			for ids[slot]!=0 && ids[slot]!=m.enemy.id {slot=(slot+1)%len(ids)}
			found:=ids[slot]!=0
			if found {m.enemy=room.enemies[indices[slot]]}
			if !found { m.alive=false; m.deployed=false; amount:=2+i32(rank(w.biome));xp+=amount;add_xp_drop(w,m.enemy.position,amount) }
		}
		alive:=0; for m in g.members[:g.count] {if m.alive {alive+=1}}
		if alive==0 && g.active {
			g.active=false
			if g.site>=0 {
				s:=&w.sites[g.site]
				if s.kind==.Boss {w.boss_defeated=true;s.state=.Resolved}
				else if s.kind==.Trial || s.kind==.Nest { s.reward_pending=s.kind==.Trial || s.wave>=s.waves; if s.reward_pending {s.state=.Resolved} }
			}
		}
	}
	return xp
}

engage :: proc(w:^World,room:^game.Room,index:int) -> bool {
	if w == nil || room == nil || index<0 || index>=w.group_count || room.player == nil ||
	   room.qte.kind != .None || room.tactical_pulse.pending || game.tactical_is_casting(room) {return false}
	g:=&w.groups[index]
	count,existing:=0,0
	for m in g.members[:g.count] {if m.alive {if m.deployed {existing+=1}else {count+=1}}}
	if count==0 || len(room.enemies)+count>game.MAX_ENEMIES_PER_ROOM {return false}
	if room.phase!=.Combat && !game.begin_expedition_encounter(room) {return false}
	deployed := 0
	for &m in g.members[:g.count] {
		if !m.alive || m.deployed {continue}
		for attempt in 0..<50 {
			p:=m.enemy.position
			if attempt>0 {p=grid.offset(g.anchor, (attempt-1)%7-3, (attempt-1)/7-3)}
			id,ok:=game.spawn_enemy(room,{position=p,health=m.enemy.health,attack=m.enemy.attack,archetype=m.enemy.archetype,drops_healing=m.enemy.drops_healing})
			if !ok {continue}
			m.enemy.id=id;m.enemy.position=p;m.deployed=true;deployed+=1
			if enemy_index, found := game.enemy_index_by_id(room, id); found {
				enemy := &room.enemies[enemy_index]
				enemy.max_health = m.enemy.max_health
				enemy.statuses = m.enemy.statuses
				enemy.boss_phase, enemy.boss_cycle = m.enemy.boss_phase, m.enemy.boss_cycle
				enemy.recovery_pulses=m.enemy.recovery_pulses
				enemy.boss_approach_pulses=m.enemy.boss_approach_pulses
				enemy.intent={};enemy.tactical_cooldown=0
			}
			break
		}
	}
	g.active=deployed+existing>0
	if deployed>0 {
		// A baited patrol can fight beyond its old territory. Its first
		// deployment establishes the encounter where it actually arrived;
		// otherwise the old twelve-cell leash would instantly remove it.
		if existing==0 && g.lure_phase!=.None {
			for member in g.members[:g.count] {if member.alive && member.deployed {g.anchor=member.enemy.position;break}}
			g.patrol_step=0
		}
		w.mounted=false;g.lure_phase=.None;game.plan_enemy_intents(room)
	}
	g.pursuing=false
	if !g.active && len(room.enemies)==0 {game.end_expedition_encounter(room)}
	return deployed>0
}

@(private)
move_sleeping_group :: proc(w:^World,g: ^Group, room: ^game.Room, step: grid.Position) {
	if step == {} {return}
	for &m in g.members[:g.count] {
		if !m.alive || m.deployed {continue}
		p := game.add_position(m.enemy.position, step)
		if !patrol_cell_free(w,room,p,&m) || game.step_height_blocked(room,m.enemy.position,p) {continue}
		if step.x != 0 && step.y != 0 && game.cell_blocks_movement(room, {x = p.x, y = m.enemy.position.y}) &&
		   game.cell_blocks_movement(room, {x = m.enemy.position.x, y = p.y}) {continue}
		m.enemy.position = p
	}
}

tick :: proc(w:^World,room:^game.Room,dt:f32) {
	if w == nil || room == nil || room.player == nil || room.phase==.Defeat || dt<=0 ||
	   game.tactical_is_casting(room) || game.tactical_shadow_active(room) || room.qte.kind != .None || room.tactical_pulse.pending {return}
	previous_beat:=w.beat
	w.clock+=dt; w.patrol_clock+=dt
	w.beat=u64(w.clock)
	room.player.tactical.environment_beat=w.beat
	// In a cave nothing of the biome's ground or weather reaches the player (biome 255 has none).
	room.player.tactical.config.expedition_biome=u8(w.biome) if w.in_cave==0 else 255
	room.player.tactical.config.low_gravity=w.biome==.Space && w.in_cave==0
	if room.phase==.Loot && w.beat!=previous_beat && w.beat%4==0 {game.expedition_gravity_pulse(room,room.recent_events)}
	if room.phase==.Loot && w.beat!=previous_beat {game.expedition_exploration_terrain_beat(room)}
	if room.player.health<=0 {room.phase=.Defeat;return}
	patrol_due := w.patrol_clock >= 1.4
	player:=room.player.position
	if room.player.health<w.last_health {w.mounted=false}
	w.last_health=room.player.health
	for &s,site_index in w.sites[:w.site_count] {
		if !s.active || w.in_cave>0 {continue}
		if distance(player,s.position)<=5 && s.state==.Unvisited {s.state=.Discovered}
		activation:=4 if s.layout_version==0 else site_layout(s.kind).trigger_radius
		if s.kind==.Nest && s.state!=.Resolved && distance(player,s.position)<=activation {
			if !s.triggered && distance(player,s.position)<=2 {s.triggered=true}
			if s.triggered && s.wave<s.waves {
				alive:=false
				if s.group>=0 {for m in w.groups[s.group].members[:w.groups[s.group].count] {alive=alive||m.alive}}
				if !alive && w.group_count<MAX_GROUPS {
					index:=site_index
					add_group(w,room.level_data,index,s.position,2+rank(w.biome)/2+s.wave,false,false);s.wave+=1
					_=engage(w,room,s.group)
				} else if alive && s.group>=0 {_=engage(w,room,s.group)}
			} else if s.triggered && s.group>=0 {
				// The last wave has no next wave to schedule, but still resumes.
				_=engage(w,room,s.group)
			}
		}
	}
	for &g,i in w.groups[:w.group_count] {
		if !in_scope(w,g.cave) {continue}
		if g.active {
			// A blocked member remains finite and alive. Retry just that member
			// after a placed object expires; never duplicate deployed actors.
			_=engage(w,room,i)
			leash:=20 if g.killer else 12
			if g.site>=0 && w.sites[g.site].layout_version==SITE_LAYOUT_VERSION {leash=site_layout(w.sites[g.site].kind).encounter_radius}
			if distance(player,g.anchor)>leash {
				for &m,member_index in g.members[:g.count] {
					if !m.deployed {continue}
					for e,j in room.enemies {if e.id==m.enemy.id {m.enemy=e;ordered_remove(&room.enemies,j);break}}
					m.deployed=false
					m.enemy.position=site_spawn_position(&w.sites[g.site],max(0,w.sites[g.site].wave-1),member_index) if g.site>=0 && w.sites[g.site].layout_version==SITE_LAYOUT_VERSION else grid.offset(g.anchor, member_index%3-1, member_index/3-1)
				}
				g.active=false
			}
			continue
		}
		if g.lure_phase!=.None {tick_patrol_lure(w,room,&g,patrol_due)}
		if distance(player,g.anchor)>18 && !g.killer && g.lure_phase==.None {continue}
		if g.patrol && patrol_due && !g.pursuing && g.lure_phase==.None {
			steps := [4]grid.Position{{x = 1, y = 0},{x = 0, y = 1},{x = -1, y = 0},{x = 0, y = -1}}
			move_sleeping_group(w,&g, room, steps[(g.patrol_step/3)%4]);g.patrol_step+=1
		}
		if g.pursuing && distance(player,g.anchor)>12 {g.pursuing=false}
		if g.pursuing && patrol_due {
			first:=g.members[0].enemy.position
			move_sleeping_group(w,&g,room,{x = clamp(player.x-first.x,-1,1), y = clamp(player.y-first.y,-1,1)})
		}
		if g.killer && patrol_due {
			dx,dy:=clamp(player.x-g.anchor.x,-1,1),clamp(player.y-g.anchor.y,-1,1)
			p:=grid.offset(g.anchor, dx, dy); if game.base_cell_is_walkable(room,p) {g.anchor=p;g.members[0].enemy.position=p}
		}
		for m in g.members[:g.count] {
			if !m.alive {continue}
			radius:=3 if ground(w,m.enemy.position)==.Grass else 6
			if g.lure_phase==.Seeking || g.lure_phase==.Waiting {radius=1}
			if distance(player,m.enemy.position)<=radius && can_see(room,m.enemy.position,player) {
				if w.mounted { // riders may outrun pursuit; a close hit dismounts
					g.pursuing=true
					if distance(player,m.enemy.position)>1 {continue}
					room.player.health=max(0,room.player.health-max(i32(1),m.enemy.attack-room.player.stats.defense));w.mounted=false
					if room.player.health==0 {room.phase=.Defeat;return}
				}
				_=engage(w,room,i);break
			}
		}
	}
	if w.patrol_clock>=1.4 {w.patrol_clock=0}
	if room.phase==.Combat && len(room.enemies)==0 {game.end_expedition_encounter(room)}
	cycle:=w.beat%9
	if w.in_cave>0 {w.lane_warning=false}
	if w.in_cave==0 && !w.lane_warning && cycle==7 && w.biome!=.Gothic {w.lane_warning=true;w.lane_vertical=(w.beat/9)%2==0;w.lane=player.x if w.lane_vertical else player.y;w.lane_center=player}
	if w.lane_warning && cycle==0 {
		w.lane_warning=false
		if w.biome==.Inferno {
			for offset in -12..=12 {
				p:=grid.Position{x = w.lane, y = w.lane_center.y+offset} if w.lane_vertical else grid.Position{x = w.lane_center.x+offset, y = w.lane}
				protected:=false
				for site in w.sites[:w.site_count] {if distance(site.position,p)<=2 {protected=true;break}}
				if !protected {_=game.expedition_fracture_floor(room,p)}
			}
		}
		if lane_contains(w,player) {
			if w.biome==.Sky {_=game.expedition_wind_push(room,game.PLAYER_ENTITY,{x = 1, y = 0} if w.lane_vertical else {x = 0, y = 1})}
			else {room.player.health=max(0,room.player.health-3-i32(rank(w.biome)));w.mounted=false}
		}
		if w.biome==.Sky {for enemy in room.enemies {if lane_contains(w,enemy.position) {_=game.expedition_wind_push(room,game.enemy_entity(enemy.id),{x = 1, y = 0} if w.lane_vertical else {x = 0, y = 1})}}}
	}
	if room.player.health<=0 {room.phase=.Defeat}
}

lane_contains :: proc(w:^World,p:grid.Position) -> bool {
	return (p.x if w.lane_vertical else p.y)==w.lane &&
		abs((p.y-w.lane_center.y) if w.lane_vertical else (p.x-w.lane_center.x))<=12
}

walk :: proc(w:^World,room:^game.Room,offset:grid.Position) -> bool {
	if room.phase!=.Loot || offset=={} {return false}
	p:=game.add_position(room.player.position,offset)
	if !game.base_cell_is_walkable(room,p) || game.cell_blocks_movement(room,p) || game.step_height_blocked(room,room.player.position,p) {return false}
	if offset.x!=0 && offset.y!=0 && (game.cell_blocks_movement(room,{x = p.x, y = room.player.position.y}) || game.cell_blocks_movement(room,{x = room.player.position.x, y = p.y})) {return false}
	under:=ground(w,p)
	if under==.Bridge && w.beat%4>=2 {return false}
	room.player.position=p
	if under==.Ice {slide:=game.add_position(p,offset);if game.base_cell_is_walkable(room,slide) && !game.cell_blocks_movement(room,slide) {room.player.position=slide}}
	before_health:=room.player.health
	game.expedition_enter_cell(room)
	if room.player.health<before_health {w.mounted=false}
	if room.player.health==0 {room.phase=.Defeat}
	return true
}

metadata :: proc(b:campaign.Biome) -> Metadata { all:=METADATA; return all[b] }

// Called once for a newly generated expedition, before the initial snapshot.
// Traps live in the room thereafter, so disarming survives saves and leashes.
prepare_room :: proc(w:^World,room:^game.Room) {
	if w==nil || room==nil || w.biome!=.Vietnam || len(room.traps)>0 {return}
	side:=size(w)
	for y in 12..<side-8 {for x in 14..<side-8 {
		if (x*17+y*31)%173!=0 || len(room.traps)>=game.MAX_TRAPS_PER_ROOM {continue}
		p:=grid.Position{x = x, y = y};if !game.base_cell_is_walkable(room,p) || distance(p,room.player.position)<8 {continue}
		near_site:=false;for &site in w.sites[:w.site_count] {near_site=near_site || distance(p,site.position)<3 || site_cell(&site,p).inside}
		if near_site {continue}
		append(&room.traps,game.Trap{id=room.next_trap_id,position=p,damage=4,armed=true});room.next_trap_id+=1
	}}
}

// A shortcut never emerges inside a wall, an actor or a hidden pressure plate.
// This also uses the saved dimensions when resuming an older small map.
tunnel_destination :: proc(w:^World,room:^game.Room)->(position:grid.Position,ok:bool) {
	if w==nil || room==nil {return}
	anchor:=grid.Position{x = size(w)-14, y = 16}
	for radius in 0..=8 {for y in -radius..=radius {for x in -radius..=radius {
		p:=game.add_position(anchor,{x = x, y = y});if !game.base_cell_is_walkable(room,p) || game.cell_blocks_movement(room,p) {continue}
		occupied:=false
		for enemy in room.enemies {occupied=occupied || enemy.position==p}
		for &group in w.groups[:w.group_count] {for member in group.members[:group.count] {occupied=occupied || (member.alive && member.enemy.position==p)}}
		for trap in room.traps {occupied=occupied || (trap.armed && trap.position==p)}
		if !occupied {return p,true}
	}}}
	return
}
