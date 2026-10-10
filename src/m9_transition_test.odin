package main

import "core:testing"
import engine "engine"
import host "engine/host"
import input "engine/input"
import ui "engine/ui"
import fight "fight"
import game "game"
import fps "minigames/fps"
import render "render"

@(test)
test_unified_catalog_routes_room_and_menu_to_the_same_ring_and_fps :: proc(t: ^testing.T) {
    for control in ([2]render.M8_Control{.Ring,.FPS}) {
        info, found := m8_requested_activity_info(control)
        testing.expect(t,found)
        menu, registered := minigame_info(minigame_index_by_id(info.id))
        testing.expect(t,registered && info.create==menu.create)
        if control==.FPS {testing.expect(t,info.create==fps.info().create)}
        else {testing.expect(t,info.create==ring_minigame_create)}
    }
    _, found := m8_requested_activity_info(.Character)
    testing.expect(t,!found,"Only the two canonical activity buttons route to a scene")
    testing.expect(t,EXTRA_CHALLENGE_COUNT==5,"Existing seeds retain their extra-challenge sequence")
    testing.expect_value(t,minigame_index_by_id("ring"),5)
}

@(test)
test_unified_ring_request_consumes_click_and_preserves_the_run :: proc(t: ^testing.T) {
    rs := host_run_fixture(t)
    defer roguelike_destroy(rs)
    rs.card_interaction.selected_card_id=42
    rs.gameplay_buffer.occupied=true
    before:=rs.run_state.player
    pulse:=rs.room.pulse_count
    point:=m8_test_button_center(&rs.iso_renderer,.Ring,&rs.room)
    consumed:=step_m8_session(&rs.m8_session,&rs.room,&rs.iso_renderer,&rs.tactical_controller,
        &rs.card_interaction,&rs.gameplay_buffer,true,0,{focused=true,inside=true,pressed=true,mouse=point})
    testing.expect(t,consumed && rs.m8_session.requested==.Ring && rs.m8_session.ring_pending)
    testing.expect(t,rs.room.ring_challenge_attempted && !rs.gameplay_buffer.occupied && rs.card_interaction.selected_card_id==0)
    testing.expect_value(t,rs.run_state.player,before)
    testing.expect_value(t,rs.room.pulse_count,pulse)
    // No second click or delta can advance the board while the host handoff waits.
    testing.expect(t,step_m8_session(&rs.m8_session,&rs.room,&rs.iso_renderer,&rs.tactical_controller,
        &rs.card_interaction,&rs.gameplay_buffer,true,8,{focused=true,inside=true,pressed=true,mouse=point}))
    testing.expect_value(t,rs.run_state.player,before)
}

@(test)
test_unified_ring_return_validates_receipt_and_unlocks_once :: proc(t: ^testing.T) {
    rs:=host_run_fixture(t)
    defer roguelike_destroy(rs)
    rs.m8_session.ring,_=game.begin_ring_challenge(&rs.room)
    rs.m8_session.ring_pending=true
    before:=rs.run_state.player
    frame: host.Frame
    result:=host.Result{minigame="ring",outcome=.Won,stars=3}
    roguelike_resume(rs,&frame,"fps",result)
    testing.expect(t,rs.m8_session.ring_pending)
    result.minigame="fps"
    roguelike_resume(rs,&frame,"ring",result)
    testing.expect_value(t,rs.run_state.player,before)
    testing.expect(t,rs.m8_session.ring_pending)
    result.minigame="ring"
    roguelike_resume(rs,&frame,"ring",result)
    testing.expect(t,!rs.m8_session.ring_pending && rs.m8_session.reward.won && rs.m8_session.reward.has_unlock)
    testing.expect_value(t,rs.m8_session.reward.unlocked,game.Card_Id.Titan_Grip)
    testing.expect_value(t,rs.run_state.player.m8_profile.ring_wins,u32(1))
    testing.expect_value(t,rs.run_state.player.deck.owned_count,before.deck.owned_count+1)
    testing.expect_value(t,rs.run_state.player.health,before.health)
    testing.expect_value(t,rs.run_state.player.dice,before.dice)
    testing.expect_value(t,rs.run_state.player.gold,before.gold)
    after:=rs.run_state.player
    roguelike_resume(rs,&frame,"ring",result)
    testing.expect_value(t,rs.run_state.player,after)
}

@(test)
test_unified_ring_abandon_or_loss_consumes_attempt_without_penalty :: proc(t: ^testing.T) {
    for has_result in ([2]bool{false,true}) {
        rs:=host_run_fixture(t)
        rs.m8_session.ring,_=game.begin_ring_challenge(&rs.room)
        rs.m8_session.ring_pending=true
        before:=rs.run_state.player
        result: Maybe(host.Result)
        if has_result {result=host.Result{minigame="ring",outcome=.Lost}}
        frame: host.Frame
        roguelike_resume(rs,&frame,"ring",result)
        testing.expect(t,!rs.m8_session.ring_pending && rs.m8_session.ring.settled && !rs.m8_session.reward.won)
        testing.expect(t,rs.room.ring_challenge_attempted)
        testing.expect_value(t,rs.run_state.player,before)
        testing.expect_value(t,rs.room.phase,game.Room_Phase.Loot)
        testing.expect_value(t,rs.room.pulse_count,u64(0))
        roguelike_destroy(rs)
    }
}

@(test)
test_unified_practice_result_never_unlocks_cards_or_consumes_ring :: proc(t: ^testing.T) {
    rs:=host_run_fixture(t)
    defer roguelike_destroy(rs)
    before:=rs.run_state.player
    frame: host.Frame
    for id in ([2]string{"fps","ring"}) {
        roguelike_resume(rs,&frame,id,host.Result{minigame=id,outcome=.Won,stars=3})
        testing.expect_value(t,rs.run_state.player,before)
        testing.expect(t,!rs.room.ring_challenge_attempted)
    }
}

@(test)
test_unified_activity_entry_respects_tactical_input_owners :: proc(t: ^testing.T) {
    rs:=host_run_fixture(t)
    defer roguelike_destroy(rs)
    for control in ([2]render.M8_Control{.Ring,.FPS}) {
        for gate in 0..<4 {
            rs.tactical_controller.hologram=gate==0
            rs.tactical_controller.paused=gate==1
            rs.room.phase=.Combat if gate==2 else .Loot
            point:=m8_test_button_center(&rs.iso_renderer,control,&rs.room)
            consumed:=step_m8_session(&rs.m8_session,&rs.room,&rs.iso_renderer,&rs.tactical_controller,
                &rs.card_interaction,&rs.gameplay_buffer,true,0,{focused=gate!=3,inside=true,pressed=true,mouse=point})
            testing.expect(t,!consumed)
            testing.expect_value(t,rs.m8_session.requested,render.M8_Control.None)
            testing.expect(t,!rs.room.ring_challenge_attempted)
        }
    }
}

@(test)
test_unified_ring_shell_freezes_and_drops_buffered_edges :: proc(t: ^testing.T) {
    scene:=ring_minigame_create({})
    defer scene.destroy(scene.data)
    shell:=host.shell_of(&scene)
    g:=cast(^Ring_Minigame)shell.hooks.data
    testing.expect_value(t,g.session.ring,fight.begin())
    ring_minigame_advance(g,0,true,{jab=true})
    testing.expect(t,g.session.pending.ring.jab)
    before:=g.session.ring
    ring_minigame_advance(g,5,false,{heavy=true})
    testing.expect_value(t,g.session.ring,before)
    testing.expect_value(t,g.session.pending,M9_Tick_Input{})
    testing.expect_value(t,g.session.clock.accumulator,f64(0))
    sample:=input.Sample(Ring_Input_Action){down={.Jab}}
    command:=ring_minigame_command(g,sample,0.016)
    testing.expect(t,!command.jab,"Held intro/resume action is not a fresh attack")
    ring_minigame_advance(g,f32(engine.FIXED_DT),true,command)
    testing.expect_value(t,g.session.ring.fighters[0].move_serial,u32(0))
    ring_minigame_command(g,{},0.016)
    command=ring_minigame_command(g,sample,0.016)
    testing.expect(t,command.jab)
    ring_minigame_advance(g,f32(engine.FIXED_DT),true,command)
    testing.expect_value(t,g.session.ring.fighters[0].move_serial,u32(1))
}

@(test)
test_unified_ring_is_winnable_and_shell_score_uses_real_outcome :: proc(t: ^testing.T) {
    scene:=ring_minigame_create({})
    defer scene.destroy(scene.data)
    g:=cast(^Ring_Minigame)host.shell_of(&scene).hooks.data
    status:=host.Round_Status.Playing
    for _ in 0..<1800 {
        status=ring_minigame_advance(g,f32(engine.FIXED_DT),true,ring_minigame_bot(&g.session.ring))
        if status!=.Playing {break}
    }
    testing.expect_value(t,status,host.Round_Status.Won)
    score,stars:=ring_minigame_score(g)
    testing.expect(t,score>=1000 && stars>=1 && stars<=3)
    testing.expect(t,g.session.ring.landed_hits[0]>0)
}

@(test)
test_m9_diagnostic_workshop_retains_continuous_body_collisions :: proc(t: ^testing.T) {
    session: M9_Session
    defer destroy_m9_session(&session)
    begin_m9_session(&session,.Arena,true,true)
    m9_control(&session,.Level)
    testing.expect_value(t,session.level_index,1)
    session.ring.fighters[0].position={-1,0,1}
    session.ring.fighters[1].position={1,0,1}
    for &fighter in session.ring.fighters {fighter.previous=fighter.position}
    fight.sync_fighters(&session.ring)
    for _ in 0..<180 {step_m9_session(&session,f32(engine.FIXED_DT),{focused=true,ring={move={1,0,0}}})}
    a,b:=session.ring.fighters[0],session.ring.fighters[1]
    testing.expect(t,a.position.x<b.position.x)
    testing.expect(t,engine.vec_length(engine.vec_sub(a.position,b.position))>=2*fight.BODY_RADIUS-0.001)
}

@(test)
test_m9_ring_pad_actions_do_not_consume_shell_back :: proc(t: ^testing.T) {
    actions := ring_minigame_actions()
    ctx := ui.create(nil)
    defer ui.destroy(ctx)
    grab_on_rb := false
    for binding in actions.bindings[.Grab] {
        grab_on_rb = grab_on_rb || binding == input.pad(.RIGHT_TRIGGER_1)
    }
    testing.expect(t,grab_on_rb,"The advertised RB grab must have a real gameplay binding")
    for action in Ring_Input_Action {
        for binding in actions.bindings[action] {
            if binding.kind != .Gamepad_Button {continue}
            testing.expect(t,binding.button != .RIGHT_FACE_RIGHT && binding.button != .MIDDLE_RIGHT,
                "B and Start belong to pause/menu, never to a ring move")
            for back in ctx.nav_map.bindings[.Back] {
                if back.kind == .Gamepad_Button {
                    testing.expect(t,binding.button != back.button,
                        "The shell handles Back before gameplay; sharing it would swallow a move")
                }
            }
        }
    }
}
