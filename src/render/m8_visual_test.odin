package render

import "core:math"
import "core:testing"
import rl "vendor:raylib"
import game "../game"

@(test)
test_d4_faces_have_exactly_four_distinct_results_and_closed_tetrahedron :: proc(t: ^testing.T) {
    for result in i32(1)..=4 {
        seen: [5]bool
        for face in 0..<4 {
            value := d4_face_value(face,result)
            testing.expect(t,value >= 1 && value <= 4 && !seen[value])
            seen[value]=true
        }
        testing.expect_value(t,d4_face_value(0,result),result)
    }
    vertices := D4_VERTICES
    faces := D4_FACES
    edges: [4][4]int
    for face in faces {
        a,b,c := vertices[face[0]],vertices[face[1]],vertices[face[2]]
        normal := rl.Vector3CrossProduct(b-a,c-a)
        testing.expect(t,rl.Vector3Length(normal)>0.1)
        for i in 0..<3 { lo,hi := min(face[i],face[(i+1)%3]),max(face[i],face[(i+1)%3]); edges[lo][hi]+=1 }
    }
    for a in 0..<4 { for b in a+1..<4 { testing.expect_value(t,edges[a][b],2) } }
}

@(test)
test_ring_grab_has_four_distinct_held_poses_and_safe_endpoints :: proc(t: ^testing.T) {
    previous := m8_ring_pose(0)
    for i in 1..<4 {
        pose := m8_ring_pose(i)
        testing.expect(t,pose != previous)
        previous=pose
    }
    testing.expect_value(t,m8_ring_pose(-1),m8_ring_pose(0))
    testing.expect_value(t,m8_ring_pose(90),m8_ring_pose(3))
    testing.expect(t,m8_ring_pose(1).enemy_offset.y>1)
    testing.expect(t,abs(m8_ring_pose(3).enemy_angle+math.PI/2)<0.001)
    for i in 0..<4 {
        ring := game.Ring_Challenge{action=.Grab_Throw,action_time=f32(i)*0.3+0.01}
        testing.expect_value(t,game.ring_grab_pose(&ring),i)
    }
}

@(test)
test_m8_device_descriptions_keep_d4_targets_separate_from_damage :: proc(t: ^testing.T) {
    for tactical in ([2]bool{false,true}) {
        first,second := gothic_card_lines({definition_id=.Shock_Floor,upgrade_level=0},tactical)
        testing.expect_value(t,string(first),"D4 SCARICHE / D4 BERSAGLI")
        testing.expect_value(t,string(second),"1 DANNO / AREA 3X3")
        first,second=gothic_card_lines({definition_id=.Tesla_Coil},tactical)
        testing.expect_value(t,string(first),"8 / DISTANZA DANNI")
        testing.expect_value(t,string(second),"MAX 4 / OGGETTO ATTIVO")
        first,second=gothic_card_lines({definition_id=.Storm_Crown},tactical)
        testing.expect_value(t,string(second),"LEGGENDARIA / RIMBALZO 3")
    }
}

@(test)
test_active_equipment_bar_keeps_hand_and_energy_clear :: proc(t: ^testing.T) {
    renderer := new(Renderer)
    defer free(renderer)
    for width in ([3]f32{640,960,1280}) {
        renderer.canvas_width,renderer.canvas_height=width,540
        bar := m8_active_bar_bounds(renderer)
        hand := tactical_hand_card_bounds(renderer,0,5)
        testing.expect(t,bar.x>=0 && bar.x+bar.width<=width)
        testing.expect(t,bar.y+bar.height<hand.y-25)
    }
}

@(test)
test_m8_presentation_keeps_gold_healing_and_weapon_drops_for_every_enemy :: proc(t: ^testing.T) {
    player := game.Player{}
    room := game.Room{player=&player}
    defer delete(room.loot)
    kinds := [3]game.Loot_Kind{.Gold,.Healing,.Weapon}
    for enemy in 0..<game.MAX_ENEMIES_PER_ROOM {
        for kind in kinds { append(&room.loot,game.Loot{position={enemy,1},kind=kind,amount=1}) }
    }
    snapshot := capture_room_presentation(&room)
    testing.expect_value(t,snapshot.loot_count,len(room.loot))
    testing.expect_value(t,snapshot.dropped,0)
    for item,index in snapshot.loot[:snapshot.loot_count] {
        testing.expect_value(t,item.kind,room.loot[index].kind)
        testing.expect(t,item.visible)
    }
}

@(test)
test_ring_throw_landing_never_penetrates_the_three_dimensional_canvas :: proc(t: ^testing.T) {
    // A full-height cutout used to rotate around its feet and sink half of
    // the landed opponent into the opaque ring floor, in either facing.
    original := Tactical_Billboard{points={{-0.5,1.42,0},{-0.5,0.02,0},{0.5,0.02,0},{0.5,1.42,0}}, source={0,0,64,80}}
    for facing in ([2]f32{-1,1}) {
        for frame in 0..<4 {
            pose := m8_ring_pose(frame)
            quad := m8_ring_transform_quad(original,pose.enemy_offset.y,pose.enemy_angle*facing,0)
            for point in quad.points { testing.expect(t,point.y >= 0.06499) }
            for paper_frame in 0..<4 {
                cutout := comic_cutout_geometry(quad,{},f64(paper_frame)*0.2)
                for point in cutout.points { testing.expect(t,point.y >= 0.06499) }
            }
            // Ground correction translates the whole cutout without cropping
            // or changing its physical size.
            testing.expect(t,abs(rl.Vector3Length(quad.points[1]-quad.points[0])-1.4)<0.001)
            testing.expect(t,abs(rl.Vector3Length(quad.points[2]-quad.points[1])-1)<0.001)
        }
    }
}

@(test)
test_m8_pointer_controls_match_drawn_buttons_and_respect_action_gates :: proc(t: ^testing.T) {
    renderer := new(Renderer)
    defer free(renderer)
    renderer.canvas_width,renderer.canvas_height=960,540
    renderer.tactical.enabled=true
    player := game.Player{}
    room := game.Room{player=&player,phase=.Loot}
    for control in ([2]M8_Control{.Character,.Ring}) {
        b := m8_control_bounds(renderer,control)
        testing.expect_value(t,m8_control_at_point(renderer,&room,{b.x+b.width/2,b.y+b.height/2}),control)
    }
    equip := m8_control_bounds(renderer,.Equip)
    point := [2]f32{equip.x+5,equip.y+5}
    testing.expect_value(t,m8_control_at_point(renderer,&room,{point[0],point[1]}),M8_Control.None)
    player.equipment.reserve={.Iron_Cleaver,4}
    testing.expect_value(t,m8_control_at_point(renderer,&room,{point[0],point[1]}),M8_Control.Equip)
    ring := m8_control_bounds(renderer,.Ring)
    room.ring_challenge_attempted=true
    testing.expect_value(t,m8_control_at_point(renderer,&room,{ring.x+3,ring.y+3}),M8_Control.None)
    room.phase=.Combat
    append(&room.objects,game.Grid_Object{kind=.Shock_Floor,device_charges=3})
    defer delete(room.objects)
    active := m8_control_bounds(renderer,.Activate)
    testing.expect_value(t,m8_control_at_point(renderer,&room,{active.x+3,active.y+3}),M8_Control.Activate)
    player.tactical.config.enabled=true
    player.tactical.phase=.Recovery
    player.tactical.remaining=0.5
    testing.expect_value(t,m8_control_at_point(renderer,&room,{active.x+3,active.y+3}),M8_Control.None)
    for i in 0..<5 {
        card := tactical_hand_card_bounds(renderer,i,5)
        testing.expect_value(t,m8_control_at_point(renderer,&room,{card.x+5,card.y+5}),M8_Control.None)
    }
}

@(test)
test_m8_modal_mouse_buttons_stay_visible_and_clear_of_action_text :: proc(t: ^testing.T) {
    renderer := new(Renderer)
    defer free(renderer)
    renderer.canvas_height=540
    for width in ([3]f32{640,960,1280}) {
        renderer.canvas_width=width
        close := m8_modal_control_bounds(renderer,.Close_Character)
        leave := m8_modal_control_bounds(renderer,.Leave_Ring)
        for button in ([2]rl.Rectangle{close,leave}) {
            testing.expect(t,button.width>0 && button.height>=26)
            testing.expect(t,button.x>=0 && button.x+button.width<=width)
            testing.expect(t,button.y>=0 && button.y+button.height<=renderer.canvas_height)
            testing.expect(t,point_in_rectangle({button.x+button.width/2,button.y+button.height/2},button))
        }
        // Character statistics start below the top-right close button.
        testing.expect(t,close.y+close.height<130)
        // Ring keyboard combat instructions end before the mouse-only leave button.
        testing.expect(t,leave.x>width-290)
        testing.expect(t,leave.y>renderer.canvas_height-56)
        testing.expect(t,!point_in_rectangle({close.x+4,close.y+4},leave))
    }
}
