package fps

import "core:math"
import camera "../../engine/camera"
import physics "../../engine/physics"

// A simple autopilot: walks a BFS path to the nearest rune (then the
// portal) and shoots whatever it can see. Tests use it to prove every crypt
// can be won; the preview harness uses it to capture action screenshots.
Bot :: struct {
	field:      [MAX_COLUMNS]i32,
	target:     int, // column the field was built from, -1 for none
	last_feet:  Vec3,
	stuck_time: f32,
	sidestep:   f32,
}

// Fills the bot's path field toward the current objective; returns its
// column and exact position.
@(private)
bot_objective :: proc(w: ^World) -> (col: int, goal: Vec3) {
	col = -1
	best := FLOW_UNREACHED
	for i in 0..<w.pickup_count {
		pk := w.pickups[i]
		if pk.taken || pk.kind != .Rune {
			continue
		}
		c := column_of(w, pk.position)
		if c >= 0 && w.flow[c] < best {
			best, col, goal = w.flow[c], c, pk.position
		}
	}
	if col < 0 && w.portal.open {
		goal = Vec3{w.portal.center.x + 0.5, FLOOR_Y, w.portal.center.z}
		col = column_of(w, goal)
	}
	if col >= 0 && col != w.bot.target {
		w.bot.target = col
		flow_from(w, &w.bot.field, col)
	}
	return
}

bot_input :: proc(w: ^World, dt: f32) -> Player_Input {
	result: Player_Input
	if w.status != .Playing {
		return result
	}
	p := &w.player
	feet := player_feet(p^)
	eye := player_eye(p^)
	col, goal := bot_objective(w)

	move_dir: Vec2
	if col >= 0 {
		if column_of(w, feet) == col || w.bot.field[max(column_of(w, feet), 0)] <= 1 {
			move_dir = physics.normalize2(Vec2{goal.x - feet.x, goal.z - feet.z})
		} else if next, ok := flow_step(w, &w.bot.field, feet); ok {
			move_dir = physics.normalize2(Vec2{next.x - feet.x, next.z - feet.z})
		}
	}

	// Combat: the nearest visible living enemy (or incoming bolt) is the target.
	aim_at: Vec3
	has_aim := false
	best := f32(16)
	for i in 0..<w.enemy_count {
		e := w.enemies[i]
		if e.state == .Dead {
			continue
		}
		lo, hi := enemy_box(e)
		center := (lo + hi) * 0.5
		d := physics.length3(center - eye)
		if d < best && physics.voxel_line_of_sight(&w.voxels, eye, center) {
			best, aim_at, has_aim = d, center, true
		}
	}
	for pr in w.projectiles {
		if !pr.alive {
			continue
		}
		d := physics.length3(pr.position - eye)
		if d < min(best, 7) {
			best, aim_at, has_aim = d, pr.position, true
		}
	}

	desired_yaw, desired_pitch := p.yaw, f32(0)
	if has_aim {
		to := aim_at - eye
		desired_yaw = math.atan2(to.x, to.z)
		desired_pitch = math.atan2(to.y, physics.length2(Vec2{to.x, to.z}))
	} else if move_dir != {} {
		desired_yaw = math.atan2(move_dir.x, move_dir.y)
	}
	turn := 7 * dt
	result.look.x = clamp(math.angle_diff(p.yaw, desired_yaw), -turn, turn)
	result.look.y = clamp(desired_pitch-p.pitch, -turn, turn)

	// Unstick: if barely moving for a while, sidestep and hop.
	moved := physics.length2(Vec2{feet.x - w.bot.last_feet.x, feet.z - w.bot.last_feet.z})
	w.bot.last_feet = feet
	if move_dir != {} && moved < 0.5*dt {
		w.bot.stuck_time += dt
	} else {
		w.bot.stuck_time = max(w.bot.stuck_time-dt*2, 0)
	}
	if w.bot.stuck_time > 0.6 {
		w.bot.stuck_time = 0
		w.bot.sidestep = 0.5
		result.jump = true
	}
	if w.bot.sidestep > 0 {
		w.bot.sidestep -= dt
		move_dir = physics.normalize2(move_dir + Vec2{-move_dir.y, move_dir.x}*1.5)
	}

	// Move in the frame the step will use, after the look delta is applied.
	forward, right := camera.fps_ground_basis(p.yaw + result.look.x)
	result.move = Vec2{move_dir.x*right.x + move_dir.y*right.y, move_dir.x*forward.x + move_dir.y*forward.y}
	result.sprint = !has_aim
	if has_aim {
		yaw_err := abs(math.angle_diff(p.yaw+result.look.x, desired_yaw))
		pitch_err := abs(desired_pitch - (p.pitch + result.look.y))
		result.fire = yaw_err < 0.06 && pitch_err < 0.08
	}
	return result
}
