extends Node

## Thin wrapper autoload that holds the ClassRegistryService instance
## Ensures app-wide singleton behavior while keeping the service testable

const ClassRegistryService = preload("res://scripts/core/services/class_registry_service.gd")

var service: ClassRegistryService

func _ready() -> void:
	service = ClassRegistryService.new()
	service.initialize()

func get_spell_class(name: String) -> GDScript:
	return service.get_spell_class(name)

func get_entity_class(name: String) -> GDScript:
	return service.get_entity_class(name)

func get_class_by_name(name: String) -> GDScript:
	return service.get_class_by_name(name)
