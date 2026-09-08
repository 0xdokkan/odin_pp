package render

import "core:math"
import "core:testing"
import rl "vendor:raylib"
import view "../view"

@(test)
test_sprite_clip_keys_extend_the_manifest_without_renumbering_idle_sprites :: proc(t: ^testing.T) {
	names := [?]string{
		"player", "chaser", "archer", "brute", "bomber", "custodian", "demolitionist", "ice_block", "fire", "barrel", "bomb",
		"player_cast", "player_hit", "firebomb_cast", "firebomb_projectile", "firebomb_impact", "chain_bolt", "fate_cast", "fate_impact",
	}
	for name, index in names {
		key, valid := sprite_key_from_name(name)
		testing.expect(t, valid)
		testing.expect_value(t, int(key), index)
		testing.expect_value(t, sprite_key_is_clip(key), index >= 11)
	}
	testing.expect_value(t, MAX_SPRITE_TEXTURES, len(names))
	_, valid := sprite_key_from_name("player_attack_unknown")
	testing.expect(t, !valid)

	texture := Sprite_Texture{texture = {width = 24, height = 32}}
	asset, configured := sprite_entry_config({key = "firebomb_impact", file = "impact.png"}, &texture)
	testing.expect(t, configured, "single-frame PNGs are valid event clips")
	testing.expect_value(t, sprite_clip_frame_index(&asset, 1), 0)
	texture.is_gif = true
	texture.columns, texture.frames, texture.frame_width, texture.frame_height = 2, 3, 12, 16
	asset, configured = sprite_entry_config({key = "fate_cast", file = "cast.gif"}, &texture)
	testing.expect(t, configured, "event GIFs use the existing decoded atlas layout")
	testing.expect_value(t, sprite_clip_frame_index(&asset, 1), 2)
}

@(test)
test_sprite_clip_progress_clamps_to_first_and_last_frames_without_looping :: proc(t: ^testing.T) {
	asset := Sprite_Asset{
		configured = true, columns = 3, frames = 7, frame_width = 16, frame_height = 24,
		width = 32, height = 48, anchor = {0.5, 1}, fps = 8,
	}
	for progress in ([?]f32{-3, 0, math.inf_f32(-1), math.nan_f32()}) {
		testing.expect_value(t, sprite_clip_frame_index(&asset, progress), 0)
	}
	for progress in ([?]f32{1, 1.01, 20, math.inf_f32(1)}) {
		testing.expect_value(t, sprite_clip_frame_index(&asset, progress), 6)
	}
	testing.expect_value(t, sprite_clip_frame_index(&asset, 0.14), 0)
	testing.expect_value(t, sprite_clip_frame_index(&asset, 0.15), 1)
	testing.expect_value(t, sprite_clip_frame_index(&asset, 0.5), 3)
	testing.expect_value(t, sprite_clip_frame_index(&asset, 0.999), 6)
	source, destination := sprite_clip_rectangles(&asset, 1, {100, 100}, 2)
	testing.expect_value(t, source, rl.Rectangle{0, 48, 16, 24})
	testing.expect_value(t, destination, rl.Rectangle{68, 4, 64, 96})
	asset.frames = 1
	testing.expect_value(t, sprite_clip_frame_index(&asset, 1), 0)
	testing.expect_value(t, sprite_clip_frame_index(nil, 1), 0)
}

@(test)
test_sprite_clips_share_an_atlas_but_have_independent_progress_from_each_other_and_idle :: proc(t: ^testing.T) {
	assets := Sprite_Assets{texture_count = 1, elapsed = 123.25}
	assets.textures[0] = {texture = {width = 80, height = 20}, filename = "shared.png"}
	shared := Sprite_Asset{
		configured = true, texture_index = 0, columns = 4, frames = 4, frame_width = 20, frame_height = 20,
		width = 40, height = 40, anchor = {0.5, 0.5}, fps = 8,
	}
	assets.sprites[int(Sprite_Key.Player)] = shared
	assets.sprites[int(Sprite_Key.Firebomb_Impact)] = shared
	assets.sprites[int(Sprite_Key.Fate_Impact)] = shared
	first := &assets.sprites[int(Sprite_Key.Firebomb_Impact)]
	second := &assets.sprites[int(Sprite_Key.Fate_Impact)]
	first_source, first_bounds := sprite_clip_rectangles(first, 0.25, {100, 100}, 1)
	second_source, second_bounds := sprite_clip_rectangles(second, 0.75, {300, 200}, 1)
	testing.expect_value(t, first_source, rl.Rectangle{20, 0, 20, 20})
	testing.expect_value(t, second_source, rl.Rectangle{60, 0, 20, 20})
	testing.expect_value(t, first_bounds, rl.Rectangle{80, 80, 40, 40})
	testing.expect_value(t, second_bounds, rl.Rectangle{280, 180, 40, 40})
	same_asset_other_instance, _ := sprite_clip_rectangles(first, 0, {200, 100}, 1)
	testing.expect_value(t, same_asset_other_instance, rl.Rectangle{0, 0, 20, 20})
	again, _ := sprite_clip_rectangles(first, 0.25, {100, 100}, 1)
	testing.expect(t, again == first_source, "another instance cannot reset shared clip playback")
	advance_sprite_assets(&assets, 0.5)
	first.fps = 60
	again, _ = sprite_clip_rectangles(first, 0.25, {100, 100}, 1)
	testing.expect(t, again == first_source, "cue progress controls clips independently of idle clock and fps")
	testing.expect_value(t, assets.elapsed, f64(123.75))
	testing.expect_value(t, assets.texture_count, 1)
	testing.expect_value(t, first.texture_index, assets.sprites[int(Sprite_Key.Player)].texture_index)
	testing.expect_value(t, first.texture_index, second.texture_index)
}

@(test)
test_sprite_clip_fallback_prevents_event_assets_from_becoming_idle_or_click_targets :: proc(t: ^testing.T) {
	assets := Sprite_Assets{texture_count = 1}
	center := view.Vec2{100, 100}
	testing.expect(t, !draw_sprite_clip(&assets, .Firebomb_Impact, center, 1, 0.5), "missing clips retain procedural effects")
	assets.sprites[int(Sprite_Key.Firebomb_Impact)] = {
		configured = true, texture_index = 0, columns = 1, frames = 1, frame_width = 20, frame_height = 20,
		width = 40, height = 40, anchor = {0.5, 0.5}, fps = 8,
	}
	testing.expect(t, !draw_sprite_asset(&assets, .Firebomb_Impact, center, 1), "event clips cannot enter the idle draw path")
	testing.expect(t, !draw_sprite_clip(&assets, .Player, center, 1, 0.5), "idle body keys cannot replace event clips implicitly")
	hit, configured := sprite_asset_contains_point(&assets, .Firebomb_Impact, center, center, 1)
	testing.expect(t, !hit && !configured, "cosmetic effects must not steal target selection")
	testing.expect(t, !draw_sprite_clip(&assets, .Firebomb_Impact, center, 0, 0.5))
}
