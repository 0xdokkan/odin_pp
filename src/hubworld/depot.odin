package hubworld

// INSIDE THE DEPOT (Fase 10 of docs/piano-griglia.md): a room like the casino's hall,
// as in the user's drawing (docs/immagini/hub-deposito.png). The robot arrives at the
// middle; the backpack lies up to the left on its mat, the mannequin that wears the
// character's gear stands up to the right on its plinth, the card archive (a terminal
// whose screen is a shelf of cards that light up) is at the bottom, and the way out
// to the plaza is down to the right. Stepping on the mat or the plinth, or into the
// terminal, opens the panel of the same name. The crates are only there to be walked
// round: they pile up with what the depot holds.

Depot_Station :: enum u8 { Backpack, Character, Archive, Plaza, Crates }

// The stations with a door are the first four; the crates have none.
DEPOT_DOORS :: 4

DEPOT_ROOM_RADIUS :: f32(15)

depot_room :: proc() -> Room {
	room := Room{name = "IL DEPOSITO", radius = DEPOT_ROOM_RADIUS, count = len(Depot_Station), exit = int(Depot_Station.Plaza)}
	put :: proc(room: ^Room, which: Depot_Station, name, subtitle: string, center, half: Vec2, height: f32, decor := false) {
		room.stations[which] = {name = name, subtitle = subtitle, center = center, front = normalize({-center.x, -center.y}), half = half, height = height, decor = decor}
	}
	put(&room, .Backpack, "ZAINO", "sali sul tappeto", {-8.5, -8.5}, {0.9, 0.7}, 1.3)
	put(&room, .Character, "PERSONAGGIO", "manichino con il tuo equipaggiamento", {8.5, -8.5}, {1.3, 1.3}, 3.4)
	put(&room, .Archive, "ARCHIVIO DELLE CARTE", "le carte scoperte, con Mostra effetto", {0, 10.5}, {2.8, 0.9}, 3.4)
	// A wall of the octagon (an eighth of a turn down to the right).
	put(&room, .Plaza, "PIAZZA", "torna in piazza", {10.25, 10.25}, {1.5, 0.5}, 4.4)
	put(&room, .Crates, "CASSE", "crescono con gli oggetti nel deposito", {-12, 2}, {1.5, 2.1}, 2.6, true)
	return room
}

// What the mannequin wears: the weapon and the relics of the backpack, as the item
// variants that name them (the weapon and relic ids of the game).
MANNEQUIN_RELICS :: 3

Gear :: struct {
	has_weapon: bool,
	weapon:     i32,
	has_relic:  [MANNEQUIN_RELICS]bool,
	relic:      [MANNEQUIN_RELICS]i32,
}

// How many crates stand in the depot for `stored` things inside it: a couple when it
// is empty, one more for every three things, up to a heap.
CRATES_MINIMUM :: 2
CRATES_MAXIMUM :: 12

crate_count :: proc(stored: int) -> int {
	return clamp(CRATES_MINIMUM+max(stored, 0)/3, CRATES_MINIMUM, CRATES_MAXIMUM)
}

// How many of the archive's `cells` spines are lit when `discovered` of `total` cards
// are known: in proportion, at least one lit once any card is known, none while none
// is, and all of them only when every card is known.
shelf_lit :: proc(discovered, total, cells: int) -> int {
	if discovered <= 0 || total <= 0 || cells <= 0 { return 0 }
	if discovered >= total { return cells }
	return clamp(discovered*cells/total, 1, cells-1)
}

// What the depot shows of the campaign: the gear on the mannequin, how many things the
// depot holds (the crates), and how many of the cards are known (the archive's lights).
Depot_View :: struct {
	gear:       Gear,
	stored:     int,
	discovered: int,
	total:      int,
}
