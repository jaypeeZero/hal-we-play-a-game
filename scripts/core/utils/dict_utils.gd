class_name DictUtils
extends RefCounted

## Utility functions for dictionary operations

## Merges two dictionaries, with override taking precedence
static func merge_dict(base: Dictionary, override: Dictionary) -> Dictionary:
	var result = base.duplicate(true)
	for key in override:
		result[key] = override[key]
	return result
