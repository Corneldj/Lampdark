class_name SimStateWriter
extends RefCounted
## Little-endian, typed serialisation for run state (NET-01's state hash; NET-09's snapshots).

var _buffer: StreamPeerBuffer = StreamPeerBuffer.new()


func put_i64(value: int) -> void:
	_buffer.put_64(value)


func put_i32(value: int) -> void:
	_buffer.put_32(value)


func put_f64(value: float) -> void:
	_buffer.put_double(value)


func put_bool(value: bool) -> void:
	_buffer.put_8(1 if value else 0)


func put_string(value: String) -> void:
	_buffer.put_utf8_string(value)


func bytes() -> PackedByteArray:
	return _buffer.data_array


func sha256_hex() -> String:
	var context: HashingContext = HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(_buffer.data_array)
	return context.finish().hex_encode()
