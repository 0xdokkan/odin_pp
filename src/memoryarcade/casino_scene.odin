package memoryarcade

import "core:fmt"
import "core:math"
import rl "vendor:raylib"
import canvas_target "../engine/canvas"
import host "../engine/host"
import input "../engine/input"
import ui "../engine/ui"
import audio "../engine/audio"
import rng "../engine/rng"
import render "../render"

Casino_View :: struct {
	wallet: Casino_Wallet,
	local_transaction: Casino_Transaction,
	local_random: u64,
	local_credits: i64,
	kind: Casino_Kind,
	wager: i64,
	selection, number: int,
	bet: Roulette_Bet,
	clock, save_clock, celebration: f32,
	paused, demo: bool,
	commit_needed: bool,
	status: string,
	die: render.Polyhedral_Die,
}

casino_title :: proc(kind: Casino_Kind) -> string {
	switch kind {
	case .Ranch: return "6 RANCH 7 / La slot del ranch"
	case .Escape: return "Tre in fuga"
	case .Roulette: return "Roulette europea"
	case .Dice: return "Duello di d20"
	}
	return "Casino"
}

casino_create :: proc(kind: Casino_Kind, wallet: Casino_Wallet, seed: u64=1) -> host.Scene {
	g:=new(Casino_View)
	g.wallet=wallet; g.kind=kind; g.wager=10; g.bet=.Red
	g.die=render.build_polyhedral_die(.D20)
	g.local_random=rng.derive(seed,0xCA51); g.local_credits=500
	if g.wallet.transaction==nil { g.wallet.transaction=&g.local_transaction }
	if g.wallet.random_state==nil { g.wallet.random_state=&g.local_random }
	if g.wallet.random_state^==0 { g.wallet.random_state^=g.local_random }
	if g.wallet.transaction.active { g.kind=g.wallet.transaction.kind }
	return host.Scene{name="casino",data=g,opaque=true,modal=true,
		update=casino_update,draw=casino_draw,destroy=proc(data: rawptr) { free(data) },
		suspend=proc(data: rawptr) { g:=cast(^Casino_View)data; casino_commit(g) }}
}

casino_create_demo :: proc(kind: Casino_Kind, seed: u64=1) -> host.Scene {
	s:=casino_create(kind,{},seed)
	g:=cast(^Casino_View)s.data
	g.demo=true
	casino_begin(g.wallet.transaction,kind,10,seed)
	g.wallet.transaction.elapsed=1.5
	return s
}

casino_balance :: proc(g: ^Casino_View) -> i64 {
	return g.wallet.balance(g.wallet.data) if g.wallet.balance!=nil else g.local_credits
}
casino_persist :: proc(g: ^Casino_View) {
	if g.commit_needed { casino_commit(g); return }
	if g.wallet.changed!=nil { g.wallet.changed(g.wallet.data) }
	g.save_clock=0
}

casino_commit :: proc(g: ^Casino_View) -> bool {
	accepted:=true
	if g.wallet.commit!=nil { accepted=g.wallet.commit(g.wallet.data) }
	else if g.wallet.changed!=nil { g.wallet.changed(g.wallet.data) }
	g.commit_needed=!accepted
	g.save_clock=0
	g.status="" if accepted else "Salvataggio non riuscito: la giocata attende un checkpoint sicuro."
	return accepted
}

casino_wager :: proc(g: ^Casino_View) {
	t:=g.wallet.transaction
	if t.active || g.commit_needed { return }
	paid:=false
	if g.wallet.debit!=nil { paid=g.wallet.debit(g.wallet.data,g.wager) }
	else if g.local_credits>=g.wager { g.local_credits-=g.wager; paid=true }
	if !paid { g.status="Crediti insufficienti nel deposito."; return }
	seed:=rng.step(g.wallet.random_state)
	casino_begin(t,g.kind,g.wager,seed,g.selection,g.bet,g.number)
	g.status=""
	casino_commit(g)
}

casino_settle :: proc(g: ^Casino_View) {
	t:=g.wallet.transaction
	if !t.active || !t.settled { return }
	paid:=true
	if t.payout>0 {
		if g.wallet.credit!=nil { paid=g.wallet.credit(g.wallet.data,t.payout) }
		else { g.local_credits+=t.payout }
	}
	if !paid { g.status="Deposito pieno: l'incasso resta custodito. Fai spazio e torna."; return }
	t.active=false
	g.celebration=1.2
	casino_commit(g)
}

bet_label :: proc(bet: Roulette_Bet) -> string {
	switch bet {
	case .Number: return "Numero pieno / 35 a 1"
	case .Red: return "Rosso / 1 a 1"
	case .Black: return "Nero / 1 a 1"
	case .Even: return "Pari / 1 a 1"
	case .Odd: return "Dispari / 1 a 1"
	case .Low: return "Basso 1-18 / 1 a 1"
	case .High: return "Alto 19-36 / 1 a 1"
	case .Dozen_1: return "Prima dozzina / 2 a 1"
	case .Dozen_2: return "Seconda dozzina / 2 a 1"
	case .Dozen_3: return "Terza dozzina / 2 a 1"
	case .Column_1: return "Prima colonna / 2 a 1"
	case .Column_2: return "Seconda colonna / 2 a 1"
	case .Column_3: return "Terza colonna / 2 a 1"
	}
	return ""
}

casino_update :: proc(data: rawptr, frame: ^host.Frame) {
	g:=cast(^Casino_View)data; t:=g.wallet.transaction
	g.clock+=frame.dt; g.celebration=max(0,g.celebration-frame.dt)
	if g.commit_needed {
		g.save_clock+=frame.dt
		if g.save_clock>=1 { casino_commit(g) }
	}
	if !frame.visible { return }
	audio.play_music(frame.audio,.Menu,4)
	ctx:=frame.ui; p:=ctx.theme.palette; w:=frame.canvas.width; h:=frame.canvas.height
	if g.paused && frame.window_focused { g.paused=false }
	if !frame.window_focused {
		if !g.paused { casino_commit(g); g.paused=true }
	}
	bottom:=rl.Rectangle{26,h-157,w-52,131}
	ui.fill(ctx,bottom,p.panel)
	inner:=ui.shrink_xy(bottom,14,10)
	buttons:=ui.cut_bottom(&inner,38)
	exit_rect:=ui.cut_right(&buttons,150)
	ui.cut_right(&buttons,10)
	if ui.button(ctx,exit_rect,"Torna all'hub") || (ui.back_pressed(ctx)&&g.clock>0.2) {
		casino_commit(g); host.pop(frame); return
	}
	cmd:=Casino_Command{}
	if t.active && !t.settled {
		if g.kind==.Ranch || g.kind==.Escape {
			if ui.button(ctx,buttons,fmt.tprintf("INCASSA  ~%.0f crediti",casino_cash_value(t)),primary=true) { cmd.cash=true }
		}
		legend:="W  Avanza    Spazio  Salta    Invio  Incassa" if g.kind==.Ranch else "Invio  Incassa prima della caduta"
		if g.kind==.Roulette || g.kind==.Dice { legend="Il risultato e gia fissato. La puntata resta salvata." }
		ui.label(ctx,ui.cut_top(&inner,24),legend,.Body,p.text)
		ui.label(ctx,inner,g.status if g.commit_needed else "Puoi tornare all'hub: la giocata riprende da qui.",.Small,p.warning if g.commit_needed else p.text_dim)
		if frame.focused && !g.paused && !g.commit_needed {
			cmd.cash=cmd.cash||input.key_pressed(frame.devices,.ENTER)
			cmd.forward=input.key_down(frame.devices,.W)||input.key_down(frame.devices,.UP)
			cmd.jump=input.key_pressed(frame.devices,.SPACE)
			if g.demo { cmd.forward=true; cmd.jump=true }
			before_coins:=t.coins
			casino_step(t,cmd,min(frame.dt,0.05))
			if t.coins>before_coins { audio.play(frame.audio,.Explosion if t.last_bang else .Coin) }
			g.save_clock+=frame.dt
			if g.save_clock>=0.5 { casino_persist(g) }
		}
	} else if !t.active {
		row:=ui.cut_top(&inner,30)
		stake:=ui.cut_left(&row,250)
		if ui.button(ctx,ui.cut_left(&stake,32),"-") { g.wager=max(5,g.wager-5) }
		if ui.button(ctx,ui.cut_right(&stake,32),"+") { g.wager=min(50,g.wager+5) }
		ui.label(ctx,stake,fmt.tprintf("Puntata  %d",g.wager),.Body,p.text,.Center)
		ui.cut_left(&row,16)
		switch g.kind {
		case .Escape:
			labels:=[3]string{"Dinosauro","Panda 4x4","Moto"}
			for label,i in labels { if ui.button(ctx,ui.column(row,3,i,8),label,primary=g.selection==i) { g.selection=i } }
		case .Roulette:
			if ui.button(ctx,ui.cut_left(&row,32),"<") { g.bet=Roulette_Bet((int(g.bet)+12)%13) }
			if ui.button(ctx,ui.cut_right(&row,32),">") { g.bet=Roulette_Bet((int(g.bet)+1)%13) }
			if g.bet==.Number {
				n:=ui.cut_right(&row,135)
				if ui.button(ctx,ui.cut_left(&n,28),"-") { g.number=(g.number+36)%37 }
				if ui.button(ctx,ui.cut_right(&n,28),"+") { g.number=(g.number+1)%37 }
				ui.label(ctx,n,fmt.tprintf("%d",g.number),.Body,GOLD,.Center)
			}
			ui.label(ctx,row,bet_label(g.bet),.Small,p.text,.Center)
		case .Ranch,.Dice:
			ui.label(ctx,row,"Crediti di gioco / nessun acquisto",.Small,p.text_dim,.Right)
		}
		ui.cut_top(&inner,4)
		line_text:=g.status
		if line_text=="" {
			if t.settled { line_text=fmt.tprintf("Ultima giocata: %d puntati / %d restituiti",t.wager,t.payout) }
			else { line_text="Scegli la puntata. Il deposito e la tua posta in gioco." }
		}
		ui.label(ctx,inner,line_text,.Small,p.text_dim)
		if ui.button(ctx,buttons,"PUNTA",primary=true) && casino_balance(g)>=g.wager { casino_wager(g); audio.play(frame.audio,.Confirm) }
	}
	if t.active && t.settled {
		casino_settle(g)
		if t.active { ui.label(ctx,inner,g.status,.Small,p.warning) }
		else { audio.play(frame.audio,.Win if t.payout>0 else .Lose) }
	}
	if !t.active && t.settled && g.kind==.Escape { t.elapsed+=f64(min(frame.dt,0.05)) }
}

casino_draw :: proc(data: rawptr, frame: ^host.Frame) {
	g:=cast(^Casino_View)data; t:=g.wallet.transaction
	w:=frame.canvas.width; h:=frame.canvas.height
	draw_backdrop(frame.canvas,g.clock,GOLD)
	ui.draw_text(frame.theme,"CASINO DELLA MEMORIA",{28,18},.Small,GOLD)
	ui.draw_text(frame.theme,casino_title(g.kind),{26,43},.Title,PAPER)
	ui.draw_text_fit(frame.theme,fmt.tprintf("%d CR",casino_balance(g)),{w-230,42,200,42},.Large,GOLD,.Right)
	a:=rl.Rectangle{26,100,w-52,h-277}
	rl.DrawRectangleRec(a,rl.Color{9,17,28,255})
	rl.DrawRectangleLinesEx(a,1,rl.Color{64,65,71,255})
	canvas_target.begin_scissor(a.x,a.y,a.width,a.height)
	switch g.kind {
	case .Ranch: draw_casino_ranch(g,frame,a)
	case .Escape: draw_casino_escape(g,frame,a)
	case .Roulette: draw_casino_roulette(g,frame,a)
	case .Dice: draw_casino_dice(g,frame,a)
	}
	rl.EndScissorMode()
	edge:="Banco 2% / BANG 2%, +3 punti a moneta, massimo 60%"
	switch g.kind {
	case .Ranch:
	case .Escape: edge="Banco 3% / stessi rischi per i tre / raddoppio ogni 6 s"
	case .Roulette: edge="Banco 2,70% / 37 numeri / un solo zero"
	case .Dice: edge="Banco 5% / vince il piu alto / il pari va al banco"
	}
	ui.draw_text_fit(frame.theme,edge,{a.x+14,a.y+a.height-27,a.width-28,22},.Small,rl.Color{162,175,188,255},.Center)
	if t.settled && !t.active && g.kind!=.Escape {
		label:=fmt.tprintf("INCASSO  %d CR",t.payout) if t.payout>0 else "LA PUNTATA RESTA AL BANCO"
		ui.draw_text_fit(frame.theme,label,{a.x,a.y+16,a.width,32},.Large,GOLD if t.payout>0 else PINK,.Center)
	}
}

draw_casino_ranch :: proc(g: ^Casino_View, f: ^host.Frame, a: rl.Rectangle) {
	t:=g.wallet.transaction
	draw_horizon(a,GOLD,g.clock)
	// The track runs from the player toward the horizon, bottom to top.
	line(a,0.43,0.22,0.30,0.92,3,GOLD); line(a,0.59,0.22,0.72,0.92,3,GOLD)
	for i in 0..<8 {
		distance:=f32(t.coins)+0.5+f32(i)*0.5-f32(t.distance)
		y:=0.80-distance*0.25
		if y<0.16 || y>0.88 { continue }
		x:=f32(0.5)
		p:=point(a,x,y)
		if i%2==1 { rl.DrawCircleV(p,7+y*5,GOLD); rl.DrawCircleLinesV(p,4+y*3,PAPER) }
		else {
			span:=a.width*(0.03+y*0.1)
			rl.DrawLineEx({p.x-span,p.y},{p.x+span,p.y},6,PAPER)
			rl.DrawLineEx({p.x-span,p.y-9},{p.x-span,p.y+14},5,GOLD)
			rl.DrawLineEx({p.x+span,p.y-9},{p.x+span,p.y+14},5,GOLD)
		}
	}
	scale:=a.height/100
	jump:=math.sin(f64(t.jump/0.7)*math.PI)*28
	draw_paper(.Horse,a.x+a.width*0.5-scale*6,a.y+a.height*0.80-scale*10-f32(jump),scale,GOLD)
	draw_paper(.Robot,a.x+a.width*0.5-scale*3,a.y+a.height*0.80-scale*17-f32(jump),scale*0.75,PINK if t.last_bang else CYAN,false,70 if t.last_bang else 0)
	draw_paper(.Cowboy,a.x+a.width*0.78,a.y+a.height*0.6-scale*11,scale,PINK,true)
	if t.last_bang {
		from:=point(a,.79,.60);to:=point(a,.50,.66)
		progress:=clamp((1.2-g.celebration)*4,0,1)
		rl.DrawLineEx(from,to,2,rl.Color{255,199,92,90})
		rl.DrawCircleV(from+(to-from)*progress,5,GOLD)
		for n in 0..<9 {
			angle:=f32(n)*math.TAU/9
			d:=rl.Vector2{math.cos(angle),math.sin(angle)}
			rl.DrawLineEx(to+d*(12+progress*10),to+d*(18+progress*22),3,PINK)
		}
	}
	flag:=rl.Rectangle{a.x+a.width*0.75,a.y+a.height*0.2,a.width*0.20,38}
	rl.DrawRectangleRec(flag,PAPER)
	ui.draw_text_fit(f.theme,"BANG" if t.last_bang else "MANCATO",flag,.Large,INK,.Center)
	ui.draw_text(f.theme,fmt.tprintf("MONETE  %d",t.coins),{a.x+22,a.y+26},.Body,GOLD)
	ui.draw_text(f.theme,fmt.tprintf("x%.2f",ranch_multiplier(t.coins)),{a.x+22,a.y+60},.Title,PAPER)
	ui.draw_text(f.theme,fmt.tprintf("Prossimo BANG  %.0f%%",ranch_risk(t.coins+1)*100),{a.x+22,a.y+106},.Small,PINK)
	if t.stumble>0 { ui.draw_text_fit(f.theme,"INCIAMPO / nessuna perdita",{a.x,a.y+a.height*0.84,a.width,24},.Small,GOLD,.Center) }
}

draw_casino_escape :: proc(g: ^Casino_View, f: ^host.Frame, a: rl.Rectangle) {
	t:=g.wallet.transaction
	draw_horizon(a,CYAN,g.clock)
	selected:=t.selection if t.active||t.settled else g.selection
	value:=crash_multiplier(t.elapsed) if t.active||t.settled else 1
	ui.draw_text_fit(f.theme,fmt.tprintf("x%.2f",value),{a.x,a.y+14,a.width,52},.Title,PAPER,.Center)
	names:=[3]string{"DINOSAURO","PANDA 4x4","MOTO"}
	kinds:=[3]Paper_Kind{.Dino,.Panda,.Bike}
	colors:=[3]rl.Color{{177,223,99,255},GOLD,PINK}
	for i in 0..<3 {
		y:=0.33+f32(i)*0.20
		line(a,0.05,y+0.13,0.49,y+0.13,2,colors[i])
		fallen:=(t.active||t.settled)&&t.crash[i]<value
		x:=0.20+f32(math.sin(g.clock*2+f32(i)))*0.02
		fall_age:=max(0,f32(t.elapsed-6*math.log2(max(1,t.crash[i]))))
		angle:f32
		if fallen {
			x-=min(fall_age*.08,.13)
			angle=min(fall_age*230,85) if i==0 else min(fall_age*260,180)
			if i==2 {angle=-min(fall_age*180,65)}
		}
		p:=point(a,x,y)
		if fallen&&i==0 {p.y+=min(fall_age*35,18)}
		draw_paper(kinds[i],p.x,p.y,a.height/130,colors[i],false,angle)
		if fallen && i==2 {
			for n in 0..<12 {
				phase:=f32(n)*math.TAU/12+g.clock*.6
				d:=rl.Vector2{math.cos(phase),math.sin(phase)}
				rl.DrawLineEx(p+{25,20}+d*16,p+{25,20}+d*(30+f32(n%3)*7),2,CYAN if n%2==0 else PINK)
			}
		} else if fallen {
			for n in 0..<4 {rl.DrawCircleV(p+{f32(n)*11,36},3+f32(n%2),rl.Color{201,174,123,100})}
		}

		label_y:=a.y+a.height*y
		label:=names[i]
		if selected==i { label=fmt.tprintf("%s / TU",names[i]) }
		ui.draw_text_fit(f.theme,label,{a.x+a.width*0.53,label_y,a.width*0.4,23},.Body,colors[i],.Right)
		if fallen { ui.draw_text_fit(f.theme,fmt.tprintf("CADUTO a x%.2f",t.crash[i]),{a.x+a.width*0.53,label_y+23,a.width*0.4,19},.Small,PINK,.Right) }
	}
	if t.settled { ui.draw_text_fit(f.theme,fmt.tprintf("INCASSO  %d CR",t.payout),{a.x+18,a.y+16,a.width*.28,24},.Small,GOLD if t.payout>0 else PINK,.Left) }
}

draw_casino_roulette :: proc(g: ^Casino_View, f: ^host.Frame, a: rl.Rectangle) {
	t:=g.wallet.transaction
	center:=point(a,0.33,0.50); radius:=min(a.height*0.39,a.width*0.22)
	rl.DrawCircleV(center,radius+9,CYAN)
	rl.DrawCircleV(center,radius+5,PAPER)
	order:=[37]int{0,32,15,19,4,21,2,25,17,34,6,27,13,36,11,30,8,23,10,5,24,16,33,1,20,14,31,9,22,18,29,7,28,12,35,3,26}
	result_index:=0
	for n,i in order { if n==t.wheel { result_index=i } }
	rotation:=-90-(f32(result_index)+0.5)*360/37
	if t.active&&!t.settled { rotation+=1080*math.pow(max(0,1-f32(t.elapsed)/3),3) }
	for n,i in order {
		angle:=f32(i)*360/37+rotation
		c:=rl.Color{162,43,73,255} if roulette_red(n) else INK
		if n==0 { c=rl.Color{44,145,123,255} }
		rl.DrawCircleSector(center,radius,angle,angle+360.0/37,4,c)
		a2:=(angle+180.0/37)*math.PI/180
		p:=rl.Vector2{center.x+math.cos(a2)*radius*0.81,center.y+math.sin(a2)*radius*0.81}
		ui.draw_text_fit(f.theme,fmt.tprintf("%d",n),{p.x-11,p.y-8,22,16},.Small,PAPER,.Center)
	}
	rl.DrawCircleV(center,radius*0.53,rl.Color{36,54,63,255})
	rl.DrawCircleLinesV(center,radius*0.50,GOLD)
	label:="?" if t.active&&!t.settled else fmt.tprintf("%d",t.wheel)
	ui.draw_text_fit(f.theme,label,{center.x-55,center.y-30,110,60},.Title,PAPER,.Center)
	triangle({center.x-8,center.y-radius-14},{center.x+8,center.y-radius-14},{center.x,center.y-radius+4},GOLD)
	// Felt betting reference, including the single green zero.
	grid:=rl.Rectangle{a.x+a.width*0.54,a.y+a.height*0.30,a.width*0.43,a.height*0.42}
	cellw:=grid.width/13; cellh:=grid.height/3
	for n in 0..=36 {
		row:=(n-1)%3; col:=0 if n==0 else (n-1)/3+1
		box:=rl.Rectangle{grid.x+f32(max(col,0))*cellw,grid.y+f32(row)*cellh,cellw-2,cellh-1}
		if n==0 { box.height=grid.height-1; box.y=grid.y }
		c:=rl.Color{120,34,58,255} if roulette_red(n) else rl.Color{22,29,38,255}
		if n==0 { c=rl.Color{31,115,96,255} }
		rl.DrawRectangleRec(box,c)
		ui.draw_text_fit(f.theme,fmt.tprintf("%d",n),box,.Small,PAPER,.Center)
	}
}

draw_casino_dice :: proc(g: ^Casino_View, f: ^host.Frame, a: rl.Rectangle) {
	t:=g.wallet.transaction
	// Reuse the exact bevelled, numbered D20 geometry from combat.
	pixels:f32=80
	camera:=rl.Camera3D{position={0,8,6},target={},up={0,1,0},fovy=f.canvas.height/pixels,projection=.ORTHOGRAPHIC}
	canvas_target.begin_scissor(a.x,a.y,a.width,a.height)
	rl.BeginMode3D(camera)
	for i in 0..<2 {
		p:=point(a,.29+f32(i)*.42,.48)
		q:=(p-rl.Vector2{f.canvas.width*.5,f.canvas.height*.5})/pixels
		position:=rl.Vector3{q.x,-q.y*.6,q.y*.8}
		value:=t.player_die if i==0 else t.bank_die
		value=max(value,1)
		rotation:=rl.Quaternion(1)
		for face in g.die.faces[:g.die.face_count] {
			if face.value!=i32(value) {continue}
			rotation=rl.QuaternionFromVector3ToVector3(face.normal,{0,.8,.6})
			up:=rl.Vector3RotateByQuaternion(face.v,rotation)
			angle:=math.atan2(up.x,rl.Vector3DotProduct(up,{0,.6,-.8}))
			rotation=rl.QuaternionFromAxisAngle({0,.8,.6},angle)*rotation
			break
		}
		if t.active&&!t.settled {
			left:=max(0,1-f32(t.elapsed)/2.5)
			rotation=rl.QuaternionFromEuler(left*16,left*12+f32(i)*left*4,left*7)*rotation
			position.y+=abs(math.sin(f32(t.elapsed)*9))*left*.3
		}
		render.draw_polyhedral_die(&g.die,position,rotation,f.theme.fonts[.Title],false,true)
	}
	rl.EndMode3D()
	rl.EndScissorMode()
	for i in 0..<2 {
		p:=point(a,.29+f32(i)*.42,.48)
		value:=t.player_die if i==0 else t.bank_die
		label:="ROBOT" if i==0 else "BANCO"
		if t.settled {label=fmt.tprintf("%s / %d",label,value)}
		ui.draw_text_fit(f.theme,label,{p.x-100,p.y+77,200,30},.Body,CYAN if i==0 else PINK,.Center)
	}
	ui.draw_text_fit(f.theme,"D20",{a.x+a.width*.44,a.y+a.height*.42,a.width*.12,40},.Large,GOLD,.Center)
}
