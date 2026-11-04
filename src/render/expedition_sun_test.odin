package render

import "core:testing"
import grid "../engine/grid"
import game "../game"
import level "../level"

// Shadow maps are stable during a short walk, but never survive a roof, silhouette,
// terrain or architecture change. This also covers the last supported roof bit.
@(test)
test_expedition_sun_cache_reuses_only_unchanged_casters :: proc(t: ^testing.T) {
	old := Expedition_Sun_Key{center = {20, 0, 20}, right = {1, 0, 0},
		geometry_rebuilds = 2, geometry_uploads = 7, terrain_rebuilds = 3, roofs = u64(1)<<63}
	near := old
	near.center.x += EXPEDITION_SUN_REUSE
	testing.expect(t, expedition_sun_reusable(old, near))
	near.center.x += .01
	testing.expect(t, !expedition_sun_reusable(old, near))
	for change in 0..<6 {
		now := old
		switch change {
		case 0: now.geometry_rebuilds += 1
		case 1: now.geometry_uploads += 1
		case 2: now.terrain_rebuilds += 1
		case 3: now.roofs = 0
		case 4: now.biome += 1
		case 5: now.right = {0, 0, 1}
		}
		testing.expect(t, !expedition_sun_reusable(old, now))
	}
}

// The first shadow pass has both the relief and an elevated bridge, before any visible
// floor draw or GPU upload. Repeated preparation is free; an edited bridge is rebuilt.
@(test)
test_expedition_sun_surfaces_are_ready_on_first_frame_and_after_edits :: proc(t: ^testing.T) {
	data, ok := level.create(16, 16, {.Floor})
	testing.expect(t, ok)
	defer level.destroy(&data)
	_ = level.set_height(&data, {x = 3, y = 3}, 6)
	bridge := grid.Position{x = 8, y = 8, layer = 1}
	_ = level.set_tile(&data, bridge, {.Floor})
	_ = level.set_height(&data, bridge, 14)
	f: Expedition_Floor
	defer { destroy_expedition_terrain(&f.terrain); destroy_expedition_under(&f.decks) }
	prepare_expedition_sun_surfaces(&f, &data, true)
	testing.expect(t, f.terrain.ready && f.decks.ready)
	testing.expect_value(t, f.terrain.revision, data.geometry_revision)
	testing.expect_value(t, f.decks.revision, data.geometry_revision)
	testing.expect(t, len(f.terrain.chunks[0].vertices) > 0)
	deck := &f.decks.chunks[3]
	testing.expect(t, len(deck.vertices) > 0)
	maximum: f32
	for v in deck.vertices { maximum = max(maximum, v.position.y) }
	testing.expect(t, abs(maximum-14*game.HEIGHT_STEP_DRAWN) < .02)
	vertices := raw_data(deck.vertices)
	rebuilds := f.terrain.rebuilds
	prepare_expedition_sun_surfaces(&f, &data, true)
	testing.expect_value(t, raw_data(f.decks.chunks[3].vertices), vertices)
	testing.expect_value(t, f.terrain.rebuilds, rebuilds)
	_ = level.set_height(&data, bridge, 20)
	prepare_expedition_sun_surfaces(&f, &data, true)
	testing.expect_value(t, f.terrain.rebuilds, rebuilds+1)
	testing.expect_value(t, f.decks.revision, data.geometry_revision)
	maximum = 0
	for v in f.decks.chunks[3].vertices { maximum = max(maximum, v.position.y) }
	testing.expect(t, abs(maximum-20*game.HEIGHT_STEP_DRAWN) < .02)
}
