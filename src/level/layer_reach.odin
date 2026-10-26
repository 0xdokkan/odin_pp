package level

import grid "../engine/grid"

// WHERE A WALKER GETS (for the map editor's checks, Fase 6 of docs/piano-profondita.md): from `start`, a step at a time
// as the rules of the layers have it (game.layer_step): into the neighbour column, onto its floor a step up at most or
// any drop down that its room lets him through; that is a walk only a step up or down at most. And the ladders, both
// ways. One flag a cell of every layer, at layer_reach_index.
layer_reach :: proc(data: ^Level, start: grid.Position, allocator := context.allocator) -> []bool {
	seen := make([]bool, len(data.tiles.cells)*LAYER_COUNT, allocator)
	if !layer_contains(data, start) { return seen }
	m := layer_map(data)
	layered := has_layers(data)
	queue := make([dynamic]grid.Position, context.temp_allocator)
	seen[layer_reach_index(data, start)] = true
	append(&queue, start)
	steps := [4]grid.Position{{x = 1, y = 0}, {x = -1, y = 0}, {x = 0, y = 1}, {x = 0, y = -1}}
	for head := 0; head < len(queue); head += 1 {
		from := queue[head]
		height := height_at(data, from)
		for step in steps {
			next := grid.offset(from, step.x, step.y)
			ladder := false
			if end, found := ladder_end(data, from, step); found {
				next, ladder = end, true
			} else if layered {
				if landing, landed := column_landing(&m, next.x, next.y, height, 1); landed { next = landing }
			}
			if !layer_contains(data, next) { continue }
			tile, _ := tile_at(data, next)
			if !is_walkable(tile.kind) || !ladder && abs(height_at(data, next)-height) > 1 { continue }
			at := layer_reach_index(data, next)
			if seen[at] { continue }
			seen[at] = true
			append(&queue, next)
		}
	}
	return seen
}

// Where `p` is kept in layer_reach's flags.
layer_reach_index :: proc(data: ^Level, p: grid.Position) -> int {
	return layer_slot(p.layer)*len(data.tiles.cells)+p.y*data.tiles.width+p.x
}
