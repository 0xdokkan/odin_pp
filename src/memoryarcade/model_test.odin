package memoryarcade

import "core:fmt"
import "core:math"
import "core:testing"
import rng "../engine/rng"

@(test)
six_memories_replay_and_terminate :: proc(t: ^testing.T) {
	for kind in Kind {
		wins:=0
		for seed in u64(1)..=16 {
			a,b: State
			reset(&a,kind,seed); reset(&b,kind,seed)
			for _ in 0..<120*80 {
				cmd:=autoplay(&a)
				step(&a,cmd); step(&b,cmd)
				if a.status!=.Playing { break }
			}
			testing.expect(t,a==b,"The same commands and seed must reproduce the complete model")
			testing.expect(t,a.status!=.Playing,"Every cabinet must have a finite result")
			if a.status==.Won { wins+=1 }
		}
		fmt.printf("Memory %v: autoplay wins %d/16\n",kind,wins)
		testing.expect(t,wins>0,"A rules-following player must be able to win every cabinet")
	}
}

@(test)
lightcycle_walls_heads_and_reverse :: proc(t: ^testing.T) {
	s: State; reset(&s,.Lightcycles,1)
	s.cycles[0].pos={0,5}; s.cycles[0].dir=2
	step(&s,{move={1,0}},0.11)
	testing.expect(t,!s.cycles[0].alive,"Reversing cannot escape a wall")
	reset(&s,.Lightcycles,1)
	s.cycles[0].pos={15,15}; s.cycles[0].dir=0
	s.cycles[1].pos={17,15}; s.cycles[1].dir=2
	// Block alternate paths so the AI continues into the shared head cell.
	for x in 16..=19 { s.grid[14*GRID_W+x]=1; s.grid[16*GRID_W+x]=1 }
	step(&s,{},0.11)
	testing.expect(t,!s.cycles[0].alive&&!s.cycles[1].alive,"Simultaneous collisions kill both heads")
}

@(test)
showdown_punishes_early_draw_and_accepts_reaction :: proc(t: ^testing.T) {
	s: State; reset(&s,.Showdown,41)
	step(&s,{fire=true})
	testing.expect(t,s.early&&s.health==2&&s.duel_wins==0)
	reset(&s,.Showdown,41)
	s.clock=s.cue+0.21
	step(&s,{fire=true})
	testing.expect(t,!s.early&&s.health==3&&s.duel_wins==1&&s.score>600)
}

@(test)
karaoke_judgements_and_spam :: proc(t: ^testing.T) {
	s: State; reset(&s,.Karaoke,99)
	s.time=s.notes[0].time-TICK
	c:=Command{}; c.lanes[s.notes[0].lane]=true
	step(&s,c)
	testing.expect(t,s.perfect==1&&s.combo==1&&s.notes[0].judgement==3)
	before:=s.score
	step(&s,c)
	testing.expect(t,s.hits==1&&s.combo==0&&s.score<before,"A note scores once; random tapping carries a cost")
}

@(test)
casino_rules_and_resume :: proc(t: ^testing.T) {
	tx: Casino_Transaction
	testing.expect(t,!casino_begin(&tx,.Dice,4,1)&&!casino_begin(&tx,.Dice,51,1))
	testing.expect(t,casino_begin(&tx,.Dice,10,1))
	testing.expect(t,!casino_begin(&tx,.Ranch,10,99),"A pending stake cannot be replaced")
	tx.player_die=12; tx.bank_die=12
	casino_step(&tx,{},3.1)
	testing.expect(t,tx.settled&&tx.payout==0,"Ties belong to the house")
	for bet in Roulette_Bet {
		if bet!=.Number { testing.expect(t,roulette_payout(bet,0,0)==0,"Zero loses every outside bet") }
	}
	testing.expect(t,roulette_payout(.Number,0,0)==36)
	a: Casino_Transaction
	casino_begin(&a,.Escape,20,6789,1)
	casino_step(&a,{},0.8)
	b:=a // exact saved snapshot, including the hidden outcomes
	for _ in 0..<100 { casino_step(&a,{},TICK); casino_step(&b,{},TICK) }
	casino_step(&a,{cash=true},TICK); casino_step(&b,{cash=true},TICK)
	testing.expect(t,a==b,"Resuming cannot reroll a wager or double debit it")
	testing.expect(t,math.abs(ranch_survival(12)*ranch_multiplier(12)-0.98)<1e-12)
}

Test_Wallet :: struct { balance: i64, saves, debits, credits, commits: int, blocked, save_fails: bool }

@(test)
casino_wallet_commits_once_and_preserves_owed_reward :: proc(t: ^testing.T) {
	w:=Test_Wallet{balance=100}
	tx: Casino_Transaction
	seed:=u64(78)
	g:=Casino_View{kind=.Dice,wager=10,wallet={data=&w,transaction=&tx,random_state=&seed,
		balance=proc(data:rawptr)->i64 {w:=cast(^Test_Wallet)data; return w.balance},
		debit=proc(data:rawptr,amount:i64)->bool {
			w:=cast(^Test_Wallet)data
			if amount>w.balance {return false}; w.balance-=amount; w.debits+=1; return true
		},
		credit=proc(data:rawptr,amount:i64)->bool {
			w:=cast(^Test_Wallet)data
			if w.blocked {return false}; w.balance+=amount; w.credits+=1; return true
		},
		changed=proc(data:rawptr) {w:=cast(^Test_Wallet)data; w.saves+=1},
	}}
	casino_wager(&g); casino_wager(&g)
	testing.expect(t,w.balance==90&&w.debits==1&&w.saves==1,"Pending wager is debited and persisted exactly once")
	tx.player_die=20; tx.bank_die=1; casino_finish(&tx,true)
	w.blocked=true; casino_settle(&g)
	testing.expect(t,tx.active&&tx.settled&&tx.payout==20&&w.balance==90,"Unaccepted reward remains in escrow")
	w.blocked=false; casino_settle(&g); casino_settle(&g)
	testing.expect(t,!tx.active&&w.balance==110&&w.credits==1&&w.saves==2,"Settlement credits and saves exactly once")
	// A failed disk checkpoint holds the same stake without a second debit.
	g.wallet.commit=proc(data:rawptr)->bool {w:=cast(^Test_Wallet)data; w.commits+=1; return !w.save_fails}
	w.save_fails=true
	casino_wager(&g);outcome:=tx
	testing.expect(t,g.commit_needed&&w.balance==100&&w.debits==2)
	casino_wager(&g);casino_commit(&g)
	testing.expect(t,tx==outcome&&w.debits==2&&w.commits==2)
	w.save_fails=false;casino_commit(&g)
	testing.expect(t,!g.commit_needed&&tx==outcome&&w.commits==3)
}

@(test)
casino_million_trials_house_edges :: proc(t: ^testing.T) {
	TRIALS :: 1_000_000
	r:=rng.create(0xCA51A0)
	rounding:=rng.create(0xCA51B0)
	// All twelve practical exit points, including the minimum bet: stochastic
	// settlement rounding must preserve the promised 98% expected return.
	ranch_total: [12]f64
	for _ in 0..<TRIALS {
		alive:=true
		for coin in 1..=12 {
			alive=alive && unit64(&r)>=ranch_risk(coin)
			if alive { ranch_total[coin-1]+=f64(round_credit(&rounding,5*ranch_multiplier(coin)))/5 }
		}
	}
	for total,i in ranch_total {
		rtp:=total/TRIALS
		testing.expect(t,math.abs(rtp-0.98)<0.014,fmt.tprintf("Ranch exit %d: return %.5f",i+1,rtp))
	}
	crash_total: [3][4]f64
	exits:=[4]f64{1,2,5,10}
	for _ in 0..<TRIALS {
		for runner in 0..<3 {
			threshold:=crash_draw(&r)
			for exit,i in exits { if threshold>=exit { crash_total[runner][i]+=exit } }
		}
	}
	for totals,runner in crash_total {
		for total,i in totals { testing.expect(t,math.abs(total/TRIALS-0.97)<0.014,fmt.tprintf("Crash runner %d exit %.0f: %.5f",runner,exits[i],total/TRIALS)) }
	}
	roulette_total: [Roulette_Bet]f64
	dice_total:=f64(0)
	for _ in 0..<TRIALS {
		wheel:=int(rng.below(&r,37))
		for bet in Roulette_Bet { roulette_total[bet]+=f64(roulette_payout(bet,17,wheel)) }
		if rng.int_range(&r,1,20)>rng.int_range(&r,1,20) { dice_total+=2 }
	}
	for bet in Roulette_Bet {
		rtp:=roulette_total[bet]/TRIALS
		testing.expect(t,math.abs(rtp-36.0/37)<0.014,fmt.tprintf("Roulette %v: %.5f",bet,rtp))
		// Exhaustive probabilities additionally check every payout category.
		total:=0
		for number in 0..=36 { total+=roulette_payout(bet,17,number) }
		testing.expect_value(t,total,36)
	}
	testing.expect(t,math.abs(dice_total/TRIALS-0.95)<0.005)
	fmt.printf("Casino: %d rounds per game; Ranch %.4f..%.4f, crash %.4f, roulette %.4f, dice %.4f RTP\n",TRIALS,
		ranch_total[0]/TRIALS,ranch_total[11]/TRIALS,crash_total[0][1]/TRIALS,roulette_total[.Red]/TRIALS,dice_total/TRIALS)
}
