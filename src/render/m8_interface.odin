package render

import "core:c"
import "core:fmt"
import rl "vendor:raylib"
import game "../game"

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
    if m8_control_visible(room,.Activate) {
        title,label := m8_tesla_control_labels(room)
        m8_mouse_button(renderer,m8_control_bounds(renderer,.Activate,room),title,m8_control_enabled(renderer,room,.Activate),label)
    }
    floors := game.board_device_count(room,.Shock_Floor)
    charges: i32
    triggered := 0
    for object in room.objects {
        if object.kind == .Shock_Floor {charges+=object.device_charges; if object.device_armed {triggered+=1}}
    }
    if floors > 0 {
        status := m8_trap_status_bounds(renderer,room)
        gothic_text_fit(renderer,fmt.ctprintf("TRAPPOLE %d / ATTIVE %d / COLPI %d",floors,triggered,charges),
            status,11,GOTHIC_BLUE if triggered>0 else GOTHIC_MUTED)
    }
    equipment := &room.player.equipment
    if equipment.weapon.id != .None || equipment.reserve.id != .None {
        bounds := m8_weapon_bounds(renderer,room)
        hud_frame(bounds,HUD_AMBER)
        name: cstring = "ARMA IN RISERVA"
        if def,found := game.weapon_definition(equipment.weapon.id); found {name=fmt.ctprintf("%s / %d USI",def.name,equipment.weapon.uses_remaining)}
        gothic_text_fit(renderer,name,{bounds.x+9,bounds.y+6,bounds.width-18,18},12,GOTHIC_PAPER)
    }
    controls := [3]M8_Control{.Equip,.Ring,.FPS}
    labels := [3]cstring{"EQUIPAGGIA","SFIDA RING","CRIPTA DELLE RUNE"}
    for control,index in controls {
        if m8_control_visible(room,control) {m8_mouse_button(renderer,m8_control_bounds(renderer,control,room),labels[index],m8_control_enabled(renderer,room,control))}
    }
}

draw_m8_character_panel :: proc(renderer: ^Renderer, room: ^game.Room) {
    if renderer == nil || room == nil || room.player == nil { return }
    draw_character_sheet(renderer, room)
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
