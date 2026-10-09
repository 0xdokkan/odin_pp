package render

import rl "vendor:raylib"
import game "../game"
import grid "../grid"

// Small code-native pixel crests stay sharp at hand-card resolution.
draw_device_card_icon :: proc(id: game.Card_Id, bounds: rl.Rectangle, color: rl.Color) {
    x, y := bounds.x+bounds.width*0.5, bounds.y+bounds.height*0.5
    s := min(bounds.width/52, bounds.height/44)
    if id == .Shock_Floor {
        for row in 0..<3 { for col in 0..<3 {
            rl.DrawRectangleRec({x+(f32(col)-1)*13*s-5*s, y+(f32(row)-1)*10*s-4*s, 10*s, 8*s}, color)
        } }
    } else {
        rl.DrawRectangleRec({x-17*s, y+14*s, 34*s, 6*s}, GOTHIC_INK)
        rl.DrawRectangleRec({x-4*s, y-12*s, 8*s, 30*s}, GOTHIC_STEEL)
        for i in 0..<4 { rl.DrawRectangleRec({x-11*s, y+(f32(i)*6-7)*s, 22*s, 3*s}, color) }
        rl.DrawRectangleRec({x-14*s, y-18*s, 28*s, 7*s}, color)
    }
    bolt := [5]rl.Vector2{{x+7*s,y-21*s},{x-3*s,y-6*s},{x+4*s,y-6*s},{x-6*s,y+10*s},{x+1*s,y-2*s}}
    for i in 0..<len(bolt)-1 { rl.DrawLineEx(bolt[i], bolt[i+1], max(f32(2),3*s), GOTHIC_PAPER) }
}

draw_m8_device_object :: proc(renderer: ^Renderer, object: Presentation_Grid_Object) {
    p := rl.Vector3{object.position.x+0.5, 0.075, object.position.y+0.5}
    blue := rl.Color{82, 181, 238, 255}
    if object.kind == .Shock_Floor {
        draw_resin_cube(renderer, p, 0.88, 0.09, 0.88, RESIN_DARK)
        for axis in 0..<2 { for i in 0..<3 {
            offset := f32(i-1)*0.27
            center := p+rl.Vector3{offset, 0.055, 0} if axis == 0 else p+rl.Vector3{0, 0.055, offset}
            size := rl.Vector3{0.045, 0.022, 0.78} if axis == 0 else rl.Vector3{0.78, 0.022, 0.045}
            rl.DrawCubeV(center, size, blue)
        } }
        draw_resin_cube(renderer, p+rl.Vector3{0, 0.085, 0}, 0.17, 0.06, 0.17, GOTHIC_PAPER)
    } else {
        draw_resin_cube(renderer, p, 0.65, 0.14, 0.65, RESIN_DARK)
        draw_resin_cube(renderer, p+rl.Vector3{0, 0.40, 0}, 0.20, 0.75, 0.20, RESIN_WALL)
        for i in 0..<5 {
            draw_resin_cube(renderer, p+rl.Vector3{0, 0.22+f32(i)*0.13, 0}, 0.39, 0.06, 0.39, RESIN_CAP)
            rl.DrawCube(p+rl.Vector3{0, 0.26+f32(i)*0.13, 0}, 0.25, 0.027, 0.25, blue)
        }
        draw_resin_cube(renderer, p+rl.Vector3{0, 0.99, 0}, 0.56, 0.16, 0.56, RESIN_CAP)
        rl.DrawCube(p+rl.Vector3{0, 1.08, 0}, 0.39, 0.035, 0.39, blue)
    }
}

// Ground coverage is the exact resolver query, not a separate polygon approximation.
// All overlays are fog-clipped, including every cell along long Tesla links.
draw_m8_device_network :: proc(renderer: ^Renderer, room: ^game.Room) {
    network := game.query_board_device_network(room)
    blue := rl.Color{88, 176, 230, 130} if network.ready else rl.Color{76, 101, 128, 85}
    if network.count >= 2 {
        points := network.hull[:] if network.field else network.positions[:]
        count := network.hull_count if network.field else network.count
        links := count if count > 2 else 1
        for i in 0..<links {
            if network.field || (network.active_links & (u8(1)<<u8(i))) != 0 { draw_m8_tesla_link(renderer,points[i],points[(i+1)%count],network.ready) }
        }
        for y in 0..<room.level_data.tiles.height { for x in 0..<room.level_data.tiles.width {
            cell := grid.Position{x,y}
            if !tactical_render_visible(renderer, cell) || !game.board_device_network_contains_cell(room, &network, cell) { continue }
            p := rl.Vector3{f32(x)+0.5, 0.065, f32(y)+0.5}
            rl.DrawCubeWires(p, 0.76, 0.014, 0.76, blue)
            if network.ready {
                // A thin segmented fence leaves the center of the cell readable.
                phase := f32(comic_pose_frame(renderer.sprite_assets.elapsed))*0.02
                rl.DrawLine3D(p+rl.Vector3{-0.32,0.19+phase,0}, p+rl.Vector3{0.02,0.12-phase,0.10}, blue)
                rl.DrawLine3D(p+rl.Vector3{0.02,0.12-phase,0.10}, p+rl.Vector3{0.32,0.19+phase,0}, blue)
            }
        } }
    }
    for object in room.objects {
        if object.kind != .Shock_Floor || !tactical_render_visible(renderer, object.position) { continue }
        if object.device_armed {
            for dy in -1..=1 { for dx in -1..=1 {
                cell := grid.Position{object.position.x+dx, object.position.y+dy}
                if tactical_render_visible(renderer, cell) && game.shock_floor_contains_cell(room, object.position, cell) {
                    rl.DrawCubeWires({f32(cell.x)+0.5, 0.059, f32(cell.y)+0.5}, 0.83, 0.01, 0.83, {88,184,240,95})
                }
            } }
        }
    }
}

// Clip each short beam section against current visibility. This keeps a wire
// from disclosing the position of its unseen endpoint through tactical fog.
draw_m8_tesla_link :: proc(renderer: ^Renderer, a,b: grid.Position, ready: bool) {
    start := rl.Vector3{f32(a.x)+0.5,0,f32(a.y)+0.5}
    delta := rl.Vector3{f32(b.x-a.x),0,f32(b.y-a.y)}
    steps := max(1,max(abs(b.x-a.x),abs(b.y-a.y))*5)
    color := rl.Color{116,205,250,180} if ready else rl.Color{77,111,141,90}
    for i in 0..<steps {
        p,q := start+delta*(f32(i)/f32(steps)),start+delta*(f32(i+1)/f32(steps))
        if !tactical_render_visible(renderer,{int(p.x),int(p.z)}) || !tactical_render_visible(renderer,{int(q.x),int(q.z)}) { continue }
        wobble := f32((i+comic_pose_frame(renderer.sprite_assets.elapsed))%3-1)*0.045 if ready else 0
        for height in ([3]f32{0.34,0.73,1.10}) {
            rl.DrawLine3D(p+rl.Vector3{0,height+wobble,0},q+rl.Vector3{0,height-wobble,0},color)
        }
    }
}
