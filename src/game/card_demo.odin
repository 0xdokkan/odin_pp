package game

import grid "../engine/grid"
import level "../level"

// MOSTRA EFFETTO: every card shown at work in a small room of its own, built
// and run by the game's own rules (main/card_demo.odin directs the take,
// render/card_demo.odin draws its glove and its captions). A scene is data:
// the room's foes, objects, coils and pools, the deck's other cards, the dice
// the take rolls, the gesture that plays the card and what the player does
// after it. Each card gets the default of its targeting and its effects
// (card_demo_default_scene); a card the default cannot show gets an override
// in card_demo_scene. What the take must show comes from the card's own
// definition (card_demo_expected_events, exhaustive over Effect_Kind and, for
// what the player carries, Status_Kind): the test that every Card_Id's take
// shows it is what tells a new card it needs an override, and a new kind of
// effect or status does not compile until it says how its take shows it.

CARD_DEMO_WIDTH :: 11
CARD_DEMO_HEIGHT :: 9
CARD_DEMO_PLAYER :: grid.Position{5, 4}
// The far corner: an exit the room needs (create_room), out of the way.
CARD_DEMO_EXIT :: grid.Position{1, 1}
CARD_DEMO_MAX_FOES :: 6
CARD_DEMO_MAX_OBJECTS :: 4
CARD_DEMO_MAX_COILS :: 2
CARD_DEMO_MAX_POOLS :: 8
CARD_DEMO_MAX_FILLERS :: 3
CARD_DEMO_MAX_ACTIONS :: 12
// FIRST PERSON SHOOTER's take: a burst of the AK every this many seconds,
// held this long (its shots: FIRST_PERSON_SHOTS_PER_SECOND), the life a burst
// takes for sure, and the view's last seconds, too few for one more.
CARD_DEMO_BURST_EVERY :: f32(3)
CARD_DEMO_BURST_SECONDS :: f32(1.3)
CARD_DEMO_BURST_DAMAGE :: i32(6)
CARD_DEMO_BURST_TAIL :: f32(2.7)
CARD_DEMO_DECK_SEED :: u64(0xDE30_C4BD)
CARD_DEMO_ROOM_SEED :: u64(0xDE30_500D)
// The take's player: the game's own pilgrim, his life a little short where a
// cure must show (Card_Demo_Scene.wounds).
CARD_DEMO_PLAYER_STATS :: Player_Stats{max_health = 22, attack = 2, defense = 0}
CARD_DEMO_RULES :: Deck_Rules{hand_size = 1, max_energy = 3, energy_regen_per_pulse = 1}
// A face of Card_Demo_Scene.faces: the die's top face, whatever the die.
CARD_DEMO_TOP :: i32(-1)
// Seeds tried for the dice of a scene (card_demo_dice): three faces of a d20
// come within some thousands.
CARD_DEMO_DICE_TRIES :: u64(400_000)

// How the card leaves the hand.
Card_Demo_Gesture :: enum u8 {
	// Clicked, then clicked again: a card with no target to choose (a Self
	// card, or one with no target at all), played as the hand plays it.
	Double_Click,
	// Let go on the player's own figure.
	Drag_To_Player,
	// Let go on a foe (Card_Demo_Scene.target_foe).
	Drag_To_Foe,
	// Let go on a cell (Card_Demo_Scene.target).
	Drag_To_Cell,
	// Let go on a cell straight from the player (Card_Demo_Scene.target): a line.
	Drag_Along_Line,
	// The Canna da Pesca: picked up from its slot, let go over `target`.
	Rod_Slot,
}

Card_Demo_Foe :: struct {
	at: grid.Position,
	archetype: Enemy_Archetype,
	health, attack: i32,
	// Free foes plan and act; the others are held where they stand.
	free: bool,
}

Card_Demo_Action_Kind :: enum u8 {
	None,
	// A step (`direction`; W, D, S or A), or a bump when a foe stands there.
	Step,
	// FERETRO: Ctrl held and a click on the scene's foe `foe`: an arrow.
	Shoot,
	// FIRST PERSON SHOOTER: the view turned to the scene's foe `foe`, then the
	// trigger held `seconds`.
	Fire,
	// ATTIVA: the Tesla network discharges (its button on the board's bar).
	Activate,
	// A wait (Space).
	Wait,
}

// What the player does once the card has played: `after` seconds after the
// card's cast and cues are over, as soon as the board lets him.
Card_Demo_Action :: struct {
	kind: Card_Demo_Action_Kind,
	after: f32,
	direction: Move_Direction,
	foe: int,
	seconds: f32,
}

Card_Demo_Scene :: struct {
	gesture: Card_Demo_Gesture,
	target_foe: int,
	target: grid.Position,
	foes: [CARD_DEMO_MAX_FOES]Card_Demo_Foe,
	foe_count: int,
	objects: [CARD_DEMO_MAX_OBJECTS]Grid_Object_Spawn,
	object_count: int,
	// Tesla coils already standing (deployed as the card deploys them).
	coils: [CARD_DEMO_MAX_COILS]grid.Position,
	coil_count: int,
	// Veleno 2 poured before the take.
	pools: [CARD_DEMO_MAX_POOLS]grid.Position,
	pool_count: int,
	// More cards in the deck, so that draws have something to draw.
	fillers: [CARD_DEMO_MAX_FILLERS]Card_Id,
	filler_count: int,
	// A stack status on the player as the take starts (what the card washes away).
	player_status: Status_Kind,
	player_stacks: i32,
	// Life the player has lost as the take starts, so that a cure shows.
	wounds: i32,
	// No defence prompt for the free foes' blows: his dodge is spent.
	no_dodge: bool,
	// This many foes must have lost life by the take's end (the card's use).
	foe_hurt: int,
	// A room already cleared: the rod's.
	cleared: bool,
	// The window's seconds (0: the game's) and the fog (0: none).
	window_seconds, vision: int,
	// The faces the take's first roll shows, die by die (0: as it falls).
	faces: [MAX_ROLL_DICE]i32,
	actions: [CARD_DEMO_MAX_ACTIONS]Card_Demo_Action,
	action_count: int,
	// Seconds the room runs on once the card's own cast and cues are over
	// (the actions' `after` counts from then too).
	seconds: f32,
	// What the take must show beyond the card's own effects (its use).
	expects: bit_set[Game_Event_Kind],
}

@(private = "file")
card_demo_add_foe :: proc(scene: ^Card_Demo_Scene, at: grid.Position, archetype := Enemy_Archetype.Chaser, health := i32(30), free := false) {
	if scene.foe_count >= CARD_DEMO_MAX_FOES { return }
	scene.foes[scene.foe_count] = {at = at, archetype = archetype, health = health, attack = 1, free = free}
	scene.foe_count += 1
}

@(private = "file")
card_demo_add_action :: proc(scene: ^Card_Demo_Scene, action: Card_Demo_Action) {
	if scene.action_count >= CARD_DEMO_MAX_ACTIONS { return }
	scene.actions[scene.action_count] = action
	scene.action_count += 1
}

// A cell `dx` east and `dy` south of the player (north is -dy).
@(private)
card_demo_offset :: proc(dx, dy: int) -> grid.Position {
	return {CARD_DEMO_PLAYER.x+dx, CARD_DEMO_PLAYER.y+dy}
}

// A cell `reach` away by `metric`, as far as can be to the player's right on
// the board's screen: the board looks from the south east, so north east of
// him is right of him at his own depth, and what he aims at stands beside him,
// never in front of him or behind. A step north where the reach is odd and
// the metric counts steps (north is up and right, never under his card).
@(private = "file")
card_demo_reach :: proc(metric: Targeting_Range_Metric, reach: int) -> grid.Position {
	switch metric {
	case .Chebyshev: return card_demo_offset(reach, -reach)
	case .Manhattan, .None:
		east := reach/2
		return card_demo_offset(east, -(reach-east))
	}
	return card_demo_offset(0, -reach)
}

// A line runs straight or diagonal from the player: diagonal where the metric
// lets it (to his right on the screen), else north.
@(private = "file")
card_demo_line :: proc(metric: Targeting_Range_Metric, reach: int) -> grid.Position {
	return card_demo_offset(reach, -reach) if metric == .Chebyshev else card_demo_offset(0, -reach)
}

// The default scene of a card, from its targeting and its effects alone: the
// gesture its targeting asks; a foe where a foe is its target; two inside an
// area it strikes; a barrel there too when it lights barrels; two in reach of
// a card that strikes every foe; the deck's other cards when it draws or
// discards; on the player the status it washes away. A card that needs more
// gets it in card_demo_scene.
@(private)
card_demo_default_scene :: proc(given: Card_Definition) -> (scene: Card_Demo_Scene) {
	definition := given
	spec := definition.targeting
	metric := spec.cast_range.metric
	// A second of the room once the card is done: its mark stays in sight.
	scene.seconds = 1
	// A reach inside the card's range, never further than three cells.
	reach := clamp(2, spec.cast_range.minimum, min(spec.cast_range.maximum, 3)) if spec.cast_range.maximum > 0 else 1
	affected, objects, each_enemy, draws := false, false, false, false
	for template in definition.effects[:definition.effect_count] {
		affected = affected || template.target == .Each_Affected_Enemy
		objects = objects || template.affects_objects
		each_enemy = each_enemy || template.target == .Each_Enemy
		draws = draws || template.kind == .Draw_Cards || template.kind == .Discard_Cards
		if template.kind == .Remove_Status && template.target == .Player && status_kind_stacks(template.status) {
			scene.player_status, scene.player_stacks = template.status, 2
		}
	}
	switch spec.rule {
	// Nothing to choose: the hand plays it at a second click.
	case .Self, .Player, .None:
		scene.gesture = .Double_Click
	case .Any, .Entity, .Opponent, .Opponent_Or_Object, .Adjacent_Opponent:
		if spec.rule == .Adjacent_Opponent { reach = 1 }
		scene.gesture = .Drag_Along_Line if spec.shape == .Line else .Drag_To_Foe
		at := card_demo_line(metric, reach) if spec.shape == .Line else card_demo_reach(metric, reach)
		card_demo_add_foe(&scene, at)
		scene.target_foe, scene.target = 0, at
	case .Cell, .Walkable_Cell:
		scene.gesture = .Drag_Along_Line if spec.shape == .Line else .Drag_To_Cell
		if spec.shape == .Line {
			reach = min(3, spec.cast_range.maximum)
			scene.target = card_demo_line(metric, reach)
		} else {
			scene.target = card_demo_reach(metric, reach)
		}
		t := scene.target
		if affected {
			if spec.shape == .Line {
				// What it strikes stands on the line short of the cell.
				card_demo_add_foe(&scene, card_demo_line(metric, 1))
				card_demo_add_foe(&scene, card_demo_line(metric, 2))
			} else {
				// What it strikes stands inside its area, east and north of the
				// cell: one over the other on the screen.
				card_demo_add_foe(&scene, {t.x+1, t.y})
				card_demo_add_foe(&scene, {t.x, t.y-1})
			}
		}
		if objects && spec.shape != .Line {
			scene.objects[0] = {kind = .Barrel, position = {t.x-1, t.y}}
			scene.object_count = 1
		}
	}
	if each_enemy && scene.foe_count == 0 {
		card_demo_add_foe(&scene, card_demo_offset(2, -1))
		card_demo_add_foe(&scene, card_demo_offset(1, -2))
	}
	if draws {
		scene.fillers[0], scene.fillers[1], scene.fillers[2] = .Strike, .Guard, .Arc_Bolt
		scene.filler_count = 3
	}
	return
}

// Each card's scene at `upgrade_level`: the default of its targeting, or what
// it needs instead (a scene that changes with the level: the AK's, whose view
// lasts longer).
card_demo_scene :: proc(id: Card_Id, upgrade_level: i32 = 0) -> (scene: Card_Demo_Scene) {
	definition, _ := card_definition_by_id(id)
	scene = card_demo_default_scene(definition)
	#partial switch id {
	// Two 4s: the 8 that pushes.
	case .Sundering_Blow:
		scene.faces = {4, 4, 0}
	// The die's top face carries the bolt on to a second foe, beside the first.
	case .Fate_Strike:
		card_demo_add_foe(&scene, {scene.target.x+1, scene.target.y-1})
		scene.faces = {CARD_DEMO_TOP, 0, 0}
		scene.foe_hurt = 2
	// The bolt leaps on to the two foes next in line.
	case .Chain_Lightning, .Storm_Crown:
		card_demo_add_foe(&scene, {scene.target.x+1, scene.target.y-1})
		card_demo_add_foe(&scene, {scene.target.x+2, scene.target.y-2})
		scene.foe_hurt = 3
	// Two hits and a miss that guards; a pair that poisons.
	case .Prismatic_Barrage:
		scene.faces = {4, 1, 4}
	case .Twin_Venom:
		scene.faces = {3, 3, 0}
	// The hook pulls a foe three cells off.
	case .Grappling_Hook:
		scene.foes[0].at, scene.target = card_demo_offset(3, -3), card_demo_offset(3, -3)
	// Its blow comes after it, no defence offered: thorns and the rune answer it.
	case .Thorn_Coat, .Counter_Rune:
		card_demo_add_foe(&scene, card_demo_offset(0, -1), free = true)
		scene.no_dodge = true
		scene.seconds = 3
		scene.foe_hurt = 1
	// A step after it: the afterimage shields him.
	case .Afterimage:
		card_demo_add_action(&scene, {kind = .Step, after = 0.3, direction = .North})
	// A free archer's bolt, turned back: it shoots along a straight line.
	case .Deflect:
		card_demo_add_foe(&scene, card_demo_offset(0, -3), .Archer, free = true)
		scene.seconds = 4
		scene.expects = {.Attack_Deflected}
		scene.foe_hurt = 1
	// Ctrl and a click: an arrow at the foe in the line of fire.
	case .Coffin:
		card_demo_add_foe(&scene, card_demo_offset(2, -2))
		card_demo_add_action(&scene, {kind = .Shoot, after = 0.3, foe = 0})
		scene.foe_hurt = 1
	// The loaded bump rolls its die at the hit.
	case .Fate_Dice:
		card_demo_add_foe(&scene, card_demo_offset(0, -1))
		card_demo_add_action(&scene, {kind = .Step, after = 0.3, direction = .North})
		scene.faces = {2, 0, 0}
		scene.expects = {.Fate_Rolled}
	case .Venom_Blade:
		card_demo_add_foe(&scene, card_demo_offset(0, -1))
		card_demo_add_action(&scene, {kind = .Step, after = 0.3, direction = .North})
		scene.faces = {3, 0, 0}
		scene.foe_hurt = 1
	// The survey widens a fog.
	case .Battle_Focus:
		scene.vision = 5
	// Four shadow steps, then the rise.
	case .Shadow_Step:
		card_demo_add_action(&scene, {kind = .Step, after = 0.1, direction = .North})
		card_demo_add_action(&scene, {kind = .Step, after = 0.9, direction = .East})
		card_demo_add_action(&scene, {kind = .Step, after = 1.7, direction = .North})
		card_demo_add_action(&scene, {kind = .Step, after = 2.5, direction = .East})
	// The ring of pools the card closes around a foe: the area floods.
	case .Poison_Pool:
		scene.foes[0] = {at = card_demo_offset(0, -2), archetype = .Chaser, health = 30, attack = 1}
		scene.foe_count = 1
		scene.target = card_demo_offset(0, -1)
		ring := [?]grid.Position{card_demo_offset(0, -3), card_demo_offset(1, -3), card_demo_offset(2, -2), card_demo_offset(1, -1),
			card_demo_offset(-1, -2)}
		for cell in ring {
			scene.pools[scene.pool_count] = cell
			scene.pool_count += 1
		}
	// Windows pass: the fire grows, catches the brute and goes out. It is lit
	// beside the player at his right, so that its cross spreads in the board's
	// middle, between the HUD and the hand, and never under him.
	case .Wildfire:
		scene.foes[0] = {at = card_demo_offset(1, -3), archetype = .Brute, health = 40, attack = 1}
		scene.foe_count = 1
		scene.target = card_demo_offset(1, -1)
		scene.window_seconds = 2
		scene.seconds = 15
	// Two coils, one over the other at his right: one standing, the card's
	// own, then ATTIVA through the foe between them.
	case .Tesla_Coil:
		scene.coils[0] = card_demo_offset(0, -2)
		scene.coil_count = 1
		scene.target = card_demo_offset(2, 0)
		scene.foes[0] = {at = card_demo_offset(1, -1), archetype = .Chaser, health = 30, attack = 1}
		scene.foe_count = 1
		card_demo_add_action(&scene, {kind = .Activate, after = 0.3})
		scene.foe_hurt = 1
	// A foe beside the floor: shocked at each beat, as many times as its die.
	case .Shock_Floor:
		card_demo_add_foe(&scene, {scene.target.x-1, scene.target.y})
		scene.faces = {3, 0, 0}
		scene.seconds = 4
		scene.foe_hurt = 1
	// LAZZO: the foe pulled onto the ring, two more on it to strike.
	case .Lasso:
		scene.foes[0] = {at = card_demo_offset(2, -3), archetype = .Chaser, health = 12, attack = 1}
		scene.target = scene.foes[0].at
		card_demo_add_foe(&scene, card_demo_offset(0, -3))
		card_demo_add_foe(&scene, card_demo_offset(0, 3))
	// PINBALL: the ball struck away among three foes, till it bursts.
	case .Pinball:
		scene.target = scene.foes[0].at
		card_demo_add_foe(&scene, card_demo_offset(-2, -2))
		card_demo_add_foe(&scene, card_demo_offset(3, -2))
		card_demo_add_foe(&scene, card_demo_offset(-3, 1))
	// FIRST PERSON SHOOTER: played by a second click, then the AK turned from
	// foe to foe of the three before him (ahead, at his left, at his right), a
	// burst at each in turn every three seconds for as long as the view lasts
	// at the card's level, each foe as hardy as its bursts take down: the
	// view's seconds show the AK at work, and the three fall one by one near
	// their end.
	case .First_Person:
		seconds := f32(FIRST_PERSON_SECONDS)
		for template in definition.effects[:definition.effect_count] {
			if template.kind == .First_Person { seconds = f32(card_effect_amount(template, clamp(upgrade_level, 0, FIRST_PERSON_MAX_UPGRADE_LEVEL))) }
		}
		bursts := clamp(int((seconds-CARD_DEMO_BURST_TAIL)/CARD_DEMO_BURST_EVERY)+1, 3, CARD_DEMO_MAX_ACTIONS)
		for at, foe in ([3]grid.Position{card_demo_offset(0, -3), card_demo_offset(-2, -2), card_demo_offset(2, -2)}) {
			// The bursts this foe takes: every third one from its own.
			card_demo_add_foe(&scene, at, health = CARD_DEMO_BURST_DAMAGE*i32((bursts-foe+2)/3))
		}
		for burst in 0..<bursts {
			card_demo_add_action(&scene, {kind = .Fire, after = 0.3+f32(burst)*CARD_DEMO_BURST_EVERY, foe = burst%3, seconds = CARD_DEMO_BURST_SECONDS})
		}
		scene.foe_hurt = 3
	// CANNA DA PESCA: a cleared room, the rod's slot, the water at his right,
	// the player a little hurt so that the food's cure shows.
	case .Fishing_Rod:
		scene = {gesture = .Rod_Slot, target = card_demo_offset(2, -2), cleared = true, faces = {3, 0, 0}, seconds = 1, wounds = 6}
	}
	return
}

// The game events the take must show for the card's own effects, and how many
// of the scene's foes it must hurt: from its definition alone, so that a new
// card's take is held to it with no word of its own. Every kind of effect is
// named, so a new one does not compile until it says how its take shows it.
card_demo_expected_events :: proc(id: Card_Id) -> (events: bit_set[Game_Event_Kind], foes_hurt: int) {
	definition, found := card_definition_by_id(id)
	if !found { return }
	// The rod is no card played: its slot casts it (Fish_Cast).
	if !card_is_room_tool(id) { events += {.Card_Played} }
	for template in definition.effects[:definition.effect_count] {
		switch template.kind {
		case .Damage:
			events += {.Damaged}
			if template.target != .Player { foes_hurt = max(foes_hurt, 1) }
		case .Heal: events += {.Healed}
		case .Gain_Gold: events += {.Gold_Gained}
		case .Move: events += {.Moved}
		case .Apply_Status:
			events += {.Status_Applied}
			// What the player carries shows in its use (card_demo_status_use).
			if template.target == .Player {
				use, hurts := card_demo_status_use(template.status)
				events += use
				if hurts { foes_hurt = max(foes_hurt, 1) }
			}
		case .Remove_Status: events += {.Status_Removed}
		// The rune shows in its answer: the blow's source wounded.
		case .Add_Reaction_Binding:
			events += {.Reaction_Binding_Added, .Damaged}
			foes_hurt = max(foes_hurt, 1)
		case .Draw_Cards: events += {.Card_Drawn}
		case .Discard_Cards: events += {.Card_Moved}
		case .Create_Card: events += {.Card_Created}
		case .Gain_Energy: events += {.Energy_Gained}
		case .Deploy_Device: events += {.Object_Spawned}
		case .Enter_Shadow: events += {.Shadow_Entered, .Shadow_Emerged}
		// A pool or a fire is thrown to its cell and lands there; the ground it
		// leaves has no event of its own (card_demo_ground_expected).
		case .Place_Ground: events += {.Spell_Impact}
		case .Lasso: events += {.Lasso_Caught, .Lasso_Struck}
		// Its scene catches food: the food's d4 rolls, and it cures him.
		case .Fish: events += {.Fish_Cast, .Fish_Caught, .Dice_Rolled, .Healed}
		case .Pinball: events += {.Pinball_Made, .Pinball_Launched, .Pinball_Bumped, .Pinball_Burst}
		// Its shots record no event: the take counts the room's hits.
		case .First_Person: events += {.First_Person_Begun}
		}
	}
	// A dice card shows its roll; the Dado del Destino's die rolls at the bump
	// it loads (its scene's Fate_Rolled).
	if card_dice_count(id) > 0 && id != .Fate_Dice { events += {.Dice_Rolled} }
	scene := card_demo_scene(id)
	events += scene.expects
	foes_hurt = max(foes_hurt, scene.foe_hurt)
	return
}

// How a status the player carries shows in use, beyond its chip: the events
// its use makes and whether a foe is wounded by it. Every kind of status is
// named, so a new one does not compile until it says how its take shows it.
@(private = "file")
card_demo_status_use :: proc(kind: Status_Kind) -> (events: bit_set[Game_Event_Kind], foe_hurt: bool) {
	switch kind {
	// Their chips and the paper tags say it all.
	case .Poison, .Shield, .Stagger, .Survey, .Burn, .Slow:
	// SPINE: a blow on him answered.
	case .Thorns: return {.Damaged}, true
	// SCIA: a step that shields him.
	case .Afterimage: return {.Moved}, false
	// RIFLESSO: a blow turned back at its striker.
	case .Deflect: return {.Attack_Deflected}, true
	// FRECCE: an arrow into a foe.
	case .Arrows: return {.Damaged}, true
	// DESTINO: a bump that rolls its die.
	case .Fate: return {.Fate_Rolled}, true
	// LAMA: a bump that poisons.
	case .Venom_Blade: return {.Damaged}, true
	}
	return
}

// What the ground must show by the take's end, when the card leaves one: a
// pool (Pozza di Veleno), or a fire grown past its first cell (Incendio).
Card_Demo_Ground :: enum u8 {None, Pool, Fire}

card_demo_ground_expected :: proc(id: Card_Id) -> Card_Demo_Ground {
	definition, found := card_definition_by_id(id)
	if !found { return .None }
	for template in definition.effects[:definition.effect_count] {
		if template.kind != .Place_Ground { continue }
		return .Fire if template.status == .Burn else .Pool
	}
	return .None
}

// Whether the card's take must count the room's own hits of the AK.
card_demo_counts_shots :: proc(id: Card_Id) -> bool {
	definition, found := card_definition_by_id(id)
	if !found { return false }
	for template in definition.effects[:definition.effect_count] {
		if template.kind == .First_Person { return true }
	}
	return false
}

// Dice whose next roll of `card` (or of one die of `sides`, for a card with
// no dice of its own: the rod's d4) shows `faces`, die by die (0: any;
// CARD_DEMO_TOP: the die's top face).
card_demo_dice :: proc(card: Card_Instance, faces: [MAX_ROLL_DICE]i32, sides: i32) -> (dice: Dice_State, ok: bool) {
	count := card_dice_count(card.definition_id)
	for seed in u64(1)..<CARD_DEMO_DICE_TRIES {
		dice = make_dice_state(seed)
		staged := dice
		roll: Dice_Roll
		rolled: bool
		if count > 0 { roll, rolled = roll_card_dice(&staged, card) } else { roll, rolled = roll_dice_pool(&staged, 1, sides) }
		if !rolled { continue }
		all := true
		for rolled_face, index in roll.faces[:roll.count] {
			wanted := roll.sides if faces[index] == CARD_DEMO_TOP else faces[index]
			all = all && (wanted == 0 || rolled_face == wanted)
		}
		if all { return dice, true }
	}
	return {}, false
}

// The rod's stream whose next catch is food.
@(private = "file")
card_demo_fish_stream :: proc() -> (random: u64, ok: bool) {
	for candidate in u64(1)..<u64(100_000) {
		stream := candidate
		if !fishing_catch_is_card(&stream) { return candidate, true }
	}
	return
}

card_definition_temporary :: proc(id: Card_Id) -> bool {
	definition, found := card_definition_by_id(id)
	return found && definition.temporary_only
}

// The take's room, built into `room`: a small walled floor, the player in the
// middle with `card` in hand (or the rod in his deck), and what the scene
// asks. `dice` are the take's (card_demo_dice, found once for the card: a zero
// state rolls as it falls). `data`, `player` and `room` belong to the caller
// (a room is large: it is built where it stays); nothing of the run is
// touched. On failure nothing is left to free but `data`.
create_card_demo_room :: proc(given: Card_Demo_Scene, card: Card_Instance, dice: Dice_State, data: ^level.Level, player: ^Player,
	tactical: Tactical_Config, room: ^Room) -> (ok: bool) {
	scene := given
	rows: [CARD_DEMO_HEIGHT]string
	buffer: [CARD_DEMO_HEIGHT][CARD_DEMO_WIDTH]u8
	for y in 0..<CARD_DEMO_HEIGHT {
		for x in 0..<CARD_DEMO_WIDTH {
			cell := grid.Position{x, y}
			switch {
			case x == 0 || y == 0 || x == CARD_DEMO_WIDTH-1 || y == CARD_DEMO_HEIGHT-1: buffer[y][x] = '#'
			case cell == CARD_DEMO_PLAYER: buffer[y][x] = '@'
			case cell == CARD_DEMO_EXIT: buffer[y][x] = '>'
			case: buffer[y][x] = '.'
			}
		}
		rows[y] = string(buffer[y][:])
	}
	parsed: level.Parse_Error
	data^, parsed, _ = level.from_ascii(rows[:])
	if parsed != .None { return }
	created: bool
	player^, created = create_player(CARD_DEMO_PLAYER_STATS)
	if !created { return }
	config := tactical
	config.vision_size, config.timed_actions = scene.vision, true
	config.shrinking_window = false
	if scene.window_seconds > 0 { config.timer_seconds = scene.window_seconds }
	if !configure_tactical(player, config) { return }
	if !initialize_empty_deck(&player.deck, CARD_DEMO_RULES, CARD_DEMO_DECK_SEED) { return }
	// A card made only in a fight (the Spark) is made there: the deck owns its
	// maker meanwhile.
	temporary := card_definition_temporary(card.definition_id)
	owned := card.definition_id
	if temporary { owned = .Spark_Forge }
	if _, added := add_owned_card(&player.deck, owned, 0 if temporary else card.upgrade_level); !added { return }
	for filler in scene.fillers[:scene.filler_count] {
		if _, added := add_owned_card(&player.deck, filler); !added { return }
	}
	if dice != {} { player.dice = dice }
	spawns: [CARD_DEMO_MAX_FOES]Enemy_Spawn
	for foe, index in scene.foes[:scene.foe_count] {
		spawns[index] = {position = foe.at, health = foe.health, attack = foe.attack, archetype = foe.archetype}
	}
	room^, ok = create_room(data, player, {enemies = spawns[:scene.foe_count], objects = scene.objects[:scene.object_count],
		room_seed = CARD_DEMO_ROOM_SEED, endless = !scene.cleared})
	if !ok { return }
	defer if !ok { destroy_room(room) }
	ok = false
	if !configure_tactical_room(room, config) { return }
	// The hand holds the card alone: draws find the rest in the draw pile.
	deck := &player.deck
	if temporary {
		// Its maker leaves for Exhaust, which no refill draws from.
		if deck.hand_count > 0 { if _, moved := exhaust_hand_card(deck, 0); !moved { return } }
		if _, made := create_temporary_card(deck, card.definition_id, card.upgrade_level); !made { return }
	} else if !card_is_room_tool(card.definition_id) {
		index := -1
		for held, at in deck.hand[:deck.hand_count] { if held.definition_id == card.definition_id { index = at } }
		if index < 0 {
			for drawn, at in deck.draw_pile[:deck.draw_count] {
				if drawn.definition_id != card.definition_id || deck.hand_count == 0 { continue }
				deck.hand[0], deck.draw_pile[at] = deck.draw_pile[at], deck.hand[0]
				index = 0
				break
			}
		}
		if index < 0 || !validate_deck_state(deck) { return }
	}
	// The held foes stand still: no plan, no blow, for as long as a take lasts.
	for id in 0..<len(room.enemies) {
		if scene.foes[id].free { continue }
		enemy := &room.enemies[id]
		enemy.recovery_pulses = 999
		enemy.intent, enemy.tactical_cooldown = {}, 0
	}
	plan_enemy_intents(room)
	for at in scene.coils[:scene.coil_count] {
		// The coil's own event goes nowhere: the take starts with it standing.
		if !deploy_board_device(room, .Tesla_Coil, at, 8, 0, room.recent_events) { return }
	}
	for cell in scene.pools[:scene.pool_count] {
		action := make_action(.Card, PLAYER_ENTITY, cell_target(cell), .Walkable_Cell)
		if !add_effect(&action, place_ground_effect(cell, .Poison, 2)) || !resolve_action(room, &action).accepted { return }
	}
	if scene.player_stacks > 0 {
		if applied, _ := apply_status(room, PLAYER_ENTITY, scene.player_status, scene.player_stacks, 0); !applied { return }
	}
	if scene.wounds > 0 { player.health = max(1, player.health-scene.wounds) }
	if scene.no_dodge { player.tactical.dodge_recovery = 999 }
	if scene.cleared {
		if stream, found := card_demo_fish_stream(); found { room.fishing.random = stream }
	}
	clear_event_log(room.recent_events)
	ok = true
	return
}
