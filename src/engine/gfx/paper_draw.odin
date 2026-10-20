package gfx

import rl "vendor:raylib"
import rlgl "vendor:raylib/rlgl"

// The paper shader's complete per-draw contract. Callers choose the cut,
// texel scale and sheet colour; they keep pass guards and depth/blend state.
Paper_Material :: struct {
	frames: Flipbook_Paper,
	cell, edge: Vec2,
	sheet: [3]f32,
}

begin_paper_material :: proc(assets: ^Flipbook_Assets, material: Paper_Material) {
	values := material
	rl.SetShaderValue(assets.paper_shader, assets.frame_a_location, &values.frames.from, .VEC4)
	rl.SetShaderValue(assets.paper_shader, assets.frame_b_location, &values.frames.to, .VEC4)
	rl.SetShaderValue(assets.paper_shader, assets.morph_location, &values.frames.morph, .FLOAT)
	rl.SetShaderValue(assets.paper_shader, assets.cell_location, &values.cell, .VEC2)
	rl.SetShaderValue(assets.paper_shader, assets.edge_location, &values.edge, .VEC2)
	rl.SetShaderValue(assets.paper_shader, assets.sheet_location, &values.sheet, .VEC3)
	rl.BeginShaderMode(assets.paper_shader)
}

// Grow a print's corners in its own texel axes, preserving lean and turns.
paper_quad_points :: proc(print: [4]Vec3, cell: Vec2, margin: f32) -> [4]Vec3 {
	right := (print[2]-print[1])/max(cell.x, 1)
	up := (print[0]-print[1])/max(cell.y, 1)
	return {print[0]+(-right+up)*margin, print[1]+(-right-up)*margin,
		print[2]+(right-up)*margin, print[3]+(right+up)*margin}
}

// Corners and normalized UVs run top-left, bottom-left, bottom-right,
// top-right. The caller owns the shader and the surrounding render pass.
draw_texture_quad :: proc(texture: u32, points: [4]Vec3, uv: [4]Vec2, tint: rl.Color) {
	rlgl.SetTexture(texture)
	rlgl.Begin(rlgl.QUADS)
	rlgl.Color4ub(tint.r, tint.g, tint.b, tint.a)
	for point, index in points {
		rlgl.TexCoord2f(uv[index].x, uv[index].y)
		rlgl.Vertex3f(point.x, point.y, point.z)
	}
	rlgl.End()
	rlgl.SetTexture(0)
}
