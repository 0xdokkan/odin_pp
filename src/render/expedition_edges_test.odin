package render

import "core:math"
import "core:testing"
import rl "vendor:raylib"

@(private)
edge_test_project :: proc(camera:rl.Camera3D,p:rl.Vector3,pixels:rl.Vector2,reflection:bool)->rl.Vector2 {
	q:=p;if reflection {q.y=-q.y}
	return rl.GetWorldToScreenEx(q,camera,i32(pixels.x),i32(pixels.y))
}

@(test)
test_expedition_ribbons_keep_physical_width_in_perspective_ortho_and_reflection :: proc(t:^testing.T) {
	for projection in ([2]rl.CameraProjection{.PERSPECTIVE,.ORTHOGRAPHIC}) {
		camera:=rl.Camera3D{position={14,16,21},target={4,0,4},up={0,1,0},fovy=44 if projection==.PERSPECTIVE else 25,projection=projection}
		for pixels in ([4]rl.Vector2{{960,540},{1920,1080},{3840,2160},{1600,1000}}) {
			for reflection in ([2]bool{false,true}) {
				frame:=expedition_edge_frame(camera,pixels,1.35,reflection)
				for endpoints in ([4][2]rl.Vector3{{{2,0,3},{8,0,3}},{{3,0,4},{3,4,4}},{{2,1,2},{8,3,8}},{{-7,0,-8},{12,5,12}}}) {
					q,ok:=expedition_ribbon(&frame,endpoints[0],endpoints[1]);testing.expect(t,ok)
					p:[4]rl.Vector2
					for v,i in q.vertices {p[i]=edge_test_project(camera,v,pixels,reflection);testing.expect(t,!math.is_nan(p[i].x) && !math.is_nan(p[i].y))}
					// The quad includes 1.25 physical pixels of analytic coverage
					// around both sides, independent of target DPI and view depth.
					testing.expect(t,abs(rl.Vector2Distance(p[0],p[3])-(1.35+2.5))<.005)
					testing.expect(t,abs(rl.Vector2Distance(p[1],p[2])-(1.35+2.5))<.005)
					testing.expect(t,q.uv[0].x<0 && q.uv[1].x>1 && q.uv[0].y== -q.uv[3].y)
				}
			}
		}
	}
}

@(test)
test_expedition_ribbons_clip_behind_camera_and_reject_zero_length :: proc(t:^testing.T) {
	camera:=rl.Camera3D{position={0,0,5},target={0,0,0},up={0,1,0},fovy=50,projection=.PERSPECTIVE}
	frame:=expedition_edge_frame(camera,{1920,1080})
	_,ok:=expedition_ribbon(&frame,{1,1,1},{1,1,1});testing.expect(t,!ok)
	_,ok=expedition_ribbon(&frame,{1,1,6},{2,2,7});testing.expect(t,!ok)
	q:Expedition_Ribbon;q,ok=expedition_ribbon(&frame,{-1,1,6},{1,2,0});testing.expect(t,ok)
	for p in q.vertices {for component in p {testing.expect(t,!math.is_nan(component) && !math.is_inf(component))}}
}

@(test)
test_expedition_line_emitters_are_nearest_deduplicated_and_hdr :: proc(t:^testing.T) {
	e:Expedition_Edges
	for i:=48;i>0;i-=1 {expedition_collect_edge(&e,{f32(i),0,0},{f32(i),2,0},{80,200,255,254})}
	testing.expect_value(t,e.emitter_count,EXPEDITION_LINE_EMITTERS)
	for emitter,i in e.emitters {
		testing.expect_value(t,emitter.a.x,f32(i+1));testing.expect_value(t,emitter.radiance.z,EXPEDITION_EDGE_EMISSION)
		testing.expect(t,emitter.radiance.y>1 && emitter.radiance.x>0 && emitter.radiance.x<1)
	}
	expedition_collect_edge(&e,{1,2,0},{1,0,0},{80,200,255,254})
	expedition_collect_edge(&e,{0,0,0},{0,2,0},{30,30,30,254})
	testing.expect_value(t,e.emitter_count,EXPEDITION_LINE_EMITTERS)
	testing.expect_value(t,e.emitters[0].a.x,f32(1));testing.expect_value(t,e.emitters[31].a.x,f32(32))
}

@(test)
test_expedition_ink_faces_have_outward_normals_on_caps_sides_and_apices :: proc(t:^testing.T) {
	bottom:=[4]rl.Vector3{{-1,0,-1},{1,0,-1},{1,0,1},{-1,0,1}}
	top:[4]rl.Vector3;for p,i in bottom {top[i]=p+{.2,2,.1}}
	cap:=ink_face_normal(top[0],top[2],top[1]);testing.expect(t,cap.y>.999)
	for i in 0..<4 {
		j:=(i+1)%4;n:=ink_face_normal(bottom[i],top[j],bottom[j]);out:=(bottom[i]+bottom[j])*.5
		testing.expect(t,rl.Vector3DotProduct(n,out)>.9 && abs(rl.Vector3Length(n)-1)<.0001)
		apex:=ink_face_normal(bottom[i],{0,3,0},bottom[j]);testing.expect(t,rl.Vector3DotProduct(apex,out)>0 && apex.y>0)
	}
}
