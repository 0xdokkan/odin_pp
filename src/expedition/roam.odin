package expedition

import "core:math"
import grid "../engine/grid"
import game "../game"

// Exploration walks continuously; encounters keep their cell steps. The cell
// under the explorer's center stays the room's authoritative position, so
// every rule written for cells (sites, traps, lava, patrols, engagement)
// still reads the same grid while the body glides between cell centers.
ROAM_RADIUS :: f32(0.3)
ROAM_WALK_SPEED :: f32(3.6)
ROAM_MOUNT_SPEED :: f32(8.4)
// A substep never crosses more than one cell edge per axis, and stays below
// the radius, so the center can never tunnel into a blocker.
ROAM_MAX_STEP :: f32(0.2)

Roam :: struct {
	// Cell units: cell (x,y) spans [x,x+1)×[y,y+1); its center is +0.5.
	position, velocity: [2]f32,
	// Presentation-only: eases out a relocation forced by gravity or wind.
	offset: [2]f32,
	cell: grid.Position,
	// Distance walked, for the gait of the robot and its mount.
	stride: f32,
	ready: bool,
}

roam_center :: proc(cell:grid.Position)->[2]f32 {return {f32(cell.x)+.5,f32(cell.y)+.5}}
roam_cell :: proc(p:[2]f32)->grid.Position {return {x = int(math.floor(p.x)), y = int(math.floor(p.y))}}

// Gravity wells, wind, tunnels, encounters and saves move the room's player
// directly. The walker adopts that cell instead of overriding it.
roam_sync :: proc(r:^Roam,room:^game.Room) {
	if r==nil || room==nil || room.player==nil {return}
	cell:=room.player.position
	if r.ready && cell==r.cell {return}
	target:=roam_center(cell)
	// A short shove glides; a tunnel or a restored save simply arrives.
	jump:=r.position+r.offset-target
	r.offset={}
	if r.ready && abs(jump.x)+abs(jump.y)<4 {r.offset=jump}
	r.position=target;r.velocity={};r.cell=cell;r.ready=true
}

// The cell the walker stands in never blocks it: a light bridge may close
// beneath the robot, and it can still step off. A cell more than a step higher or lower than the one
// it stands in is a cliff, a wall to a walker (game/height.odin), whether on foot or in the saddle.
@(private)
roam_blocked :: proc(r:^Roam,room:^game.Room,cell:grid.Position)->bool {
	return cell!=r.cell && (game.cell_blocks_movement(room,cell) || game.step_height_blocked(room,r.cell,cell))
}

// Circle against solid cells. A corner shared with a neighbouring solid cell
// is an inner seam of a flat wall: it pushes along the wall's face, never
// against the walk, so sliding along long walls does not catch at the seams.
@(private)
roam_resolve :: proc(r:^Roam,room:^game.Room) {
	for _ in 0..<3 {
		pushed:=false
		base:=roam_cell(r.position)
		for dy in -1..=1 {for dx in -1..=1 {
			cell:=grid.offset(base, dx, dy)
			if !roam_blocked(r,room,cell) {continue}
			lo:=[2]f32{f32(cell.x),f32(cell.y)};hi:=lo+1
			closest:=[2]f32{clamp(r.position.x,lo.x,hi.x),clamp(r.position.y,lo.y,hi.y)}
			d:=r.position-closest;length:=math.sqrt(d.x*d.x+d.y*d.y)
			if length>=ROAM_RADIUS {continue}
			normal:[2]f32;depth:f32
			if length<1e-5 {
				// Only reachable after an external relocation: leave by the nearest face.
				faces:=[4]f32{r.position.x-lo.x,hi.x-r.position.x,r.position.y-lo.y,hi.y-r.position.y}
				normals:=[4][2]f32{{-1,0},{1,0},{0,-1},{0,1}}
				side:=0;for f,i in faces {if f<faces[side] {side=i}}
				normal=normals[side];depth=faces[side]+ROAM_RADIUS
			} else {
				normal=d/length;depth=ROAM_RADIUS-length
				if d.x!=0 && d.y!=0 {
					sx,sy:=int(math.sign(d.x)),int(math.sign(d.y))
					along_x:=roam_blocked(r,room,grid.offset(cell, sx, 0))
					along_y:=roam_blocked(r,room,grid.offset(cell, 0, sy))
					if along_x && along_y {continue}
					if along_x {normal={0,f32(sy)};depth=ROAM_RADIUS-abs(d.y)}
					else if along_y {normal={f32(sx),0};depth=ROAM_RADIUS-abs(d.x)}
				}
			}
			if depth<=0 {continue}
			r.position+=normal*depth;pushed=true
			into:=r.velocity.x*normal.x+r.velocity.y*normal.y
			if into<0 {r.velocity-=normal*into}
		}}
		if !pushed {break}
	}
}

// Entering a cell uses the exact trap and hazard pipeline of a grid step.
@(private)
roam_enter :: proc(w:^World,room:^game.Room,r:^Roam,cell:grid.Position)->bool {
	r.cell=cell;room.player.position=cell
	before:=room.player.health
	game.expedition_enter_cell(room)
	if room.player.health<before {w.mounted=false}
	if room.player.health<=0 {room.phase=.Defeat;r.velocity={};return false}
	if room.player.position!=cell || room.phase!=.Loot {r.velocity={};roam_sync(r,room);return false}
	return true
}

roam_speed :: proc(w:^World,ground:Terrain)->f32 {
	speed:=ROAM_MOUNT_SPEED if w.mounted else ROAM_WALK_SPEED
	if ground==.Sand || ground==.Water || ground==.Snow || ground==.Swamp {speed*=.5}
	return speed
}

// `wish` is the walk direction in cells, already turned to the camera; its
// length is clamped to one. Exploration only: encounters own the cell steps.
roam_step :: proc(w:^World,room:^game.Room,r:^Roam,wish:[2]f32,dt:f32) {
	if w==nil || room==nil || room.player==nil || r==nil {return}
	if room.phase!=.Loot {
		// Encounters step by cells: the walker waits at the cell's center.
		r^={position=roam_center(room.player.position),cell=room.player.position,stride=r.stride,ready=true}
		return
	}
	roam_sync(r,room)
	elapsed:=min(max(dt,0),f32(.1))
	r.offset*=math.exp(-12*elapsed)
	if elapsed<=0 {return}
	under:=ground(w,r.cell)
	direction:=wish;length:=math.sqrt(direction.x*direction.x+direction.y*direction.y)
	if length>1 {direction/=length;length=1}
	// Brisk on foot, weighty in the saddle, slippery on ice.
	rate:=f32(4.5) if w.mounted else 16
	if length<.01 {rate=6 if w.mounted else 22}
	if under==.Ice {rate=2.2 if length>=.01 else .7}
	r.velocity+=(direction*roam_speed(w,under)-r.velocity)*(1-math.exp(-rate*elapsed))
	if length<.01 && r.velocity.x*r.velocity.x+r.velocity.y*r.velocity.y<.0004 {r.velocity={}}
	travel:=r.velocity*elapsed
	steps:=max(1,int(math.ceil(max(abs(travel.x),abs(travel.y))/ROAM_MAX_STEP)))
	start:=r.position
	for _ in 0..<steps {
		r.position+=travel/f32(steps)
		roam_resolve(r,room)
		cell:=roam_cell(r.position)
		if cell!=r.cell && !roam_enter(w,room,r,cell) {return}
	}
	moved:=r.position-start
	r.stride+=math.sqrt(moved.x*moved.x+moved.y*moved.y)
}
