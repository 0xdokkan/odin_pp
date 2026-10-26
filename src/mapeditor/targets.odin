package mapeditor

import "core:fmt"
import "core:strings"
import campaign "../campaign"
import world "../expedition"
import level "../level"
import run "../run"

// THE MAP EDITOR (Fase 6 of docs/piano-profondita.md): a program of its own (`--editor-mappe`) that sculpts the maps
// the code makes, the Prova meccaniche's arenas and the biomes' maps, layer by layer, and saves what it changed as
// their retouches (files.odin), which the game puts over them (run.mechanics_lab_edits, world.biome_map_edits).

// What the editor opens: an arena of the lab, or a biome's map.
Target :: struct {
	arena: run.Mechanics_Lab_Arena,
	biome: campaign.Biome,
	is_biome: bool,
}

// The arenas' folders' names, in their order.
ARENA_NAMES :: [run.Mechanics_Lab_Arena]string{.Flat = "piana", .Heights = "altezze", .Structures = "strutture", .Mountain = "montagna", .Cave = "grotta", .Layers = "piani", .Lifts = "ascensori"}

// Every map the editor opens: the arenas first, then the biomes.
target_count :: proc() -> int {
	return len(run.Mechanics_Lab_Arena)+int(campaign.Biome.Count)
}

target_at :: proc(index: int) -> Target {
	i := (index%target_count()+target_count())%target_count()
	if i < len(run.Mechanics_Lab_Arena) { return {arena = run.Mechanics_Lab_Arena(i)} }
	return {biome = campaign.Biome(i-len(run.Mechanics_Lab_Arena)), is_biome = true}
}

// Its name on screen.
target_title :: proc(target: Target) -> string {
	if target.is_biome { return fmt.tprintf("Bioma: %s", campaign.biome_name(target.biome)) }
	names := ARENA_NAMES
	return fmt.tprintf("Prova meccaniche: arena %s", names[target.arena])
}

// Its folder under the root of the retouches.
target_folder :: proc(root: string, target: Target, allocator := context.temp_allocator) -> string {
	if target.is_biome {
		name := strings.to_lower(fmt.tprintf("%v", target.biome), context.temp_allocator)
		return fmt.aprintf("%s/biomi/%s", root, name, allocator = allocator)
	}
	names := ARENA_NAMES
	return fmt.aprintf("%s/laboratorio/%s", root, names[target.arena], allocator = allocator)
}

// The size of its map.
target_size :: proc(target: Target) -> (width, height: int) {
	if target.is_biome { side := world.map_size(target.biome); return side, side }
	return run.mechanics_lab_size(target.arena)
}

// Its map as the code makes it, without any retouch, and for a biome its world (the sites and the caves the checks
// read). A biome's map is the same whatever the seed: it is made with seed 1.
target_base :: proc(target: Target, w: ^world.World) -> (data: level.Level, ok: bool) {
	if target.is_biome {
		ok = world.generate(w, &data, target.biome, 1, retouched = false)
		return
	}
	w^ = {}
	return run.mechanics_lab_level(target.arena, retouched = false)
}
