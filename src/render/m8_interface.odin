package render

import "core:fmt"
import rl "vendor:raylib"
import game "../game"

m8_tesla_control_labels :: proc(query: game.Tesla_Control_Query) -> (title, detail: cstring) {
    title="ATTIVA"
    network := query.network
    if network.count == 0 {return title,"NESSUN OGGETTO ATTIVO"}
    cooldown := network.cooldown
    // A square around enemies opens the floor's ring instead of discharging.
    if query.ring.count > 0 {
        return "APRI IL RING","1 SFIDANTE / DUELLO" if query.ring.count == 1 else fmt.ctprintf("TAG MATCH / %d SFIDANTI",query.ring.count)
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
    if room.phase == .Combat || room.phase == .Loot {
        query := game.query_tesla_controls(room)
        if query.network.count > 0 {
            title,label := m8_tesla_control_labels(query)
            enabled := query.can_activate && m8_controls_allow_pointer(renderer,room)
            m8_mouse_button(renderer,m8_control_bounds(renderer,.Activate,room),title,enabled,label)
        }
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
    if m8_control_visible(room,.Equip) {m8_mouse_button(renderer,m8_control_bounds(renderer,.Equip,room),"EQUIPAGGIA",m8_control_enabled(renderer,room,.Equip))}
}

draw_m8_character_panel :: proc(renderer: ^Renderer, room: ^game.Room, state: Character_Sheet_State = {}) {
    if renderer == nil || room == nil || room.player == nil { return }
    draw_character_sheet(renderer, room, state)
}


begin_m8_model_lighting :: proc(renderer: ^Renderer, camera: rl.Camera3D) -> bool {
    v := &renderer.tactical
    if v.light_shader.id == 0 { return false }
    begin_resin_lighting(renderer, {eye = camera.position, lantern = {-2,4,3}, mode = .Model})
    return true
}
