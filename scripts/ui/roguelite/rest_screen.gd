class_name RestScreen
extends CrewManagementScreen

## R&R crew screen: reassign crew (drag-and-drop board with ice/activate),
## view stats by clicking callsigns or hull headers. No buying, no hiring,
## no dismissal — those stay Shop-only.
## Lifecycle: overlay — caller frees after closed signal.


func _init() -> void:
	title_text = "REST & REPAIR"
	leave_text = "Leave"
