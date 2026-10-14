package render

import "core:math"
import "core:testing"
import rl "vendor:raylib"
import game "../game"
import fight "../fight"
import level "../level"

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
        ring := fight.State{throw_active=true,throw_tick=i*fight.THROW_POSE_TICKS+1}
        testing.expect_value(t,fight.throw_pose(&ring),i)
    }
}

@(test)
test_m8_device_descriptions_keep_d4_targets_separate_from_damage :: proc(t: ^testing.T) {
    for tactical in ([2]bool{false,true}) {
        first,second := gothic_card_lines({definition_id=.Shock_Floor,upgrade_level=0},tactical)
        testing.expect_value(t,string(first),"1d4 SCARICHE / 1d4 BERSAGLI")
        testing.expect_value(t,string(second),"1 DANNO / TRAPPOLA 3X3")
        first,second=gothic_card_lines({definition_id=.Tesla_Coil},tactical)
        testing.expect_value(t,string(first),"8 / DISTANZA DANNI")
        testing.expect_value(t,string(second),"CAMPO: CONSUMA 4 TESLA")
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
    for control in ([1]M8_Control{.Character}) {
        b := m8_control_bounds(renderer,control,&room)
        testing.expect_value(t,m8_control_at_point(renderer,&room,{b.x+b.width/2,b.y+b.height/2}),control)
    }
    equip := m8_control_bounds(renderer,.Equip,&room)
    point := [2]f32{equip.x+5,equip.y+5}
    testing.expect_value(t,m8_control_at_point(renderer,&room,{point[0],point[1]}),M8_Control.None)
    player.equipment.reserve={.Iron_Cleaver,4}
    testing.expect_value(t,m8_control_at_point(renderer,&room,{point[0],point[1]}),M8_Control.Equip)
    room.phase=.Combat
    append(&room.objects,game.Grid_Object{kind=.Shock_Floor,device_charges=3})
    defer delete(room.objects)
    active := m8_control_bounds(renderer,.Activate,&room)
    testing.expect_value(t,m8_control_at_point(renderer,&room,{active.x+3,active.y+3}),M8_Control.None)
    room.objects[0].device_armed=true
    testing.expect_value(t,m8_control_at_point(renderer,&room,{active.x+3,active.y+3}),M8_Control.None)
    data, created := level.create(4,4,{kind=.Floor})
    testing.expect(t,created)
    defer level.destroy(&data)
    room.level_data=&data
    append(&room.objects,game.Grid_Object{kind=.Tesla_Coil,id=2,position={1,1},device_damage=8})
    append(&room.objects,game.Grid_Object{kind=.Tesla_Coil,id=3,position={2,1},device_damage=8})
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
test_shock_floor_presentation_preserves_trigger_state_without_live_aliasing :: proc(t: ^testing.T) {
    player := game.Player{}
    room := game.Room{player=&player,phase=.Combat}
    defer delete(room.objects)
    append(&room.objects,game.Grid_Object{kind=.Shock_Floor,id=1,device_charges=3})
    waiting := capture_room_presentation(&room)
    room.objects[0].device_armed=true
    triggered := capture_room_presentation(&room)
    testing.expect(t,!waiting.objects[0].device_armed)
    testing.expect(t,triggered.objects[0].device_armed)
    room.objects[0].device_armed=false
    testing.expect(t,triggered.objects[0].device_armed)
}

@(test)
test_shock_floor_entry_cue_arms_the_visual_snapshot_without_a_damage_notice :: proc(t: ^testing.T) {
    player := game.Player{}
    room := game.Room{player=&player,phase=.Combat}
    defer delete(room.objects)
    defer delete(room.enemies)
    append(&room.objects,game.Grid_Object{kind=.Shock_Floor,id=1,position={2,2},device_charges=3})
    append(&room.enemies,game.Enemy{id=4,position={2,3},health=5,max_health=5})
    before := capture_room_presentation(&room)
    events: game.Event_Log
    game.arm_shock_floor(&room.objects[0],game.enemy_entity(4),&events)
    timeline := new(Presentation_Timeline)
    defer free(timeline)
    testing.expect(t,begin_event_timeline(timeline,before,&events))
    testing.expect(t,update_event_timeline(timeline,PRESENTATION_NOTICE_DURATION))
    testing.expect_value(t,timeline.update_failures,0)
    testing.expect(t,timeline.view.objects[0].device_armed)
    testing.expect_value(t,timeline.view.enemies[0].health,i32(5))
}

@(test)
test_tesla_button_discloses_consumption_only_for_a_real_field :: proc(t: ^testing.T) {
    data,created := level.create(7,7,{kind=.Floor})
    testing.expect(t,created)
    defer level.destroy(&data)
    player := game.Player{}
    room := game.Room{level_data=&data,player=&player,phase=.Combat}
    defer delete(room.objects)
    for position,index in ([4][2]int{{1,1},{5,1},{5,5},{1,5}}) {
        append(&room.objects,game.Grid_Object{kind=.Tesla_Coil,id=u32(index+1),position={position[0],position[1]},device_damage=8})
        title,detail := m8_tesla_control_labels(&room)
        if index == 1 {
            testing.expect_value(t,string(title),"ATTIVA")
            testing.expect_value(t,string(detail),"TESLA 2/4 / PARETI RIUSABILI")
        } else if index == 3 {
            testing.expect_value(t,string(title),"ATTIVA MEGA")
            testing.expect_value(t,string(detail),"CONSUMA 4 / FUOCO AMICO")
        }
    }
    // Four in a line still form reusable lightning walls, not the mega field.
    for &object,index in room.objects {object.position={index+1,1}}
    title,detail := m8_tesla_control_labels(&room)
    testing.expect_value(t,string(title),"ATTIVA")
    testing.expect_value(t,string(detail),"TESLA 4/4 / PARETI RIUSABILI")
}

@(test)
test_m8_modal_mouse_buttons_stay_visible_and_clear_of_action_text :: proc(t: ^testing.T) {
    renderer := new(Renderer)
    defer free(renderer)
    renderer.canvas_height=540
    for width in ([3]f32{640,960,1280}) {
        renderer.canvas_width=width
        close := m8_modal_control_bounds(renderer,.Close_Character)
        for button in ([1]rl.Rectangle{close}) {
            testing.expect(t,button.width>0 && button.height>=26)
            testing.expect(t,button.x>=0 && button.x+button.width<=width)
            testing.expect(t,button.y>=0 && button.y+button.height<=renderer.canvas_height)
            testing.expect(t,point_in_rectangle({button.x+button.width/2,button.y+button.height/2},button))
        }
        // Character statistics start below the top-right close button.
        testing.expect(t,close.y+close.height<130)

    }
}

@(test)
test_m8_hidden_controls_do_not_occlude_board_and_visible_disabled_controls_do :: proc(t: ^testing.T) {
    renderer := new(Renderer)
    defer free(renderer)
    renderer.canvas_width,renderer.canvas_height=960,540
    renderer.tactical.enabled=true
    player: game.Player
    room := game.Room{player=&player,phase=.Combat}
    defer delete(room.objects)
    activate := m8_control_bounds(renderer,.Activate,&room)
    point := [2]f32{activate.x+4,activate.y+4}
    testing.expect(t,!m8_hud_contains_point(renderer,&room,{point.x,point.y}))
    append(&room.objects,game.Grid_Object{kind=.Tesla_Coil})
    testing.expect(t,m8_hud_contains_point(renderer,&room,{point.x,point.y}))
    testing.expect(t,m8_control_at_point(renderer,&room,{point.x,point.y})==M8_Control.None,
        "one visible Tesla needs another tower; its disabled button must still intercept the pointer")
    equip := m8_control_bounds(renderer,.Equip,&room)
    testing.expect(t,!m8_hud_contains_point(renderer,&room,{equip.x+4,equip.y+4}))
    player.equipment.reserve={.Iron_Cleaver,4}
    testing.expect(t,m8_hud_contains_point(renderer,&room,{equip.x+4,equip.y+4}))
}

@(test)
test_m8_footer_controls_fit_and_do_not_overlap_between_phases :: proc(t: ^testing.T) {
    renderer := new(Renderer)
    defer free(renderer)
    player: game.Player
    room := game.Room{player=&player}
    for width in ([3]f32{640,960,1280}) {
        renderer.canvas_width,renderer.canvas_height=width,540
        for phase in ([2]game.Room_Phase{.Combat,.Loot}) {
            room.phase=phase
            controls := [3]M8_Control{.Activate,.Equip,.Character}
            for control,i in controls {
                a := m8_control_bounds(renderer,control,&room)
                testing.expect(t,a.x>=0 && a.y>=0 && a.x+a.width<=width && a.y+a.height<=540)
                for other,j in controls {
                    if j<=i {continue}
                    b := m8_control_bounds(renderer,other,&room)
                    testing.expect(t,!rl.CheckCollisionRecs(a,b))
                }
                if phase == .Combat {
                    for card in 0..<8 {testing.expect(t,!rl.CheckCollisionRecs(a,tactical_hand_card_bounds(renderer,card,8)))}
                }
            }
        }
    }
}

