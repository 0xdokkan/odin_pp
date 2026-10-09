package render

import "core:math"
import "core:testing"
import rl "vendor:raylib"

@(test)
test_world_characters_keep_thick_projected_outlines_at_every_combat_zoom :: proc(t: ^testing.T) {
    renderer := new(Renderer)
    defer free(renderer)
    renderer.canvas_width, renderer.canvas_height = 960, 540
    renderer.tactical.enabled, renderer.tactical.scene_3d = true, true
    renderer.tactical.art.figures = {id = 1, width = 1254, height = 1254}
    for &source in renderer.tactical.art.figure_sources { source = {0, 0, 240, 320} }
    for key in ([9]Sprite_Key{.Player,.Player_Cast,.Player_Hit,.Chaser,.Archer,.Brute,.Bomber,.Custodian,.Demolitionist}) {
        for perspective in ([2]bool{false, true}) {
            for distance in ([3]f32{7, 12.5, 24}) {
                for yaw in ([4]f32{0, math.PI/2, math.PI, math.PI*1.5}) {
                    renderer.tactical.camera = tactical_orbit_camera({yaw=yaw,pitch=0.68,distance=distance}, {3.5,0,3.5}, perspective)
                    renderer.tactical.outline_mode = .World
                    quad := tactical_billboard_geometry(renderer, key, {3,3})
                    scale := comic_source_pixel_scale(renderer, quad)
                    renderer.tactical.outline_mode = .World
                    radii := comic_outline_radii(renderer, quad)
                    // Actual screen coverage, not the number of atlas texels:
                    // all ordinary game sprites retain a broad paper fringe.
                    testing.expect(t, radii.x*scale >= 3.9999)
                    testing.expect(t, radii.y*scale >= 2.9999)
                    testing.expect(t, radii.x > radii.y)
                    renderer.tactical.outline_mode = .Ring
                    ring_radii := comic_outline_radii(renderer, quad)
                    testing.expect_value(t, ring_radii, rl.Vector2{8,6})
                    if distance >= 12.5 {
                        testing.expect(t, radii.x > ring_radii.x && radii.y > ring_radii.y)
                    }
                    expanded := comic_cutout_geometry(quad, {}, 0, radii.x)
                    testing.expect(t, abs(expanded.source.width-quad.source.width-radii.x*2) < 0.001)
                    testing.expect(t, abs(expanded.source.height-quad.source.height-radii.x*2) < 0.001)
                    for phase in 0..<4 {
                        expanded = comic_cutout_geometry(quad, {}, f64(phase)*0.2, radii.x)
                        for point in expanded.points { testing.expect(t, point.y >= 0.0249) }
                    }
                }
            }
        }
    }
}

@(test)
test_hologram_outlines_stay_compact_and_world_mode_restores_thickness :: proc(t: ^testing.T) {
    renderer := new(Renderer)
    defer free(renderer)
    renderer.canvas_width, renderer.canvas_height = 960, 540
    renderer.tactical.art.figures = {id=1, width=1254, height=1254}
    for &source in renderer.tactical.art.figure_sources { source = {0,0,240,320} }
    for width in ([3]int{17,33,45}) {
        renderer.tactical.camera = tactical_hologram_camera(renderer, width, 31, {yaw=math.PI/4,pitch=0.68,distance=12.5})
        quad := tactical_billboard_geometry(renderer, .Player, {f32(width)/2,15})
        scale := comic_source_pixel_scale(renderer, quad)
        renderer.tactical.outline_mode = .Hologram
        radii := comic_outline_radii(renderer, quad)
        testing.expect(t, abs(radii.x*scale-1.25) < 0.0001)
        testing.expect(t, abs(radii.y*scale-0.85) < 0.0001)
        renderer.tactical.outline_mode = .World
        restored := comic_outline_radii(renderer, quad)
        testing.expect(t, restored.x*scale >= 3.9999 && restored.y*scale >= 2.9999)
    }
}
