class_name SimStateReader
extends RefCounted
## Reads what SimStateWriter wrote, in the same order.

var _buffer: StreamPeerBuffer = StreamPeerBuffer.new()


func _init(data: PackedByteArray) -> void:
	_buffer.data_array = data


func get_i64() -> int:
	return _buffer.get_64()


func get_i32() -> int:
	return _buffer.get_32()


func get_f64() -> float:
	return _buffer.get_double()


func get_bool() -> bool:
	return _buffer.get_8() != 0


func get_string() -> String:
	return _buffer.get_utf8_string()


func at_end() -> bool:
	return _buffer.get_position() >= _buffer.get_size()
