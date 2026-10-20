package render

import "core:math"
import rl "vendor:raylib"

// Discrete choreography is independent of combat interpolation: exactly four
// silhouettes for reach, lift, throw and landing, each held for 0.3 seconds.
M8_Ring_Pose :: struct { enemy_offset: rl.Vector2, enemy_angle, player_lean: f32 }
@(private)
m8_ring_pose :: proc(frame: int) -> M8_Ring_Pose {
    poses := [4]M8_Ring_Pose{
        {{0,0}, 0, 0.12}, {{-0.34,1.04}, -0.4, -0.08},
        {{0.62,0.75}, -1.8, 0.17}, {{0.94,-0.01}, -math.PI/2, 0.03},
    }
    return poses[clamp(frame,0,3)]
}

@(private)
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
