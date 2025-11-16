class_name DictUtils
extends RefCounted

## Utility functions for dictionary operations

## Merges two dictionaries, with override taking precedence
static func merge_dict(base: Dictionary, override: Dictionary) -> Dictionary:
	var result = base.duplicate(true)
	for key in override:
		var value = override[key]
		# Deep duplicate arrays and dictionaries to avoid reference issues
		if value is Array:
			result[key] = value.duplicate(true)
		elif value is Dictionary:
			result[key] = value.duplicate(true)
		else:
			result[key] = value
	return result
