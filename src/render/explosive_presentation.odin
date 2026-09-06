package render

import game "../game"

show_spawned_presentation_object :: proc(presentation: ^Room_Presentation, event: game.Game_Event) -> bool {
	if presentation == nil || !presentation.valid || event.target.kind != .Object || event.target.id == 0 ||
	   presentation.object_count < 0 || presentation.object_count > len(presentation.objects) {
		return false
	}
	definition, valid := game.grid_object_definition(event.object_kind)
	if !valid {
		return false
	}
	if _, exists := presentation_grid_object_in_view(presentation, event.target); exists {
		return false
	}
	slot := presentation.object_count
	for object, index in presentation.objects[:presentation.object_count] {
		if !object.visible {
			slot = index
			break
		}
	}
	if slot == len(presentation.objects) {
		return false
	}
	if slot == presentation.object_count {
		presentation.object_count += 1
	}
	presentation.objects[slot] = {
		entity = event.target, kind = event.object_kind,
		position = presentation_position(event.to_position),
		health = definition.max_health, max_health = definition.max_health,
		opacity = 1, visible = true,
	}
	return true
}
