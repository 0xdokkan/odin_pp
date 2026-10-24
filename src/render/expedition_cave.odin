package render

import "core:math"
import rl "vendor:raylib"
import world "../expedition"

// THE CAVE'S ARCH on the open map (expedition/cave.odin): in the mass of rock the tiles carry, over the doorway between its two
// legs, a lintel and a round arch of light in the biome's colour, and a dark opening behind it. On the spiral mountain, where
// the path is the floor and there is no rock of its own, the legs are drawn too, as a gate across the path.

CAVE_ROCK     :: rl.Color{50, 55, 66, 255}
CAVE_ROCK_CAP :: rl.Color{88, 96, 112, 255}
CAVE_DARK     :: rl.Color{5, 7, 11, 255}

@(private)
draw_expedition_cave_arch :: proc(pass: Ink_Pass, w: ^world.World, site: ^world.Site, layer: Ink_Layer, m: ^Expedition_Material) {
	centre := rl.Vector2{f32(site.position.x)+.5, f32(site.position.y)+.5}
	if ink_layer_skips(layer, m, centre, 3.4) { return }
	base := rl.Vector3{centre.x, 0, centre.y}
	// The legs, where the tiles have none.
	if site.layout_version != world.SITE_LAYOUT_VERSION {
		for side in ([2]f32{-1, 1}) { ink_box(pass, base+{side*1, 0, 0}, {.46, .46}, 1.7, 0, CAVE_ROCK, CAVE_ROCK_CAP, {}) }
	}
	// The lintel across both legs, and the dark opening between them, set back a little from the front.
	ink_box(pass, base+{0, 1.7, 0}, {1.48, .46}, .3, 0, CAVE_ROCK, CAVE_ROCK_CAP, {})
	ink_box(pass, base+{0, 0, -1.4}, {.46, .04}, 1.7, 0, CAVE_DARK, CAVE_DARK, {})
	// The arch of light on the front face of the legs.
	color := ink_edge(expedition_color(w.biome), 1)
	if site.state == .Resolved { color = ink_scale(color, .5) }
	segments := 14
	for i in 0..<segments {
		a, z := f32(i)*math.PI/f32(segments), f32(i+1)*math.PI/f32(segments)
		from := base+{math.cos(a)*.52, 1.28+math.sin(a)*.52-.48, .46}
		to := base+{math.cos(z)*.52, 1.28+math.sin(z)*.52-.48, .46}
		ink_line(pass, from, to, color)
	}
	ink_line(pass, base+{-.52, 0.04, .46}, base+{-.52, .8, .46}, color)
	ink_line(pass, base+{.52, 0.04, .46}, base+{.52, .8, .46}, color)
}
