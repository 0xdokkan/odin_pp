package expedition

import grid "../engine/grid"
import game "../game"

PATROL_LURE_RANGE :: 24
PATROL_LURE_SECONDS :: f32(40)
PATROL_LURE_WAIT_SECONDS :: f32(6)
PATROL_PATH_RADIUS :: 32
PATROL_PATH_SIDE :: PATROL_PATH_RADIUS*2+1

// A lure retains the patrol's original anchor. The group really travels to
// the sound, investigates briefly, then returns to its original territory.
lure_patrol :: proc(w:^World,room:^game.Room,target:grid.Position)->bool {
	if w==nil || room==nil || room.player==nil || !game.base_cell_is_walkable(room,target) || game.cell_blocks_movement(room,target) {return false}
	best:= -1;nearest:=PATROL_LURE_RANGE+1
	for &group,i in w.groups[:w.group_count] {
		if !group.patrol || group.active {continue}
		for member in group.members[:group.count] {
			if !member.alive || member.deployed {continue}
			d:=distance(member.enemy.position,target)
			if d<nearest {nearest=d;best=i}
		}
	}
	if best<0 {return false}
	g:=&w.groups[best];g.lure_phase=.Seeking;g.lure_target=target;g.lure_until=w.clock+PATROL_LURE_SECONDS;g.lure_wait_until=0;g.pursuing=false
	return true
}

@(private)
patrol_cell_free :: proc(w:^World,room:^game.Room,p:grid.Position,self:^Member)->bool {
	if p==room.player.position || game.cell_blocks_movement(room,p) {return false}
	for enemy in room.enemies {if enemy.position==p {return false}}
	for &group in w.groups[:w.group_count] {for &member in group.members[:group.count] {
		if &member!=self && member.alive && !member.deployed && member.enemy.position==p {return false}
	}}
	return true
}

@(private)
patrol_mark_occupied :: proc(blocked:^[PATROL_PATH_SIDE*PATROL_PATH_SIDE]bool,origin,p:grid.Position) {
	x,y:=p.x-origin.x,p.y-origin.y
	if x>=0 && y>=0 && x<PATROL_PATH_SIDE && y<PATROL_PATH_SIDE {blocked[y*PATROL_PATH_SIDE+x]=true}
}

@(private)
patrol_move_toward :: proc(w:^World,room:^game.Room,g:^Group,target:grid.Position,stop_distance:int) {
	// One small, allocation-free distance field serves the entire patrol.
	// Static blockers shape the route; actors are checked at the final step.
	distances:[PATROL_PATH_SIDE*PATROL_PATH_SIDE]i16
	for &d in distances {d= -1}
	queue:[PATROL_PATH_SIDE*PATROL_PATH_SIDE]u16
	origin:=grid.Position{target.x-PATROL_PATH_RADIUS,target.y-PATROL_PATH_RADIUS}
	blocked:[PATROL_PATH_SIDE*PATROL_PATH_SIDE]bool
	patrol_mark_occupied(&blocked,origin,room.player.position)
	for enemy in room.enemies {patrol_mark_occupied(&blocked,origin,enemy.position)}
	for &other in w.groups[:w.group_count] {if &other==g {continue};for member in other.members[:other.count] {
		if member.alive && !member.deployed {patrol_mark_occupied(&blocked,origin,member.enemy.position)}
	}}
	center:=PATROL_PATH_RADIUS*PATROL_PATH_SIDE+PATROL_PATH_RADIUS
	distances[center]=0;queue[0]=u16(center);head,tail:=0,1
	steps:=[4]grid.Position{{0,-1},{1,0},{0,1},{-1,0}}
	for head<tail {
		i:=int(queue[head]);head+=1;x,y:=i%PATROL_PATH_SIDE,i/PATROL_PATH_SIDE
		for step in steps {
			nx,ny:=x+step.x,y+step.y
			if nx<0 || ny<0 || nx>=PATROL_PATH_SIDE || ny>=PATROL_PATH_SIDE {continue}
			j:=ny*PATROL_PATH_SIDE+nx
			if distances[j]>=0 || blocked[j] || game.cell_blocks_movement(room,{origin.x+nx,origin.y+ny}) ||
			   game.step_height_blocked(room,{origin.x+x,origin.y+y},{origin.x+nx,origin.y+ny}) {continue}
			distances[j]=distances[i]+1;queue[tail]=u16(j);tail+=1
		}
	}
	for &member in g.members[:g.count] {
		if !member.alive || member.deployed || distance(member.enemy.position,target)<=stop_distance {continue}
		p:=member.enemy.position;local:=grid.Position{p.x-origin.x,p.y-origin.y}
		if local.x<0 || local.y<0 || local.x>=PATROL_PATH_SIDE || local.y>=PATROL_PATH_SIDE {continue}
		best:=distances[local.y*PATROL_PATH_SIDE+local.x];destination:=p
		if best<0 {continue}
		for step in steps {
			q:=game.add_position(p,step);nx,ny:=local.x+step.x,local.y+step.y
			if nx<0 || ny<0 || nx>=PATROL_PATH_SIDE || ny>=PATROL_PATH_SIDE {continue}
			d:=distances[ny*PATROL_PATH_SIDE+nx]
			if d<0 || d>=best || !patrol_cell_free(w,room,q,&member) || game.step_height_blocked(room,p,q) {continue}
			best=d;destination=q
		}
		member.enemy.position=destination
	}
}

@(private)
tick_patrol_lure :: proc(w:^World,room:^game.Room,g:^Group,step_due:bool) {
	if g.lure_phase==.None {return}
	if w.clock>=g.lure_until && g.lure_phase!=.Returning {g.lure_phase=.Returning}
	if g.lure_phase==.Waiting && w.clock>=g.lure_wait_until {g.lure_phase=.Returning}
	if g.lure_phase==.Seeking {
		arrived:=false
		for member in g.members[:g.count] {if member.alive && distance(member.enemy.position,g.lure_target)<=2 {arrived=true}}
		if arrived {g.lure_phase=.Waiting;g.lure_wait_until=min(g.lure_until,w.clock+PATROL_LURE_WAIT_SECONDS)}
	}
	if g.lure_phase==.Returning {
		home:=true
		for member in g.members[:g.count] {if member.alive && distance(member.enemy.position,g.anchor)>3 {home=false}}
		if home {g.lure_phase=.None;g.patrol_step=0;return}
	}
	if !step_due || g.lure_phase==.Waiting {return}
	patrol_move_toward(w,room,g,g.anchor if g.lure_phase==.Returning else g.lure_target,3 if g.lure_phase==.Returning else 2)
}
