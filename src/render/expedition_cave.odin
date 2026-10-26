package render

import "core:math"
import rl "vendor:raylib"
import world "../expedition"
import game "../game"
import grid "../engine/grid"
import level "../level"

// THE MOUTH OF A CAVE (expedition/cave.odin): the opening the relief leaves in the side of the massif, or of the spiral
// mountain's core, over the cave's floor (expedition_terrain.odin, expedition_layers.odin), framed by an arch of light
// in the biome's colour, dimmer once the cave's secret is taken.

@(private)
draw_expedition_cave_arch :: proc(pass: Ink_Pass, w: ^world.World, site: ^world.Site, layer: Ink_Layer, m: ^Expedition_Material) {
	// A site with no cave of the world's (a world made by hand) has the open map's mouth: the cave to its east.
	place := world.Cave_Place{mouth = site.position, arrival = grid.offset(site.position, 1, 0)}
	for cave in w.caves[:w.cave_count] { if cave.place.mouth == site.position { place = cave.place } }
	// The step from the mouth into the cave: the tunnel's first cell on the open map (east), the room in the mountain.
	inside := place.arrival if place.mountain else grid.offset(place.mouth, 1, 0)
	d := rl.Vector2{f32(clamp(inside.x-place.mouth.x, -1, 1)), f32(clamp(inside.y-place.mouth.y, -1, 1))}
	centre := rl.Vector2{f32(place.mouth.x)+.5+d.x*.5, f32(place.mouth.y)+.5+d.y*.5}
	if ink_layer_skips(layer, m, centre, 2) { return }
	// Just in front of the rock's face, across it.
	base := rl.Vector3{centre.x-d.x*.02, f32(place.floor)*game.HEIGHT_STEP_DRAWN, centre.y-d.y*.02}
	across := rl.Vector3{-d.y, 0, d.x}
	color := ink_edge(expedition_color(w.biome), 1)
	if site.state == .Resolved { color = ink_scale(color, .5) }
	half := f32(.46)
	spring := f32(level.LAYER_CLEARANCE)*game.HEIGHT_STEP_DRAWN-half
	segments := 14
	for i in 0..<segments {
		a, z := f32(i)*math.PI/f32(segments), f32(i+1)*math.PI/f32(segments)
		from := base+across*(math.cos(a)*half)+{0, spring+math.sin(a)*half*.9, 0}
		to := base+across*(math.cos(z)*half)+{0, spring+math.sin(z)*half*.9, 0}
		ink_line(pass, from, to, color)
	}
	ink_line(pass, base+across*half+{0, .04, 0}, base+across*half+{0, spring, 0}, color)
	ink_line(pass, base-across*half+{0, .04, 0}, base-across*half+{0, spring, 0}, color)
}
