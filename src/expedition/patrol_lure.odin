package expedition

import grid "../engine/grid"
import game "../game"
import level "../level"

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
		if !group.patrol || group.active || !in_scope(w,group.cave) {continue}
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

// The window of the patrol's distance field round its target: a cell's place in it, on its layer (one layer only
// on a map without others), and the cell at a place.
@(private)
Patrol_Window :: struct { origin:grid.Position, layers:int }

@(private)
patrol_window_index :: proc(window:Patrol_Window,p:grid.Position)->(index:int,ok:bool) {
	x,y:=p.x-window.origin.x,p.y-window.origin.y
	layer:=int(p.layer)-grid.LOWEST_LAYER if window.layers>1 else 0
	if x<0 || y<0 || x>=PATROL_PATH_SIDE || y>=PATROL_PATH_SIDE || layer<0 || layer>=window.layers {return}
	return (layer*PATROL_PATH_SIDE+y)*PATROL_PATH_SIDE+x,true
}

@(private)
patrol_window_cell :: proc(window:Patrol_Window,index:int)->grid.Position {
	at:=index%(PATROL_PATH_SIDE*PATROL_PATH_SIDE)
	layer:=i8(index/(PATROL_PATH_SIDE*PATROL_PATH_SIDE)+grid.LOWEST_LAYER) if window.layers>1 else grid.GROUND_LAYER
	return {x = window.origin.x+at%PATROL_PATH_SIDE, y = window.origin.y+at/PATROL_PATH_SIDE, layer = layer}
}

@(private)
patrol_move_toward :: proc(w:^World,room:^game.Room,g:^Group,target:grid.Position,stop_distance:int) {
	// One small distance field serves the entire patrol, across the layers as a walker steps (a cave's mouth:
	// game.layer_step). Static blockers shape the route; actors are checked at the final step.
	window:=Patrol_Window{origin = grid.offset(target, -PATROL_PATH_RADIUS, -PATROL_PATH_RADIUS), layers = level.LAYER_COUNT if game.room_has_layers(room) else 1}
	cells:=PATROL_PATH_SIDE*PATROL_PATH_SIDE*window.layers
	distances:=make([]i16,cells,context.temp_allocator)
	queue:=make([]i32,cells,context.temp_allocator)
	blocked:=make([]bool,cells,context.temp_allocator)
	for &d in distances {d= -1}
	mark :: proc(blocked:[]bool,window:Patrol_Window,p:grid.Position) {if i,ok:=patrol_window_index(window,p);ok {blocked[i]=true}}
	mark(blocked,window,room.player.position)
	for enemy in room.enemies {mark(blocked,window,enemy.position)}
	for &other in w.groups[:w.group_count] {if &other==g {continue};for member in other.members[:other.count] {
		if member.alive && !member.deployed {mark(blocked,window,member.enemy.position)}
	}}
	start,inside:=patrol_window_index(window,target)
	if !inside {return}
	distances[start]=0;queue[0]=i32(start);head,tail:=0,1
	steps:=[4]grid.Position{{x = 0, y = -1},{x = 1, y = 0},{x = 0, y = 1},{x = -1, y = 0}}
	for head<tail {
		i:=int(queue[head]);head+=1
		cell:=patrol_window_cell(window,i)
		for step in steps {
			next,_:=game.layer_step(room,cell,step)
			j,ok:=patrol_window_index(window,next)
			if !ok || distances[j]>=0 || blocked[j] || game.cell_blocks_movement(room,next) || game.step_height_blocked(room,cell,next) {continue}
			distances[j]=distances[i]+1;queue[tail]=i32(j);tail+=1
		}
	}
	for &member in g.members[:g.count] {
		if !member.alive || member.deployed || distance(member.enemy.position,target)<=stop_distance {continue}
		p:=member.enemy.position
		here,ok:=patrol_window_index(window,p)
		if !ok {continue}
		best:=distances[here];destination:=p
		if best<0 {continue}
		for step in steps {
			q,_:=game.layer_step(room,p,step)
			j,in_window:=patrol_window_index(window,q)
			if !in_window {continue}
			d:=distances[j]
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
