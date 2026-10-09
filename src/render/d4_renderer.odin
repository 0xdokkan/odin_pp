package render

import "core:c"
import "core:fmt"
import "core:math"
import rl "vendor:raylib"
import rlgl "vendor:raylib/rlgl"

D4_VERTICES :: [4]rl.Vector3{{-0.57,-0.32,0.33},{0.57,-0.32,0.33},{0,-0.32,-0.66},{0,0.62,0}}
D4_FACES :: [4][3]int{{0,1,3},{1,2,3},{2,0,3},{0,2,1}}

d4_face_value :: proc(face: int, result: i32) -> i32 {
    return (clamp(result,i32(1),i32(4))-1+i32(clamp(face,0,3)))%4+1
}

// Tetrahedral geometry and four consistent face values. The committed result
// faces the camera at rest; cosmetic motion never changes or re-rolls that value.
draw_d4_mesh :: proc(position: rl.Vector3, progress: f32, result: i32) {
    p := dice_progress(progress)
    tumble := clamp((DICE_PHYSICS_REVEAL_PROGRESS-p)/DICE_PHYSICS_REVEAL_PROGRESS,f32(0),f32(1))
    rotation := rl.QuaternionFromEuler(tumble*math.PI*4,tumble*math.PI*6,tumble*math.PI*2)
    vertices := D4_VERTICES
    for face,index in D4_FACES {
        points: [3]rl.Vector3
        for vertex,i in face { points[i]=rl.Vector3RotateByQuaternion(vertices[vertex],rotation) }
        normal := rl.Vector3Normalize(rl.Vector3CrossProduct(points[1]-points[0],points[2]-points[0]))
        center := (points[0]+points[1]+points[2])/3
        if rl.Vector3DotProduct(normal,center)<0 { points[1],points[2]=points[2],points[1]; normal = -normal }
        colors := [4]rl.Color{{207,225,234,255},{114,148,178,255},{67,103,140,255},{41,65,91,255}}
        color := colors[index]
        rlgl.SetTexture(rlgl.GetTextureIdDefault())
        rlgl.Begin(rlgl.TRIANGLES)
        rlgl.Color4ub(color.r,color.g,color.b,color.a)
        rlgl.Normal3f(normal.x,normal.y,normal.z)
        for local in points { point := local+position; rlgl.TexCoord2f(0,0); rlgl.Vertex3f(point.x,point.y,point.z) }
        rlgl.End()
        rlgl.SetTexture(0)
        value := d4_face_value(index,result)
        a := rl.Vector3Normalize(points[1]-points[0])*0.12
        b := rl.Vector3Normalize(rl.Vector3CrossProduct(normal,a))*0.10
        for pip in 0..<value {
            offset := rl.Vector3{}
            if value == 2 { offset = a*(f32(pip)*2-1) }
            if value == 3 { offset = (a*math.cos(f32(pip)*2*math.PI/3)+b*math.sin(f32(pip)*2*math.PI/3)) }
            if value == 4 { offset = a*(f32(pip%2)*2-1)+b*(f32(pip/2)*2-1) }
            rl.DrawSphereEx(position+center+normal*0.012+offset,0.038,4,6,{14,31,47,255})
        }
    }
}

draw_d4_result_label :: proc(renderer: ^Dice_Renderer, layout: Dice_Pool_Layout, progress: f32, value: i32) {
    theme := renderer.theme if renderer != nil else nil
    title: cstring = "D4 / SCARICHE + BERSAGLI"
    result := "LANCIO / TEMPO SOSPESO" if progress < DICE_PHYSICS_REVEAL_PROGRESS else fmt.ctprintf("%d SCARICHE / FINO A %d NEMICI",value,value)
    size := c.int(max(f32(12),14*layout.scale))
    x := c.int(layout.ground.x)
    y := c.int(layout.ground.y-layout.pixels_per_world*1.75)
    width := max(menu_measure_text(theme,title,size),menu_measure_text(theme,result,size))+24
    rl.DrawRectangle(x-width/2,y-8,width,size*2+28,{7,15,25,235})
    menu_text(theme,title,x-menu_measure_text(theme,title,size)/2,y,size,GOTHIC_BLUE)
    menu_text(theme,result,x-menu_measure_text(theme,result,size)/2,y+size+8,size,GOTHIC_PAPER)
}
