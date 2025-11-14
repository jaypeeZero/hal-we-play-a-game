class_name CommandChainSystem
extends RefCounted

## Pure functional command chain system
## Handles order passing down hierarchy and information flow up
## Following functional programming principles - all data is immutable

# ============================================================================
# MAIN API - Process command chain communications
# ============================================================================

## Process all command chain communications
static func process_command_chain(crew_list: Array) -> Array:
	# First pass: distribute orders down the chain
	var with_orders = distribute_orders_down_chain(crew_list)

	# Second pass: share information up the chain
	var with_info = share_information_up_chain(with_orders)

	return with_info

# ============================================================================
# ORDER DISTRIBUTION (DOWN THE CHAIN)
# ============================================================================

## Distribute orders from superiors to subordinates
static func distribute_orders_down_chain(crew_list: Array) -> Array:
	var crew_map = create_crew_map(crew_list)
	var updated_crew = {}

	# Initialize with original crew
	for crew in crew_list:
		updated_crew[crew.crew_id] = crew

	# Process each crew member's issued orders
	for crew in crew_list:
		if crew.orders.issued.is_empty():
			continue

		# Distribute orders to subordinates
		for order in crew.orders.issued:
			var subordinate_id = order.get("to")
			if subordinate_id and updated_crew.has(subordinate_id):
				var subordinate = updated_crew[subordinate_id]
				var updated_subordinate = deliver_order(subordinate, order)
				updated_crew[subordinate_id] = updated_subordinate

		# Clear issued orders after distribution
		var updated_superior = crew.duplicate(true)
		updated_superior.orders.issued = []
		updated_crew[crew.crew_id] = updated_superior

	return updated_crew.values()

## Deliver order to subordinate
static func deliver_order(subordinate: Dictionary, order: Dictionary) -> Dictionary:
	var updated = subordinate.duplicate(true)

	# Store received order (overwrites previous order)
	var cleaned_order = order.duplicate()
	cleaned_order.erase("to")  # Remove routing info
	updated.orders.received = cleaned_order

	return updated

## Process a single order for one crew member (EVENT-DRIVEN)
static func process_single_order(crew: Dictionary, order: Dictionary) -> Dictionary:
	# Simply deliver the order to this crew member
	return deliver_order(crew, order)

# ============================================================================
# INFORMATION SHARING (UP THE CHAIN)
# ============================================================================

## Share information from subordinates to superiors
static func share_information_up_chain(crew_list: Array) -> Array:
	var crew_map = create_crew_map(crew_list)
	var updated_crew = {}

	# Initialize with original crew
	for crew in crew_list:
		updated_crew[crew.crew_id] = crew

	# Process each crew member
	for crew in crew_list:
		if crew.command_chain.superior == null:
			continue  # No one to report to

		var superior_id = crew.command_chain.superior
		if not updated_crew.has(superior_id):
			continue

		# Share awareness with superior
		var superior = updated_crew[superior_id]
		var updated_superior = merge_subordinate_awareness(superior, crew)
		updated_crew[superior_id] = updated_superior

	return updated_crew.values()

## Merge subordinate's awareness into superior's awareness
static func merge_subordinate_awareness(superior: Dictionary, subordinate: Dictionary) -> Dictionary:
	var updated = superior.duplicate(true)

	# Combine threat lists
	var combined_threats = combine_entity_lists(
		superior.awareness.threats,
		subordinate.awareness.threats,
		"_threat_priority"
	)
	updated.awareness.threats = limit_list_size(combined_threats, get_awareness_limit(superior.role))

	# Combine opportunity lists
	var combined_opportunities = combine_entity_lists(
		superior.awareness.opportunities,
		subordinate.awareness.opportunities,
		"_opportunity_score"
	)
	updated.awareness.opportunities = limit_list_size(combined_opportunities, get_awareness_limit(superior.role))

	# Combine known entities (but don't let it grow unbounded)
	var combined_entities = combine_known_entities(
		superior.awareness.known_entities,
		subordinate.awareness.known_entities
	)
	updated.awareness.known_entities = limit_list_size(combined_entities, get_awareness_limit(superior.role) * 2)

	return updated

## Combine two entity lists, keeping higher priority items
static func combine_entity_lists(list1: Array, list2: Array, priority_key: String) -> Array:
	var combined = {}

	# Add all from list1
	for entity in list1:
		combined[entity.id] = entity

	# Merge from list2 (keep higher priority)
	for entity in list2:
		if not combined.has(entity.id):
			combined[entity.id] = entity
		elif entity.get(priority_key, 0.0) > combined[entity.id].get(priority_key, 0.0):
			combined[entity.id] = entity

	# Convert back to array and sort by priority
	var result = combined.values()
	result.sort_custom(func(a, b): return a.get(priority_key, 0.0) > b.get(priority_key, 0.0))
	return result

## Combine known entities lists
static func combine_known_entities(list1: Array, list2: Array) -> Array:
	var combined = {}

	# Add all from both lists (most recent info wins)
	for entity in list1:
		combined[entity.id] = entity

	for entity in list2:
		combined[entity.id] = entity  # Overwrites if exists

	return combined.values()

## Limit list size based on role
static func limit_list_size(list: Array, max_size: int) -> Array:
	if list.size() <= max_size:
		return list
	return list.slice(0, max_size)

## Get awareness limit based on role (higher ranks track more)
static func get_awareness_limit(role: int) -> int:
	match role:
		CrewData.Role.PILOT: return 5
		CrewData.Role.GUNNER: return 5
		CrewData.Role.CAPTAIN: return 10
		CrewData.Role.SQUADRON_LEADER: return 20
		CrewData.Role.FLEET_COMMANDER: return 50
		_: return 5

# ============================================================================
# ORDER VALIDATION AND FILTERING
# ============================================================================

## Validate that order is appropriate for recipient's role
static func validate_order(order: Dictionary, recipient_role: int) -> bool:
	var order_type = order.get("type", "")

	match recipient_role:
		CrewData.Role.PILOT:
			return order_type in ["engage", "withdraw", "maneuver"]
		CrewData.Role.GUNNER:
			return order_type in ["engage", "cease_fire"]
		CrewData.Role.CAPTAIN:
			return order_type in ["engage", "withdraw", "patrol", "defend"]
		CrewData.Role.SQUADRON_LEADER:
			return order_type in ["engage", "withdraw", "regroup", "formation"]
		CrewData.Role.FLEET_COMMANDER:
			return true  # Can receive any strategic order
		_:
			return false

## Filter orders to only those appropriate for recipient
static func filter_valid_orders(orders: Array, recipient_role: int) -> Array:
	return orders.filter(func(order): return validate_order(order, recipient_role))

# ============================================================================
# COMMAND CHAIN QUERIES
# ============================================================================

## Find superior of a crew member
static func find_superior(crew_data: Dictionary, crew_list: Array) -> Dictionary:
	if crew_data.command_chain.superior == null:
		return {}

	for crew in crew_list:
		if crew.crew_id == crew_data.command_chain.superior:
			return crew

	return {}

## Find all subordinates of a crew member
static func find_subordinates(crew_data: Dictionary, crew_list: Array) -> Array:
	var subordinates = []

	for sub_id in crew_data.command_chain.subordinates:
		for crew in crew_list:
			if crew.crew_id == sub_id:
				subordinates.append(crew)
				break

	return subordinates

## Find all crew in chain of command (up to root)
static func get_chain_to_root(crew_data: Dictionary, crew_list: Array) -> Array:
	var chain = [crew_data]
	var current = crew_data

	while current.command_chain.superior != null:
		var superior = find_superior(current, crew_list)
		if superior.is_empty():
			break
		chain.append(superior)
		current = superior

	return chain

## Find the top commander in crew list
static func find_top_commander(crew_list: Array) -> Dictionary:
	for crew in crew_list:
		if crew.command_chain.superior == null:
			# This crew has no superior, they're at the top
			if crew.role in [CrewData.Role.FLEET_COMMANDER, CrewData.Role.SQUADRON_LEADER, CrewData.Role.CAPTAIN]:
				return crew

	return {}

## Get all crew assigned to a specific entity
static func get_crew_for_entity(entity_id: String, crew_list: Array) -> Array:
	return crew_list.filter(func(crew): return crew.assigned_to == entity_id)

## Get crew member by role assigned to entity
static func get_crew_by_role_for_entity(entity_id: String, role: int, crew_list: Array) -> Dictionary:
	for crew in crew_list:
		if crew.assigned_to == entity_id and crew.role == role:
			return crew

	return {}

# ============================================================================
# UTILITY FUNCTIONS
# ============================================================================

## Create map of crew_id -> crew_data for fast lookups
static func create_crew_map(crew_list: Array) -> Dictionary:
	var crew_map = {}
	for crew in crew_list:
		crew_map[crew.crew_id] = crew
	return crew_map

## Check if crew member has any subordinates
static func has_subordinates(crew_data: Dictionary) -> bool:
	return not crew_data.command_chain.subordinates.is_empty()

## Check if crew member has a superior
static func has_superior(crew_data: Dictionary) -> bool:
	return crew_data.command_chain.superior != null

## Count crew in hierarchy under this crew member
static func count_subordinates_recursive(crew_data: Dictionary, crew_list: Array) -> int:
	var count = 0
	var subordinates = find_subordinates(crew_data, crew_list)

	count += subordinates.size()
	for sub in subordinates:
		count += count_subordinates_recursive(sub, crew_list)

	return count
