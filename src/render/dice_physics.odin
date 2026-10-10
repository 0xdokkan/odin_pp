package render

import "core:math"
import rl "vendor:raylib"
import tween "../engine/tween"

DICE_PHYSICS_MAX_BODIES :: 3
DICE_PHYSICS_DT :: f32(1.0/120.0)
DICE_THROW_FRAME_COUNT :: 721
DICE_PHYSICS_HALF_EXTENT :: f32(0.5)
DICE_PHYSICS_INVERSE_INERTIA :: f32(6)
DICE_PHYSICS_MAX_CONTACTS :: 80
DICE_PHYSICS_LINEAR_DAMPING :: f32(0.35)
DICE_PHYSICS_ANGULAR_DAMPING :: f32(0.45)

Dice_Physics_Frame :: struct {
	positions: [DICE_PHYSICS_MAX_BODIES]rl.Vector3,
	orientations: [DICE_PHYSICS_MAX_BODIES]rl.Quaternion,
}

Dice_Throw :: struct {
	frames: [DICE_THROW_FRAME_COUNT]Dice_Physics_Frame,
	count: int,
	contact_count: int,
	first_impact_frame: int,
	rebound_frames: [2]int,
	physics_steps: int,
	last_motion_frame: int,
	attempts: int,
	settled: bool,
}

Dice_Physics_Body :: struct {
	position, velocity, angular_velocity: rl.Vector3,
	orientation: rl.Quaternion,
	cached_orientation: rl.Quaternion,
	cached_axes: [3]rl.Vector3,
	quiet_steps: int,
	stationary_steps: int,
	asleep: bool,
	touched_ground: bool,
	bounce_peak: f32,
	visible_bounces: int,
	floor_contact: bool,
	floor_kicks: int,
	rebound_spin_axis: rl.Vector3,
}

Dice_Physics_Contact :: struct {
	a, b: int, // b = -1 denotes an immovable plane.
	point, normal, tangent_1, tangent_2: rl.Vector3,
	penetration, target_velocity: f32,
	normal_impulse: f32,
	friction_impulse: rl.Vector2,
	normal_mass, tangent_mass_1, tangent_mass_2: f32,
}

Dice_Physics_Contacts :: struct {
	items: [DICE_PHYSICS_MAX_CONTACTS]Dice_Physics_Contact,
	count: int,
	pair_count: int,
	ground_contact: bool,
	ground_bodies: [DICE_PHYSICS_MAX_BODIES]bool,
	touched_bodies: [DICE_PHYSICS_MAX_BODIES]bool,
}

Dice_Physics_SAT :: struct {
	overlaps: bool,
	normal: rl.Vector3,
	depth: f32,
	face_body, axis_a, axis_b: int, // face_body = -1 means an edge/edge contact.
}

dice_physics_axes :: proc(body: ^Dice_Physics_Body) -> [3]rl.Vector3 {
	if body.cached_orientation == body.orientation { return body.cached_axes }
	body.cached_axes = {rl.Vector3RotateByQuaternion({1, 0, 0}, body.orientation),
		rl.Vector3RotateByQuaternion({0, 1, 0}, body.orientation),
		rl.Vector3RotateByQuaternion({0, 0, 1}, body.orientation)}
	body.cached_orientation = body.orientation
	return body.cached_axes
}

dice_physics_projected_radius :: proc(axes: [3]rl.Vector3, direction: rl.Vector3) -> f32 {
	return 0.5*(abs(rl.Vector3DotProduct(axes[0], direction))+
		abs(rl.Vector3DotProduct(axes[1], direction))+abs(rl.Vector3DotProduct(axes[2], direction)))
}

dice_physics_support_height :: proc(body: ^Dice_Physics_Body) -> f32 {
	return dice_physics_projected_radius(dice_physics_axes(body), {0, 1, 0})
}

dice_physics_sat :: proc(a, b: ^Dice_Physics_Body) -> (result: Dice_Physics_SAT) {
	axes_a, axes_b :=dice_physics_axes(a),dice_physics_axes(b)
	delta := b.position-a.position
	result.depth = f32(math.F32_MAX)
	for index in 0..<15 {
		axis: rl.Vector3
		if index < 3 { axis = axes_a[index] }
		else if index < 6 { axis = axes_b[index-3] }
		else { axis = rl.Vector3CrossProduct(axes_a[(index-6)/3], axes_b[(index-6)%3]) }
		length := rl.Vector3Length(axis)
		if length < 0.0001 { continue }
		axis /= length
		distance := rl.Vector3DotProduct(delta, axis)
		depth :=dice_physics_projected_radius(axes_a, axis)+dice_physics_projected_radius(axes_b, axis)-abs(distance)
		if depth < -0.0001 { return {} }
		// Prefer a face manifold over a nearly equivalent cross axis.
		penalty: f32 = 0.002 if index >= 6 else 0
		if depth+penalty < result.depth {
			result.depth = max(f32(0), depth)
			result.normal = -axis if distance < 0 else axis
			result.face_body = 0 if index < 3 else 1 if index < 6 else -1
			result.axis_a = index if index < 3 else index-3 if index < 6 else (index-6)/3
			result.axis_b = (index-6)%3 if index >= 6 else 0
		}
	}
	result.overlaps = true
	return
}

dice_physics_add_contact :: proc(contacts: ^Dice_Physics_Contacts, a, b: int, point, normal: rl.Vector3, penetration: f32) {
	if contacts.count >= len(contacts.items) { return }
	contacts.touched_bodies[a] = true
	if b >= 0 { contacts.touched_bodies[b] = true }
	basis := rl.Vector3{1, 0, 0} if abs(normal.x) < 0.8 else rl.Vector3{0, 1, 0}
	tangent_1 := rl.Vector3Normalize(rl.Vector3CrossProduct(normal, basis))
	contacts.items[contacts.count] = {a = a, b = b, point = point, normal = normal,
		penetration = penetration, tangent_1 = tangent_1, tangent_2 = rl.Vector3CrossProduct(normal, tangent_1)}
	contacts.count += 1
}

// Clip the incident face against the four side planes of the reference face.
// Keeping several contact points lets cubes rest on faces rather than wobble on one point.
dice_physics_clip_polygon :: proc(input: []rl.Vector3, normal: rl.Vector3, limit: f32, output: ^[16]rl.Vector3) -> (count: int) {
	if len(input) == 0 { return }
	previous := input[len(input)-1]
	previous_distance := rl.Vector3DotProduct(previous, normal)-limit
	for point in input {
		distance := rl.Vector3DotProduct(point, normal)-limit
		if (distance <= 0) != (previous_distance <= 0) {
			t := previous_distance/(previous_distance-distance)
			output[count] = previous+(point-previous)*t
			count += 1
		}
		if distance <= 0 { output[count] = point; count += 1 }
		previous, previous_distance = point, distance
	}
	return
}

dice_physics_face_contacts :: proc(bodies: []Dice_Physics_Body, a, b: int, sat: Dice_Physics_SAT, contacts: ^Dice_Physics_Contacts) {
	reference := &bodies[a] if sat.face_body == 0 else &bodies[b]
	incident := &bodies[b] if sat.face_body == 0 else &bodies[a]
	normal := sat.normal if sat.face_body == 0 else -sat.normal
	ref_axes, inc_axes :=dice_physics_axes(reference),dice_physics_axes(incident)
	ref_center := reference.position+normal*0.5
	u, v := ref_axes[(sat.axis_a+1)%3], ref_axes[(sat.axis_a+2)%3]
	incident_axis, most_parallel := 0, f32(-1)
	for axis, index in inc_axes {
		parallel := abs(rl.Vector3DotProduct(axis, normal))
		if parallel > most_parallel { incident_axis, most_parallel = index, parallel }
	}
	inc_normal := inc_axes[incident_axis]
	if rl.Vector3DotProduct(inc_normal, normal) > 0 { inc_normal = -inc_normal }
	inc_center := incident.position+inc_normal*0.5
	inc_u, inc_v := inc_axes[(incident_axis+1)%3], inc_axes[(incident_axis+2)%3]
	polygon: [16]rl.Vector3
	polygon[0], polygon[1] = inc_center-inc_u*0.5-inc_v*0.5, inc_center+inc_u*0.5-inc_v*0.5
	polygon[2], polygon[3] = inc_center+inc_u*0.5+inc_v*0.5, inc_center-inc_u*0.5+inc_v*0.5
	count := 4
	planes := [4]rl.Vector3{u, -u, v, -v}
	for plane in planes {
		clipped: [16]rl.Vector3
		count =dice_physics_clip_polygon(polygon[:count], plane, rl.Vector3DotProduct(ref_center, plane)+0.5, &clipped)
		polygon = clipped
	}
	for point in polygon[:count] {
		distance := rl.Vector3DotProduct(point-ref_center, normal)
		if distance > 0.004 { continue }
		dice_physics_add_contact(contacts, a, b, point-normal*distance*0.5, sat.normal, max(f32(0), -distance))
	}
}

dice_physics_closest_segments :: proc(a0, a1, b0, b1: rl.Vector3) -> (point_a, point_b: rl.Vector3) {
	d1, d2, r := a1-a0, b1-b0, a0-b0
	a, e := rl.Vector3DotProduct(d1, d1), rl.Vector3DotProduct(d2, d2)
	b, c, f := rl.Vector3DotProduct(d1, d2), rl.Vector3DotProduct(d1, r), rl.Vector3DotProduct(d2, r)
	denominator := a*e-b*b
	s: f32
	if denominator > 0.000001 { s = clamp((b*f-c*e)/denominator, f32(0), f32(1)) }
	t := (b*s+f)/e
	if t < 0 { t = 0; s = clamp(-c/a, f32(0), f32(1)) }
	else if t > 1 { t = 1; s = clamp((b-c)/a, f32(0), f32(1)) }
	return a0+d1*s, b0+d2*t
}

dice_physics_edge_contacts :: proc(bodies: []Dice_Physics_Body, a, b: int, sat: Dice_Physics_SAT, contacts: ^Dice_Physics_Contacts) {
	axes_a, axes_b :=dice_physics_axes(&bodies[a]),dice_physics_axes(&bodies[b])
	center_a, center_b := bodies[a].position, bodies[b].position
	for axis, index in axes_a {
		if index != sat.axis_a { center_a += axis*(0.5 if rl.Vector3DotProduct(axis, sat.normal) >= 0 else -0.5) }
	}
	for axis, index in axes_b {
		if index != sat.axis_b { center_b += axis*(-0.5 if rl.Vector3DotProduct(axis, sat.normal) >= 0 else 0.5) }
	}
	point_a, point_b :=dice_physics_closest_segments(center_a-axes_a[sat.axis_a]*0.5, center_a+axes_a[sat.axis_a]*0.5,
		center_b-axes_b[sat.axis_b]*0.5, center_b+axes_b[sat.axis_b]*0.5)
	dice_physics_add_contact(contacts, a, b, (point_a+point_b)*0.5, sat.normal, sat.depth)
}

dice_physics_plane_contacts :: proc(body: ^Dice_Physics_Body, body_index: int, normal: rl.Vector3, plane_offset: f32, contacts: ^Dice_Physics_Contacts) {
	axes :=dice_physics_axes(body)
	// Plane normal points into the permitted region; contact normal points body -> plane.
	for x in 0..<2 { for y in 0..<2 { for z in 0..<2 {
		vertex := body.position+axes[0]*(f32(x)-0.5)+axes[1]*(f32(y)-0.5)+axes[2]*(f32(z)-0.5)
		distance := rl.Vector3DotProduct(vertex, normal)-plane_offset
		if distance > 0.002 { continue }
		dice_physics_add_contact(contacts, body_index, -1, vertex, -normal, max(f32(0), -distance))
		if normal.y > 0.5 {
			contacts.ground_contact = true
			contacts.ground_bodies[body_index] = true
		}
	} } }
}

dice_physics_velocity_at :: proc(body: ^Dice_Physics_Body, point: rl.Vector3) -> rl.Vector3 {
	return body.velocity+rl.Vector3CrossProduct(body.angular_velocity, point-body.position)
}

dice_physics_relative_velocity :: proc(bodies: []Dice_Physics_Body, contact: ^Dice_Physics_Contact) -> rl.Vector3 {
	velocity := -dice_physics_velocity_at(&bodies[contact.a], contact.point)
	if contact.b >= 0 { velocity +=dice_physics_velocity_at(&bodies[contact.b], contact.point) }
	return velocity
}

dice_physics_impulse_denominator :: proc(bodies: []Dice_Physics_Body, contact: ^Dice_Physics_Contact, direction: rl.Vector3) -> f32 {
	ra := rl.Vector3CrossProduct(contact.point-bodies[contact.a].position, direction)
	denominator := 1+DICE_PHYSICS_INVERSE_INERTIA*rl.Vector3DotProduct(ra, ra)
	if contact.b >= 0 {
		rb := rl.Vector3CrossProduct(contact.point-bodies[contact.b].position, direction)
		denominator += 1+DICE_PHYSICS_INVERSE_INERTIA*rl.Vector3DotProduct(rb, rb)
	}
	return denominator
}

dice_physics_apply_impulse :: proc(bodies: []Dice_Physics_Body, contact: ^Dice_Physics_Contact, impulse: rl.Vector3) {
	a := &bodies[contact.a]
	if a.asleep && rl.Vector3Length(impulse) > 0.02 { a.asleep = false; a.quiet_steps = 0 }
	a.velocity -= impulse
	a.angular_velocity -= rl.Vector3CrossProduct(contact.point-a.position, impulse)*DICE_PHYSICS_INVERSE_INERTIA
	if contact.b >= 0 {
		b := &bodies[contact.b]
		if b.asleep && rl.Vector3Length(impulse) > 0.02 { b.asleep = false; b.quiet_steps = 0 }
		b.velocity += impulse
		b.angular_velocity += rl.Vector3CrossProduct(contact.point-b.position, impulse)*DICE_PHYSICS_INVERSE_INERTIA
	}
}

dice_physics_solve_contacts :: proc(bodies: []Dice_Physics_Body, contacts: ^Dice_Physics_Contacts) {
	for &contact in contacts.items[:contacts.count] {
		closing := rl.Vector3DotProduct(dice_physics_relative_velocity(bodies, &contact), contact.normal)
		// A face shares one rebound target. Per-vertex restitution reflects spin
		// differently at each corner and turns a clean landing into a rocking edge.
		if contact.b < 0 { closing = bodies[contact.a].velocity.y }
		restitution: f32 = 0.70 if contact.b < 0 else 0.34
		contact.target_velocity = -closing*restitution if closing < -1.1 else 0
		// Tall letterboxed windows need a higher release, not an unbounded rebound.
		if contact.b < 0 { contact.target_velocity = min(contact.target_velocity, f32(9.6)) }
		contact.normal_mass = 1/dice_physics_impulse_denominator(bodies, &contact, contact.normal)
		contact.tangent_mass_1 = 1/dice_physics_impulse_denominator(bodies, &contact, contact.tangent_1)
		contact.tangent_mass_2 = 1/dice_physics_impulse_denominator(bodies, &contact, contact.tangent_2)
	}
	iterations := 16 if contacts.ground_contact else 8
	for _ in 0..<iterations {
		for &contact in contacts.items[:contacts.count] {
			velocity :=dice_physics_relative_velocity(bodies, &contact)
			change := (contact.target_velocity-rl.Vector3DotProduct(velocity, contact.normal))*contact.normal_mass
			previous := contact.normal_impulse
			contact.normal_impulse = max(f32(0), previous+change)
			dice_physics_apply_impulse(bodies, &contact, contact.normal*(contact.normal_impulse-previous))
			velocity =dice_physics_relative_velocity(bodies, &contact)
			friction := contact.friction_impulse
			friction.x -= rl.Vector3DotProduct(velocity, contact.tangent_1)*contact.tangent_mass_1
			friction.y -= rl.Vector3DotProduct(velocity, contact.tangent_2)*contact.tangent_mass_2
			friction_coefficient: f32 = 0.45 if contact.b < 0 && contact.target_velocity > 1 else 0.65
			limit := contact.normal_impulse*friction_coefficient
			length := rl.Vector2Length(friction)
			if length > limit && length > 0 { friction *= limit/length }
			difference := friction-contact.friction_impulse
			contact.friction_impulse = friction
			dice_physics_apply_impulse(bodies, &contact, contact.tangent_1*difference.x+contact.tangent_2*difference.y)
		}
	}
}

// Conservative position correction is separate from velocity impulses so resting
// penetration is not converted into an artificial source of bounce energy.
dice_physics_correct_positions :: proc(bodies: []Dice_Physics_Body) {
	for _ in 0..<4 {
		for &body in bodies {
			axes :=dice_physics_axes(&body)
			body.position.y = max(body.position.y,dice_physics_projected_radius(axes, {0, 1, 0})-0.0005)
		}
		for a in 0..<len(bodies) { for b in a+1..<len(bodies) {
			sat :=dice_physics_sat(&bodies[a], &bodies[b])
			if sat.overlaps && sat.depth > 0.0005 {
				correction := sat.normal*(sat.depth-0.0005)*0.45
				bodies[a].position -= correction
				bodies[b].position += correction
			}
		} }
	}
}

dice_physics_apply_floor_kick :: proc(body: ^Dice_Physics_Body, ground_contact: bool, incoming_velocity_y: f32) {
	new_impact := ground_contact && !body.floor_contact
	body.floor_contact = ground_contact
	if !new_impact || incoming_velocity_y >= -1.1 || body.floor_kicks >= 2 { return }
	// These two explicit arcade impulses act on the simulated rigid body once
	// per landing. The normal contact solver still supplies friction and torque.
	minimum_upward_velocity: f32 = 12 if body.floor_kicks == 0 else 9
	body.velocity.y = max(body.velocity.y, minimum_upward_velocity)
	spin_axis := body.rebound_spin_axis
	if rl.Vector3Length(spin_axis) < 0.1 { spin_axis = rl.Vector3Normalize({0.2, 0.04, 1}) }
	angular_impulse: f32 = 3.4 if body.floor_kicks == 0 else 2.1
	body.angular_velocity += spin_axis*angular_impulse
	angular_speed := rl.Vector3Length(body.angular_velocity)
	if angular_speed > 4 { body.angular_velocity *= 4/angular_speed }
	body.floor_kicks += 1
	body.quiet_steps, body.stationary_steps, body.asleep = 0, 0, false
}

dice_physics_step :: proc(bodies: []Dice_Physics_Body) -> (pair_contacts: int, ground_contact: bool) {
	incoming_velocity_y: [DICE_PHYSICS_MAX_BODIES]f32
	for &body, index in bodies {
		if body.asleep { continue }
		body.velocity.y -= 18*DICE_PHYSICS_DT
		body.velocity *= 1-DICE_PHYSICS_LINEAR_DAMPING*DICE_PHYSICS_DT
		if body.floor_kicks > 0 {
			body.velocity.x *= 1-2.2*DICE_PHYSICS_DT
			body.velocity.z *= 1-2.2*DICE_PHYSICS_DT
		}
		incoming_velocity_y[index] = body.velocity.y
		body.angular_velocity *= 1-DICE_PHYSICS_ANGULAR_DAMPING*DICE_PHYSICS_DT
		body.position += body.velocity*DICE_PHYSICS_DT
		speed := rl.Vector3Length(body.angular_velocity)
		if speed > 0.00001 {
			rotation := rl.QuaternionFromAxisAngle(body.angular_velocity/speed, speed*DICE_PHYSICS_DT)
			body.orientation = rl.QuaternionNormalize(rotation*body.orientation)
		}
	}
	contacts: Dice_Physics_Contacts
	for &body, index in bodies {
		if !body.asleep { dice_physics_plane_contacts(&body, index, {0, 1, 0}, 0, &contacts) }
	}
	for a in 0..<len(bodies) { for b in a+1..<len(bodies) {
		sat :=dice_physics_sat(&bodies[a], &bodies[b])
		if !sat.overlaps { continue }
		contacts.pair_count += 1
		if sat.face_body >= 0 {dice_physics_face_contacts(bodies, a, b, sat, &contacts) }
		else {dice_physics_edge_contacts(bodies, a, b, sat, &contacts) }
	} }
	dice_physics_solve_contacts(bodies, &contacts)
	dice_physics_correct_positions(bodies)
	for &body, index in bodies {
		dice_physics_apply_floor_kick(&body, contacts.ground_bodies[index], incoming_velocity_y[index])
		// Dissipative arcade contact friction bounds lateral energy without
		// rearranging positions or replacing the simulated angular trajectory.
		if body.floor_kicks > 0 && contacts.touched_bodies[index] {
			tangent_speed := rl.Vector2Length({body.velocity.x, body.velocity.z})
			if tangent_speed > 1.2 {
				body.velocity.x *= 1.2/tangent_speed
				body.velocity.z *= 1.2/tangent_speed
			}
		}
		axes := dice_physics_axes(&body)
		clearance := body.position.y-dice_physics_projected_radius(axes, {0, 1, 0})
		if clearance <= 0.012 {
			minimum_peak: f32 = 3 if body.visible_bounces == 0 else 1.5
			if body.touched_ground && body.bounce_peak >= minimum_peak { body.visible_bounces += 1 }
			body.touched_ground, body.bounce_peak = true, 0
		} else if body.touched_ground { body.bounce_peak = max(body.bounce_peak, clearance) }
		up := max(abs(axes[0].y), abs(axes[1].y), abs(axes[2].y))
		if rl.Vector3Length(body.velocity) < 0.05 && rl.Vector3Length(body.angular_velocity) < 0.06 {
			body.stationary_steps += 1
		} else { body.stationary_steps = 0 }
		if up > 0.99998 && abs(body.position.y-0.5) < 0.005 &&
		   rl.Vector3Length(body.velocity) < 0.04 && rl.Vector3Length(body.angular_velocity) < 0.05 {
			body.quiet_steps += 1
			if body.quiet_steps >= 18 { body.asleep = true; body.velocity = {}; body.angular_velocity = {} }
		} else { body.quiet_steps = 0; body.asleep = false }
	}
	return contacts.pair_count, contacts.ground_contact
}

Dice_Cosmetic_Random :: struct {state: u64}

dice_cosmetic_random :: proc(random: ^Dice_Cosmetic_Random) -> f32 {
	value := random.state
	value ~= value >> 12
	value ~= value << 25
	value ~= value >> 27
	random.state = value
	value *= 0x2545F4914F6CDD1D
	return f32(value>>40)/16777216
}

// Solve only the initial release. During playback every pose still comes from
// gravity and rigid-body contact impulses, including all X/Z tumbling.
dice_physics_free_fall_factors :: proc(height: f32) -> (rotation, aligned_height: f32) {
	y, velocity := height, f32(0)
	angular_decay := f32(1)
	for _ in 1..<DICE_THROW_FRAME_COUNT {
		velocity = (velocity-18*DICE_PHYSICS_DT)*(1-DICE_PHYSICS_LINEAR_DAMPING*DICE_PHYSICS_DT)
		y += velocity*DICE_PHYSICS_DT
		angular_decay *= 1-DICE_PHYSICS_ANGULAR_DAMPING*DICE_PHYSICS_DT
		rotation += angular_decay*DICE_PHYSICS_DT
		if y <= 0.5 { break }
	}
	// Align the actual first contact with a full face, rather than letting the
	// preceding step catch one rotating corner a fraction above the floor.
	aligned_height = height+0.5-y
	return
}

dice_physics_initial_bodies :: proc(count: int, seed: u64, release_height: f32, controlled: bool = false) -> (bodies: [3]Dice_Physics_Body) {
	random := Dice_Cosmetic_Random{seed if seed != 0 else 0xCC891031DB61EF12}
	group_yaw := (dice_cosmetic_random(&random)-0.5)*0.20
	group_rotation := rl.QuaternionFromAxisAngle({0, 1, 0}, group_yaw)
	group_offset := rl.Vector3{(dice_cosmetic_random(&random)-0.5)*0.16, 0, (dice_cosmetic_random(&random)-0.5)*0.12}
	rotation, aligned_height := dice_physics_free_fall_factors(release_height)
	angle := (1.5+dice_cosmetic_random(&random)*0.5)*(1 if dice_cosmetic_random(&random) > 0.5 else -1)
	spin_axis := rl.Vector3RotateByQuaternion({1, 0, 0}, group_rotation)
	for index in 0..<count {
		body := &bodies[index]
		x: f32
		if count > 1 { x = -1.15 if index == 0 else 1.15 if index == 1 else 0 }
		body.position = {x, aligned_height, 0}
		body.velocity = {-x*(0.84+dice_cosmetic_random(&random)*0.12), 0, 0}
		direction: f32 = 1 if index == 0 else -1
		body.angular_velocity = spin_axis*(angle/rotation)
		body.orientation = rl.QuaternionFromAxisAngle({1, 0, 0}, -angle)
		body.position = rl.Vector3RotateByQuaternion(body.position, group_rotation)+group_offset
		body.velocity = rl.Vector3RotateByQuaternion(body.velocity, group_rotation)
		body.orientation = group_rotation*body.orientation
		spin_random := Dice_Cosmetic_Random{seed~(u64(index+1)*0x9E3779B97F4A7C15)}
		body.rebound_spin_axis = rl.Vector3Normalize({(dice_cosmetic_random(&spin_random)-0.5)*0.7,
			(dice_cosmetic_random(&spin_random)-0.5)*0.1, direction})
		if controlled {
			// A bounded last attempt uses a symmetric release: still rigid bodies and
			// collisions, with fewer degrees of variation that could lead to a stack.
			fallback_x: f32 = 0 if count == 1 || index == 2 else -1.15 if index == 0 else 1.15
			body.position = {fallback_x, release_height, 0}
			body.velocity = {-fallback_x*0.6, 0, 0}
			body.angular_velocity = {0, direction*(0.6 if count == 1 else 1.2), 0}
			body.orientation = rl.QuaternionFromEuler(0, direction*0.08, 0)
		}
	}
	return
}

dice_physics_frame :: proc(bodies: []Dice_Physics_Body) -> (frame: Dice_Physics_Frame) {
	for body, index in bodies {
		frame.positions[index] = body.position
		frame.orientations[index] = body.orientation
	}
	return
}

dice_physics_rest_target :: proc(body: ^Dice_Physics_Body) -> Dice_Physics_Body {
	result := body^
	axes := dice_physics_axes(body)
	axis_index := 0
	for axis, index in axes { if abs(axis.y) > abs(axes[axis_index].y) { axis_index = index } }
	up := axes[axis_index]
	if up.y < 0 { up = -up }
	correction := rl.QuaternionFromVector3ToVector3(up, {0, 1, 0})
	result.orientation = rl.QuaternionNormalize(correction*body.orientation)
	result.position.y = 0.5
	result.velocity, result.angular_velocity = {}, {}
	return result
}

dice_physics_finish_quiet_tail :: proc(throw: ^Dice_Throw, bodies: []Dice_Physics_Body, final_index: int) -> bool {
	visible_bounces := 0
	for body in bodies {
		if !body.asleep || abs(body.position.x) > 2.4 || abs(body.position.z) > 1.2 { return false }
		visible_bounces = max(visible_bounces, body.visible_bounces)
	}
	if visible_bounces < 2 { return false }
	if len(bodies) > 1 && throw.contact_count == 0 { return false }
	rest: [3]Dice_Physics_Body
	for &body, index in bodies { rest[index] = dice_physics_rest_target(&body) }
	for a in 0..<len(bodies) { for b in a+1..<len(bodies) {
		sat := dice_physics_sat(&rest[a], &rest[b])
		if sat.overlaps && sat.depth > 0.001 { return false }
	} }
	// Only subpixel rest error is eased away. The contact simulation has already
	// stopped the cubes on faces; no positions are rearranged or results imposed.
	start := max(throw.first_impact_frame, final_index-18)
	for frame_index in start..=final_index {
		t := f32(frame_index-start)/f32(max(1, final_index-start))
		ease := tween.smoothstep(t)
		for index in 0..<len(bodies) {
			frame := &throw.frames[frame_index]
			frame.positions[index] += (rest[index].position-frame.positions[index])*ease
			frame.orientations[index] = rl.QuaternionNormalize(rl.QuaternionSlerp(frame.orientations[index], rest[index].orientation, ease))
		}
	}
	last := dice_physics_frame(rest[:len(bodies)])
	for frame_index in final_index..<DICE_THROW_FRAME_COUNT { throw.frames[frame_index] = last }
	throw.last_motion_frame = final_index
	return true
}

dice_physics_hold_tail :: proc(throw: ^Dice_Throw, last_frame: int) {
	if throw == nil || last_frame < 0 || last_frame >= DICE_THROW_FRAME_COUNT { return }
	last := throw.frames[last_frame]
	for frame_index in last_frame+1..<DICE_THROW_FRAME_COUNT { throw.frames[frame_index] = last }
	throw.last_motion_frame = last_frame
}

build_dice_throw :: proc(throw: ^Dice_Throw, count: int, seed: u64, release_height: f32 = 7) {
	if throw == nil { return }
	throw^ = {}
	defer prepare_dice_playback(throw)
	if count < 1 || count > DICE_PHYSICS_MAX_BODIES { return }
	height := release_height
	if math.is_nan(height) { height = 7 }
	height = clamp(height, f32(7), f32(24))
	random := Dice_Cosmetic_Random{seed if seed != 0 else 0xA9935611B2854397}
	last_frame := 0
	for attempt in 0..<4 {
		throw.count = count
		throw.attempts = attempt+1
		throw.contact_count, throw.first_impact_frame = 0, 0
		bodies := dice_physics_initial_bodies(count, random.state, height, attempt == 3)
		dice_cosmetic_random(&random)
		throw.frames[0] = dice_physics_frame(bodies[:count])
		last_frame = 0
		for frame_index in 1..<DICE_THROW_FRAME_COUNT {
			pairs, ground := dice_physics_step(bodies[:count])
			throw.contact_count += pairs
			if ground && throw.first_impact_frame == 0 { throw.first_impact_frame = frame_index }
			throw.frames[frame_index] = dice_physics_frame(bodies[:count])
			last_frame = frame_index
			throw.physics_steps += 1
			invalid_rest := false
			for body in bodies[:count] {
				if body.stationary_steps >= 24 && !body.asleep && body.position.y > 0.52 { invalid_rest = true }
				if body.asleep && (abs(body.position.x) > 2.4 || abs(body.position.z) > 1.2) { invalid_rest = true }
			}
			if invalid_rest { break }
			asleep := true
			for body in bodies[:count] { asleep = asleep && body.asleep }
			if asleep {
				throw.settled = dice_physics_finish_quiet_tail(throw, bodies[:count], frame_index)
				break
			}
		}
		if throw.settled { return }
	}
	// A failed final attempt must never expose tail frames left by a prior attempt.
	// This remains a coherent (reported unsettled) trajectory, without rearrangement.
	dice_physics_hold_tail(throw, last_frame)
}
