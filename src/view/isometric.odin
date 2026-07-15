package view

import "core:math"
import grid "../grid"

Isometric_Projection :: struct {
	tile_width, tile_height: f32,
}

Isometric_Camera :: struct {
	origin:             Vec2,
	zoom:               f32,
	min_zoom, max_zoom: f32,
}

make_camera :: proc(origin: Vec2 = {}, zoom: f32 = 1) -> Isometric_Camera {
	return Isometric_Camera{
		origin   = origin,
		zoom     = zoom,
		min_zoom = 0.35,
		max_zoom = 3.0,
	}
}

projection_is_valid :: proc(projection: ^Isometric_Projection) -> bool {
	return projection != nil && projection.tile_width > 0 && projection.tile_height > 0
}

grid_point_to_world :: proc(projection: ^Isometric_Projection, grid_point: Vec2) -> Vec2 {
	assert(projection_is_valid(projection))
	return Vec2{
		x = (grid_point.x-grid_point.y) * projection.tile_width * 0.5,
		y = (grid_point.x+grid_point.y) * projection.tile_height * 0.5,
	}
}

world_to_grid_point :: proc(projection: ^Isometric_Projection, world_point: Vec2) -> Vec2 {
	assert(projection_is_valid(projection))
	return Vec2{
		x = world_point.x/projection.tile_width + world_point.y/projection.tile_height,
		y = world_point.y/projection.tile_height - world_point.x/projection.tile_width,
	}
}

world_to_canvas :: proc(camera: ^Isometric_Camera, world_point: Vec2) -> Vec2 {
	assert(camera != nil && camera.zoom > 0)
	return Vec2{
		x = camera.origin.x + world_point.x*camera.zoom,
		y = camera.origin.y + world_point.y*camera.zoom,
	}
}

canvas_to_world :: proc(camera: ^Isometric_Camera, canvas_point: Vec2) -> Vec2 {
	assert(camera != nil && camera.zoom > 0)
	return Vec2{
		x = (canvas_point.x-camera.origin.x) / camera.zoom,
		y = (canvas_point.y-camera.origin.y) / camera.zoom,
	}
}

grid_point_to_canvas :: proc(
	camera: ^Isometric_Camera,
	projection: ^Isometric_Projection,
	grid_point: Vec2,
) -> Vec2 {
	return world_to_canvas(camera, grid_point_to_world(projection, grid_point))
}

canvas_to_grid_point :: proc(
	camera: ^Isometric_Camera,
	projection: ^Isometric_Projection,
	canvas_point: Vec2,
) -> Vec2 {
	return world_to_grid_point(projection, canvas_to_world(camera, canvas_point))
}

canvas_to_cell :: proc(
	camera: ^Isometric_Camera,
	projection: ^Isometric_Projection,
	canvas_point: Vec2,
) -> grid.Position {
	point := canvas_to_grid_point(camera, projection, canvas_point)
	return grid.Position{
		x = cast(int)math.floor(point.x),
		y = cast(int)math.floor(point.y),
	}
}

pan_camera :: proc(camera: ^Isometric_Camera, delta: Vec2) {
	assert(camera != nil)
	camera.origin.x += delta.x
	camera.origin.y += delta.y
}

set_zoom_around :: proc(camera: ^Isometric_Camera, anchor: Vec2, requested_zoom: f32) {
	assert(camera != nil && camera.zoom > 0)

	world_at_anchor := canvas_to_world(camera, anchor)
	new_zoom := clamp(requested_zoom, camera.min_zoom, camera.max_zoom)
	camera.zoom = new_zoom
	camera.origin = Vec2{
		x = anchor.x-world_at_anchor.x*new_zoom,
		y = anchor.y-world_at_anchor.y*new_zoom,
	}
}

frame_grid :: proc(
	camera: ^Isometric_Camera,
	projection: ^Isometric_Projection,
	grid_width, grid_height: int,
	canvas_width, canvas_height, padding: f32,
) {
	assert(camera != nil)
	assert(projection_is_valid(projection))
	assert(grid_width > 0 && grid_height > 0)

	grid_w := cast(f32)grid_width
	grid_h := cast(f32)grid_height
	world_width := (grid_w+grid_h) * projection.tile_width * 0.5
	world_height := (grid_w+grid_h) * projection.tile_height * 0.5
	available_width := max(canvas_width-padding*2, 1)
	available_height := max(canvas_height-padding*2, 1)
	zoom := min(available_width/world_width, available_height/world_height)
	camera.zoom = clamp(zoom, camera.min_zoom, camera.max_zoom)

	world_min_x := -grid_h * projection.tile_width * 0.5
	world_max_x := grid_w * projection.tile_width * 0.5
	world_center := Vec2{
		x = (world_min_x+world_max_x) * 0.5,
		y = world_height * 0.5,
	}
	camera.origin = Vec2{
		x = canvas_width*0.5-world_center.x*camera.zoom,
		y = canvas_height*0.5-world_center.y*camera.zoom,
	}
}
