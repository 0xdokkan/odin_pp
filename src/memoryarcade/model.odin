// Six memories, six independent rulesets. Simulation never reads devices or
// calls the renderer: the same seed and commands reproduce an entire round.
package memoryarcade

import "core:math"
import rng "../engine/rng"
import host "../engine/host"

Kind :: enum u8 { Lightcycles, Showdown, Trex, Karaoke, Helicopter, Descent }
TICK :: f32(1.0/120.0)
GRID_W :: 54
GRID_H :: 30
NOTE_COUNT :: 64

Command :: struct {
	move: [2]f32,
	turn: int,
	jump, duck, fire, reload: bool,
	lanes: [4]bool,
	aim: [2]f32,
}
Obstacle :: struct { active: bool, pos: [2]f32, kind: int, timer: f32, resolved: bool }
Cycle :: struct { alive: bool, pos: [2]int, dir: int, previous: [2]int }
Note :: struct { time: f32, lane: int, judgement: int }
State :: struct {
	kind: Kind,
	random: rng.Rng,
	time: f32,
	status: host.Round_Status,
	score, combo, best_combo, health, hits, misses: int,
	flash, shake, invincible, clock, spawn_clock: f32,
	pos, velocity: [2]f32,
	obstacles: [48]Obstacle,
	// Light cycles: trail ownership is permanent for the entire round.
	grid: [GRID_W*GRID_H]u8,
	cycles: [4]Cycle,
	cycle_steps: int,
	// Showdown: five draws, each with its own concealed cue.
	duel, duel_wins: int,
	cue, reaction, round_pause: f32,
	early, fired: bool,
	// Karaoke: authored rhythm with seed-derived phrases and lane changes.
	notes: [NOTE_COUNT]Note,
	judged, perfect: int,
	judgement: int,
	// Helicopter: magazine and crosshair are part of the model.
	ammo: int,
	reload_timer, shot_timer: f32,
	aim: [2]f32,
}

reset :: proc(s: ^State, kind: Kind, seed: u64) {
	s^ = State{kind=kind, random=rng.create(rng.derive(seed,u64(kind))), health=3,
		pos={0.2,0.78}, ammo=16, aim={0.5,0.5}}
	s.spawn_clock=1.4
	s.cue=rng.float_range(&s.random,2,4.5)
	if kind == .Lightcycles {
		s.cycles = {{true,{8,8},0,{8,8}}, {true,{45,8},2,{45,8}},
			{true,{45,22},2,{45,22}}, {true,{8,22},0,{8,22}}}
		for c,i in s.cycles { s.grid[c.pos.y*GRID_W+c.pos.x]=u8(i+1) }
	}
	if kind == .Karaoke {
		for &n,i in s.notes {
			n.time=f32(i+4)*(60.0/112.0)
			n.lane=(i%4+int(rng.below(&s.random,3)))%4
			if i%8==6 { n.time-=60.0/224.0 }
		}
	}
	if kind == .Helicopter { s.health=6; s.spawn_clock=0.3 }
	if kind == .Descent { s.pos={0.5,0.8}; s.spawn_clock=0.35 }
}

damage :: proc(s: ^State) {
	if s.invincible>0 { return }
	s.health-=1
	s.invincible=1.2
	s.shake=0.35
	s.flash=0.25
	s.combo=0
	if s.health<=0 { s.status=.Lost }
}

free_obstacle :: proc(s: ^State) -> ^Obstacle {
	for &o in s.obstacles { if !o.active { return &o } }
	return nil
}

dir_delta :: proc(dir: int) -> [2]int {
	switch dir%4 {
	case 0: return {1,0}
	case 1: return {0,1}
	case 2: return {-1,0}
	case 3: return {0,-1}
	}
	return {}
}

cycle_open :: proc(s: ^State, pos: [2]int) -> bool {
	return pos.x>=0 && pos.x<GRID_W && pos.y>=0 && pos.y<GRID_H && s.grid[pos.y*GRID_W+pos.x]==0
}

// Reachability, not omniscience: opponents prefer the lane with breathing
// room, but only inspect a short corridor and the next turn.
cycle_space :: proc(s: ^State, pos: [2]int, dir: int) -> int {
	score:=0
	for n in 1..=14 {
		p:=pos+dir_delta(dir)*n
		if !cycle_open(s,p) { break }
		score+=2
		if cycle_open(s,p+dir_delta((dir+1)%4)) { score+=1 }
		if cycle_open(s,p+dir_delta((dir+3)%4)) { score+=1 }
	}
	return score
}

step_cycles :: proc(s: ^State, cmd: Command, dt: f32) {
	c:=&s.cycles[0]
	if cmd.turn!=0 { c.dir=(c.dir+cmd.turn+4)%4 }
	if cmd.move.x!=0 || cmd.move.y!=0 {
		d:=0
		if cmd.move.x<0 { d=2 } else if cmd.move.y>0 { d=1 } else if cmd.move.y<0 { d=3 }
		if (d+2)%4!=c.dir { c.dir=d }
	}
	s.clock+=dt
	if s.clock<0.105 { return }
	s.clock-=0.105
	s.cycle_steps+=1
	next: [4][2]int
	for &bike,i in s.cycles {
		if !bike.alive { continue }
		if i>0 {
			best:=-1
			chosen:=bike.dir
			for turn in -1..=1 {
				d:=(bike.dir+turn+4)%4
				value:=cycle_space(s,bike.pos,d)*10
				if turn==0 { value+=12 }
				value+=int(rng.below(&s.random,8))
				if value>best { best=value; chosen=d }
			}
			bike.dir=chosen
		}
		next[i]=bike.pos+dir_delta(bike.dir)
	}
	// Resolve all heads simultaneously, including head-on collisions.
	crashed: [4]bool
	for bike,i in s.cycles {
		if !bike.alive { continue }
		blocked:=!cycle_open(s,next[i])
		for other,j in s.cycles { if i!=j && other.alive && next[i]==next[j] { blocked=true } }
		crashed[i]=blocked
	}
	for &bike,i in s.cycles {
		if crashed[i] { bike.alive=false; s.flash=0.3; if i>0 { s.score+=500 } }
	}
	alive:=0
	for &bike,i in s.cycles {
		if !bike.alive { continue }
		bike.previous=bike.pos
		bike.pos=next[i]
		s.grid[bike.pos.y*GRID_W+bike.pos.x]=u8(i+1)
		alive+=1
	}
	if !s.cycles[0].alive { s.status=.Lost } else {
		s.score+=5
		if alive==1 || s.time>=60 { s.status=.Won }
	}
}

step_showdown :: proc(s: ^State, cmd: Command, dt: f32) {
	if s.round_pause>0 {
		s.round_pause-=dt
		if s.round_pause<=0 {
			s.duel+=1
			if s.duel>=5 { s.status=.Won if s.duel_wins>=3 else .Lost; return }
			s.clock=0; s.fired=false; s.early=false
			s.cue=rng.float_range(&s.random,1.7,4.7)
		}
		return
	}
	s.clock+=dt
	limit:=0.68-f32(s.duel)*0.055
	if cmd.fire || cmd.jump {
		s.fired=true
		s.early=s.clock<s.cue
		s.reaction=s.clock-s.cue
		if !s.early && s.reaction<=limit {
			s.duel_wins+=1; s.score+=max(100,1000-int(s.reaction*1400)); s.flash=0.15
		} else { s.health-=1; s.shake=0.3 }
		s.round_pause=1.5
	} else if s.clock>s.cue+limit {
		s.health-=1; s.reaction=limit; s.round_pause=1.5; s.shake=0.3
	}
	if s.health<=0 { s.status=.Lost }
}

step_trex :: proc(s: ^State, cmd: Command, dt: f32) {
	if cmd.jump && s.pos.y>=0.779 { s.velocity.y=-1.45 }
	s.velocity.y+=3.8*dt
	s.pos.y=min(0.78,s.pos.y+s.velocity.y*dt)
	if s.pos.y>=0.78 { s.velocity.y=0 }
	s.spawn_clock-=dt
	if s.spawn_clock<=0 {
		if o:=free_obstacle(s); o!=nil {
			o^=Obstacle{active=true,pos={1.08,0.78},kind=int(rng.below(&s.random,3))}
			if o.kind==2 { o.pos.y=0.59 }
		}
		s.spawn_clock=rng.float_range(&s.random,1.05,1.7)
	}
	for &o in s.obstacles {
		if !o.active { continue }
		o.pos.x-=(0.36+s.time*0.0024)*dt
		if !o.resolved && math.abs(o.pos.x-s.pos.x)<0.045 {
			collides:=s.pos.y>0.64 if o.kind!=2 else (!cmd.duck && s.pos.y>0.54 && s.pos.y<0.8)
			if collides { damage(s); o.resolved=true }
		}
		if !o.resolved && o.pos.x<s.pos.x-0.055 { o.resolved=true; s.score+=100; s.combo+=1; s.best_combo=max(s.best_combo,s.combo) }
		if o.pos.x< -0.1 { o.active=false }
	}
	if s.time>=48 && s.health>0 { s.status=.Won; s.score+=s.health*300 }
}

step_karaoke :: proc(s: ^State, cmd: Command, dt: f32) {
	for pressed,lane in cmd.lanes {
		if !pressed { continue }
		closest:=-1
		window:=f32(0.16)
		for n,i in s.notes {
			if n.judgement!=0 || n.lane!=lane { continue }
			d:=math.abs(n.time-s.time)
			if d<window { closest=i; window=d }
		}
		if closest>=0 {
			n:=&s.notes[closest]
			n.judgement=3 if window<=0.065 else 2
			s.judgement=n.judgement
			s.judged+=1; s.hits+=1; s.combo+=1
			s.perfect+=1 if n.judgement==3 else 0
			s.best_combo=max(s.best_combo,s.combo)
			s.score+=(100 if n.judgement==3 else 65)+min(s.combo,30)*2
			s.flash=0.24
		} else { s.combo=0; s.judgement=-1; s.flash=0.18; s.score=max(0,s.score-25) }
	}
	for &n in s.notes {
		if n.judgement==0 && s.time>n.time+0.16 {
			n.judgement=-1; s.judged+=1; s.misses+=1; s.combo=0; s.judgement=-1
		}
	}
	if s.time>s.notes[NOTE_COUNT-1].time+1.2 { s.status=.Won if s.hits>=NOTE_COUNT/3 else .Lost }
}

step_helicopter :: proc(s: ^State, cmd: Command, dt: f32) {
	s.aim=cmd.aim
	s.shot_timer=max(0,s.shot_timer-dt)
	if cmd.reload && s.ammo<16 && s.reload_timer<=0 { s.reload_timer=1.2 }
	if s.reload_timer>0 {
		s.reload_timer-=dt
		if s.reload_timer<=0 { s.ammo=16 }
	} else if cmd.fire && s.shot_timer<=0 {
		if s.ammo==0 { s.reload_timer=1.2 } else {
			s.ammo-=1; s.shot_timer=0.14; s.flash=0.06
			for &o in s.obstacles {
				if !o.active { continue }
				d:=o.pos-s.aim
				if d.x*d.x+d.y*d.y<0.0036 {
					o.active=false; s.score+=150; s.hits+=1; s.combo+=1; s.best_combo=max(s.best_combo,s.combo)
					break
				}
			}
		}
	}
	s.spawn_clock-=dt
	if s.spawn_clock<=0 {
		if o:=free_obstacle(s); o!=nil {
			o^=Obstacle{active=true,pos={rng.float_range(&s.random,0.15,0.85),rng.float_range(&s.random,0.30,0.72)},
				kind=int(rng.below(&s.random,3)),timer=rng.float_range(&s.random,2.7,4.1)}
		}
		s.spawn_clock=max(0.42,0.95-s.time*0.009)
	}
	for &o in s.obstacles {
		if !o.active { continue }
		o.timer-=dt
		o.pos.x-=dt*0.012
		if o.timer<=0 { damage(s); o.active=false; s.misses+=1 }
	}
	if s.time>=45 && s.health>0 { s.status=.Won; s.score+=s.health*200 }
}

step_descent :: proc(s: ^State, cmd: Command, dt: f32) {
	s.velocity.x+=(cmd.move.x*3.8-s.velocity.x*4.5)*dt
	s.pos.x=clamp(s.pos.x+s.velocity.x*dt,0.08,0.92)
	s.spawn_clock-=dt
	if s.spawn_clock<=0 {
		if o:=free_obstacle(s); o!=nil {
			o^=Obstacle{active=true,pos={rng.float_range(&s.random,0.12,0.88),0.13},kind=int(rng.below(&s.random,5))}
		}
		s.spawn_clock=rng.float_range(&s.random,0.32,0.6)
	}
	for &o in s.obstacles {
		if !o.active { continue }
		o.pos.y+=(0.23+s.time*0.002)*dt
		if !o.resolved && o.pos.y>=s.pos.y-0.02 {
			o.resolved=true
			d:=math.abs(s.pos.x-o.pos.x)
			if o.kind==4 {
				if d<0.115 { s.score+=250; s.hits+=1; s.combo+=1; s.flash=0.2 }
				else { s.misses+=1; s.combo=0 }
			} else if d<0.055 { damage(s) } else { s.score+=40 }
			s.best_combo=max(s.best_combo,s.combo)
		}
		if o.pos.y>1.15 { o.active=false }
	}
	if s.time>=48 && s.health>0 { s.status=.Won; s.score+=s.health*300 }
}

step :: proc(s: ^State, cmd: Command, dt: f32=TICK) -> host.Round_Status {
	if s.status!=.Playing { return s.status }
	s.time+=dt
	s.flash=max(0,s.flash-dt); s.shake=max(0,s.shake-dt); s.invincible=max(0,s.invincible-dt)
	switch s.kind {
	case .Lightcycles: step_cycles(s,cmd,dt)
	case .Showdown: step_showdown(s,cmd,dt)
	case .Trex: step_trex(s,cmd,dt)
	case .Karaoke: step_karaoke(s,cmd,dt)
	case .Helicopter: step_helicopter(s,cmd,dt)
	case .Descent: step_descent(s,cmd,dt)
	}
	return s.status
}

stars :: proc(s: ^State) -> u8 {
	if s.status!=.Won { return 0 }
	switch s.kind {
	case .Lightcycles: return 3 if s.score>=2000 else 2
	case .Showdown: return 3 if s.duel_wins==5 else (2 if s.duel_wins==4 else 1)
	case .Trex, .Descent: return u8(clamp(s.health,1,3))
	case .Karaoke: return 3 if s.hits>=58 && s.perfect>=40 else (2 if s.hits>=48 else 1)
	case .Helicopter: return 3 if s.health>=5 && s.hits>=45 else (2 if s.health>=3 else 1)
	}
	return 1
}

// Shared with smoke captures and deterministic endurance tests. It is a
// player of the normal rules, never an alternate simulation.
autoplay :: proc(s: ^State) -> Command {
	c:=Command{aim={0.5,0.5}}
	switch s.kind {
	case .Lightcycles:
		if s.clock+TICK<0.105 { return c }
		bike:=s.cycles[0]; chosen:=bike.dir; best:=-1000000
		for turn in -1..=1 {
			d:=(bike.dir+turn+4)%4
			value:=cycle_area(s,bike.pos+dir_delta(d))*10+cycle_space(s,bike.pos,d)
			if turn==0 { value+=2 }
			for enemy,i in s.cycles {
				if i==0 || !enemy.alive { continue }
				ahead:=bike.pos+dir_delta(d)*3
				distance:=abs(ahead.x-enemy.pos.x)+abs(ahead.y-enemy.pos.y)
				if distance<5 { value-=30000+(5-distance)*100 }
			}
			if value>best { chosen=d; best=value }
		}
		d:=dir_delta(chosen); c.move={f32(d.x),f32(d.y)}
	case .Showdown: c.fire=s.clock>=s.cue+0.22 && s.round_pause<=0
	case .Trex:
		for o in s.obstacles {
			if o.active && o.pos.x>s.pos.x-0.07 && o.pos.x<s.pos.x+0.19 {
				if o.kind==2 { c.duck=true } else { c.jump=true }
			}
		}
	case .Karaoke:
		for n in s.notes { if n.judgement==0 && math.abs(n.time-s.time)<0.015 { c.lanes[n.lane]=true } }
	case .Helicopter:
		for o in s.obstacles { if o.active { c.aim=o.pos; c.fire=true; break } }
		c.reload=s.ammo==0
	case .Descent:
		target:=f32(0.5); nearest:=f32(0)
		for o in s.obstacles {
			if !o.active || o.resolved || o.pos.y>0.82 || o.pos.y<0.5 { continue }
			if o.pos.y>nearest {
				nearest=o.pos.y
				if o.kind==4 { target=o.pos.x } else if math.abs(o.pos.x-s.pos.x)<0.14 { target=clamp(s.pos.x+(0.19 if o.pos.x<0.5 else -0.19),0.1,0.9) }
			}
		}
		c.move.x=clamp((target-s.pos.x)*7,-1,1)
	}
	return c
}

// The capture bot estimates reachable empty space, without seeing future
// opponent choices. This also exercises tight endgames instead of dying at
// the first corner, making captures useful for actual gameplay regression.
cycle_area :: proc(s: ^State, start: [2]int) -> int {
	if !cycle_open(s,start) { return -100 }
	seen: [GRID_W*GRID_H]bool
	queue: [GRID_W*GRID_H][2]int
	head,tail:=0,1
	queue[0]=start; seen[start.y*GRID_W+start.x]=true
	for head<tail {
		p:=queue[head]; head+=1
		for d in 0..<4 {
			n:=p+dir_delta(d)
			if !cycle_open(s,n) || seen[n.y*GRID_W+n.x] { continue }
			seen[n.y*GRID_W+n.x]=true
			queue[tail]=n; tail+=1
		}
	}
	return tail
}
