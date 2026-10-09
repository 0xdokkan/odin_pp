// Application host: owns the window, audio, UI and a stack of scenes, and runs
// the frame loop. Every mode of the game, from the roguelike run to each
// minigame, is a Scene; menus and pauses are scenes pushed on top.
package host

import rl "vendor:raylib"
import app "../../app"
import audio "../audio"
import gui "../ui"

Outcome :: enum u8 {
	Won,
	Lost,
	Abandoned,
}

// What a finished minigame reports to the scene underneath.
Result :: struct {
	minigame: string,
	outcome:  Outcome,
	score:    i64,
	stars:    u8, // 0..3
	elapsed:  f32,
}

Frame :: struct {
	dt:             f32,
	time:           f64,
	index:          u64,
	canvas:         rl.Rectangle,
	mouse:          [2]f32,
	mouse_inside:   bool,
	// The scene is the top of the stack and the window has focus: it owns input.
	focused:        bool,
	// The scene is drawn this frame; emit UI only when visible.
	visible:        bool,
	window_focused: bool,
	ui:             ^gui.Context,
	theme:          ^gui.Theme,
	audio:          ^audio.Bank,
	window:         ^app.Window,
	profile:        ^Profile,
	commands:       ^Commands,
}

Scene :: struct {
	name:          string,
	data:          rawptr,
	// Scenes below an opaque scene are not drawn.
	opaque:        bool,
	// Scenes below a modal scene are not updated.
	modal:         bool,
	clear_color:   rl.Color,
	// World drawing in canvas space. UI widgets belong in `update`, so they
	// layer correctly above every scene's world.
	update:        proc(data: rawptr, frame: ^Frame),
	draw:          proc(data: rawptr, frame: ^Frame),
	// Optional: window-space drawing after the canvas is composed.
	draw_window:   proc(data: rawptr, frame: ^Frame),
	// Optional: runs after the frame is on screen (screenshots).
	after_present: proc(data: rawptr, frame: ^Frame),
	// Optional: the scene above was popped, possibly with a result.
	resume:        proc(data: rawptr, frame: ^Frame, from: string, result: Maybe(Result)),
	destroy:       proc(data: rawptr),
}

Command_Kind :: enum u8 {
	Push,
	Pop,
	Replace,
	Quit,
}

Command :: struct {
	kind:   Command_Kind,
	scene:  Scene,
	result: Maybe(Result),
}

MAX_COMMANDS :: 8

// Requests issued during a frame, applied in order after drawing.
Commands :: struct {
	items:   [MAX_COMMANDS]Command,
	count:   int,
	dropped: int,
}

@(private)
queue :: proc(c: ^Commands, cmd: Command) {
	if c.count >= MAX_COMMANDS {
		c.dropped += 1
		if cmd.scene.destroy != nil {
			cmd.scene.destroy(cmd.scene.data)
		}
		return
	}
	c.items[c.count] = cmd
	c.count += 1
}

push :: proc(f: ^Frame, scene: Scene) {
	queue(f.commands, Command{kind = .Push, scene = scene})
}

// Closes the calling scene. A result is delivered to the scene underneath.
pop :: proc(f: ^Frame, result: Maybe(Result) = nil) {
	queue(f.commands, Command{kind = .Pop, result = result})
}

replace :: proc(f: ^Frame, scene: Scene) {
	queue(f.commands, Command{kind = .Replace, scene = scene})
}

quit :: proc(f: ^Frame) {
	queue(f.commands, Command{kind = .Quit})
}

MAX_SCENES :: 16

Stack :: struct {
	items: [MAX_SCENES]Scene,
	count: int,
}

stack_top :: proc(s: ^Stack) -> ^Scene {
	if s.count == 0 {
		return nil
	}
	return &s.items[s.count-1]
}

// First index that receives update calls this frame.
update_start :: proc(s: ^Stack) -> int {
	for i := s.count - 1; i >= 0; i -= 1 {
		if s.items[i].modal {
			return i
		}
	}
	return 0
}

// First index that is drawn this frame.
draw_start :: proc(s: ^Stack) -> int {
	for i := s.count - 1; i >= 0; i -= 1 {
		if s.items[i].opaque {
			return i
		}
	}
	return 0
}

stack_push :: proc(s: ^Stack, scene: Scene) -> bool {
	if s.count >= MAX_SCENES {
		if scene.destroy != nil {
			scene.destroy(scene.data)
		}
		return false
	}
	s.items[s.count] = scene
	s.count += 1
	return true
}

stack_pop :: proc(s: ^Stack) -> (Scene, bool) {
	if s.count == 0 {
		return {}, false
	}
	s.count -= 1
	popped := s.items[s.count]
	s.items[s.count] = {}
	return popped, true
}

// Applies queued commands; returns false when the application should stop.
apply :: proc(s: ^Stack, c: ^Commands, frame: ^Frame) -> bool {
	keep_running := true
	for i in 0..<c.count {
		cmd := c.items[i]
		switch cmd.kind {
		case .Push:
			stack_push(s, cmd.scene)
		case .Pop:
			popped, ok := stack_pop(s)
			if !ok {
				continue
			}
			if popped.destroy != nil {
				popped.destroy(popped.data)
			}
			if top := stack_top(s); top != nil && top.resume != nil {
				top.resume(top.data, frame, popped.name, cmd.result)
			}
		case .Replace:
			if popped, ok := stack_pop(s); ok && popped.destroy != nil {
				popped.destroy(popped.data)
			}
			stack_push(s, cmd.scene)
		case .Quit:
			keep_running = false
		}
	}
	c.count = 0
	c.dropped = 0
	return keep_running && s.count > 0
}

destroy_all :: proc(s: ^Stack) {
	for s.count > 0 {
		popped, _ := stack_pop(s)
		if popped.destroy != nil {
			popped.destroy(popped.data)
		}
	}
}
