class_name Medallion

var id: String

func _init(medallion_id: String) -> void:
	id = medallion_id

func get_medallion_name() -> String:
	var data: MedallionData = _get_medallion_data_singleton()
	if data:
		return data.get_medallion(id).get("name", "Unknown")
	return "Unknown"

func get_medallion_cost() -> float:
	var data: MedallionData = _get_medallion_data_singleton()
	if data:
		return data.get_medallion(id).get("mana_cost", 0.0)
	return 0.0

func get_medallion_icon() -> String:
	var data: MedallionData = _get_medallion_data_singleton()
	if data:
		return data.get_medallion(id).get("icon", "?")
	return "?"

func get_casting_range() -> float:
	var data: MedallionData = _get_medallion_data_singleton()
	if data:
		return data.get_medallion(id).get("casting_range", 200.0)
	return 200.0

func get_data() -> Dictionary:
	var data: MedallionData = _get_medallion_data_singleton()
	if data:
		return data.get_medallion(id)
	return {}

func _get_medallion_data_singleton() -> MedallionData:
	# Create instance to access medallion data
	return MedallionData.new()
