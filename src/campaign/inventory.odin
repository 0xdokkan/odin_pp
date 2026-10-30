package campaign

import game "../game"
import level "../level"

GRID_MAX_WIDTH :: 12
GRID_MAX_HEIGHT :: 8
GRID_MAX_ITEMS :: GRID_MAX_WIDTH * GRID_MAX_HEIGHT
BACKPACK_WIDTH :: 8
BACKPACK_HEIGHT :: 5
ACTIVE_RELICS :: 3
PENDING_ITEMS :: 3

// `Structure_Kit` (Fase 7): a structure the player can set down on the open map; its variant is the level.Structure_Id.
Item_Kind :: enum u8 { None, Healing, Energy, Temporary_Card, Decoy, Upgrade, Weapon, Relic, Credits, Memory, Backpack, Structure_Kit }
Item :: struct {
	kind: Item_Kind,
	variant: i32,
	quantity: i32,
	rotation: u8,
	uses: i32,
}
Cell :: struct { x, y: int }
Shape :: struct { cells: [6]Cell, count, width, height: int }
Entry :: struct { item: Item, x, y: int }
Inventory_Grid :: struct {
	width, height: int,
	entries: [GRID_MAX_ITEMS]Entry,
	count: int,
}
Backpack :: struct {
	grid: Inventory_Grid,
	relics: [ACTIVE_RELICS]Item,
	weapon: Item,
	pending: [PENDING_ITEMS]Item,
	pending_count: int,
}
Pickup_Result :: enum { Rejected, Stored, Pending }
Consume_Effect :: struct { heal, energy, upgrade_points: i32, card: game.Card_Id, has_card, decoy: bool, action_seconds: f32 }

make_grid :: proc(width := BACKPACK_WIDTH, height := BACKPACK_HEIGHT) -> Inventory_Grid {
	return {width = clamp(width, 1, GRID_MAX_WIDTH), height = clamp(height, 1, GRID_MAX_HEIGHT)}
}
make_backpack :: proc(width := BACKPACK_WIDTH) -> Backpack { return {grid = make_grid(width, BACKPACK_HEIGHT)} }
make_item :: proc(kind: Item_Kind, quantity: i32 = 1, variant: i32 = 0) -> Item {
	item := Item{kind = kind, quantity = quantity, variant = variant}
	if kind == .Weapon {
		definition, ok := game.weapon_definition(game.Weapon_Id(variant))
		if ok { item.uses = definition.max_uses }
	}
	return item
}

// What a structure's kit is called: "Casetta", "Carro"... as the catalog names it.
structure_kit_name :: proc(id: level.Structure_Id) -> string {
	return level.structure_definition(id).name
}

// Spends one kit of structure `variant` from the backpack's grid (the one the player has just set down). False if there is none.
spend_structure_kit :: proc(backpack: ^Backpack, variant: i32) -> bool {
	if backpack == nil { return false }
	for entry, i in backpack.grid.entries[:backpack.grid.count] {
		if entry.item.kind == .Structure_Kit && entry.item.variant == variant { _, removed := grid_remove(&backpack.grid, i); return removed }
	}
	return false
}

item_name :: proc(item: Item) -> string {
	#partial switch item.kind {
	case .None: return "Vuoto"
	case .Healing: return "Cibo pescato" if item.variant > 0 else "Kit di riparazione"
	case .Energy: return "Cella di energia"
	case .Temporary_Card: return "Chip tattico"
	case .Decoy: return "Esca olografica"
	case .Upgrade: return "Nucleo di potenziamento"
	case .Weapon:
		definition, ok := game.weapon_definition(game.Weapon_Id(item.variant))
		if ok { return definition.name }
	case .Relic:
		definition, ok := game.relic_definition(game.Relic_Id(item.variant))
		if ok { return definition.name }
	case .Credits: return "Crediti"
	case .Memory: return "Frammento di memoria"
	case .Backpack: return "Modulo zaino"
	case .Structure_Kit:
		if item.variant >= 0 && item.variant < i32(level.Structure_Id.Count) { return structure_kit_name(level.Structure_Id(item.variant)) }
	}
	return "Oggetto sconosciuto"
}
item_description :: proc(item: Item) -> string {
	#partial switch item.kind {
	case .Healing:
		if item.variant > 0 {
			descriptions := [4]string{"Ripristina 1 vita. Puoi conservarlo ed estrarlo.","Ripristina 2 vita. Puoi conservarlo ed estrarlo.","Ripristina 3 vita. Puoi conservarlo ed estrarlo.","Ripristina 4 vita. Puoi conservarlo ed estrarlo."}
			return descriptions[clamp(item.variant,1,4)-1]
		}
		return "Ripara 12 vita. In scontro richiede un'azione."
	case .Energy: return "Ripristina 35 energia. In scontro richiede un'azione."
	case .Temporary_Card: return "Aggiunge alla mano una copia temporanea della carta."
	case .Decoy: return "Richiama una pattuglia lontano dalla tua posizione."
	case .Upgrade: return "Conferisce un punto potenziamento per questa spedizione."
	case .Weapon: return "Equipaggia fuori dallo scontro per potenziare l'urto."
	case .Relic:
		definition, ok := game.relic_definition(game.Relic_Id(item.variant))
		if ok { return definition.description }
	case .Credits: return "Valuta per officine e casino. Estrai per conservarla."
	case .Memory: return "Una memoria del creatore. Estrai per leggerla nell'hub."
	case .Backpack: return "Estrai questo modulo per sbloccare uno zaino piu grande."
	case .Structure_Kit:
		if item.variant >= 0 && item.variant < i32(level.Structure_Id.Count) && level.structure_max_health(level.Structure_Id(item.variant)) > 0 {
			return "Usalo fuori dagli scontri per posarla sulla mappa. I colpi dei nemici la rompono."
		}
		return "Usalo fuori dagli scontri per posarla sulla mappa. Resta per tutta la spedizione."
	case .None:
	}
	return ""
}
stack_limit :: proc(kind: Item_Kind) -> i32 {
	#partial switch kind {
	case .Credits: return 99
	case .Healing, .Energy, .Temporary_Card, .Decoy, .Upgrade: return 5
	case: return 1
	}
}
item_valid :: proc(item: Item) -> bool {
	if item.kind <= .None || item.kind > .Structure_Kit || item.quantity < 1 ||
	   item.quantity > stack_limit(item.kind) || item.rotation > 3 { return false }
	#partial switch item.kind {
	case .Healing: return item.variant >= 0 && item.variant <= 4
	case .Weapon:
		definition, ok := game.weapon_definition(game.Weapon_Id(item.variant))
		return ok && item.uses > 0 && item.uses <= definition.max_uses
	case .Relic: return item.variant > i32(game.Relic_Id.None) && item.variant < i32(game.Relic_Id.Count)
	case .Temporary_Card: return item.variant >= 0 && item.variant < i32(game.Card_Id.Count)
	case .Memory: return item.variant >= 0 && item.variant < 64
	case .Backpack: return item.variant >= 0 && item.variant <= GRID_MAX_WIDTH-BACKPACK_WIDTH
	case .Structure_Kit: return item.variant >= 0 && item.variant < i32(level.Structure_Id.Count)
	case: return item.variant == 0
	}
}

// Shapes are normalized after every quarter-turn, so the grid origin never
// depends on a particular rotation. Rare relics really cost more grid cells.
item_shape :: proc(item: Item) -> (shape: Shape) {
	shape.cells[0] = {0, 0}; shape.count = 1
	#partial switch item.kind {
	case .Weapon:
		shape.cells = {{0, 0}, {1, 0}, {2, 0}, {}, {}, {}}
		shape.count = 3 if item.variant == i32(game.Weapon_Id.Storm_Pike) else 2
	case .Backpack:
		shape.cells = {{0, 0}, {1, 0}, {0, 1}, {1, 1}, {}, {}}; shape.count = 4
	case .Structure_Kit:
		// A building's kit is two cells; the others' one.
		if item.variant >= 0 && item.variant < i32(level.Structure_Id.Count) && level.structure_definition(level.Structure_Id(item.variant)).kind == .Building {
			shape.cells = {{0, 0}, {1, 0}, {}, {}, {}, {}}; shape.count = 2
		}
	case .Relic:
		#partial switch game.Relic_Id(item.variant) {
		case .Iron_Knuckle: shape.count = 1
		case .Ash_Bookmark: shape.cells[1] = {1, 0}; shape.count = 2
		case .Swift_Soles: shape.cells = {{0, 0}, {0, 1}, {1, 1}, {}, {}, {}}; shape.count = 3
		case .Venom_Vial: shape.cells = {{0, 0}, {1, 0}, {1, 1}, {2, 1}, {}, {}}; shape.count = 4
		case .Guard_Sigil: shape.cells = {{1, 0}, {0, 1}, {1, 1}, {2, 1}, {1, 2}, {}}; shape.count = 5
		case .Mending_Thread: shape.cells = {{0, 0}, {0, 1}, {0, 2}, {1, 2}, {2, 2}, {3, 2}}; shape.count = 6
		case:
		}
	case:
	}
	for _ in 0..<int(item.rotation % 4) {
		for &cell in shape.cells[:shape.count] { cell = {-cell.y, cell.x} }
	}
	min_x, min_y := shape.cells[0].x, shape.cells[0].y
	for cell in shape.cells[:shape.count] { min_x = min(min_x, cell.x); min_y = min(min_y, cell.y) }
	for &cell in shape.cells[:shape.count] {
		cell.x -= min_x; cell.y -= min_y
		shape.width = max(shape.width, cell.x+1); shape.height = max(shape.height, cell.y+1)
	}
	return
}

grid_item_at :: proc(grid: ^Inventory_Grid, x, y: int, ignore := -1) -> int {
	if grid == nil { return -1 }
	for entry, index in grid.entries[:clamp(grid.count, 0, GRID_MAX_ITEMS)] {
		if index == ignore { continue }
		shape := item_shape(entry.item)
		for cell in shape.cells[:shape.count] { if entry.x+cell.x == x && entry.y+cell.y == y { return index } }
	}
	return -1
}
grid_can_place :: proc(grid: ^Inventory_Grid, item: Item, x, y: int, ignore := -1) -> bool {
	if grid == nil || !item_valid(item) { return false }
	shape := item_shape(item)
	if x < 0 || y < 0 || x+shape.width > grid.width || y+shape.height > grid.height { return false }
	for cell in shape.cells[:shape.count] { if grid_item_at(grid, x+cell.x, y+cell.y, ignore) >= 0 { return false } }
	return true
}
grid_place :: proc(grid: ^Inventory_Grid, item: Item, x, y: int) -> bool {
	if grid == nil || grid.count >= GRID_MAX_ITEMS || !grid_can_place(grid, item, x, y) { return false }
	grid.entries[grid.count] = {item, x, y}; grid.count += 1
	return true
}
grid_move :: proc(grid: ^Inventory_Grid, index, x, y: int, rotation: u8) -> bool {
	if grid == nil || index < 0 || index >= grid.count || rotation > 3 { return false }
	item := grid.entries[index].item; item.rotation = rotation
	if !grid_can_place(grid, item, x, y, index) { return false }
	grid.entries[index] = {item, x, y}
	return true
}
grid_remove :: proc(grid: ^Inventory_Grid, index: int) -> (Item, bool) {
	if grid == nil || index < 0 || index >= grid.count { return {}, false }
	item := grid.entries[index].item
	for i in index..<grid.count-1 { grid.entries[i] = grid.entries[i+1] }
	grid.count -= 1; grid.entries[grid.count] = {}
	return item, true
}

@(private)
items_stack :: proc(a, b: Item) -> bool { return a.kind == b.kind && a.variant == b.variant && a.uses == b.uses && stack_limit(a.kind) > 1 }

// Insertion is transactional: if the whole pickup does not fit, no partial
// stack has been consumed. This keeps magnet pickups on the floor intact.
grid_add :: proc(grid: ^Inventory_Grid, item: Item) -> bool {
	if grid == nil || !item_valid(item) { return false }
	next := grid^
	left := item
	for &entry in next.entries[:next.count] {
		if items_stack(entry.item, item) {
			amount := min(left.quantity, stack_limit(item.kind)-entry.item.quantity)
			entry.item.quantity += amount; left.quantity -= amount
			if left.quantity == 0 { grid^ = next; return true }
		}
	}
	for rotation in 0..<4 {
		left.rotation = u8((int(item.rotation)+rotation)%4)
		for y in 0..<next.height { for x in 0..<next.width {
			if grid_place(&next, left, x, y) { grid^ = next; return true }
		} }
	}
	return false
}
grid_valid :: proc(grid: ^Inventory_Grid) -> bool {
	if grid == nil || grid.width < 1 || grid.width > GRID_MAX_WIDTH || grid.height < 1 ||
	   grid.height > GRID_MAX_HEIGHT || grid.count < 0 || grid.count > GRID_MAX_ITEMS { return false }
	for entry, index in grid.entries[:grid.count] {
		if !grid_can_place(grid, entry.item, entry.x, entry.y, index) { return false }
	}
	return true
}
backpack_valid :: proc(bag: ^Backpack) -> bool {
	if bag == nil || !grid_valid(&bag.grid) || bag.pending_count < 0 || bag.pending_count > PENDING_ITEMS { return false }
	for item in bag.relics {
		if item.kind != .None && (item.kind != .Relic || !item_valid(item)) { return false }
	}
	for item, index in bag.relics {
		if item.kind == .None { continue }
		for other in bag.relics[:index] { if other.kind == .Relic && other.variant == item.variant { return false } }
	}
	if bag.weapon.kind != .None && (bag.weapon.kind != .Weapon || !item_valid(bag.weapon)) { return false }
	for item in bag.pending[:bag.pending_count] { if !item_valid(item) { return false } }
	return true
}
pickup :: proc(bag: ^Backpack, item: Item, manual := false) -> Pickup_Result {
	if bag == nil || !item_valid(item) { return .Rejected }
	if grid_add(&bag.grid, item) { return .Stored }
	if manual && bag.pending_count < PENDING_ITEMS {
		bag.pending[bag.pending_count] = item; bag.pending_count += 1
		return .Pending
	}
	return .Rejected
}
pending_remove :: proc(bag: ^Backpack, index: int) -> (Item, bool) {
	if bag == nil || index < 0 || index >= bag.pending_count { return {}, false }
	item := bag.pending[index]
	for i in index..<bag.pending_count-1 { bag.pending[i] = bag.pending[i+1] }
	bag.pending_count -= 1; bag.pending[bag.pending_count] = {}
	return item, true
}
hold_item :: proc(bag: ^Backpack, index: int) -> bool {
	if bag == nil || bag.pending_count >= PENDING_ITEMS { return false }
	item, ok := grid_remove(&bag.grid, index)
	if !ok { return false }
	bag.pending[bag.pending_count] = item; bag.pending_count += 1
	return true
}
place_pending :: proc(bag: ^Backpack, index, x, y: int, rotation: u8) -> bool {
	if bag == nil || index < 0 || index >= bag.pending_count { return false }
	item := bag.pending[index]; item.rotation = rotation
	if !grid_place(&bag.grid, item, x, y) { return false }
	pending_remove(bag, index)
	return true
}
// Caller warns before invoking, then creates world loot at the player for
// every returned item. Closing without confirmation leaves pending intact.
drop_pending :: proc(bag: ^Backpack, confirmed: bool) -> ([PENDING_ITEMS]Item, int) {
	if bag == nil || !confirmed { return {}, 0 }
	items, count := bag.pending, bag.pending_count
	bag.pending = {}; bag.pending_count = 0
	return items, count
}
equip :: proc(bag: ^Backpack, index, slot: int, in_combat: bool) -> bool {
	if bag == nil || in_combat || index < 0 || index >= bag.grid.count { return false }
	next := bag^
	item, _ := grid_remove(&next.grid, index)
	old: Item
	#partial switch item.kind {
	case .Relic:
		if slot < 0 || slot >= ACTIVE_RELICS { return false }
		for active, i in next.relics { if i != slot && active.kind == .Relic && active.variant == item.variant { return false } }
		old = next.relics[slot]; next.relics[slot] = item
	case .Weapon: old = next.weapon; next.weapon = item
	case: return false
	}
	if old.kind != .None && !grid_add(&next.grid, old) { return false }
	bag^ = next
	return true
}
unequip :: proc(bag: ^Backpack, slot: int, weapon, in_combat: bool) -> bool {
	if bag == nil || in_combat || (!weapon && (slot < 0 || slot >= ACTIVE_RELICS)) { return false }
	item := bag.weapon if weapon else bag.relics[slot]
	if item.kind == .None || !grid_add(&bag.grid, item) { return false }
	if weapon { bag.weapon = {} } else { bag.relics[slot] = {} }
	return true
}
consume :: proc(bag: ^Backpack, index: int, in_combat: bool) -> (effect: Consume_Effect, ok: bool) {
	if bag == nil || index < 0 || index >= bag.grid.count { return }
	item := bag.grid.entries[index].item
	#partial switch item.kind {
	case .Healing: effect.heal = item.variant if item.variant > 0 else 12
	case .Energy: effect.energy = 35
	case .Temporary_Card: effect.card = game.Card_Id(item.variant); effect.has_card = true
	case .Decoy: effect.decoy = true
	case .Upgrade: effect.upgrade_points = 1
	case: return
	}
	effect.action_seconds = 1 if in_combat else 0
	bag.grid.entries[index].item.quantity -= 1
	if bag.grid.entries[index].item.quantity <= 0 { grid_remove(&bag.grid, index) }
	return effect, true
}

// Equipped inventory is authoritative. Carried relics never become passive.
apply_equipment :: proc(bag: ^Backpack, player: ^game.Player) {
	if bag == nil || player == nil { return }
	combat := player.relics.combat
	player.relics = {}; player.relics.combat = combat
	for item in bag.relics { if item.kind == .Relic { game.acquire_relic(player, game.Relic_Id(item.variant)) } }
	player.equipment = {}
	if bag.weapon.kind == .Weapon { player.equipment.weapon = {game.Weapon_Id(bag.weapon.variant), bag.weapon.uses} }
}
sync_weapon :: proc(bag: ^Backpack, player: ^game.Player) {
	if bag == nil || player == nil { return }
	if player.equipment.weapon.id == .None { bag.weapon = {} } else {
		bag.weapon = make_item(.Weapon, 1, i32(player.equipment.weapon.id)); bag.weapon.uses = player.equipment.weapon.uses_remaining
	}
}

backpack_credits :: proc(bag: ^Backpack) -> (total: i32) {
	if bag == nil { return }
	for entry in bag.grid.entries[:bag.grid.count] { if entry.item.kind == .Credits { total += entry.item.quantity } }
	return
}
backpack_pay :: proc(bag: ^Backpack, amount: i32) -> bool {
	if bag == nil || amount < 0 || backpack_credits(bag) < amount { return false }
	left, index := amount, 0
	for index < bag.grid.count && left > 0 {
		entry := &bag.grid.entries[index]
		if entry.item.kind != .Credits { index += 1; continue }
		paid := min(left, entry.item.quantity); left -= paid; entry.item.quantity -= paid
		if entry.item.quantity == 0 { grid_remove(&bag.grid, index) } else { index += 1 }
	}
	return true
}
// Returns the accepted amount; the remainder belongs to world loot. Credits
// rejected by the magnet are never silently discarded.
backpack_credit :: proc(bag: ^Backpack, amount: i32) -> (accepted: i32) {
	if bag == nil || amount <= 0 { return }
	for accepted < amount {
		// Fill an existing stack first, even if no empty grid cell remains.
		for &entry in bag.grid.entries[:bag.grid.count] {
			if entry.item.kind == .Credits && entry.item.quantity < 99 {
				part := min(amount-accepted, 99-entry.item.quantity)
				entry.item.quantity += part; accepted += part
				if accepted == amount { return }
			}
		}
		part := min(99, amount-accepted)
		if grid_add(&bag.grid, make_item(.Credits, part)) { accepted += part } else { return }
	}
	return
}
