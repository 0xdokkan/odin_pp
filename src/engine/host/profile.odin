package host

import save "../save"

PROFILE_VERSION :: 1

Settings :: struct {
	master_volume:     f32,
	music_volume:      f32,
	sfx_volume:        f32,
	muted:             bool,
	show_fps:          bool,
	mouse_sensitivity: f32, // multiplier on each minigame's default
	screen_shake:      f32, // 0 disables shake, 1 is full strength
}

DEFAULT_SETTINGS :: Settings{
	master_volume     = 0.8,
	music_volume      = 0.45,
	sfx_volume        = 1,
	mouse_sensitivity = 1,
	screen_shake      = 1,
}

Record :: struct {
	best_score: i64,
	best_stars: u8,
	plays:      int,
	wins:       int,
}

// Persistent player data shared by every mode.
Profile :: struct {
	settings: Settings,
	records:  map[string]Record,
}

profile_default :: proc() -> Profile {
	return Profile{settings = DEFAULT_SETTINGS}
}

profile_destroy :: proc(p: ^Profile) {
	for key in p.records {
		delete(key)
	}
	delete(p.records)
	p^ = {}
}

// Keeps defaults when the file is missing or unreadable; a corrupt file is
// left in place so it can be inspected instead of being silently replaced.
profile_load :: proc(path: string) -> (Profile, save.Load_Status) {
	loaded, status := save.read(path, PROFILE_VERSION, Profile)
	if status != .Loaded {
		return profile_default(), status
	}
	p := loaded
	p.settings.master_volume = clamp(p.settings.master_volume, 0, 1)
	p.settings.music_volume = clamp(p.settings.music_volume, 0, 1)
	p.settings.sfx_volume = clamp(p.settings.sfx_volume, 0, 1)
	p.settings.screen_shake = clamp(p.settings.screen_shake, 0, 1)
	if p.settings.mouse_sensitivity <= 0 {
		p.settings.mouse_sensitivity = 1
	}
	return p, status
}

profile_save :: proc(path: string, p: ^Profile) -> bool {
	return save.write(path, PROFILE_VERSION, p^)
}

record_get :: proc(p: ^Profile, id: string) -> Record {
	return p.records[id] or_else Record{}
}

// Folds a finished round into the record; returns true on a new best score.
record_result :: proc(p: ^Profile, r: Result) -> bool {
	if r.minigame == "" {
		return false
	}
	rec, existed := p.records[r.minigame]
	new_best := false
	rec.plays += 1
	if r.outcome == .Won {
		rec.wins += 1
	}
	if r.outcome != .Abandoned && (r.score > rec.best_score || rec.plays == 1) {
		new_best = r.score > rec.best_score
		rec.best_score = max(rec.best_score, r.score)
	}
	if r.outcome == .Won {
		rec.best_stars = max(rec.best_stars, r.stars)
	}
	if existed {
		p.records[r.minigame] = rec
	} else {
		key := clone_string(r.minigame)
		p.records[key] = rec
	}
	return new_best
}

@(private)
clone_string :: proc(s: string) -> string {
	b := make([]u8, len(s))
	copy(b, s)
	return string(b)
}
