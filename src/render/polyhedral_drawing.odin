package render

import "core:math"
import rl "vendor:raylib"
import rlgl "vendor:raylib/rlgl"

polyhedral_body_color :: proc(normal: rl.Vector3, bevel, resin: bool) -> rl.Color {
	if resin {return {58,102,154,255} if bevel else {20,46,87,255}}
	light := rl.Vector3Normalize(rl.Vector3{-0.55,0.86,0.36})
	diffuse := max(f32(0), rl.Vector3DotProduct(normal, light))
	reflection := normal*(2*rl.Vector3DotProduct(normal, light))-light
	specular := math.pow(max(f32(0), rl.Vector3DotProduct(reflection, DICE_VIEW_DIRECTION)), f32(22))
	brightness := 0.48+diffuse*0.72
	edge: f32 = 1.5 if bevel else 1
	return {u8(min(f32(255), 23*brightness*edge+120*specular)),
		u8(min(f32(255), 66*brightness*edge+160*specular)),
		u8(min(f32(255), 122*brightness*edge+170*specular)), 255}
}

polyhedral_ink_vertex :: proc(point: rl.Vector3, uv: rl.Vector2, position: rl.Vector3, rotation: rl.Quaternion) {
	p := rl.Vector3RotateByQuaternion(point, rotation)+position
	rlgl.TexCoord2f(uv.x, uv.y)
	rlgl.Vertex3f(p.x, p.y, p.z)
}

polyhedral_draw_label :: proc(font: rl.Font, digits: [2]int, count: int,
	center, u, v, normal: rl.Vector3, height: f32, position: rl.Vector3, rotation: rl.Quaternion, underline: bool) {
	world_normal := rl.Vector3RotateByQuaternion(normal, rotation)
	rlgl.Normal3f(world_normal.x, world_normal.y, world_normal.z)
	// Atlas quads make real engraved numerals, without texture allocation in a
	// roll. Their small lift above the face prevents depth fighting.
	width := height*0.61
	gap := height*0.07
	total := width*f32(count)+gap*f32(count-1)
	for index in 0..<count {
		digit := digits[index]
		rect := rl.GetGlyphAtlasRec(font, rune('0'+digit))
		if rect.width <= 0 || rect.height <= 0 {continue}
		left := -total*0.5+f32(index)*(width+gap)
		quad := [4]rl.Vector3{center+u*left+v*(height*0.5), center+u*left-v*(height*0.5),
			center+u*(left+width)-v*(height*0.5), center+u*(left+width)+v*(height*0.5)}
		uv := [4]rl.Vector2{{rect.x/f32(font.texture.width),rect.y/f32(font.texture.height)},
			{rect.x/f32(font.texture.width),(rect.y+rect.height)/f32(font.texture.height)},
			{(rect.x+rect.width)/f32(font.texture.width),(rect.y+rect.height)/f32(font.texture.height)},
			{(rect.x+rect.width)/f32(font.texture.width),rect.y/f32(font.texture.height)}}
		for i in ([6]int{0,1,2,0,2,3}) {polyhedral_ink_vertex(quad[i],uv[i],position,rotation)}
	}
	if underline {
		// Underlined 6/9 remains unambiguous on a freely tumbling solid.
		rect := rl.GetGlyphAtlasRec(font, '_')
		quad := [4]rl.Vector3{center-u*total*0.42-v*height*0.31, center-u*total*0.42-v*height*0.70,
			center+u*total*0.42-v*height*0.70, center+u*total*0.42-v*height*0.31}
		uv := [4]rl.Vector2{{rect.x/f32(font.texture.width),rect.y/f32(font.texture.height)},
			{rect.x/f32(font.texture.width),(rect.y+rect.height)/f32(font.texture.height)},
			{(rect.x+rect.width)/f32(font.texture.width),(rect.y+rect.height)/f32(font.texture.height)},
			{(rect.x+rect.width)/f32(font.texture.width),rect.y/f32(font.texture.height)}}
		for i in ([6]int{0,1,2,0,2,3}) {polyhedral_ink_vertex(quad[i],uv[i],position,rotation)}
	}
}

// `values`: the faces read the values they roll (polyhedral_face_label).
draw_polyhedral_die :: proc(die: ^Polyhedral_Die, position: rl.Vector3, rotation: rl.Quaternion,
	font: rl.Font = {}, resin: bool = false, values: bool = false) {
	if die == nil || die.triangle_count == 0 {return}
	rlgl.SetTexture(rlgl.GetTextureIdDefault())
	rlgl.Begin(rlgl.TRIANGLES)
	for triangle, index in die.triangles[:die.triangle_count] {
		normal := rl.Vector3RotateByQuaternion(triangle.normal, rotation)
		color := polyhedral_body_color(normal, die.triangle_bevel[index], resin)
		rlgl.Normal3f(normal.x, normal.y, normal.z)
		rlgl.Color4ub(color.r,color.g,color.b,255)
		for point in triangle.points {resin_die_vertex(point, position, rotation)}
	}
	rlgl.End()
	ink_font := font
	if ink_font.texture.id == 0 {ink_font = rl.GetFontDefault()}
	rlgl.SetTexture(ink_font.texture.id)
	rlgl.Begin(rlgl.TRIANGLES)
	rlgl.Color4ub(247,235,208,255)
	for face in die.faces[:die.face_count] {
		if die.kind == .D4 {
			for index in 0..<face.count {
				vertex := die.vertices[face.vertices[index]]
				v := rl.Vector3Normalize(vertex-face.center)
				u := rl.Vector3CrossProduct(v, face.normal)
				center := face.center+(vertex-face.center)*0.49+face.normal*0.003
				polyhedral_draw_label(ink_font,{face.vertices[index]+1,0},1,center,u,v,face.normal,0.19,position,rotation,false)
			}
			continue
		}
		digits, count := polyhedral_face_label(die, face, values)
		height: f32 = 0.37
		switch die.kind {
		case .D8: height = 0.29
		case .D10, .D100: height = 0.26
		case .D12: height = 0.27
		case .D20: height = 0.23
		case .D4, .D6, .Count:
		}
		polyhedral_draw_label(ink_font,digits,count,face.center+face.normal*0.003,face.u,face.v,face.normal,
			height,position,rotation,face.value == 6 || face.value == 9)
	}
	rlgl.End()
	rlgl.SetTexture(0)
}
