package memoryarcade

import "core:fmt"
import "core:math"
import rl "vendor:raylib"
import canvas_target "../engine/canvas"
import host "../engine/host"
import input "../engine/input"
import audio "../engine/audio"
import ui "../engine/ui"

Game :: struct {
	state: State,
	kind: Kind,
	demo, was_playing: bool,
	accumulator: f32,
	command: Command,
	duck: bool,
	visual_time: f32,
}

info :: proc(kind: Kind) -> host.Minigame_Info {
	switch kind {
	case .Lightcycles:
		return {id="lightcycles", title="Scie di luce", genre="Arena di moto al neon",
			tagline="Tre rivali, una sola pista. Ogni moto lascia un muro di luce: trova una via d'uscita e resta l'ultima in corsa.",
			controls="WASD / frecce: cambia direzione\nNon puoi invertire la marcia. Evita scie e bordi.\nEsc: pausa", accent={255,69,103,255}, create=create_lightcycles}
	case .Showdown:
		return {id="showdown", title="Duello a mezzogiorno", genre="Cinque duelli alla frontiera",
			tagline="La mano ferma conta piu della fretta. Aspetta ESTRAI, poi spara prima del fuorilegge. Vinci almeno tre duelli.",
			controls="Spazio / clic sinistro: estrai e spara\nAttendi il segnale verde: sparare prima costa una vita.\nEsc: pausa", accent={255,185,89,255}, create=create_showdown}
	case .Trex:
		return {id="trex", title="Fuga dal T-Rex", genre="Corsa nella memoria preistorica",
			tagline="Il T-Rex e alle calcagna. Salta rocce e tronchi, abbassati sotto gli pterodattili e raggiungi il portale.",
			controls="Spazio / W / freccia su: salta\nS / freccia giu: abbassati\nEsc: pausa", accent={180,244,75,255}, create=create_trex}
	case .Karaoke:
		return {id="karaoke", title="Karaoke", genre="City pop / 112 BPM",
			tagline="La memoria sa ancora cantare. Colpisci le note sulla linea: PRECISO vale piu di BUONO. Costruisci una combo di 64 note.",
			controls="A / S / D / F: le quattro voci\nPremi quando la nota arriva alla linea luminosa.\nEsc: pausa", accent={255,98,205,255}, create=create_karaoke}
	case .Helicopter:
		return {id="helicopter", title="Elicottero", genre="Sparatutto dal portellone",
			tagline="Sorvola la giungla. Abbatti i bersagli prima che il mirino rosso si chiuda. Ricarica nei momenti di calma.",
			controls="Mouse: mira   Clic sinistro: fuoco continuo\nR: ricarica (16 colpi)   WASD / frecce: mira alternativa\nSpazio: fuoco   Esc: pausa", accent={183,212,100,255}, create=create_helicopter}
	case .Descent:
		return {id="descent", title="Discesa", genre="Slalom sulle montagne di vetro",
			tagline="Lo yeti segue le tue tracce. Curva fra gli abeti, attraversa i portali azzurri e raggiungi il fondo della discesa.",
			controls="A / D oppure frecce: sterza\nL'inerzia continua nelle curve. I portali danno punti.\nEsc: pausa", accent={139,229,255,255}, create=create_descent}
	}
	return {}
}

create_lightcycles :: proc(c: host.Minigame_Config) -> host.Scene { return create(.Lightcycles,c) }
create_showdown :: proc(c: host.Minigame_Config) -> host.Scene { return create(.Showdown,c) }
create_trex :: proc(c: host.Minigame_Config) -> host.Scene { return create(.Trex,c) }
create_karaoke :: proc(c: host.Minigame_Config) -> host.Scene { return create(.Karaoke,c) }
create_helicopter :: proc(c: host.Minigame_Config) -> host.Scene { return create(.Helicopter,c) }
create_descent :: proc(c: host.Minigame_Config) -> host.Scene { return create(.Descent,c) }

create :: proc(kind: Kind, config: host.Minigame_Config) -> host.Scene {
	g:=new(Game)
	g.kind=kind
	return host.minigame_scene(info(kind),host.Minigame_Hooks{
		data=g,reset=game_reset,step=game_step,draw=game_draw,score=game_score,
		destroy=proc(data: rawptr) { free(data) }, music=.Karaoke if kind==.Karaoke else .Action}, config)
}

create_autoplay :: proc(kind: Kind, config: host.Minigame_Config) -> host.Scene {
	scene:=create(kind,config)
	g:=cast(^Game)host.shell_of(&scene).hooks.data
	g.demo=true
	return scene
}

game_reset :: proc(data: rawptr, config: host.Minigame_Config) {
	g:=cast(^Game)data
	reset(&g.state,g.kind,config.seed)
	g.accumulator=0; g.command={}; g.was_playing=false
}

pressed :: proc(d: ^input.Device_Snapshot, a,b: rl.KeyboardKey) -> bool {
	return input.key_pressed(d,a)||input.key_pressed(d,b)
}
down :: proc(d: ^input.Device_Snapshot, a,b: rl.KeyboardKey) -> bool {
	return input.key_down(d,a)||input.key_down(d,b)
}

game_step :: proc(data: rawptr, frame: ^host.Frame, playing: bool) -> host.Round_Status {
	g:=cast(^Game)data
	g.visual_time+=frame.dt
	if !playing {
		if g.kind==.Karaoke && frame.audio!=nil && frame.audio.music_playing { rl.PauseMusicStream(frame.audio.music) }
		g.command={}; g.accumulator=0; g.was_playing=false
		return g.state.status
	}
	if !g.was_playing {
		if g.kind==.Karaoke && frame.audio!=nil && frame.audio.music_playing {
			rl.SeekMusicStream(frame.audio.music,math.mod(g.state.time,32*60.0/112.0))
			rl.ResumeMusicStream(frame.audio.music)
		}
		g.was_playing=true; return .Playing
	}
	c:=&g.command
	d:=frame.devices
	if g.kind!=.Lightcycles { c.move={} }
	if g.kind==.Lightcycles {
		if pressed(d,.A,.LEFT) { c.move.x=-1 }
		if pressed(d,.D,.RIGHT) { c.move.x=1 }
		if pressed(d,.W,.UP) { c.move.y=-1 }
		if pressed(d,.S,.DOWN) { c.move.y=1 }
	} else {
		c.move.x=f32(int(down(d,.D,.RIGHT))-int(down(d,.A,.LEFT)))
		c.move.y=f32(int(down(d,.S,.DOWN))-int(down(d,.W,.UP)))
	}
	c.jump=c.jump||pressed(d,.SPACE,.W)||input.key_pressed(d,.UP)
	c.duck=down(d,.S,.DOWN)
	g.duck=c.duck
	c.fire=c.fire||input.mouse_pressed(d,.LEFT)||input.key_pressed(d,.SPACE)
	if g.kind==.Helicopter {
		c.fire=input.mouse_down(d,.LEFT)||input.key_down(d,.SPACE)
		area:=play_area(frame)
		c.aim={clamp((frame.mouse.x-area.x)/area.width,0,1),clamp((frame.mouse.y-area.y)/area.height,0,1)}
		if c.move.x!=0 || c.move.y!=0 { c.aim=g.state.aim+c.move*frame.dt*0.6 }
		c.reload=c.reload||input.key_pressed(d,.R)
	}
	keys:=[4]rl.KeyboardKey{.A,.S,.D,.F}
	for k,i in keys { c.lanes[i]=c.lanes[i]||input.key_pressed(d,k) }
	g.accumulator+=min(frame.dt,0.1)
	for g.accumulator>=TICK {
		cmd:=g.command
		if g.demo { cmd=autoplay(&g.state); g.duck=cmd.duck }
		before:=g.state
		step(&g.state,cmd)
		if g.state.hits>before.hits || g.state.duel_wins>before.duel_wins { audio.play(frame.audio,.Confirm) }
		if g.state.health<before.health { audio.play(frame.audio,.Hurt) }
		if g.kind==.Karaoke && int(g.state.time/(60.0/112.0))!=int(before.time/(60.0/112.0)) { audio.play(frame.audio,.Blip,0.35,0.65) }
		c.jump=false; c.reload=false; c.lanes={}
		if g.kind!=.Helicopter { c.fire=false }
		g.accumulator-=TICK
		if g.state.status!=.Playing { break }
	}
	return g.state.status
}

game_score :: proc(data: rawptr) -> (i64,u8) {
	g:=cast(^Game)data
	return i64(g.state.score),stars(&g.state)
}

play_area :: proc(frame: ^host.Frame) -> rl.Rectangle {
	return {frame.canvas.x+26,frame.canvas.y+98,frame.canvas.width-52,frame.canvas.height-164}
}

game_draw :: proc(data: rawptr, frame: ^host.Frame) {
	g:=cast(^Game)data; s:=&g.state; meta:=info(s.kind)
	draw_backdrop(frame.canvas,g.visual_time,meta.accent)
	a:=play_area(frame)
	rl.DrawRectangleRounded({a.x-2,a.y-2,a.width+4,a.height+4},0.02,4,rl.Color{30,35,49,255})
	rl.DrawRectangleRec(a,rl.Color{8,13,24,255})
	canvas_target.begin_scissor(a.x,a.y,a.width,a.height)
	switch s.kind {
	case .Lightcycles: draw_cycles(g,frame,a)
	case .Showdown: draw_showdown(g,frame,a)
	case .Trex: draw_trex(g,frame,a)
	case .Karaoke: draw_karaoke(g,frame,a)
	case .Helicopter: draw_helicopter(g,frame,a)
	case .Descent: draw_descent(g,frame,a)
	}
	rl.EndScissorMode()
	ui.draw_text(frame.theme,"MEMORIA / CABINATO",{28,18},.Small,meta.accent)
	ui.draw_text(frame.theme,meta.title,{26,42},.Title,rl.Color{243,238,220,255})
	ui.draw_text_fit(frame.theme,fmt.tprintf("%06d",s.score),{frame.canvas.width-230,42,202,44},.Title,meta.accent,.Right)
	footer:="Esc  Pausa"
	switch s.kind {
	case .Lightcycles: footer="WASD / frecce  Cambia direzione     Evita ogni scia"
	case .Showdown: footer="Spazio / clic  Estrai SOLO al segnale verde"
	case .Trex: footer="Spazio  Salta     S / giu  Abbassati"
	case .Karaoke: footer="A     S     D     F    /    112 BPM"
	case .Helicopter: footer="Mouse  Mira     Clic / Spazio  Fuoco     R  Ricarica"
	case .Descent: footer="A / D   Sterza     Attraversa i portali azzurri"
	}
	ui.draw_text(frame.theme,footer,{28,frame.canvas.height-47},.Small,rl.Color{190,202,218,255})
	ui.draw_text_fit(frame.theme,"Esc  Pausa",{frame.canvas.width-130,frame.canvas.height-49,100,24},.Small,rl.Color{130,145,165,255},.Right)
	if s.kind!=.Lightcycles && s.kind!=.Karaoke {
		for i in 0..<s.health { rl.DrawRectangleRounded({a.x+12+f32(i)*22,a.y+12,16,7},0.4,4,meta.accent) }
	}
	if s.kind==.Trex || s.kind==.Descent || s.kind==.Helicopter {
		duration:=f32(45) if s.kind==.Helicopter else 48
		rl.DrawRectangleRec({a.x,a.y+a.height-3,a.width*min(1,s.time/duration),3},meta.accent)
		ui.draw_text_fit(frame.theme,fmt.tprintf("PORTALE  %ds",int(max(0,duration-s.time))),{a.x+a.width-150,a.y+8,135,24},.Small,meta.accent,.Right)
	}
}
