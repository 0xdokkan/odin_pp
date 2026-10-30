package render

import rl "vendor:raylib"
import rlgl "vendor:raylib/rlgl"
import game "../game"
import level "../level"
import view "../engine/view"

// HIDDEN FIGURES (Fase 4 of docs/piano-profondita.md). A figure that something drawn whole hides from the camera (a
// bridge's deck, the rock of a hill: game.layer_figure_hidden) shows its outline through it, in its own colour, as
// its stand: ivory for the robot, crimson for the foes. One bounded alpha-dilation pass over the figure's print, as
// the comic outline makes (comic_outline.odin), that keeps the ring and a faint fill inside it.
LAYER_OUTLINE_FRAGMENT :: `#version 330
in vec2 fragTexCoord;
in vec4 fragColor;
uniform sampler2D texture0;
uniform vec4 sourceBounds;
uniform vec2 texel;
uniform float outlineRadius;
out vec4 finalColor;
float ink(vec2 p) {
    if (p.x < sourceBounds.x || p.y < sourceBounds.y || p.x > sourceBounds.z || p.y > sourceBounds.w) return 0.0;
    return step(0.25, texture(texture0, p).a);
}
void main() {
    float core = ink(fragTexCoord);
    float ring = core;
    for (int i=0; i<16; ++i) {
        float a = float(i)*0.392699082;
        vec2 d = vec2(cos(a), sin(a))*texel*outlineRadius;
        ring = max(ring, ink(fragTexCoord+d));
        ring = max(ring, ink(fragTexCoord+d*0.5));
    }
    float alpha = ring-core+core*0.18;
    if (alpha < 0.02) discard;
    finalColor = vec4(fragColor.rgb, alpha*fragColor.a);
}`

// The ring's width, in the print's own pixels.
LAYER_OUTLINE_RADIUS :: f32(5)
LAYER_OUTLINE_ROBOT :: rl.Color{236, 232, 214, 235}
LAYER_OUTLINE_FOE :: rl.Color{GOTHIC_RED.r, GOTHIC_RED.g, GOTHIC_RED.b, 235}

@(private)
create_layer_outline :: proc(renderer: ^Renderer) {
	v := &renderer.tactical
	v.hidden_shader = rl.LoadShaderFromMemory(nil, LAYER_OUTLINE_FRAGMENT)
	if v.hidden_shader.id != 0 {
		v.hidden_bounds_location = rl.GetShaderLocation(v.hidden_shader, "sourceBounds")
		v.hidden_texel_location = rl.GetShaderLocation(v.hidden_shader, "texel")
		v.hidden_radius_location = rl.GetShaderLocation(v.hidden_shader, "outlineRadius")
	}
}

// The outline of a figure's print, its quad grown by the ring (points: top-left, bottom-left, bottom-right,
// top-right, as tactical_billboard_geometry makes them).
@(private)
draw_figure_outline :: proc(renderer: ^Renderer, quad: Tactical_Billboard, color: rl.Color) {
	v := &renderer.tactical
	if v.hidden_shader.id == 0 || quad.texture.id == 0 || quad.source.width <= 0 || quad.source.height <= 0 { return }
	texel := rl.Vector2{1/f32(quad.texture.width), 1/f32(quad.texture.height)}
	bounds := rl.Vector4{quad.source.x*texel.x, quad.source.y*texel.y, (quad.source.x+quad.source.width)*texel.x, (quad.source.y+quad.source.height)*texel.y}
	radius := LAYER_OUTLINE_RADIUS
	rl.SetShaderValue(v.hidden_shader, v.hidden_bounds_location, &bounds, .VEC4)
	rl.SetShaderValue(v.hidden_shader, v.hidden_texel_location, &texel, .VEC2)
	rl.SetShaderValue(v.hidden_shader, v.hidden_radius_location, &radius, .FLOAT)
	grow_x := (quad.points[2]-quad.points[1])*(radius/quad.source.width)
	grow_y := (quad.points[0]-quad.points[1])*(radius/quad.source.height)
	points := [4]rl.Vector3{quad.points[0]-grow_x+grow_y, quad.points[1]-grow_x-grow_y, quad.points[2]+grow_x-grow_y, quad.points[3]+grow_x+grow_y}
	source := rl.Rectangle{quad.source.x-radius, quad.source.y-radius, quad.source.width+2*radius, quad.source.height+2*radius}
	uv := [4]rl.Vector2{{0, 0}, {0, 1}, {1, 1}, {1, 0}}
	if quad.mirror { uv = {{1, 0}, {1, 1}, {0, 1}, {0, 0}} }
	rl.BeginShaderMode(v.hidden_shader)
	rlgl.SetTexture(quad.texture.id)
	rlgl.Begin(rlgl.QUADS)
	rlgl.Color4ub(color.r, color.g, color.b, color.a)
	for p, i in points {
		rlgl.TexCoord2f((source.x+uv[i].x*source.width)*texel.x, (source.y+uv[i].y*source.height)*texel.y)
		rlgl.Vertex3f(p.x, p.y, p.z)
	}
	rlgl.End()
	rlgl.SetTexture(0)
	rl.EndShaderMode()
}

// The outlines of the hidden figures, over everything drawn (the board's sorted pass ends with them). Nothing on a
// board without layers.
@(private)
draw_hidden_outlines :: proc(renderer: ^Renderer, room: ^game.Room) {
	if !board_view.layered || room == nil { return }
	v := &renderer.tactical
	snapshot := v.snapshot
	m := board_layer_map()
	// The rules' heights count from 0, the drawing's from the map's base (board_drawn).
	eye := [3]f32{v.camera.position.x, v.camera.position.y+board_base_drawn(), v.camera.position.z}
	rlgl.DrawRenderBatchActive()
	rlgl.DisableDepthTest()
	defer { rlgl.DrawRenderBatchActive(); rlgl.EnableDepthTest() }
	outline :: proc(renderer: ^Renderer, m: ^level.Layer_Map, eye: [3]f32, entity: game.Entity_Ref, key: Sprite_Key, position: view.Vec2, color: rl.Color) {
		cell, found := board_actor_cell(entity)
		if !found { return }
		at, lift := living_card_position(renderer, entity, key, position)
		if !game.layer_figure_hidden(m, board_view.viewer, eye, {at.x+0.5, lift+0.5+board_base_drawn(), at.y+0.5}, cell) { return }
		draw_figure_outline(renderer, tactical_billboard_geometry(renderer, key, position, true, entity), color)
	}
	for actor in snapshot.enemies[:snapshot.enemy_count] {
		if actor.visible { outline(renderer, &m, eye, actor.entity, sprite_key_for_enemy(actor.archetype), actor.position, LAYER_OUTLINE_FOE) }
	}
	if snapshot.player.visible { outline(renderer, &m, eye, game.PLAYER_ENTITY, .Player, snapshot.player.position, LAYER_OUTLINE_ROBOT) }
}
