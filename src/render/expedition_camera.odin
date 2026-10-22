package render

import "core:math"
import rl "vendor:raylib"
import game "../game"

EXPEDITION_COMBAT_FRAME_LIMIT :: f32(6)
EXPEDITION_COMBAT_FRAME_RADIUS :: f32(12)

// Translate the fixed camera along the ground toward its viewer. This raises
// nearby fighters above the hand without changing yaw, pitch, scale, or the
// ray used by picking. The first two points protect the player's whole body
// if a widely scattered encounter cannot fit at this fixed magnification.
@(private)
expedition_combat_frame_shift :: proc(camera: rl.Camera3D, height: f32, viewport: rl.Rectangle, points: []rl.Vector3) -> f32 {
	if len(points) < 2 || height <= 0 || viewport.height <= 24 { return 0 }
	look := rl.Vector3Normalize(camera.target-camera.position)
	right := rl.Vector3Normalize(rl.Vector3CrossProduct(look, camera.up))
	up := rl.Vector3CrossProduct(right, look)
	axis := rl.Vector3Normalize({camera.position.x-camera.target.x, 0, camera.position.z-camera.target.z})
	focal := height/max(camera.fovy, .01)
	if camera.projection == .PERSPECTIVE { focal = height*.5/math.tan(camera.fovy*math.PI/360) }
	low, high := -EXPEDITION_COMBAT_FRAME_LIMIT, EXPEDITION_COMBAT_FRAME_LIMIT
	player_low, player_high := low, high
	top := (height*.5-(viewport.y+12))/focal
	bottom := (height*.5-(viewport.y+viewport.height-12))/focal
	vertical := -rl.Vector3DotProduct(up, axis)
	depth_step := rl.Vector3DotProduct(look, axis) if camera.projection == .PERSPECTIVE else 0
	for point, i in points {
		relative := point-camera.position
		depth := rl.Vector3DotProduct(relative, look) if camera.projection == .PERSPECTIVE else 1
		if depth <= .05 { continue }
		y := rl.Vector3DotProduct(relative, up)
		bottom_step, top_step := vertical+bottom*depth_step, vertical+top*depth_step
		if bottom_step <= .001 || top_step <= .001 { return 0 }
		low = max(low, (bottom*depth-y)/bottom_step)
		high = min(high, (top*depth-y)/top_step)
		if i == 1 { player_low, player_high = low, high }
	}
	if player_low > player_high { return 0 }
	if low <= high { return clamp(f32(0), low, high) }
	return clamp((low+high)*.5, player_low, player_high)
}

@(private)
expedition_combat_camera_target :: proc(renderer: ^Renderer, orbit: Tactical_Orbit, target: rl.Vector3) -> rl.Vector3 {
	v := &renderer.tactical
	s := v.snapshot
	if !v.expedition || v.expedition_free || s == nil || s.phase != .Combat || v.first_person.amount > 0 { return target }
	points: [2*(game.MAX_ENEMIES_PER_ROOM+1)]rl.Vector3
	p, lift := living_card_position(renderer, game.PLAYER_ENTITY, .Player, s.player.position)
	points[0], points[1] = {p.x+.5, lift-.15, p.y+.5}, {p.x+.5, lift+2.2, p.y+.5}
	count := 2
	for actor in s.enemies[:s.enemy_count] {
		if !actor.visible || actor.health <= 0 || tactical_pinball_holds(renderer, actor.entity) { continue }
		at, actor_lift := living_card_position(renderer, actor.entity, sprite_key_for_enemy(actor.archetype), actor.position)
		delta := at-p
		if delta.x*delta.x+delta.y*delta.y > EXPEDITION_COMBAT_FRAME_RADIUS*EXPEDITION_COMBAT_FRAME_RADIUS { continue }
		points[count], points[count+1] = {at.x+.5, actor_lift-.15, at.y+.5}, {at.x+.5, actor_lift+2.2, at.y+.5}
		count += 2
	}
	if count == 2 { return target }
	camera := tactical_orbit_camera(orbit, target, v.perspective)
	shift := expedition_combat_frame_shift(camera, renderer.canvas_height, tactical_world_bounds(renderer), points[:count])
	axis := rl.Vector3{math.cos(orbit.yaw), 0, math.sin(orbit.yaw)}
	return target+axis*shift
}
