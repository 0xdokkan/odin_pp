package game

MAX_REACTION_DEFINITION_EFFECTS :: 4

Reaction_Id :: enum {
	Thorns_Counter,
	Afterimage_Guard,
	Count,
}

Reaction_Reactor_Selector :: enum {
	Event_Source,
	Event_Target,
}

Reaction_Entity_Selector :: enum {
	Event_Source,
	Event_Target,
	Reactor,
}

Reaction_Source_Relation :: enum {
	Any,
	Self,
	Opponent,
}

Reaction_Value_Source :: enum {
	Fixed,
	Activation_Potency,
	Event_Amount,
}

Reaction_Effect_Template :: struct {
	kind:          Effect_Kind,
	target:        Reaction_Entity_Selector,
	amount_source: Reaction_Value_Source,
	amount:        i32,
	status:        Status_Kind,
	duration:      i32,
}

Reaction_Definition :: struct {
	id:                   Reaction_Id,
	name:                 string,
	trigger:              Game_Event_Kind,
	reactor:              Reaction_Reactor_Selector,
	source_relation:      Reaction_Source_Relation,
	minimum_event_amount: i32,
	priority:             i32,
	combat_only:          bool,
	has_status_activation: bool,
	status_activation:     Status_Kind,
	effects:              [MAX_REACTION_DEFINITION_EFFECTS]Reaction_Effect_Template,
	effect_count:         int,
}

REACTION_DEFINITIONS :: [int(Reaction_Id.Count)]Reaction_Definition{
	{
		id = .Thorns_Counter,
		name = "Thorns Counter",
		trigger = .Damaged,
		reactor = .Event_Target,
		source_relation = .Opponent,
		minimum_event_amount = 1,
		priority = 100,
		combat_only = true,
		has_status_activation = true,
		status_activation = .Thorns,
		effects = {
			{
				kind = .Damage,
				target = .Event_Source,
				amount_source = .Activation_Potency,
			},
			{},
			{},
			{},
		},
		effect_count = 1,
	},
	{
		id = .Afterimage_Guard,
		name = "Afterimage Guard",
		trigger = .Moved,
		reactor = .Event_Target,
		source_relation = .Self,
		priority = 50,
		combat_only = true,
		has_status_activation = true,
		status_activation = .Afterimage,
		effects = {
			{
				kind = .Apply_Status,
				target = .Reactor,
				amount_source = .Activation_Potency,
				status = .Shield,
				duration = 2,
			},
			{},
			{},
			{},
		},
		effect_count = 1,
	},
}

reaction_effect_template_is_valid :: proc(
	definition: ^Reaction_Definition,
	template: Reaction_Effect_Template,
) -> bool {
	if definition == nil {
		return false
	}
	switch template.kind {
	case .Move, .Gain_Energy, .Deploy_Device, .Add_Reaction_Binding, .Draw_Cards, .Discard_Cards, .Create_Card, .Enter_Shadow,
	     .Place_Ground, .Lasso, .Fish, .Pinball, .First_Person:
		return false
	case .Remove_Status:
		return true
	case .Damage, .Heal, .Gain_Gold, .Apply_Status:
		if template.kind == .Apply_Status && template.duration <= 0 && !status_kind_stacks(template.status) {
			return false
		}
		switch template.amount_source {
		case .Fixed:
			return template.amount > 0
		case .Activation_Potency:
			return true
		case .Event_Amount:
			return definition.minimum_event_amount > 0
		}
	}
	return false
}

validate_reaction_definition :: proc(definition: ^Reaction_Definition) -> bool {
	if definition == nil || len(definition.name) == 0 || definition.minimum_event_amount < 0 ||
	   definition.effect_count <= 0 || definition.effect_count > MAX_REACTION_DEFINITION_EFFECTS {
		return false
	}
	for index in 0..<definition.effect_count {
		if !reaction_effect_template_is_valid(definition, definition.effects[index]) {
			return false
		}
	}
	return true
}

validate_reaction_definitions :: proc() -> bool {
	definitions := REACTION_DEFINITIONS
	for &definition, index in definitions {
		if int(definition.id) != index || !validate_reaction_definition(&definition) {
			return false
		}
	}
	return true
}

reaction_definition_by_id :: proc(id: Reaction_Id) -> (Reaction_Definition, bool) {
	definitions := REACTION_DEFINITIONS
	index := int(id)
	if index < 0 || index >= len(definitions) {
		return {}, false
	}
	return definitions[index], true
}

reaction_reactor_for_event :: proc(
	event: Game_Event,
	selector: Reaction_Reactor_Selector,
) -> Entity_Ref {
	switch selector {
	case .Event_Source:
		return event.source
	case .Event_Target:
		return event.target
	}
	return {}
}

reaction_source_matches :: proc(
	relation: Reaction_Source_Relation,
	event: Game_Event,
	reactor: Entity_Ref,
) -> bool {
	switch relation {
	case .Any:
		return true
	case .Self:
		return event.source == reactor
	case .Opponent:
		return entities_are_opponents(event.source, reactor)
	}
	return false
}

reaction_definition_matches :: proc(
	room: ^Room,
	definition: ^Reaction_Definition,
	event: Game_Event,
) -> (reactor: Entity_Ref, matches: bool) {
	if room == nil || definition == nil || event.kind != definition.trigger ||
	   event.amount < definition.minimum_event_amount ||
	   (definition.combat_only && room.phase != .Combat) {
		return {}, false
	}
	reactor = reaction_reactor_for_event(event, definition.reactor)
	if !entity_exists(room, reactor) ||
	   !reaction_source_matches(definition.source_relation, event, reactor) {
		return {}, false
	}
	return reactor, true
}

collect_reactions :: proc(room: ^Room, event: Game_Event) -> (batch: Reaction_Batch) {
	if room == nil {
		return
	}
	definitions := REACTION_DEFINITIONS
	for &definition in definitions {
		reactor, matches := reaction_definition_matches(room, &definition, event)
		if !matches {
			continue
		}
		if definition.has_status_activation {
			_, status_found := status_for_entity(room, reactor, definition.status_activation)
			if status_found {
				add_reaction_request(&batch, {
					definition_id = definition.id,
					reactor = reactor,
					trigger = event,
					priority = definition.priority,
					activation = .Status,
				})
			}
		}
		for binding_index in 0..<room.reaction_bindings.count {
			binding := &room.reaction_bindings.items[binding_index]
			if binding.definition_id != definition.id || binding.owner != reactor ||
			   !reaction_binding_is_active(room, binding) {
				continue
			}
			add_reaction_request(&batch, {
				definition_id = definition.id,
				reactor = reactor,
				trigger = event,
				priority = reaction_binding_priority(definition.priority, binding.priority_modifier),
				activation = .Binding,
				activation_id = binding.id,
			})
		}
	}
	sort_reaction_batch(&batch)
	return
}

reaction_effect_target :: proc(
	selector: Reaction_Entity_Selector,
	request: Reaction_Request,
) -> Entity_Ref {
	switch selector {
	case .Event_Source:
		return request.trigger.source
	case .Event_Target:
		return request.trigger.target
	case .Reactor:
		return request.reactor
	}
	return {}
}

reaction_effect_amount :: proc(
	room: ^Room,
	definition: ^Reaction_Definition,
	request: Reaction_Request,
	template: Reaction_Effect_Template,
) -> (i32, bool) {
	switch template.amount_source {
	case .Fixed:
		return template.amount, template.amount > 0
	case .Activation_Potency:
		return reaction_activation_potency(room, definition, request)
	case .Event_Amount:
		return request.trigger.amount, request.trigger.amount > 0
	}
	return 0, false
}

reaction_activation_potency :: proc(
	room: ^Room,
	definition: ^Reaction_Definition,
	request: Reaction_Request,
) -> (i32, bool) {
	if room == nil || definition == nil {
		return 0, false
	}
	switch request.activation {
	case .Status:
		if !definition.has_status_activation {
			return 0, false
		}
		status, found := status_for_entity(room, request.reactor, definition.status_activation)
		if !found {
			return 0, false
		}
		return status.potency, status.potency > 0
	case .Binding:
		binding, found := reaction_binding_by_id(room, request.activation_id)
		if !found || binding.definition_id != definition.id || binding.owner != request.reactor ||
		   !reaction_binding_is_active(room, binding) {
			return 0, false
		}
		return binding.potency, true
	}
	return 0, false
}

build_reaction_effect :: proc(
	room: ^Room,
	definition: ^Reaction_Definition,
	request: Reaction_Request,
	template: Reaction_Effect_Template,
) -> (Effect, bool) {
	target := reaction_effect_target(template.target, request)
	if !entity_exists(room, target) {
		return {}, false
	}

	switch template.kind {
	case .Damage, .Heal, .Gain_Gold, .Apply_Status:
		amount, found := reaction_effect_amount(room, definition, request, template)
		if !found {
			return {}, false
		}
		switch template.kind {
		case .Damage:
			return damage_effect(target, amount), true
		case .Heal:
			return heal_effect(target, amount), true
		case .Gain_Gold:
			if target != PLAYER_ENTITY {
				return {}, false
			}
			return gain_gold_effect(amount), true
		case .Apply_Status:
			return apply_status_effect(target, template.status, amount, template.duration), true
		case .Move, .Gain_Energy, .Deploy_Device, .Remove_Status, .Add_Reaction_Binding,
		     .Draw_Cards, .Discard_Cards, .Create_Card, .Enter_Shadow, .Place_Ground, .Lasso, .Fish, .Pinball, .First_Person:
			unreachable()
		}
	case .Remove_Status:
		return remove_status_effect(target, template.status), true
	case .Move, .Gain_Energy, .Deploy_Device, .Add_Reaction_Binding, .Draw_Cards, .Discard_Cards, .Create_Card, .Enter_Shadow,
	     .Place_Ground, .Lasso, .Fish, .Pinball, .First_Person:
		return {}, false
	}
	return {}, false
}

build_reaction_action :: proc(room: ^Room, request: Reaction_Request) -> (action: Action, ok: bool) {
	definition, found := reaction_definition_by_id(request.definition_id)
	if room == nil || !found || !validate_reaction_definition(&definition) {
		return {}, false
	}
	reactor, matches := reaction_definition_matches(room, &definition, request.trigger)
	if !matches || reactor != request.reactor {
		return {}, false
	}
	_, activation_is_active := reaction_activation_potency(room, &definition, request)
	if !activation_is_active {
		return {}, false
	}

	action = make_action(.Reaction, request.reactor, {}, .None)
	for index in 0..<definition.effect_count {
		effect, built := build_reaction_effect(room, &definition, request, definition.effects[index])
		if !built || !add_effect(&action, effect) {
			return {}, false
		}
	}
	return action, true
}
