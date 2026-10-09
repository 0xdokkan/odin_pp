package render

import "core:fmt"
import "core:math"
import rl "vendor:raylib"
import rlgl "vendor:raylib/rlgl"
import game "../game"
import view "../view"

// Discrete choreography is independent of combat interpolation: exactly four
// silhouettes for reach, lift, throw and landing, each held for 0.3 seconds.
M8_Ring_Pose :: struct { enemy_offset: rl.Vector2, enemy_angle, player_lean: f32 }
m8_ring_pose :: proc(frame: int) -> M8_Ring_Pose {
    poses := [4]M8_Ring_Pose{
        {{0,0}, 0, 0.12}, {{-0.34,1.04}, -0.4, -0.08},
        {{0.62,0.75}, -1.8, 0.17}, {{0.94,-0.01}, -math.PI/2, 0.03},
    }
    return poses[clamp(frame,0,3)]
}

draw_m8_ring_fighter :: proc(renderer: ^Renderer, key: Sprite_Key, x, lift, angle, lean: f32, tint: rl.Color = rl.WHITE) {
    position := view.Vec2{x-0.5,-0.5}
    quad := m8_ring_transform_quad(tactical_billboard_geometry(renderer,key,position),lift,angle,lean)
    draw_tactical_billboard_quad(renderer,quad,position,1,tint)
}

m8_ring_transform_quad :: proc(original: Tactical_Billboard, lift,angle,lean: f32) -> Tactical_Billboard {
    quad := original
    base := (quad.points[1]+quad.points[2])*0.5
    for &point in quad.points {
        local := point-base
        point = base+rl.Vector3{local.x*math.cos(angle)-local.y*math.sin(angle)+lean*local.y,
            local.x*math.sin(angle)+local.y*math.cos(angle)+lift,local.z}
    }
    // Rotation is about the feet; keep a horizontal landing wholly above
    // the canvas so the ring floor cannot cut the opponent in half.
    lowest := quad.points[0].y
    for point in quad.points { lowest=min(lowest,point.y) }
    clearance := f32(0.065)
    if quad.source.width > 0 && quad.source.height > 0 {
        // Include the enlarged, independently wobbling paper outline. A
        // rotated landing must not clip its lower ink edge into the ring.
        right := (quad.points[2]-quad.points[1])/quad.source.width
        up := (quad.points[0]-quad.points[1])/quad.source.height
        clearance += (abs(right.y)+abs(up.y))*(COMIC_OUTLINE_OUTER+1.2)
    }
    if lowest < clearance { for &point in quad.points { point.y+=clearance-lowest } }
    return quad
}

draw_m8_ring_overlay :: proc(renderer: ^Renderer, room: ^game.Room, ring: ^game.Ring_Challenge) {
    if renderer == nil || room == nil || ring == nil { return }
    w,h := renderer.canvas_width,renderer.canvas_height
    rl.DrawRectangleRec({0,0,w,h},{5,8,15,255})
    // Arena backdrop and ropes are actual 3D geometry; fighters stay pixel cutouts.
    camera := rl.Camera3D{position={2.3,2.8,7.2},target={0,0.52,0},up={0,1,0},fovy=5.0,projection=.ORTHOGRAPHIC}
    previous := renderer.tactical.camera
    previous_outline := renderer.tactical.outline_mode
    renderer.tactical.outline_mode = .Ring
    renderer.tactical.camera = camera
    defer {
        renderer.tactical.camera = previous
        renderer.tactical.outline_mode = previous_outline
    }
    rl.BeginMode3D(camera)
    lit := begin_m8_model_lighting(renderer,camera)
    draw_resin_cube(renderer,{0,-0.17,0},5.65,0.30,3.8,RESIN_WALL)
    draw_resin_cube(renderer,{0,0,0},5.30,0.07,3.5,{39,48,63,255})
    for x in -2..=2 { rl.DrawLine3D({f32(x),0.04,-1.7},{f32(x),0.04,1.7},{73,88,107,255}) }
    for z in ([2]f32{-1.62,1.62}) {
        for x in ([2]f32{-2.53,2.53}) {
            draw_resin_cube(renderer,{x,0.65,z},0.17,1.33,0.17,RESIN_DARK)
            rl.DrawCube({x,1.35,z},0.21,0.08,0.21,GOTHIC_RED)
        }
        for y in ([3]f32{0.40,0.80,1.20}) { rl.DrawCylinderEx({-2.53,y,z},{2.53,y,z},0.015,0.015,4,{133,63,76,255}) }
    }
    for x in ([2]f32{-2.53,2.53}) { for y in ([3]f32{0.40,0.80,1.20}) { rl.DrawCylinderEx({x,y,-1.62},{x,y,1.62},0.015,0.015,4,{112,73,97,255}) } }
    player_x,enemy_x := ring.player_x*4.8-2.4,ring.enemy_x*4.8-2.4
    lift,angle,lean := f32(0),f32(0),f32(0)
    facing := f32(1) if enemy_x >= player_x else -1
    key := Sprite_Key.Player
    if ring.action == .Grab_Throw {
        frame := game.ring_grab_pose(ring)
        pose := m8_ring_pose(frame)
        enemy_x = player_x+facing*(0.55+pose.enemy_offset.x)
        lift,angle,lean = pose.enemy_offset.y,pose.enemy_angle*facing,pose.player_lean*facing
        key = .Player_Cast
        if frame <= 1 {
            for z in ([2]f32{-0.08,0.09}) {
                a := rl.Vector3{player_x+0.14*facing,0.71,z+0.09}
                b := rl.Vector3{enemy_x,0.69+lift*0.75,z+0.09}
                rl.DrawCylinderEx(a,b,0.075,0.055,4,GOTHIC_PAPER)
            }
        }
        if frame == 3 { draw_tactical_rune({enemy_x,0.06,0},0.70,0,GOTHIC_BLUE) }
    } else if ring.action == .Jab { lean = 0.22*facing; key = .Player_Cast }
    else if ring.action == .Dodge { lean = -0.18*facing }
    if lit { rl.EndShaderMode() }
    tint := rl.WHITE
    if ring.action == .Hurt { tint = {255,115,126,255} }
    rlgl.DrawRenderBatchActive()
    rlgl.DisableDepthMask()
    draw_m8_ring_fighter(renderer,.Brute,enemy_x,lift,angle,0,{255,215,214,255} if ring.enemy_windup < 0.4 else rl.WHITE)
    draw_m8_ring_fighter(renderer,key,player_x,0,0,lean,tint)
    rlgl.DrawRenderBatchActive()
    rlgl.EnableDepthMask()
    rl.EndMode3D()
    gothic_text(renderer,"IL RING DELLE OMBRE",28,18,28,GOTHIC_PAPER)
    gothic_text(renderer,"SFIDA / IL MONDO ESTERNO E' SOSPESO",30,53,12,GOTHIC_MUTED)
    gothic_text(renderer,fmt.ctprintf("TU  %d / %d",ring.player_health,game.RING_PLAYER_MAX_HEALTH),30,90,20,GOTHIC_BLUE)
    gothic_text_fit(renderer,fmt.ctprintf("IL CAMPIONE  %d / %d",ring.enemy_health,game.RING_ENEMY_MAX_HEALTH),{w-290,90,260,25},20,GOTHIC_RED)
    status: cstring = "AVVICINATI / SCHIVA IL COLPO / AFFERRA NEL RECUPERO"
    accent := GOTHIC_MUTED
    if ring.enemy_windup < 0.6 && ring.enemy_recovery <= 0 { status="ATTACCO IN ARRIVO / 2 SCHIVA"; accent=GOTHIC_RED }
    if game.ring_enemy_vulnerable(ring) { status="CAMPIONE ESPOSTO / 3 PRESA A DUE MANI"; accent=GOTHIC_BLUE }
    if ring.action == .Grab_Throw {
        names := [4]cstring{"01 / PRESA", "02 / SOLLEVA", "03 / LANCIA", "04 / IMPATTO"}
        status=names[game.ring_grab_pose(ring)]; accent=GOTHIC_PAPER
    }
    if ring.phase != .Active {
        status="VITTORIA / SFIDA COMPLETATA" if ring.phase == .Won else "SCONFITTA / RITENTA IN UN'ALTRA STANZA"
        tactical_hud_panel({w*0.5-230,h*0.5-30,460,65},GOTHIC_BLUE if ring.phase == .Won else GOTHIC_RED)
        gothic_text_fit(renderer,status,{w*0.5-215,h*0.5-15,430,26},22,GOTHIC_PAPER)
        gothic_text_fit(renderer,"USA IL PULSANTE TORNA ALLA STANZA",{w*0.5-205,h*0.5+15,410,18},12,GOTHIC_MUTED)
    }
    gothic_text_fit(renderer,status,{30,h-93,w-60,26},18,accent)
    gothic_rule(30,h-56,w-60,GOTHIC_STEEL)
    gothic_text_fit(renderer,"A / D  MUOVI       1  PUGNO       2  SCHIVA       3  PRESA",{30,h-42,w-320,24},16,GOTHIC_PAPER)
    m8_mouse_button(renderer,m8_modal_control_bounds(renderer,.Leave_Ring),"ABBANDONA" if ring.phase == .Active else "TORNA ALLA STANZA")
}
