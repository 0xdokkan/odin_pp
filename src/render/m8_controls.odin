package render

import rl "vendor:raylib"
import game "../game"
import view "../view"

M8_Control :: enum {None, Activate, Equip, Character, Ring, FPS, Workshop}

m8_control_bounds :: proc(renderer: ^Renderer, control: M8_Control) -> rl.Rectangle {
    if renderer == nil { return {} }
    b := m8_active_bar_bounds(renderer)
    width := b.width*0.28
    switch control {
    case .Activate: return {b.x,b.y,width,b.height}
    case .Equip: return {b.x+width*2+54,b.y,100,b.height}
    case .Character: return {b.x+width*2+159,b.y,b.width-width*2-159,b.height}
    case .Ring: return {renderer.canvas_width-184,97,170,26}
    case .FPS: return {renderer.canvas_width-184,131,170,26}
    case .Workshop: return {renderer.canvas_width-184,165,170,26}
    case .None: return {}
    }
    return {}
}

m8_control_enabled :: proc(renderer: ^Renderer, room: ^game.Room, control: M8_Control) -> bool {
    if renderer == nil || room == nil || room.player == nil || !renderer.tactical.enabled ||
       (room.phase != .Combat && room.phase != .Loot) || room.qte.kind != .None ||
       game.tactical_is_casting(room) || renderer_blocks_player_input(renderer) { return false }
    switch control {
    case .Activate: return game.board_devices_can_activate(room)
    case .Equip:
        equipment := room.player.equipment
        return game.tactical_allows_action(room) && equipment.reserve.id != .None &&
            game.weapon_slot_valid(equipment.reserve) && game.weapon_slot_valid(equipment.weapon)
    case .Character: return !renderer_timeline_is_busy(renderer)
    case .Ring: return room.phase == .Loot && !room.ring_challenge_attempted && !renderer_timeline_is_busy(renderer)
    case .FPS,.Workshop: return room.phase == .Loot && !renderer_timeline_is_busy(renderer)
    case .None: return false
    }
    return false
}

m8_control_at_point :: proc(renderer: ^Renderer, room: ^game.Room, point: view.Vec2) -> M8_Control {
    for control in ([6]M8_Control{.Activate,.Equip,.Character,.Ring,.FPS,.Workshop}) {
        if m8_control_enabled(renderer,room,control) && point_in_rectangle(point,m8_control_bounds(renderer,control)) { return control }
    }
    return .None
}

M8_Modal_Control :: enum {Close_Character, Leave_Ring}

m8_modal_control_bounds :: proc(renderer: ^Renderer, control: M8_Modal_Control) -> rl.Rectangle {
    if renderer == nil { return {} }
    switch control {
    case .Close_Character: return {renderer.canvas_width-208,52,148,28}
    case .Leave_Ring: return {renderer.canvas_width-268,renderer.canvas_height-47,238,32}
    }
    return {}
}

// Mouse controls carry an action verb, never a keyboard-key badge. Optional
// detail keeps device counts/recharge separate from the activation affordance.
m8_mouse_button :: proc(renderer: ^Renderer, bounds: rl.Rectangle, label: cstring, enabled: bool = true, detail: cstring = nil) {
    accent := GOTHIC_BLUE if enabled else GOTHIC_STEEL
    ink := GOTHIC_PAPER if enabled else GOTHIC_MUTED
    rl.DrawRectangleRec({bounds.x+1,bounds.y+2,bounds.width,bounds.height},GOTHIC_INK)
    rl.DrawRectangleRec(bounds,GOTHIC_RECESS)
    rl.DrawRectangleLinesEx(bounds,1,accent)
    rl.DrawRectangleRec({bounds.x+3,bounds.y+2,bounds.width-6,1},ink)
    if detail != nil {
        gothic_text_fit(renderer,label,{bounds.x+8,bounds.y+1,bounds.width-16,14},12,ink)
        gothic_text_fit(renderer,detail,{bounds.x+8,bounds.y+14,bounds.width-16,12},10,accent if enabled else GOTHIC_MUTED)
    } else {
        text_width := min(bounds.width-16,gothic_text_width(renderer,label,14))
        gothic_text_fit(renderer,label,{bounds.x+(bounds.width-text_width)*0.5,bounds.y+(bounds.height-17)*0.5,text_width,18},14,ink)
    }
}
