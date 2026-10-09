package render

import "core:c"
import "core:fmt"
import "core:math"
import rl "vendor:raylib"
import rlgl "vendor:raylib/rlgl"
import game "../game"

m8_active_bar_bounds :: proc(renderer: ^Renderer) -> rl.Rectangle {
    width := min(f32(770), renderer.canvas_width-28)
    return {(renderer.canvas_width-width)*0.5, renderer.canvas_height-217, width, 26}
}

m8_tesla_control_labels :: proc(room: ^game.Room) -> (title, detail: cstring) {
    title="ATTIVA"
    if room == nil {return title,"NESSUN OGGETTO ATTIVO"}
    network := game.query_board_device_network(room)
    if network.count == 0 {return title,"NESSUN OGGETTO ATTIVO"}
    cooldown: i32
    for object in room.objects {
        if object.kind == .Tesla_Coil {cooldown=max(cooldown,object.device_cooldown)}
    }
    if network.field {
        return "ATTIVA MEGA","CONSUMA 4 / FUOCO AMICO" if cooldown == 0 else fmt.ctprintf("RICARICA %ds / CONSUMA 4",cooldown)
    }
    if cooldown > 0 {return title,fmt.ctprintf("TESLA %d/4 / RICARICA %ds",network.count,cooldown)}
    if network.count >= 2 {return title,fmt.ctprintf("TESLA %d/4 / PARETI RIUSABILI",network.count)}
    return title,"TESLA 1/4 / SERVONO 2"
}

draw_m8_active_bar :: proc(renderer: ^Renderer, room: ^game.Room) {
    if room == nil || room.player == nil { return }
    b := m8_active_bar_bounds(renderer)
    w := b.width*0.28
    ready := m8_control_enabled(renderer,room,.Activate)
    floors := game.board_device_count(room, .Shock_Floor)
    charges: i32
    triggered := 0
    for object in room.objects {
        if object.kind == .Shock_Floor {
            charges+=object.device_charges
            if object.device_armed { triggered+=1 }
        }
    }
    title,label := m8_tesla_control_labels(room)
    m8_mouse_button(renderer,m8_control_bounds(renderer,.Activate),title,ready,label)
    // Passive traps have a read-only status strip, separate from the Tesla button.
    if floors > 0 {
        status := rl.Rectangle{b.x,b.y-20,min(b.width,440),17}
        rl.DrawRectangleRec(status,GOTHIC_RECESS)
        rl.DrawRectangleRec({status.x,status.y,2,status.height},GOTHIC_BLUE if triggered > 0 else GOTHIC_STEEL)
        gothic_text_fit(renderer,fmt.ctprintf("TRAPPOLE / IN ATTESA %d / INNESCATE %d / COLPI %d",floors-triggered,triggered,charges),
            {status.x+7,status.y+1,status.width-14,15},11,GOTHIC_BLUE if triggered > 0 else GOTHIC_MUTED)
    }
    equipment := &room.player.equipment
    name: cstring = "ARMA: MANI NUDE"
    if def, found := game.weapon_definition(equipment.weapon.id); found {
        name = fmt.ctprintf("%s / %d USI", def.name, equipment.weapon.uses_remaining)
    }
    tactical_hud_panel({b.x+w+5,b.y,w+44,b.height}, GOTHIC_BLUE)
    gothic_text_fit(renderer, name, {b.x+w+13,b.y+5,w+30,17}, 12, GOTHIC_PAPER)
    m8_mouse_button(renderer,m8_control_bounds(renderer,.Equip),"EQUIPAGGIA",m8_control_enabled(renderer,room,.Equip))
    m8_mouse_button(renderer,m8_control_bounds(renderer,.Character),"PERSONAGGIO",m8_control_enabled(renderer,room,.Character))
    if room.phase == .Loot && !room.ring_challenge_attempted {
        m8_mouse_button(renderer,m8_control_bounds(renderer,.Ring),"SFIDA DEL RING",m8_control_enabled(renderer,room,.Ring))
    }
}

// A faceted, genuinely volumetric inspectable miniature. Its lantern, mask,
// shoulders, robe and boots have distinct depth rather than a billboard card.
draw_m8_character_model :: proc(renderer: ^Renderer, position: rl.Vector3, angle: f32 = 0) {
    rlgl.PushMatrix()
    rlgl.Translatef(position.x, position.y, position.z)
    rlgl.Rotatef(angle, 0, 1, 0)
    paper := rl.Color{205, 192, 157, 255}
    dark := rl.Color{18, 26, 35, 255}
    for side in ([2]f32{-1,1}) {
        draw_resin_cube(renderer, {side*0.14,0.10,0.04}, 0.20,0.20,0.34, dark)
        draw_resin_cube(renderer, {side*0.29,0.77,0}, 0.18,0.37,0.26, paper)
        draw_resin_cube(renderer, {side*0.32,0.56,0.07}, 0.16,0.15,0.18, {96,70,48,255})
    }
    for i in 0..<4 {
        width := 0.68-f32(i)*0.08
        draw_resin_cube(renderer, {0,0.25+f32(i)*0.15,0}, width,0.19,0.36-f32(i)*0.025, dark)
        draw_resin_cube(renderer, {-width*0.35,0.25+f32(i)*0.15,-0.035}, width*0.32,0.19,0.35, paper)
    }
    draw_resin_cube(renderer, {0,0.80,0}, 0.52,0.20,0.34, paper)
    draw_resin_cube(renderer, {0,1.08,0}, 0.51,0.35,0.42, paper)
    for i in 0..<4 {
        draw_resin_cube(renderer,{0,1.27+f32(i)*0.065,-f32(i)*0.018},0.44-f32(i)*0.085,0.09,0.36-f32(i)*0.04,paper)
    }
    draw_resin_cube(renderer, {0,1.10,0.23}, 0.32,0.32,0.03, {5,10,18,255})
    for side in ([2]f32{-1,1}) { rl.DrawCube({side*0.075,1.10,0.255}, 0.046,0.036,0.018, GOTHIC_BLUE) }
    draw_resin_cube(renderer, {0,0.74,0.19}, 0.12,0.12,0.04, GOTHIC_RED)
    draw_resin_cube(renderer, {0.37,0.39,0.12}, 0.20,0.28,0.18, RESIN_CAP)
    rl.DrawCube({0.37,0.39,0.22}, 0.13,0.18,0.025, GOTHIC_BLUE)
    for y in ([2]f32{0.25,0.54}) { draw_resin_cube(renderer, {0.37,y,0.12}, 0.24,0.05,0.22, dark) }
    rlgl.PopMatrix()
}

draw_m8_character_panel :: proc(renderer: ^Renderer, room: ^game.Room) {
    if renderer == nil || room == nil || room.player == nil { return }
    width, height := renderer.canvas_width, renderer.canvas_height
    rl.DrawRectangleRec({0,0,width,height}, {3,7,13,225})
    panel := rl.Rectangle{36,38,width-72,height-76}
    gothic_frame(panel, {11,19,29,250}, GOTHIC_STEEL)
    gothic_text(renderer, "VIANDANTE / ARCHIVIO", panel.x+22,panel.y+15,24,GOTHIC_PAPER)
    gothic_text(renderer,"TEMPO SOSPESO",panel.x+22,panel.y+46,12,GOTHIC_MUTED)
    m8_mouse_button(renderer,m8_modal_control_bounds(renderer,.Close_Character),"CHIUDI")
    left := rl.Rectangle{panel.x+12,panel.y+82,panel.width*0.40,panel.height-105}
    rl.BeginScissorMode(c.int(left.x),c.int(left.y),c.int(left.width),c.int(left.height))
    camera := rl.Camera3D{position={2.8,2.5,6.0},target={1.42,0.88,0},up={0,1,0},fovy=3.9,projection=.ORTHOGRAPHIC}
    rl.BeginMode3D(camera)
    angle := f32(math.sin(renderer.sprite_assets.elapsed*0.35))*16-18
    draw_resin_cube(renderer, {0,-0.13,0},1.65,0.23,1.4,RESIN_DARK)
    rl.DrawCubeWires({0,-0.01,0},1.56,0.01,1.31,GOTHIC_BLUE)
    lit := begin_m8_model_lighting(renderer,camera)
    draw_m8_character_model(renderer, {}, angle)
    if lit { rl.EndShaderMode() }
    rl.EndMode3D()
    rl.EndScissorMode()
    x, y := panel.x+panel.width*0.46, panel.y+92
    w := panel.width*0.50-16
    player := room.player
    lines := [7]cstring{
        fmt.ctprintf("+ VITA       %d / %d",player.health,player.stats.max_health),
        fmt.ctprintf("/ ATTACCO    %d",game.player_basic_attack_damage(player)),
        fmt.ctprintf("# DIFESA     %d",player.stats.defense),
        fmt.ctprintf("* ENERGIA    %d / %d",player.deck.energy,player.deck.rules.max_energy),
        fmt.ctprintf("$ ORO        %d",player.gold),
        fmt.ctprintf("> RING       %d VITTORIE",player.m8_profile.ring_wins),
        fmt.ctprintf("^ LEGGENDA   %d / 3",min(u32(3),player.m8_profile.ring_wins)),
    }
    for line,index in lines { gothic_text_fit(renderer,line,{x,y+f32(index)*25,w,23},18,GOTHIC_BLUE if index == 6 else GOTHIC_PAPER) }
    y += 187
    gothic_rule(x,y,w,GOTHIC_STEEL)
    equipment := player.equipment
    weapon: cstring = "ARMA / MANI NUDE"
    if def, found := game.weapon_definition(equipment.weapon.id); found { weapon=fmt.ctprintf("ARMA / %s / %d USI",def.name,equipment.weapon.uses_remaining) }
    gothic_text_fit(renderer,weapon,{x,y+10,w,22},14,GOTHIC_PAPER)
    reserve: cstring = "RISERVA / VUOTA"
    if def, found := game.weapon_definition(equipment.reserve.id); found { reserve=fmt.ctprintf("RISERVA / %s / %d USI",def.name,equipment.reserve.uses_remaining) }
    gothic_text_fit(renderer,reserve,{x,y+36,w,22},14,GOTHIC_BLUE)
    gothic_text_fit(renderer,fmt.ctprintf("PASSIVE / %d RELIQUIE",player.relics.count),{x,y+66,w,20},14,GOTHIC_MUTED)
    columns := 2 if w >= 320 else 1
    rows := max(0,int((panel.y+panel.height-16-(y+88))/18))
    capacity := columns*rows
    shown := min(player.relics.count,capacity)
    if shown < player.relics.count { shown=max(0,shown-1) }
    for id,index in player.relics.owned[:shown] {
        if def, found := game.relic_definition(id); found {
            column_width := w/f32(columns)
            gothic_text_fit(renderer,fmt.ctprintf("%s  %s",relic_mark(id),def.name),
                {x+f32(index%columns)*column_width,y+88+f32(index/columns)*18,column_width-8,17},12,relic_color(id))
        }
    }
    if shown < player.relics.count && capacity > 0 {
        gothic_text_fit(renderer,fmt.ctprintf("+ %d ALTRE PASSIVE",player.relics.count-shown),
            {x+f32(shown%columns)*w/f32(columns),y+88+f32(shown/columns)*18,w/f32(columns)-8,17},12,GOTHIC_MUTED)
    }
}


begin_m8_model_lighting :: proc(renderer: ^Renderer, camera: rl.Camera3D) -> bool {
    v := &renderer.tactical
    if v.light_shader.id == 0 { return false }
    eye, light := camera.position, rl.Vector3{-2,4,3}
    mode: c.int = 2
    rl.SetShaderValue(v.light_shader,v.light_eye_location,&eye,.VEC3)
    rl.SetShaderValue(v.light_shader,v.light_position_location,&light,.VEC3)
    rl.SetShaderValue(v.light_shader,v.light_hologram_location,&mode,.INT)
    rl.BeginShaderMode(v.light_shader)
    return true
}
