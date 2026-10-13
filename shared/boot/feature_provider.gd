class_name FeatureProvider
extends RefCounted
## Answers feature-tag queries. Boot reads tags through this so tests can inject any role
## or flavour. The default asks the engine.


func has(tag: String) -> bool:
	return OS.has_feature(tag)


## A fixed set of tags, for tests and tools.
class Fixed:
	extends FeatureProvider

	var _tags: PackedStringArray

	func _init(tags: PackedStringArray) -> void:
		_tags = tags

	func has(tag: String) -> bool:
		return tag in _tags
