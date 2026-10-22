// The casino has no global money. A hub lends its depot and a serializable
// transaction. Debit + outcome are persisted together before play begins;
// re-opening the scene resumes that same wager, never redraws its outcome.
package memoryarcade

import "core:math"
import rng "../engine/rng"

Casino_Kind :: enum u8 { Ranch, Escape, Roulette, Dice }
Roulette_Bet :: enum u8 { Number, Red, Black, Even, Odd, Low, High, Dozen_1, Dozen_2, Dozen_3, Column_1, Column_2, Column_3 }

Casino_Transaction :: struct {
	kind: Casino_Kind,
	active, settled: bool,
	wager, payout: i64,
	round: u64,
	random: rng.Rng,
	elapsed: f64,
	selection: int,
	bet: Roulette_Bet,
	number, wheel, player_die, bank_die: int,
	crash: [3]f64,
	coins: int,
	multiplier, distance: f64,
	jump, stumble: f32,
	last_bang: bool,
}

Casino_Wallet :: struct {
	data: rawptr,
	balance: proc(data: rawptr) -> i64,
	debit: proc(data: rawptr, amount: i64) -> bool,
	credit: proc(data: rawptr, amount: i64) -> bool,
	changed: proc(data: rawptr),
	// Transactions must cross the durable checkpoint before play or another
	// wager is allowed. The callback flushes queued saves, then writes now.
	commit: proc(data: rawptr) -> bool,
	transaction: ^Casino_Transaction,
	random_state: ^u64,
}

// Strictly between zero and one: large crash multipliers remain finite.
unit64 :: proc(r: ^rng.Rng) -> f64 { return (f64(rng.next_u64(r)>>11)+0.5)/9007199254740992.0 }

ranch_risk :: proc(coin: int) -> f64 { return min(0.60,0.02+f64(max(coin-1,0))*0.03) }
ranch_survival :: proc(coins: int) -> f64 {
	p:=f64(1)
	for coin in 1..=coins { p*=1-ranch_risk(coin) }
	return p
}
ranch_multiplier :: proc(coins: int) -> f64 {
	return 1 if coins<=0 else 0.98/ranch_survival(coins)
}

crash_draw :: proc(r: ^rng.Rng) -> f64 {
	u:=unit64(r)
	return 0 if u<0.03 else 0.97/(1-u)
}
crash_multiplier :: proc(seconds: f64) -> f64 { return math.pow(2.0,seconds/6.0) }

roulette_red :: proc(n: int) -> bool {
	switch n {
	case 1,3,5,7,9,12,14,16,18,19,21,23,25,27,30,32,34,36: return true
	}
	return false
}
roulette_payout :: proc(bet: Roulette_Bet, number, outcome: int) -> int {
	if outcome<0 || outcome>36 { return 0 }
	if bet==.Number { return 36 if number==outcome else 0 }
	if outcome==0 { return 0 }
	switch bet {
	case .Number:
	case .Red: return 2 if roulette_red(outcome) else 0
	case .Black: return 2 if !roulette_red(outcome) else 0
	case .Even: return 2 if outcome%2==0 else 0
	case .Odd: return 2 if outcome%2==1 else 0
	case .Low: return 2 if outcome<=18 else 0
	case .High: return 2 if outcome>=19 else 0
	case .Dozen_1,.Dozen_2,.Dozen_3: return 3 if (outcome-1)/12==int(bet)-int(Roulette_Bet.Dozen_1) else 0
	case .Column_1,.Column_2,.Column_3: return 3 if (outcome-1)%3==int(bet)-int(Roulette_Bet.Column_1) else 0
	}
	return 0
}

// Rounding is drawn only after a player commits to cashing out. Displaying
// an already rounded offer would let stopping strategies exploit rounding.
// This preserves the specified return even for the minimum five-credit bet.
round_credit :: proc(r: ^rng.Rng, value: f64) -> i64 {
	safe:=clamp(value,0,9.0e15)
	whole:=math.floor(safe)
	return i64(whole)+(1 if unit64(r)<safe-whole else 0)
}

casino_begin :: proc(t: ^Casino_Transaction, kind: Casino_Kind, wager: i64, seed: u64,
	selection:=0, bet:=Roulette_Bet.Red, number:=0) -> bool {
	if t.active || wager<5 || wager>50 { return false }
	round:=t.round+1
	t^=Casino_Transaction{kind=kind,active=true,wager=wager,round=round,random=rng.create(seed),
		selection=clamp(selection,0,2),bet=bet,number=clamp(number,0,36),multiplier=1}
	switch kind {
	case .Ranch:
	case .Escape: for &threshold in t.crash { threshold=crash_draw(&t.random) }
	case .Roulette: t.wheel=int(rng.below(&t.random,37))
	case .Dice: t.player_die=rng.int_range(&t.random,1,20); t.bank_die=rng.int_range(&t.random,1,20)
	}
	return true
}

casino_cash_value :: proc(t: ^Casino_Transaction) -> f64 {
	switch t.kind {
	case .Ranch: return f64(t.wager)*ranch_multiplier(t.coins)
	case .Escape: return f64(t.wager)*t.multiplier
	case .Roulette: return f64(t.wager)*f64(roulette_payout(t.bet,t.number,t.wheel))
	case .Dice: return f64(t.wager*2) if t.player_die>t.bank_die else 0
	}
	return 0
}

// Finish updates the model; the scene atomically credits and persists it.
casino_finish :: proc(t: ^Casino_Transaction, won: bool) {
	if !t.active || t.settled { return }
	t.payout=round_credit(&t.random,casino_cash_value(t)) if won else 0
	t.settled=true
}

Casino_Command :: struct { forward,jump,cash: bool }
casino_step :: proc(t: ^Casino_Transaction, cmd: Casino_Command, dt: f32) {
	if !t.active || t.settled { return }
	t.elapsed+=f64(dt)
	switch t.kind {
	case .Ranch:
		t.jump=max(0,t.jump-dt); t.stumble=max(0,t.stumble-dt)
		if cmd.jump && t.jump<=0 { t.jump=0.7 }
		if cmd.cash { casino_finish(t,true); return }
		if cmd.forward && t.stumble<=0 {
			old:=t.distance
			t.distance+=f64(dt)*0.55
			// Every fence is placed halfway between two coins. A stumble is
			// a delay only: the gun is the sole source of monetary risk.
			if int(old+0.5)!=int(t.distance+0.5) && t.jump<=0 { t.stumble=0.55 }
			if int(t.distance)>t.coins {
				t.coins+=1
				t.last_bang=unit64(&t.random)<ranch_risk(t.coins)
				if t.last_bang { casino_finish(t,false) }
				t.multiplier=ranch_multiplier(t.coins)
				// Numeric protection, far beyond any practical surviving run.
				if t.multiplier>1.0e13 { casino_finish(t,true) }
			}
		}
	case .Escape:
		t.multiplier=crash_multiplier(t.elapsed)
		if t.crash[t.selection]<t.multiplier { casino_finish(t,false) }
		else if cmd.cash { casino_finish(t,true) }
	case .Roulette,.Dice:
		if t.elapsed>=3 { casino_finish(t,true) }
	}
}
