package render

import "core:fmt"
import "core:math"
import engine "../engine"
import fight "../fight"
import shooter "../shooter"
import view "../view"
import rl "vendor:raylib"
import rlgl "vendor:raylib/rlgl"

m9_vector :: proc(v: engine.Vec3) -> rl.Vector3 {return {v.x,v.y,v.z}}
m9_mix_position :: proc(a,b: engine.Vec3, alpha: f32) -> rl.Vector3 {
	return m9_vector(a)+(m9_vector(b)-m9_vector(a))*clamp(alpha,0,1)
}

// Reuse the pixel cutout and its independent paper border, with no tactical
// timeline feedback: another suspended mode cannot select this actor's pose.
draw_m9_actor :: proc(renderer: ^Renderer, key: Sprite_Key, position: rl.Vector3, lean: f32 = 0, angle: f32 = 0, tint: rl.Color = rl.WHITE, body_height: f32 = fight.BODY_HEIGHT) {
	p := view.Vec2{position.x-0.5,position.z-0.5}
	quad := tactical_billboard_geometry(renderer,key,p,false)
	// The tactical atlas uses decorative heights per archetype. Free modes
	// instead fit its paper figure to the physical body, independent of pose.
	base := (quad.points[1]+quad.points[2])*0.5
	height := rl.Vector3Distance(quad.points[0],quad.points[1])
	if height>0.001 {for &point in quad.points {point=base+(point-base)*(body_height/height)}}
	quad=m8_ring_transform_quad(quad,position.y,angle,lean)
	draw_tactical_billboard_quad(renderer,quad,p,1,tint)
}

draw_m9_contact_shadow :: proc(position: rl.Vector3, radius: f32) {
	// Bounded contact shading anchors cutouts without a per-actor shadow map.
	shadow_radius:=radius
	if position.y>0.05 {shadow_radius*=max(f32(0.4),1-position.y*0.2)}
	rl.DrawCylinderEx({position.x,0.006,position.z},{position.x,0.009,position.z},shadow_radius*1.2,shadow_radius*1.2,20,{15,23,35,255})
	rl.DrawCylinderEx({position.x,0.010,position.z},{position.x,0.013,position.z},shadow_radius*0.76,shadow_radius*0.76,20,{9,15,24,255})
}

m9_world_extent :: proc(world: ^engine.World) -> rl.Vector2 {
	x,z := f32(4.8),f32(4.8)
	for solid in world.solids[:world.solid_count] {
		x=max(x,max(abs(solid.bounds.min.x),abs(solid.bounds.max.x)))
		z=max(z,max(abs(solid.bounds.min.z),abs(solid.bounds.max.z)))
	}
	return {x,z}
}

draw_m9_geometry :: proc(renderer: ^Renderer, world: ^engine.World, ring: bool, debug: bool) {
	extent := m9_world_extent(world)
	draw_resin_cube(renderer,{0,-0.22,0},extent.x*2+0.5,0.42,extent.y*2+0.5,RESIN_DARK)
	draw_resin_cube(renderer,{0,-0.02,0},extent.x*2,0.035,extent.y*2,{35,48,66,255})
	for solid in world.solids[:world.solid_count] {
		a,b := m9_vector(solid.bounds.min),m9_vector(solid.bounds.max)
		center,size := (a+b)*0.5,b-a
		if ring {
			center.y,size.y=0.16,0.32
			draw_resin_cube_v(renderer,center,size,RESIN_WALL)
			for y in ([3]f32{0.55,0.95,1.35}) {
				along_x := size.x>size.z
				p,q := center,center
				p.y,q.y=y,y
				if along_x {p.x=a.x;q.x=b.x} else {p.z=a.z;q.z=b.z}
				rl.DrawCylinderEx(p,q,0.025,0.025,5,{106,116,140,255})
			}
		} else {
			draw_resin_cube_v(renderer,center,size,RESIN_WALL)
			// Trim follows the same solid bounds; it adds no apparent playable
			// ledges or pillars that the continuous controller could pass through.
			draw_resin_cube(renderer,{center.x,a.y+0.09,center.z},size.x+0.018,0.18,size.z+0.018,RESIN_DARK)
			draw_resin_cube(renderer,{center.x,b.y+0.018,center.z},size.x+0.025,0.05,size.z+0.025,RESIN_CAP)
			draw_resin_cube(renderer,{center.x,b.y-0.08,center.z},size.x+0.012,0.028,size.z+0.012,{34,60,87,255})
			long_wall:=size.x>5 || size.z>5
			if long_wall {
				along_x:=size.x>size.z
				length:=size.x if along_x else size.z
				panels:=int(length/2.7)
				for panel in 0..<panels {
					p:=center
					offset:=(f32(panel)+0.5)*length/f32(panels)-length/2
					if along_x {p.x+=offset} else {p.z+=offset}
					p.y=a.y+size.y*0.48
					stripe:=rl.Vector3{0.026,size.y*0.60,size.z+0.024} if along_x else rl.Vector3{size.x+0.024,size.y*0.60,0.026}
					draw_resin_cube_v(renderer,p,stripe,{27,43,63,255})
					p.y=a.y+size.y*0.66
					stripe.y=0.24
					draw_resin_cube_v(renderer,p,stripe,{52,105,150,255})
				}
			} else if size.y>2 {
				rl.DrawCube({center.x,a.y+size.y*0.46,center.z},size.x+0.02,0.045,size.z+0.02,{46,122,181,255})
				rl.DrawCube({center.x,a.y+size.y*0.65,center.z},0.14,0.44,size.z+0.025,RESIN_DARK)
				rl.DrawCube({center.x,a.y+size.y*0.65,center.z},0.03,0.23,size.z+0.03,{51,133,191,255})
			} else {
				for side in ([2]f32{-1,1}) {
					rl.DrawCube({center.x+side*size.x*0.35,b.y+0.045,center.z},0.045,0.018,max(f32(0.1),size.z-0.2),{91,111,135,255})
				}
			}
		}
		if debug {rl.DrawBoundingBox({a,b},{70,190,230,180})}
	}
	if ring {
		for x in ([2]f32{-4.45,4.45}) {for z in ([2]f32{-4.45,4.45}) {
			draw_resin_cube(renderer,{x,0.76,z},0.24,1.52,0.24,RESIN_CAP)
			rl.DrawCube({x,1.58,z},0.28,0.08,0.28,GOTHIC_BLUE)
		}}
	}
}

draw_m9_floor_marks :: proc(world: ^engine.World) {
	extent:=m9_world_extent(world)
	x,z:=extent.x-0.85,extent.y-0.85
	// Inlaid perimeter seams and radial ornament communicate continuous space
	// without reintroducing a tactical checkerboard.
	for sign in ([2]f32{-1,1}) {
		rl.DrawLine3D({-x,0.015,sign*z},{x,0.015,sign*z},{58,77,103,255})
		rl.DrawLine3D({sign*x,0.015,-z},{sign*x,0.015,z},{58,77,103,255})
		rl.DrawLine3D({-x,0.015,sign*(z-0.09)},{x,0.015,sign*(z-0.09)},{22,33,50,255})
		rl.DrawLine3D({sign*(x-0.09),0.015,-z},{sign*(x-0.09),0.015,z},{22,33,50,255})
	}
	rl.DrawCircle3D({0,0.015,0},2.15,{1,0,0},90,{73,93,119,255})
	rl.DrawCircle3D({0,0.018,0},2.27,{1,0,0},90,{52,71,98,255})
	for i in 0..<8 {
		a := f32(i)*math.PI/4
		rl.DrawLine3D({math.cos(a)*2.1,0.02,math.sin(a)*2.1},{math.cos(a)*2.42,0.02,math.sin(a)*2.42},{102,123,155,255})
		for sign in ([2]f32{-1,1}) {
			b:=a+sign*0.065
			rl.DrawLine3D({math.cos(a)*2.6,0.02,math.sin(a)*2.6},{math.cos(b)*2.36,0.02,math.sin(b)*2.36},{60,101,143,255})
		}
	}
	rl.DrawLine3D({-0.20,0.019,0},{0,0.019,-0.37},{49,71,96,255})
	rl.DrawLine3D({0,0.019,-0.37},{0.20,0.019,0},{49,71,96,255})
	rl.DrawLine3D({0.20,0.019,0},{0,0.019,0.37},{49,71,96,255})
	rl.DrawLine3D({0,0.019,0.37},{-0.20,0.019,0},{49,71,96,255})
	for trigger in world.triggers[:world.trigger_count] {
		p := (m9_vector(trigger.bounds.min)+m9_vector(trigger.bounds.max))*0.5
		draw_tactical_rune({p.x,0.035,p.z},0.5,0,GOTHIC_BLUE)
	}
}

draw_m9_body_debug :: proc(body: engine.Body, color: rl.Color) {
	p := m9_vector(body.position)
	rl.DrawCylinderWiresEx(p+rl.Vector3{0,body.radius,0},p+rl.Vector3{0,body.height-body.radius,0},body.radius,body.radius,12,color)
	rl.DrawSphereWires(p+rl.Vector3{0,body.radius,0},body.radius,5,8,color)
	rl.DrawSphereWires(p+rl.Vector3{0,body.height-body.radius,0},body.radius,5,8,color)
}

m9_weapon_quad :: proc(origin: rl.Vector2, scale: f32, local: [4]rl.Vector2, color: rl.Color) {
	points: [4]rl.Vector2
	for p,i in local {
		q:=origin+p*scale
		points[i]={math.floor(q.x/2)*2,math.floor(q.y/2)*2}
	}
	rl.DrawTriangle(points[0],points[2],points[1],color)
	rl.DrawTriangle(points[0],points[3],points[2],color)
}

draw_m9_weapon :: proc(renderer: ^Renderer, state: ^shooter.State) {
	// A few snapped planes form a hand cannon with a readable muzzle, slide,
	// sight and gloved grip; the screen-space illustration has no hit volume.
	w,h:=renderer.canvas_width,renderer.canvas_height
	scale:=clamp(w/960,f32(0.75),f32(1.4))
	reload_drop:=f32(0)
	if state.player.reload_remaining>0 {
		reload_drop=28*math.sin(state.player.reload_remaining/shooter.RELOAD_DURATION*math.PI)
	}
	origin:=rl.Vector2{w*0.73,h-12+(state.player.recoil*22+reload_drop)*scale}
	m9_weapon_quad(origin,scale,{{16,-24},{68,-9},{109,69},{47,87}},{12,18,27,255})
	m9_weapon_quad(origin,scale,{{26,-16},{60,-3},{95,62},{51,75}},{100,100,94,255})
	m9_weapon_quad(origin,scale,{{39,3},{60,8},{83,52},{61,57}},{176,165,139,255})
	m9_weapon_quad(origin,scale,{{15,-40},{57,-27},{58,56},{26,43}},{6,11,18,255})
	m9_weapon_quad(origin,scale,{{24,-34},{47,-25},{47,37},{33,29}},{32,42,56,255})
	for offset in 0..<3 {
		y:=f32(offset)*10
		m9_weapon_quad(origin,scale,{{28,-12+y},{45,-7+y},{45,-3+y},{29,-8+y}},{56,69,86,255})
	}
	m9_weapon_quad(origin,scale,{{-30,-105},{11,-124},{84,-39},{47,-12}},{7,12,21,255})
	m9_weapon_quad(origin,scale,{{-20,-102},{10,-113},{70,-41},{46,-23}},RESIN_CAP)
	m9_weapon_quad(origin,scale,{{-19,-88},{7,-97},{58,-34},{43,-28}},{37,53,72,255})
	m9_weapon_quad(origin,scale,{{-5,-89},{3,-91},{40,-47},{32,-43}},{69,154,206,255})
	m9_weapon_quad(origin,scale,{{-37,-116},{-9,-135},{9,-116},{-21,-96}},{7,12,20,255})
	m9_weapon_quad(origin,scale,{{-31,-115},{-9,-128},{2,-116},{-20,-102}},{83,99,115,255})
	m9_weapon_quad(origin,scale,{{-25,-114},{-10,-123},{-4,-116},{-19,-107}},{6,10,16,255})
	m9_weapon_quad(origin,scale,{{5,-116},{12,-122},{21,-111},{14,-105}},{130,139,140,255})
	m9_weapon_quad(origin,scale,{{9,-117},{13,-120},{18,-114},{14,-111}},GOTHIC_BLUE)
	if state.shots[0].remaining>0.065 {
		muzzle:=origin+rl.Vector2{-31,-134}*scale
		rl.DrawRectangleRec({muzzle.x-7*scale,muzzle.y-16*scale,11*scale,30*scale},{96,168,220,255})
		rl.DrawRectangleRec({muzzle.x-17*scale,muzzle.y-4*scale,31*scale,9*scale},{131,196,232,255})
		rl.DrawRectangleRec({muzzle.x-7*scale,muzzle.y-7*scale,12*scale,14*scale},GOTHIC_PAPER)
		rl.DrawRectangleRec({muzzle.x-20*scale,muzzle.y-17*scale,5*scale,5*scale},GOTHIC_PAPER)
	}
}

draw_m9_fight :: proc(renderer: ^Renderer, state: ^fight.State, v: M9_View) {
	w,h := renderer.canvas_width,renderer.canvas_height
	rl.DrawRectangleRec({0,0,w,h},RESIN_BACKGROUND)
	extent := m9_world_extent(&state.world)
	camera := rl.Camera3D{position={9,11,14},target={0,0.4,0},up={0,1,0},fovy=max(extent.x,extent.y)*2.55,projection=.ORTHOGRAPHIC}
	if v.kind==.Ring {
		a:=m9_mix_position(state.fighters[0].previous,state.fighters[0].position,1 if v.paused else v.alpha)
		b:=m9_mix_position(state.fighters[1].previous,state.fighters[1].position,1 if v.paused else v.alpha)
		midpoint:=(a+b)*0.5
		camera.target=midpoint+rl.Vector3{0,0.62,0}
		camera.position=camera.target+rl.Vector3{4.8,5.8,8.8}
		camera.fovy=clamp(5.4+rl.Vector3Distance(a,b)*0.72,f32(6.6),f32(11.5))
	}
	previous,outline := renderer.tactical.camera,renderer.tactical.outline_mode
	renderer.tactical.camera,renderer.tactical.outline_mode=camera,.Ring
	defer {renderer.tactical.camera=previous;renderer.tactical.outline_mode=outline}
	rl.BeginMode3D(camera)
	lit := begin_m8_model_lighting(renderer,camera)
	draw_m9_geometry(renderer,&state.world,extent.x<6,v.debug)
	if lit {rl.EndShaderMode()}
	draw_m9_floor_marks(&state.world)
	for actor in state.fighters {draw_m9_contact_shadow(m9_vector(actor.position),fight.BODY_RADIUS)}
	// Sort cutouts by camera distance; depth still clips them against solid cover.
	order := [2]int{0,1}
	if rl.Vector3Distance(camera.position,m9_vector(state.fighters[0].position))<rl.Vector3Distance(camera.position,m9_vector(state.fighters[1].position)) {order={1,0}}
	rlgl.DrawRenderBatchActive(); rlgl.DisableDepthMask()
	for i in order {
		actor := state.fighters[i]
		p := m9_mix_position(actor.previous,actor.position,1 if v.paused else v.alpha)
		key := Sprite_Key.Player if i == 0 else .Brute
		lean,angle := f32(0),f32(0)
		tint := rl.WHITE
		if actor.action == .Jab || actor.action == .Heavy || actor.action == .Grab {
			if i == 0 {key=.Player_Cast}
			lean=0.16*actor.facing.x
		}
		if actor.action == .Hurt {tint={255,125,139,255}}
		if actor.action == .Guard {tint={165,210,250,255}}
		if actor.action == .Dodge {lean=-0.2*actor.facing.x;tint={190,225,255,255}}
		if state.throw_active {
			pose := m8_ring_pose(fight.throw_pose(state))
			if i == state.throw_victim {angle=pose.enemy_angle}
			if i == state.throw_attacker {lean=pose.player_lean;if i == 0 {key=.Player_Cast}}
		}
		draw_m9_actor(renderer,key,p,lean,angle,tint)
	}
	rlgl.DrawRenderBatchActive(); rlgl.EnableDepthMask()
	if v.debug {
		for body in state.world.actors[:state.world.actor_count] {draw_m9_body_debug(body,GOTHIC_BLUE)}
		for i in 0..<2 {
			hurt := fight.hurtbox(state,i)
			rl.DrawSphereWires(m9_vector(hurt.center),hurt.radius,6,10,{97,211,154,255})
			if hit,active := fight.hitbox(state,i); active {rl.DrawSphereWires(m9_vector(hit.center),hit.radius,6,10,GOTHIC_RED)}
		}
	}
	if state.hit_flash_ticks>0 {draw_tactical_rune(m9_vector(state.last_hit_position),0.45,0,GOTHIC_PAPER)}
	rl.EndMode3D()
	gothic_text(renderer,"M9 / ARENA LIBERA" if v.kind == .Arena else "IL RING DELLE OMBRE",20,17,23,GOTHIC_PAPER)
	for actor,i in state.fighters {
		x := f32(20) if i == 0 else w-242
		tactical_hud_panel({x,105,222,60},GOTHIC_BLUE if i == 0 else GOTHIC_RED)
		gothic_text(renderer,fmt.ctprintf("%s %d/%d","TU" if i == 0 else "CAMPIONE",actor.health,actor.max_health),x+10,111,20,GOTHIC_PAPER)
		gothic_text(renderer,fmt.ctprintf("%s / %df",m9_move_name(actor.action),actor.action_tick),x+10,138,12,GOTHIC_BLUE if i == 0 else GOTHIC_RED)
	}
	line: cstring = "WASD MUOVI / 1 PUGNO / 2 PESANTE / 3 PRESA / SPAZIO SCHIVA / SHIFT PARATA"
	gothic_text_fit(renderer,line,{20,h-121 if v.tools else h-42,w-40,20},13,GOTHIC_PAPER)
	if v.paused {gothic_text(renderer,"PAUSA / IL MONDO ESTERNO E' SOSPESO",20,h-145 if v.tools else h-70,13,GOTHIC_BLUE)}
	if state.result != .Active {
		tactical_hud_panel({w*0.5-190,h*0.5-32,380,65},GOTHIC_BLUE)
		gothic_text_fit(renderer,"VITTORIA" if state.result == .Won else "SCONFITTA",{w*0.5-175,h*0.5-20,350,24},24,GOTHIC_PAPER)
		gothic_text_fit(renderer,"TORNA ALLA STANZA O RIPROVA IN LABORATORIO",{w*0.5-175,h*0.5+9,350,20},12,GOTHIC_MUTED)
	}
	draw_m9_controls(renderer,v,&state.moves)
}

draw_m9_fps :: proc(renderer: ^Renderer, state, prior: ^shooter.State, v: M9_View) {
	w,h := renderer.canvas_width,renderer.canvas_height
	rl.DrawRectangleRec({0,0,w,h},{7,13,24,255})
	position := m9_mix_position(prior.player.position,state.player.position,1 if v.paused else v.alpha)
	eye := position+rl.Vector3{0,shooter.EYE_HEIGHT,0}
	direction := m9_vector(shooter.look_direction(state.player.yaw,state.player.pitch))
	camera := rl.Camera3D{position=eye,target=eye+direction,up={0,1,0},fovy=66,projection=.PERSPECTIVE}
	previous,outline := renderer.tactical.camera,renderer.tactical.outline_mode
	renderer.tactical.camera,renderer.tactical.outline_mode=camera,.World
	defer {renderer.tactical.camera=previous;renderer.tactical.outline_mode=outline}
	rl.BeginMode3D(camera)
	lit := begin_m8_model_lighting(renderer,camera)
	draw_m9_geometry(renderer,&state.world,false,v.debug)
	if lit {rl.EndShaderMode()}
	draw_m9_floor_marks(&state.world)
	for enemy in state.enemies[:state.enemy_count] {
		if enemy.health>0 {draw_m9_contact_shadow(m9_vector(enemy.position),shooter.ENEMY_RADIUS)}
	}
	order := [3]int{0,1,2}
	for i in 0..<state.enemy_count {for j in i+1..<state.enemy_count {
		if rl.Vector3Distance(eye,m9_vector(state.enemies[order[j]].position))>rl.Vector3Distance(eye,m9_vector(state.enemies[order[i]].position)) {order[i],order[j]=order[j],order[i]}
	}}
	rlgl.DrawRenderBatchActive();rlgl.DisableDepthMask()
	for index in order[:state.enemy_count] {
		enemy := state.enemies[index]
		if enemy.health<=0 {continue}
		p := m9_mix_position(prior.enemies[index].position,enemy.position,1 if v.paused else v.alpha)
		tint := rl.Color{255,142,95,255} if enemy.phase == .Windup else rl.WHITE
		if enemy.damage_flash>0 {tint={170,224,255,255}}
		draw_m9_actor(renderer,.Archer,p,0,0,tint,shooter.ENEMY_HEIGHT)
	}
	rlgl.DrawRenderBatchActive();rlgl.EnableDepthMask()
	for shot in state.shots {
		if shot.remaining>0 {rl.DrawLine3D(m9_vector(shot.start),m9_vector(shot.end),GOTHIC_RED if shot.enemy else GOTHIC_BLUE)}
	}
	if v.debug {for body in state.world.actors[:state.world.actor_count] {draw_m9_body_debug(body,GOTHIC_BLUE)}}
	rl.EndMode3D()
	draw_m9_weapon(renderer,state)
	color := GOTHIC_PAPER if state.hit_marker<=0 else GOTHIC_RED
	rl.DrawLineV({w/2-8,h/2},{w/2-3,h/2},color);rl.DrawLineV({w/2+3,h/2},{w/2+8,h/2},color)
	rl.DrawLineV({w/2,h/2-8},{w/2,h/2-3},color);rl.DrawLineV({w/2,h/2+3},{w/2,h/2+8},color)
	if state.player.damage_flash>0 {rl.DrawRectangleLinesEx({3,3,w-6,h-6},5,{209,45,70,210})}
	tactical_hud_panel({16,12,410,34},GOTHIC_BLUE)
	gothic_text(renderer,fmt.ctprintf("FPS / HP %d / MUNIZIONI %d + %d",state.player.health,state.player.ammo,state.player.reserve),25,17,18,GOTHIC_PAPER)
	gothic_text(renderer,fmt.ctprintf("%s / NEMICI %d",shooter.level_name(state.level_index),shooter.living_enemies(state)),20,104,16,GOTHIC_PAPER)
	if state.player.reload_remaining>0 {gothic_text(renderer,"RICARICA...",w/2-55,h/2+27,15,GOTHIC_BLUE)}
	gothic_text_fit(renderer,"WASD MUOVI / MOUSE MIRA / CLICK SPARA / R RICARICA / ESC MENU",{20,h-120 if v.tools else h-36,w-40,20},13,GOTHIC_PAPER)
	if v.paused || state.phase != .Active {
		bounds := m9_control_bounds(renderer,.Resume_FPS)
		if m9_control_enabled(v,.Resume_FPS) {
			m8_mouse_button(renderer,bounds,"CLICCA QUI PER GIOCARE")
			gothic_text_fit(renderer,"MOUSE MIRA / ESC TORNA IN PAUSA",{bounds.x+20,bounds.y+bounds.height+8,bounds.width-40,20},13,GOTHIC_MUTED)
		} else {
			tactical_hud_panel(bounds,GOTHIC_BLUE)
			title: cstring = "PAUSA / USA RIPRENDI IN ALTO"
			if state.phase == .Won {title="AREA LIBERATA"} else if state.phase == .Lost {title="SCONFITTA"}
			gothic_text_fit(renderer,title,{w/2-190,h/2-45,380,28},24,GOTHIC_PAPER)
			gothic_text_fit(renderer,"IL MONDO DELLA RUN RESTA SOSPESO",{w/2-190,h/2-9,380,20},13,GOTHIC_MUTED)
		}
	}
	draw_m9_controls(renderer,v)
}
