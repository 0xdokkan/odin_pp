package run

import host "../engine/host"

// Optional observer/driver hooks. The provider owns data until destroy;
// the run never imports the tools that supply these callbacks.
Run_Diagnostics :: struct {
	scripted: bool,
	data: rawptr,
	after_present, capture_input: proc(rs: ^Roguelike_Session, frame: ^host.Frame),
	destroy: proc(data: rawptr),
}

roguelike_after_present :: proc(data: rawptr, frame: ^host.Frame) {
	rs := cast(^Roguelike_Session)data
	if rs.diagnostics.after_present != nil { rs.diagnostics.after_present(rs, frame) }
}
