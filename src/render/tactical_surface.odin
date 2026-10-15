package render

import "core:c"
import rl "vendor:raylib"

// Geometry gets a 2x render surface; UI and sprite source textures keep their
// pixel grid. The parent canvas is borrowed, never unloaded by the renderer.
Tactical_Surface :: struct {
	target, parent: rl.RenderTexture2D,
	resolve: rl.Shader,
	frozen_location, focus_location, aspect_location: c.int,
}

// `frozen` (MOVIMENTO OMBRA): the world's colours drain toward a cold grey,
// except in a small pool of colour around the shadow (`focus`: its uv on the
// surface, and a radius in uv height; `aspect` keeps the pool round).
TACTICAL_SURFACE_RESOLVE :: `#version 330
in vec2 fragTexCoord;
uniform sampler2D texture0;
uniform float frozen;
uniform vec3 focus;
uniform float aspect;
out vec4 finalColor;
void main() {
    vec3 c = texture(texture0, fragTexCoord).rgb;
    if (frozen > 0.001) {
        float grey = dot(c, vec3(0.299, 0.587, 0.114));
        vec3 still = mix(vec3(grey), c, 0.2)*vec3(0.82, 0.88, 1.10)*0.8;
        vec2 d = (fragTexCoord-focus.xy)*vec2(aspect, 1.0);
        float keep = 1.0-smoothstep(focus.z*0.45, focus.z, length(d));
        c = mix(c, still, frozen*(1.0-keep));
    }
    finalColor = vec4(c, 1.0);
}
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
	resolve := rl.LoadShaderFromMemory(nil, TACTICAL_SURFACE_RESOLVE)
	renderer.tactical.surface^ = {target, parent, resolve, rl.GetShaderLocation(resolve, "frozen"),
		rl.GetShaderLocation(resolve, "focus"), rl.GetShaderLocation(resolve, "aspect")}
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
	frozen := renderer.tactical.shadow.frozen
	rl.SetShaderValue(surface.resolve, surface.frozen_location, &frozen, .FLOAT)
	if frozen > 0 {
		// The surface's uv runs bottom up.
		at := renderer.tactical.shadow.at
		p := tactical_project(renderer, {at.x+0.5, at.y+0.5}, 0.3)
		focus := rl.Vector3{p.x/max(renderer.canvas_width, 1), 1-p.y/max(renderer.canvas_height, 1), 0.075}
		aspect := renderer.canvas_width/max(renderer.canvas_height, 1)
		rl.SetShaderValue(surface.resolve, surface.focus_location, &focus, .VEC3)
		rl.SetShaderValue(surface.resolve, surface.aspect_location, &aspect, .FLOAT)
	}
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
