package advisor

import game "../game"
import level "../level"

// WHAT THE IA KNOWS OF THE BOARD (docs/piano-ia.md, Fase 7; the rule for ever): every object of the grid, every
// structure, every kind of cell has its line, in switches with no default. The rules in the copy already move, burn,
// explode and fire them; the tables say what an object still does past the horizon (the cannon's beats left, the
// hole's, the coils' charges), which the evaluation counts.

FLAME_WORTH_A_SECOND :: f32(1)

Object_Knowledge :: struct {
	// What one beat of it is worth to the player past the horizon, at its power (a cannon's shot, a hole's bite): the
	// player's devices; 0 for the board's own things (the copy plays them out within the horizon).
	worth_a_beat: f32,
	// At most this many beats are counted: past them the fight has changed.
	beats: i32,
	why: string,
}

object_knowledge :: proc(kind: game.Grid_Object_Kind) -> Object_Knowledge {
	switch kind {
	case .Field_Cannon: return {worth_a_beat = 0.5, beats = 8, why = "il cannone posato spara ancora per i suoi battiti"}
	case .Devouring_Hole: return {worth_a_beat = 0.5, beats = 8, why = "il buco morde chi è vicino per i suoi battiti"}
	case .Cannon: return {worth_a_beat = 0.5, beats = 8, why = "il cannone dell'arsenale spara per i suoi battiti"}
	case .Black_Hole: return {worth_a_beat = 0.5, beats = 8, why = "il buco nero morde per i suoi battiti"}
	case .Flood: return {worth_a_beat = 0.3, beats = 4, why = "l'onda spinge ancora"}
	case .Bomb_Marley: return {worth_a_beat = 0.5, beats = 8, why = "la festa di Marley scoppia ancora"}
	case .Tesla_Coil: return {worth_a_beat = 0.5, beats = 4, why = "le bobine scaricano le cariche che hanno"}
	case .Shock_Floor: return {worth_a_beat = 0.3, beats = 4, why = "il pavimento elettrico morde chi ci passa"}
	case .Ice_Block: return {why = "un blocco di ghiaccio: ferma i passi, la copia lo scioglie"}
	case .Fire: return {why = "il fuoco: brucia chi ci passa, la copia lo fa"}
	case .Barrel: return {why = "un barile: esplode nella copia come nel gioco"}
	case .Bomb: return {why = "una bomba: la sua miccia scorre nella copia"}
	case .Napoli_Table: return {why = "la tavolata: una cura (context.odin)"}
	// A spiderling every two beats, each a bite: half a bite a beat, for its beats left, at most the devices' 8 (its whole
	// 20 would have the IA refocus for it even under a blow); what the foes take off it is the copy's own, within the
	// horizon.
	case .Spider_Nest: return {worth_a_beat = 0.5, beats = 8, why = "il nido fa ancora un ragnetto ogni due battiti"}
	// A blow of her `power` every two beats, a foe on her lines about half of the time: a quarter of a blow a beat. Her cell
	// stops the player's steps too: that the copy knows.
	case .Queen: return {worth_a_beat = 0.25, beats = 8, why = "la Regina colpisce ancora chi entra nelle sue linee"}
	case .Count:
	}
	return {}
}

// What the player's devices on the board will still do past the horizon (each at its life or charges, its power).
objects_value :: proc(room: ^game.Room) -> (value: f32) {
	bites := f32(0)
	for object in room.objects {
		known := object_knowledge(object.kind)
		if known.worth_a_beat <= 0 { continue }
		beats := object.life if object.life > 0 else object.device_charges
		power := object.power if object.power > 0 else max(object.device_damage, 1)
		worth := known.worth_a_beat*f32(min(beats, known.beats))*f32(power)
		if object.kind == .Spider_Nest || object.kind == .Queen { bites += worth } else { value += worth }
	}
	// The flame's seconds past the horizon: a touch of 3 and its Bruciatura every 2 seconds, on one foe at least.
	if game.first_person_flame_active(room) { bites += f32(min(room.first_person.remaining, 8))*FLAME_WORTH_A_SECOND }
	// The spiderlings on their way: each a bite still to come. They bite no more than the foes have left.
	spiders := &room.player.tactical.spiders
	for spider in spiders.items[:spiders.count] { bites += f32(spider.bite) }
	if bites > 0 {
		left := f32(0)
		for enemy in room.enemies { left += f32(enemy.health) }
		value += min(bites, left)
	}
	return
}

structure_knowledge :: proc(id: level.Structure_Id) -> string {
	switch id {
	case .Cottage: return "una casetta: muri, una porta"
	case .Hut: return "una capanna: muri, una porta"
	case .Temple: return "un tempio: muri, muretti, un altare"
	case .Cart: return "un carro: muretti"
	case .Fountain: return "una fontana: muretti, non cura"
	case .Statue: return "una statua: un blocco"
	case .Machine: return "una macchina: un blocco"
	case .Ruin: return "una rovina: muri a pezzi"
	case .Pen: return "un recinto: muretti"
	case .Count:
	}
	return ""
}

Tile_Knowledge :: struct { walkable, stops_sight: bool, why: string }

tile_knowledge :: proc(kind: level.Tile_Kind) -> Tile_Knowledge {
	switch kind {
	case .Floor: return {walkable = true, why = "pavimento"}
	case .Door: return {walkable = true, why = "una porta"}
	case .Player_Spawn: return {walkable = true, why = "la partenza"}
	case .Exit: return {walkable = true, why = "l'uscita"}
	case .Wall: return {stops_sight = true, why = "un muro"}
	case .Fence: return {why = "un muretto: ferma i passi, non la vista"}
	case .Void: return {stops_sight = true, why = "il vuoto"}
	}
	return {}
}
