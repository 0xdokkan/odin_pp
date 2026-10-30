package grid

// Position identifies one cell in grid space. The origin is the top-left
// corner: x grows to the right and y grows downward.
//
// `layer` is the layer of the map the cell is on (docs/piano-profondita.md):
// 0 the ground, which is every map until the layers come; -1 and -2 below it,
// +1 above it. A Grid of this package has one layer, the ground: it holds no
// position on another one, so a cell of another layer is never mistaken for
// the ground's cell with the same x and y.
Position :: struct {
	x, y:  int,
	layer: i8,
}

// The layers a position can be on: two below the ground, the ground, one above.
LOWEST_LAYER :: -2
GROUND_LAYER :: 0
HIGHEST_LAYER :: 1

// The cell `dx`, `dy` away from `p`, on the same layer: a neighbour never
// falls to the ground.
offset :: proc(p: Position, dx, dy: int) -> Position {
	return {x = p.x+dx, y = p.y+dy, layer = p.layer}
}

// The cells use row-major order: index = y*width + x. Keeping them contiguous
// makes iteration predictable and cache-friendly.
Grid :: struct($T: typeid) {
	width, height: int,
	cells:         [dynamic]T,
}

create :: proc($T: typeid, width, height: int, initial_value: T) -> (result: Grid(T), ok: bool) {
	if width <= 0 || height <= 0 {
		return {}, false
	}

	result.width = width
	result.height = height
	result.cells = make([dynamic]T, width*height)
	fill(&result, initial_value)
	return result, true
}

destroy :: proc(g: ^Grid($T)) {
	if g == nil {
		return
	}

	delete(g.cells)
	g^ = {}
}

cell_count :: proc(g: ^Grid($T)) -> int {
	if g == nil {
		return 0
	}
	return g.width * g.height
}

contains :: proc(g: ^Grid($T), position: Position) -> bool {
	return g != nil && position.layer == GROUND_LAYER &&
		position.x >= 0 && position.x < g.width &&
		position.y >= 0 && position.y < g.height
}

// The index of `position` in a row-major table `width` by `height` that is not
// a Grid (a parallel table of heights, of marks): the same rule as index_of,
// the ground layer only.
cell_index :: proc(position: Position, width, height: int) -> (index: int, ok: bool) {
	if position.layer != GROUND_LAYER || position.x < 0 || position.y < 0 || position.x >= width || position.y >= height {
		return 0, false
	}
	return position.y*width + position.x, true
}

index_of :: proc(g: ^Grid($T), position: Position) -> (index: int, ok: bool) {
	if !contains(g, position) {
		return 0, false
	}
	return position.y*g.width + position.x, true
}

position_of :: proc(g: ^Grid($T), index: int) -> (position: Position, ok: bool) {
	if g == nil || index < 0 || index >= len(g.cells) {
		return {}, false
	}
	return Position{x = index % g.width, y = index / g.width}, true
}

get :: proc(g: ^Grid($T), position: Position) -> (value: T, ok: bool) {
	index, valid := index_of(g, position)
	if !valid {
		return {}, false
	}
	return g.cells[index], true
}

set :: proc(g: ^Grid($T), position: Position, value: T) -> bool {
	index, valid := index_of(g, position)
	if !valid {
		return false
	}
	g.cells[index] = value
	return true
}

fill :: proc(g: ^Grid($T), value: T) {
	if g == nil {
		return
	}
	for &cell in g.cells {
		cell = value
	}
}

generate :: proc(g: ^Grid($T), generator: proc(Position) -> T) {
	assert(g != nil)
	assert(generator != nil)

	for &cell, index in g.cells {
		position, ok := position_of(g, index)
		assert(ok)
		cell = generator(position)
	}
}
