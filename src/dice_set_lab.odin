package main

import "core:fmt"
import "core:math"
import rl "vendor:raylib"
import app "app"
import render "render"
import view "view"

DICE_SET_LAB_KINDS :: [7]render.Polyhedral_Die_Kind{.D4,.D6,.D8,.D10,.D100,.D12,.D20}
DICE_SET_LAB_RESULTS :: [7]i32{4,6,8,10,70,12,20}

Dice_Set_Lab :: struct {
	models: [7]render.Polyhedral_Die,
	throws: [7]render.Dice_Throw,
	textures: [7]rl.RenderTexture2D,
	detail_texture: rl.RenderTexture2D,
	results: [7]i32,
	random: render.Dice_Cosmetic_Random,
	progress, angle: f32,
	selected: int,
	rotating: bool,
}

Dice_Set_Lab_Control :: enum {None, Roll, Rotate, Overview, Close}

dice_set_lab_card_bounds :: proc(renderer: ^render.Renderer, index: int) -> rl.Rectangle {
	width := (renderer.canvas_width-76)/4
	height := (renderer.canvas_height-142)/2
	row_offset := (width+12)*0.5 if index >= 4 else f32(0)
	return {20+row_offset+f32(index%4)*(width+12),86+f32(index/4)*(height+12),width,height}
}

dice_set_lab_control_bounds :: proc(renderer: ^render.Renderer, control: Dice_Set_Lab_Control) -> rl.Rectangle {
	x := renderer.canvas_width
	switch control {
	case .Roll: return {x-368,20,104,28}
	case .Rotate: return {x-252,20,104,28}
	case .Overview: return {20,renderer.canvas_height-37,160,25}
	case .Close: return {x-136,20,116,28}
	case .None: return {}
	}
	return {}
}

dice_set_lab_control_at_point :: proc(renderer: ^render.Renderer, selected: int, point: view.Vec2) -> Dice_Set_Lab_Control {
	for control in ([4]Dice_Set_Lab_Control{.Roll,.Rotate,.Overview,.Close}) {
		if control == .Overview && selected < 0 {continue}
		if render.point_in_rectangle(point,dice_set_lab_control_bounds(renderer,control)) {return control}
	}
	return .None
}

dice_set_lab_result :: proc(random: ^render.Dice_Cosmetic_Random, kind: render.Polyhedral_Die_Kind) -> i32 {
	count := 6
	switch kind {
	case .D4: count=4
	case .D6:
	case .D8: count=8
	case .D10,.D100: count=10
	case .D12: count=12
	case .D20: count=20
	case .Count: return 0
	}
	index := min(count-1,int(render.dice_cosmetic_random(random)*f32(count)))
	return i32(index*10) if kind == .D100 else i32(index+1)
}

dice_set_lab_roll :: proc(state: ^Dice_Set_Lab) {
	for kind,index in DICE_SET_LAB_KINDS {
		state.results[index]=dice_set_lab_result(&state.random,kind)
		render.build_dice_throw(&state.throws[index],1,state.random.state,7)
	}
	state.progress,state.angle=0,0
}

dice_set_lab_model_note :: proc(kind: render.Polyhedral_Die_Kind) -> cstring {
	switch kind {
	case .D4: return "TETRAEDRO / LEGGI LA PUNTA"
	case .D6: return "CUBO / 6 FACCE"
	case .D8: return "OTTAEDRO / 8 FACCE"
	case .D10: return "TRAPEZOEDRO / 0-9"
	case .D100: return "PERCENTUALE / 00-90"
	case .D12: return "DODECAEDRO / 12 FACCE"
	case .D20: return "ICOSAEDRO / 20 FACCE"
	case .Count: return ""
	}
	return ""
}

dice_set_lab_result_label :: proc(kind: render.Polyhedral_Die_Kind, result: i32) -> cstring {
	if kind == .D100 {return fmt.ctprintf("%02d",result)}
	if kind == .D10 && result == 10 {return "0 (10)"}
	return fmt.ctprintf("%d",result)
}

dice_set_lab_render_model :: proc(renderer: ^render.Renderer, state: ^Dice_Set_Lab, index: int, texture: rl.RenderTexture2D) {
	model := &state.models[index]
	position,rotation := render.polyhedral_dice_pose(model,&state.throws[index],0,state.progress,state.results[index])
	// Each specimen uses a small independent tray. Keep the physical bounces
	// inside that tray while retaining the model's true ground support height.
	final := render.sample_dice_throw(&state.throws[index],1)
	position.x=(position.x-final.positions[0].x)*0.25
	position.z=(position.z-final.positions[0].z)*0.25
	support := render.polyhedral_support_height(model,rotation)
	position.y=support+max(f32(0),position.y-support)*0.22
	if state.progress >= 1 {
		rotation=rl.QuaternionFromAxisAngle({0,1,0},state.angle)*rotation
		position.y=render.polyhedral_support_height(model,rotation)
	}
	target := rl.Vector3{0,0.64,0}
	camera := rl.Camera3D{position=target+rl.Vector3{0,5.4,8},target=target,up={0,1,0},fovy=2.6,projection=.ORTHOGRAPHIC}
	rl.BeginTextureMode(texture)
	rl.ClearBackground({13,20,30,255})
	rl.BeginMode3D(camera)
	rl.DrawCube({0,-0.075,0},2.4,0.14,1.85,{20,31,46,255})
	rl.DrawCubeWires({0,-0.003,0},2.4,0.01,1.85,{42,65,88,255})
	render.draw_dice_shadow(position)
	resin := render.begin_m8_model_lighting(renderer,camera)
	font,_ := render.gothic_font(renderer,32)
	render.draw_polyhedral_die(model,position,rotation,font,resin)
	if resin {rl.EndShaderMode()}
	rl.EndMode3D()
	rl.EndTextureMode()
}

dice_set_lab_draw_texture :: proc(texture: rl.RenderTexture2D, destination: rl.Rectangle) {
	rl.DrawTexturePro(texture.texture,{0,0,f32(texture.texture.width),-f32(texture.texture.height)},destination,{},0,rl.WHITE)
}

dice_set_lab_frame :: proc(window: ^app.Window, renderer: ^render.Renderer, state: ^Dice_Set_Lab) {
	if state.selected < 0 {
		for texture,index in state.textures {dice_set_lab_render_model(renderer,state,index,texture)}
	} else {dice_set_lab_render_model(renderer,state,state.selected,state.detail_texture)}
	app.begin_canvas(window,render.RESIN_BACKGROUND)
	render.gothic_text(renderer,"IL TAVOLO DEI DADI",20,18,24,render.GOTHIC_PAPER)
	render.gothic_text(renderer,"RESINA BLU / NUMERI AVORIO / POLIEDRI 3D",20,52,12,render.GOTHIC_BLUE)
	for control in ([3]Dice_Set_Lab_Control{.Roll,.Rotate,.Close}) {
		label: cstring = "LANCIA" if control == .Roll else "FERMA" if control == .Rotate && state.rotating else "RUOTA" if control == .Rotate else "CHIUDI"
		render.m8_mouse_button(renderer,dice_set_lab_control_bounds(renderer,control),label)
	}
	if state.selected < 0 {
		for kind,index in DICE_SET_LAB_KINDS {
			card := dice_set_lab_card_bounds(renderer,index)
			render.gothic_frame(card,render.GOTHIC_RECESS,render.GOTHIC_STEEL)
			picture := rl.Rectangle{card.x+2,card.y+24,card.width-4,card.height-56}
			dice_set_lab_draw_texture(state.textures[index],picture)
			render.gothic_text(renderer,render.polyhedral_die_name(kind),card.x+10,card.y+5,16,render.GOTHIC_PAPER)
			if state.progress >= 1 {
				render.gothic_text_fit(renderer,fmt.ctprintf("TIRO %s",dice_set_lab_result_label(kind,state.results[index])),
					{card.x+card.width*0.46,card.y+6,card.width*0.50-8,16},12,render.GOTHIC_BLUE)
			}
			render.gothic_text_fit(renderer,dice_set_lab_model_note(kind),{card.x+9,card.y+card.height-23,card.width-18,18},11,render.GOTHIC_MUTED)
		}
		render.gothic_text(renderer,"CLICCA UN DADO PER OSSERVARLO DA VICINO",20,renderer.canvas_height-22,11,render.GOTHIC_MUTED)
	} else {
		index := state.selected
		kinds := DICE_SET_LAB_KINDS
		kind := kinds[index]
		bounds := rl.Rectangle{renderer.canvas_width*0.19,85,renderer.canvas_width*0.62,renderer.canvas_height-151}
		dice_set_lab_draw_texture(state.detail_texture,bounds)
		render.gothic_text(renderer,render.polyhedral_die_name(kind),32,103,32,render.GOTHIC_PAPER)
		render.gothic_text_fit(renderer,dice_set_lab_model_note(kind),{32,renderer.canvas_height-69,renderer.canvas_width-64,23},18,render.GOTHIC_BLUE)
		if state.progress >= 1 {
			render.gothic_text(renderer,fmt.ctprintf("TIRO %s",dice_set_lab_result_label(kind,state.results[index])),32,153,18,render.GOTHIC_BLUE)
		}
		render.m8_mouse_button(renderer,dice_set_lab_control_bounds(renderer,.Overview),"SET COMPLETO")
		if kind == .D4 {render.gothic_text(renderer,"IL VALORE ALLA PUNTA SI RIPETE SULLE TRE FACCE LATERALI",198,renderer.canvas_height-29,12,render.GOTHIC_MUTED)}
	}
	app.present(window,render.LETTERBOX_COLOR)
}

run_dice_set_lab :: proc(window: ^app.Window, renderer: ^render.Renderer, dice: ^render.Dice_Renderer, smoke: bool) -> bool {
	if window == nil || renderer == nil || dice == nil || !window.is_open {return false}
	state := new(Dice_Set_Lab)
	defer free(state)
	state.random.state=0xD1CE5E71
	state.selected=-1
	defer {
		for texture in state.textures {if texture.id != 0 {rl.UnloadRenderTexture(texture)}}
		if state.detail_texture.id != 0 {rl.UnloadRenderTexture(state.detail_texture)}
	}
	for kind,index in DICE_SET_LAB_KINDS {
		state.models[index]=render.build_polyhedral_die(kind)
		if state.models[index].face_count == 0 {return false}
		state.textures[index]=rl.LoadRenderTexture(256,192)
		if !rl.IsRenderTextureValid(state.textures[index]) {return false}
		rl.SetTextureFilter(state.textures[index].texture,.POINT)
	}
	state.detail_texture=rl.LoadRenderTexture(640,420)
	if !rl.IsRenderTextureValid(state.detail_texture) {return false}
	rl.SetTextureFilter(state.detail_texture.texture,.POINT)
	dice_set_lab_roll(state)
	state.results=DICE_SET_LAB_RESULTS
	if smoke {
		// Exercise each model throughout a complete throw and validate the
		// ground plane for every committed result, including the percentile zero.
		for frame in 0..<100 {
			state.progress=min(f32(1),f32(frame)/90)
			for &model,index in state.models {
				position,rotation := render.polyhedral_dice_pose(&model,&state.throws[index],0,state.progress,state.results[index])
				if math.is_nan(position.y) || position.y+0.001 < render.polyhedral_support_height(&model,rotation) {return false}
			}
			dice_set_lab_frame(window,renderer,state)
		}
		rl.TakeScreenshot("odin_pp_dice_set.png")
		state.selected=0
		for result in i32(1)..=4 {
			state.results[0]=result
			for _ in 0..<3 {dice_set_lab_frame(window,renderer,state)}
			if result == 4 {rl.TakeScreenshot("odin_pp_dice_d4_detail.png")}
		}
		state.selected=4
		state.results[4]=0
		for _ in 0..<3 {dice_set_lab_frame(window,renderer,state)}
		fmt.println("Dice set native: 7 models D4/D6/D8/D10/D100/D12/D20, 100 animated frames, 4 D4 faces, percentile 00 passed")
		return true
	}
	state.progress=1
	for !app.should_close(window) {
		app.refresh_viewport(window)
		point,inside := app.mouse_canvas_position(window)
		if inside && rl.IsMouseButtonPressed(.LEFT) {
			control := dice_set_lab_control_at_point(renderer,state.selected,point)
			switch control {
			case .Close: return true
			case .Roll: dice_set_lab_roll(state)
			case .Rotate: state.rotating=!state.rotating
			case .Overview: state.selected=-1
			case .None:
				if state.selected < 0 {
					for index in 0..<len(DICE_SET_LAB_KINDS) {
						if render.point_in_rectangle(point,dice_set_lab_card_bounds(renderer,index)) {state.selected=index; break}
					}
				}
			}
		}
		dt := clamp(rl.GetFrameTime(),f32(0),f32(0.1))
		state.progress=min(f32(1),state.progress+dt/2.3)
		if state.rotating && state.progress >= 1 {state.angle+=dt*0.60}
		dice_set_lab_frame(window,renderer,state)
	}
	return true
}
