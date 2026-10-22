package render

import "core:c"
import rl "vendor:raylib"
import rlgl "vendor:raylib/rlgl"
import canvas_target "../engine/canvas"

// Geometry gets a surface with as many pixels as its parent canvas holds (the
// display's own for the window); UI and sprite source textures keep their
// pixel grid. The parent canvas is borrowed, never unloaded by the renderer;
// `follow` tracks a canvas its owner may reallocate (a resized window).
Tactical_Surface :: struct {
	target, parent: rl.RenderTexture2D,
	follow: ^rl.RenderTexture2D,
	resolve: rl.Shader,
	post: ^Expedition_Post,
	hdr_active, hdr_failed: bool,
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

// At least twice the logical board: a small parent (a fixed stage) keeps
// the former supersampling; the window's canvas already has display pixels.
@(private="file")
tactical_surface_size :: proc(renderer: ^Renderer, parent: rl.RenderTexture2D) -> (c.int, c.int) {
	return max(parent.texture.width, c.int(renderer.canvas_width)*2), max(parent.texture.height, c.int(renderer.canvas_height)*2)
}

@(private="file")
load_tactical_surface_target :: proc(width, height: c.int) -> (rl.RenderTexture2D, bool) {
	target := rl.LoadRenderTexture(width, height)
	if !rl.IsRenderTextureValid(target) || !rlgl.FramebufferComplete(target.id) {
		if target.id != 0 { rl.UnloadRenderTexture(target) }
		return {}, false
	}
	rl.SetTextureFilter(target.texture, .BILINEAR)
	rl.SetTextureWrap(target.texture, .CLAMP)
	return target, true
}

// Draw the board onto `canvas` from now on, following it when it is reallocated.
follow_tactical_canvas :: proc(renderer: ^Renderer, canvas: ^rl.RenderTexture2D) {
	if renderer == nil || renderer.tactical.surface == nil { return }
	renderer.tactical.surface.follow = canvas
}

@(private)
create_tactical_surface :: proc(renderer: ^Renderer, parent: rl.RenderTexture2D) {
	if parent.id == 0 || renderer.tactical.surface != nil { return }
	target, ok := load_tactical_surface_target(tactical_surface_size(renderer, parent))
	if !ok { return }
	renderer.tactical.surface = new(Tactical_Surface)
	// The scene replaces the canvas. Gradient/particle blending can reduce a
	// render target's alpha; resolve it opaque so a map never ghosts the hand
	// or room that was drawn into the parent canvas earlier in the same frame.
	resolve := rl.LoadShaderFromMemory(nil, TACTICAL_SURFACE_RESOLVE)
	renderer.tactical.surface^ = {target=target,parent=parent,resolve=resolve,frozen_location=rl.GetShaderLocation(resolve,"frozen"),
		focus_location=rl.GetShaderLocation(resolve,"focus"),aspect_location=rl.GetShaderLocation(resolve,"aspect")}
}

@(private)
destroy_tactical_surface :: proc(renderer: ^Renderer) {
	surface := renderer.tactical.surface
	if surface == nil { return }
	destroy_expedition_post(&surface.post)
	rl.UnloadRenderTexture(surface.target)
	if surface.resolve.id != 0 { rl.UnloadShader(surface.resolve) }
	free(surface)
	renderer.tactical.surface = nil
}

@(private)
begin_tactical_surface :: proc(renderer: ^Renderer) -> bool {
	surface := renderer.tactical.surface
	if surface == nil { return false }
	if surface.follow != nil && surface.follow.id != 0 { surface.parent = surface.follow^ }
	width, height := tactical_surface_size(renderer, surface.parent)
	if surface.target.texture.width != width || surface.target.texture.height != height {
		if next, ok := load_tactical_surface_target(width, height); ok {
			destroy_expedition_post(&surface.post)
			surface.hdr_failed=false
			rl.UnloadRenderTexture(surface.target)
			surface.target = next
		}
	}
	surface.hdr_active=false
	if renderer.tactical.expedition && !surface.hdr_failed {
		if create_expedition_post(surface) {
			surface.hdr_active=true
			canvas_target.begin(surface.post.world,renderer.canvas_width,renderer.canvas_height)
			return true
		}
		surface.hdr_failed=true
		rl.TraceLog(.WARNING,"HDR environment unavailable; using the standard colour surface")
	}
	// The board draws in logical units at the surface's full resolution.
	canvas_target.begin(surface.target, renderer.canvas_width, renderer.canvas_height)
	return true
}

@(private)
end_tactical_surface :: proc(renderer: ^Renderer, active: bool) {
	if !active { return }
	surface := renderer.tactical.surface
	rl.EndTextureMode()
	// Raylib render targets are not a stack. Explicitly restore the borrowed
	// canvas so later HUD, dice overlays and app.present use the right target.
	canvas_target.begin(surface.parent, renderer.canvas_width, renderer.canvas_height)
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

@(private)
draw_tactical_backdrop :: proc(renderer: ^Renderer) {
	if s:=renderer.tactical.surface;s!=nil && s.hdr_active && s.post!=nil {
		rl.ClearBackground(rl.BLACK)
		rl.BeginShaderMode(s.post.backdrop)
		// Shape atlas UVs cover a tiny white patch; the default white texture
		// supplies the full 0..1 UV range to this analytic backdrop instead.
		expedition_fullscreen(renderer,{id=rlgl.GetTextureIdDefault(),width=1,height=1,mipmaps=1,format=.UNCOMPRESSED_R8G8B8A8})
		rl.EndShaderMode()
		return
	}
	rl.ClearBackground(RESIN_BACKGROUND)
	rl.DrawRectangleGradientV(0, 0, c.int(renderer.canvas_width), c.int(renderer.canvas_height), {8, 14, 23, 255}, RESIN_BACKGROUND)
	rl.DrawCircleGradient({renderer.canvas_width*0.51, renderer.canvas_height*0.4}, renderer.canvas_width*0.43,
		{25, 45, 66, 105}, {5, 9, 16, 0})
}
