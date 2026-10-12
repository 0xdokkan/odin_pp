package render

import "core:testing"
import game "../game"

@(test)
test_flipbook_player_comes_back_after_death_on_restart :: proc(t: ^testing.T) {
	renderer := new(Renderer)
	defer free(renderer)
	renderer.tactical.flipbook_state = new(Flipbook_State)
	defer free(renderer.tactical.flipbook_state)
	state := renderer.tactical.flipbook_state
	slot := flipbook_slot(state, game.PLAYER_ENTITY, .Pilgrim, 0)
	slot.action, slot.started = .Death, 0
	now := f64(100)
	// Still dead on the defeat screen: the card stays fallen.
	actor := Presentation_Actor{entity = game.PLAYER_ENTITY, health = 0, max_health = 22, visible = true}
	flipbook_observe(renderer, state, nil, actor, .Pilgrim, now, {1, 0, 0})
	found := flipbook_find(renderer, game.PLAYER_ENTITY, .Pilgrim, {})
	testing.expect(t, found != nil && found.action == .Death)
	// Alive again after a restart: a fresh standee.
	actor.health = 22
	flipbook_observe(renderer, state, nil, actor, .Pilgrim, now+1, {1, 0, 0})
	found = flipbook_find(renderer, game.PLAYER_ENTITY, .Pilgrim, {})
	testing.expect(t, found != nil && found.action == .Idle)
	// A restart also forgets every standee at once.
	found.action = .Death
	clear_event_animations(renderer)
	testing.expect(t, flipbook_find(renderer, game.PLAYER_ENTITY, .Pilgrim, {}) == nil)
}
