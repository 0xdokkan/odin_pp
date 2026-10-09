package render

import "core:c"
import rl "vendor:raylib"

// Geometry gets a 2x render surface; UI and sprite source textures keep their
// pixel grid. The parent canvas is borrowed, never unloaded by the renderer.
Tactical_Surface :: struct {
	target, parent: rl.RenderTexture2D,
	resolve: rl.Shader,
}

TACTICAL_SURFACE_RESOLVE :: `#version 330
in vec2 fragTexCoord;
uniform sampler2D texture0;
out vec4 finalColor;
void main() { finalColor = vec4(texture(texture0, fragTexCoord).rgb, 1.0); }
`

create_tactical_surface :: proc(renderer: ^Renderer, parent: rl.RenderTexture2D) {
	if !renderer.tactical.scene_3d || parent.id == 0 || renderer.tactical.surface != nil { return }
	target := rl.LoadRenderTexture(c.int(renderer.canvas_width)*2, c.int(renderer.canvas_height)*2)
	if !rl.IsRenderTextureValid(target) {
		if target.id != 0 { rl.UnloadRenderTexture(target) }
		return
	}
	rl.SetTextureFilter(target.texture, .BILINEAR)
	rl.SetTextureWrap(target.texture, .CLAMP)
	renderer.tactical.surface = new(Tactical_Surface)
	// The scene replaces the canvas. Gradient/particle blending can reduce a
	// render target's alpha; resolve it opaque so a map never ghosts the hand
	// or room that was drawn into the parent canvas earlier in the same frame.
	renderer.tactical.surface^ = {target, parent, rl.LoadShaderFromMemory(nil, TACTICAL_SURFACE_RESOLVE)}
}

destroy_tactical_surface :: proc(renderer: ^Renderer) {
	surface := renderer.tactical.surface
	if surface == nil { return }
	rl.UnloadRenderTexture(surface.target)
	if surface.resolve.id != 0 { rl.UnloadShader(surface.resolve) }
	free(surface)
	renderer.tactical.surface = nil
}

begin_tactical_surface :: proc(renderer: ^Renderer) -> bool {
	surface := renderer.tactical.surface
	if !renderer.tactical.scene_3d || surface == nil { return false }
	rl.BeginTextureMode(surface.target)
	return true
}

end_tactical_surface :: proc(renderer: ^Renderer, active: bool) {
	if !active { return }
	surface := renderer.tactical.surface
	rl.EndTextureMode()
	// Raylib render targets are not a stack. Explicitly restore the borrowed
	// canvas so later HUD, dice overlays and app.present use the right target.
	rl.BeginTextureMode(surface.parent)
	rl.ClearBackground(RESIN_BACKGROUND)
	rl.BeginShaderMode(surface.resolve)
	rl.DrawTexturePro(surface.target.texture, {0, 0, f32(surface.target.texture.width), -f32(surface.target.texture.height)},
		{0, 0, renderer.canvas_width, renderer.canvas_height}, {}, 0, rl.WHITE)
	rl.EndShaderMode()
}

draw_tactical_backdrop :: proc(renderer: ^Renderer) {
	rl.ClearBackground(RESIN_BACKGROUND)
	rl.DrawRectangleGradientV(0, 0, c.int(renderer.canvas_width), c.int(renderer.canvas_height), {8, 14, 23, 255}, RESIN_BACKGROUND)
	rl.DrawCircleGradient({renderer.canvas_width*0.51, renderer.canvas_height*0.4}, renderer.canvas_width*0.43,
		{25, 45, 66, 105}, {5, 9, 16, 0})
}
