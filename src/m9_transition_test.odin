package main

import "core:testing"
import engine "engine"
import host "engine/host"
import input "engine/input"
import ui "engine/ui"
import fight "fight"
import game "game"
import grid "grid"
import level "level"
import render "render"

@(test)
test_run_ring_is_the_catalog_ring_scene :: proc(t: ^testing.T) {
    info, found := minigame_info(minigame_index_by_id("ring"))
    testing.expect(t,found && info.create==ring_minigame_create)
    testing.expect_value(t,minigame_index_by_id("ring"),5)
}

// Two enemies inside a square of coils; the player stands with them.
tesla_ring_run_fixture :: proc(t: ^testing.T) -> ^Roguelike_Session {
    rs := host_run_fixture(t)
    game.destroy_room(&rs.room)
    level.destroy(&rs.level_data)
    rows := [?]string{"#########", "#.......#", "#.......#", "#.......#", "#...@...#", "#.......#", "#.......#", "#...>...#", "#########"}
    err: level.Parse_Error
    rs.level_data, err, _ = level.from_ascii(rows[:])
    testing.expect_value(t,err,level.Parse_Error.None)
    spawns := [?]game.Enemy_Spawn{{position={3,3},health=20,attack=1,archetype=.Brute},{position={5,5},health=10,attack=1}}
    ok: bool
    rs.room, ok = game.create_room(&rs.level_data,&rs.run_state.player,{enemies=spawns[:]})
    testing.expect(t,ok)
    log: game.Event_Log
    for cell in ([4]grid.Position{{2,2},{6,2},{6,6},{2,6}}) {
        testing.expect(t,game.deploy_board_device(&rs.room,.Tesla_Coil,cell,8,0,&log))
    }
    return rs
}

@(test)
test_tesla_square_activation_opens_the_tag_ring_and_freezes_the_run :: proc(t: ^testing.T) {
    rs := tesla_ring_run_fixture(t)
    defer roguelike_destroy(rs)
    _, ready := game.query_tesla_ring(&rs.room)
    testing.expect(t,ready)
    title, _ := render.m8_tesla_control_labels(&rs.room)
    testing.expect_value(t,string(title),"APRI IL RING")
    clock, pulse := rs.run_state.player.tactical.remaining, rs.room.pulse_count
    execution := execute_gameplay_command(&rs.room,{kind=.Activate,origin_phase=.Combat})
    testing.expect(t,execution.committed && rs.room.tesla_ring.pending)
    testing.expect_value(t,game.board_tesla_count(&rs.room),0)
    testing.expect_value(t,rs.run_state.player.tactical.remaining,clock)
    testing.expect_value(t,rs.room.pulse_count,pulse)
    rs.card_interaction.selected_card_id=42
    rs.gameplay_buffer.chord.active=true
    commands: host.Commands
    frame := host.Frame{commands=&commands}
    testing.expect(t,roguelike_open_activity(rs,&frame))
    testing.expect(t,rs.m8_session.ring_pending && !rs.gameplay_buffer.chord.active && rs.card_interaction.selected_card_id==0)
    testing.expect_value(t,commands.count,1)
    // A second frame cannot open a second duel or advance the board.
    testing.expect(t,!roguelike_open_activity(rs,&frame))
    testing.expect(t,step_m8_session(&rs.m8_session,&rs.room,&rs.iso_renderer,&rs.tactical_controller,
        &rs.card_interaction,&rs.gameplay_buffer,true,8,{focused=true,inside=true,pressed=true}))
    // The scene seats both enemies: the first fights, the other waits on the apron.
    scene := commands.items[0].scene
    defer scene.destroy(scene.data)
    g := cast(^Ring_Minigame)host.shell_of(&scene).hooks.data
    ring := &g.session.ring
    testing.expect_value(t,ring.roster_count,2)
    testing.expect_value(t,ring.active,0)
    testing.expect_value(t,ring.fighters[1].health,fight.ring_opponent_health(2))
    testing.expect(t,fight.roster_waiting(ring,1))
    testing.expect_value(t,ring.roster[1].health,fight.ring_opponent_health(2))
    testing.expect_value(t,ring.fighters[0].health,fight.RING_PLAYER_HEALTH)
    testing.expect(t,rs.m8_session.ring_link.reported)
}

@(test)
test_tesla_ring_return_settles_once_and_defeats_the_roster :: proc(t: ^testing.T) {
    rs := tesla_ring_run_fixture(t)
    defer roguelike_destroy(rs)
    testing.expect(t,game.begin_tesla_ring(&rs.room))
    rs.m8_session.ring_pending=true
    rs.m8_session.ring_link=tesla_ring_link(&rs.room)
    before := rs.run_state.player.health
    frame: host.Frame
    result := host.Result{minigame="ring",outcome=.Won,stars=3}
    roguelike_resume(rs,&frame,"fps",result)
    testing.expect(t,rs.m8_session.ring_pending)
    result.minigame="fps"
    roguelike_resume(rs,&frame,"ring",result)
    testing.expect(t,rs.m8_session.ring_pending)
    testing.expect_value(t,len(rs.room.enemies),2)
    result.minigame="ring"
    roguelike_resume(rs,&frame,"ring",result)
    testing.expect(t,!rs.m8_session.ring_pending && rs.m8_session.report.won)
    testing.expect_value(t,rs.m8_session.report.defeated,2)
    testing.expect_value(t,len(rs.room.enemies),0)
    testing.expect_value(t,rs.room.phase,game.Room_Phase.Loot)
    testing.expect_value(t,rs.run_state.player.health,before)
    testing.expect_value(t,rs.run_state.player.m8_profile.ring_wins,u32(1))
    after := rs.run_state.player
    roguelike_resume(rs,&frame,"ring",result)
    testing.expect_value(t,rs.run_state.player,after)
}

@(test)
test_tesla_ring_loss_or_abandon_costs_health_and_keeps_wounds :: proc(t: ^testing.T) {
    for has_result in ([2]bool{false,true}) {
        rs := tesla_ring_run_fixture(t)
        testing.expect(t,game.begin_tesla_ring(&rs.room))
        rs.m8_session.ring_pending=true
        rs.m8_session.ring_link=tesla_ring_link(&rs.room)
        // The Brute ended on a third of its ring health; the other was knocked out.
        link := &rs.m8_session.ring_link
        link.final=link.entered
        link.final.entries[0].health=link.entered.entries[0].health/3
        link.final.entries[1].health,link.final.entries[1].ko=0,true
        link.reported=true
        player := &rs.run_state.player
        before := player.health
        result: Maybe(host.Result)
        if has_result {result=host.Result{minigame="ring",outcome=.Lost}}
        frame: host.Frame
        roguelike_resume(rs,&frame,"ring",result)
        testing.expect(t,!rs.m8_session.ring_pending && rs.m8_session.report.settled && !rs.m8_session.report.won)
        testing.expect_value(t,player.health,max(i32(1),before-max(i32(1),player.stats.max_health/4)))
        testing.expect_value(t,len(rs.room.enemies),1)
        testing.expect_value(t,rs.room.enemies[0].archetype,game.Enemy_Archetype.Brute)
        testing.expect_value(t,rs.room.enemies[0].health,i32(7))
        testing.expect_value(t,rs.room.phase,game.Room_Phase.Combat)
        testing.expect_value(t,player.m8_profile.ring_wins,u32(0))
        roguelike_destroy(rs)
    }
}

@(test)
test_unified_practice_result_never_touches_the_run :: proc(t: ^testing.T) {
    rs:=host_run_fixture(t)
    defer roguelike_destroy(rs)
    before:=rs.run_state.player
    frame: host.Frame
    for id in ([2]string{"fps","ring"}) {
        roguelike_resume(rs,&frame,id,host.Result{minigame=id,outcome=.Won,stars=3})
        testing.expect_value(t,rs.run_state.player,before)
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
