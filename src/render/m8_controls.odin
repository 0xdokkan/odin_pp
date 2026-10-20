package render

import rl "vendor:raylib"
import game "../game"
import view "../engine/view"

M8_Control :: enum {None, Activate, Equip, Character}

// One layout drives drawing, hit testing and board occlusion. Loot controls
// move to the footer; hidden equipment never leaves an invisible hit region.
m8_active_bar_bounds :: proc(renderer: ^Renderer, room: ^game.Room = nil) -> rl.Rectangle {
    return m8_bar_bounds(renderer, room != nil && room.phase == .Loot)
}

// The bar in a fight, or in the footer once the room is cleared (`loot`).
@(private)
m8_bar_bounds :: proc(renderer: ^Renderer, loot: bool) -> rl.Rectangle {
    width := min(f32(932), renderer.canvas_width-28)
    return {(renderer.canvas_width-width)*0.5, renderer.canvas_height-(46 if loot else 218), width, 28}
}

m8_control_bounds :: proc(renderer: ^Renderer, control: M8_Control, room: ^game.Room = nil) -> rl.Rectangle {
    if renderer == nil { return {} }
    b := m8_active_bar_bounds(renderer, room)
    // Ratios also retain usable, disjoint hit targets on the 640px canvas.
    switch control {
    case .Activate: return {b.x,b.y,b.width*0.26,b.height}
    case .Equip: return {b.x+b.width*0.64,b.y,b.width*0.14-6,b.height}
    // The character sheet lives with the other commands in the top dock.
    case .Character: return tactical_hud_layout(renderer).character
    case .None: return {}
    }
    return {}
}

m8_weapon_bounds :: proc(renderer: ^Renderer, room: ^game.Room) -> rl.Rectangle {
    b := m8_active_bar_bounds(renderer,room)
    return {b.x+b.width*0.28,b.y,b.width*0.35-6,b.height}
}

@(private)
m8_trap_status_bounds :: proc(renderer: ^Renderer, room: ^game.Room) -> rl.Rectangle {
    b := m8_active_bar_bounds(renderer,room)
    return {b.x,b.y-20,min(b.width,370),16}
}

@(private)
m8_control_visible :: proc(room: ^game.Room, control: M8_Control) -> bool {
    if room == nil || room.player == nil || (room.phase != .Combat && room.phase != .Loot) {return false}
    switch control {
    case .Activate: return game.board_device_count(room,.Tesla_Coil)>0
    case .Equip: return room.player.equipment.reserve.id != .None
    case .Character: return true
    case .None: return false
    }
    return false
}

m8_hud_contains_point :: proc(renderer: ^Renderer, room: ^game.Room, point: view.Vec2) -> bool {
    for control in M8_Control {
        if m8_control_visible(room,control) && point_in_rectangle(point,m8_control_bounds(renderer,control,room)) {return true}
    }
    if room == nil || room.player == nil {return false}
    equipment := room.player.equipment
    if (equipment.weapon.id != .None || equipment.reserve.id != .None) && point_in_rectangle(point,m8_weapon_bounds(renderer,room)) {return true}
    return game.board_device_count(room,.Shock_Floor)>0 && point_in_rectangle(point,m8_trap_status_bounds(renderer,room))
}

// A control the pointer can use now. Behind the player's eyes (and while the
// view rises from them) the pointer is the view's and reaches none: each one
// is drawn off (first_person_owns_pointer).
@(private)
m8_controls_allow_pointer :: proc(renderer: ^Renderer, room: ^game.Room) -> bool {
    return !(renderer == nil || room == nil || room.player == nil ||
       (room.phase != .Combat && room.phase != .Loot) || room.qte.kind != .None ||
       game.tactical_is_casting(room) || renderer_blocks_player_input(renderer) || first_person_owns_pointer(renderer, room))
}

@(private)
m8_control_enabled :: proc(renderer: ^Renderer, room: ^game.Room, control: M8_Control) -> bool {
    if !m8_controls_allow_pointer(renderer,room) || !m8_control_visible(room,control) { return false }
    switch control {
    case .Activate: return game.board_devices_can_activate(room)
    case .Equip:
        equipment := room.player.equipment
        return game.tactical_allows_action(room) && equipment.reserve.id != .None &&
            game.weapon_slot_valid(equipment.reserve) && game.weapon_slot_valid(equipment.weapon)
    case .Character: return !renderer_timeline_is_busy(renderer)
    case .None: return false
    }
    return false
}

m8_control_at_point :: proc(renderer: ^Renderer, room: ^game.Room, point: view.Vec2) -> M8_Control {
    for control in ([3]M8_Control{.Activate,.Equip,.Character}) {
        if m8_control_enabled(renderer,room,control) && point_in_rectangle(point,m8_control_bounds(renderer,control,room)) { return control }
    }
    return .None
}

M8_Modal_Control :: enum {Close_Character}

m8_modal_control_bounds :: proc(renderer: ^Renderer, control: M8_Modal_Control) -> rl.Rectangle {
    if renderer == nil { return {} }
    switch control {
    case .Close_Character: return {renderer.canvas_width-208,52,148,28}
    }
    return {}
}

// Mouse controls carry an action verb, never a keyboard-key badge. Optional
// detail keeps device counts/recharge separate from the activation affordance.
m8_mouse_button :: proc(renderer: ^Renderer, bounds: rl.Rectangle, label: cstring, enabled: bool = true, detail: cstring = nil) {
    hud_button(renderer,bounds,nil,label,enabled,GOTHIC_BLUE,detail)
}
