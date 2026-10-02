class_name NetCodec
extends RefCounted
## Binary codec interpreted from shared/protocol.json (mirror of
## server/src/net/codec.ts; the golden vectors in shared/tests/golden.json keep
## them identical). Little-endian: u8 message id, then fields in order.
## decode() returns {name, msg} or {error} on a malformed frame.

const TWO_PI := TAU

var _by_name := {"C2S": {}, "S2C": {}}
var _by_id := {"C2S": {}, "S2C": {}}
var _structs := {}
var _pos_scale := 64.0
var _err := ""


func _init(protocol: Dictionary) -> void:
	_pos_scale = float(protocol.quantization.posScale)
	for tname in protocol.types:
		if protocol.types[tname] is Array:
			_structs[tname] = protocol.types[tname]
	for dir in ["C2S", "S2C"]:
		for mname in protocol.messages[dir]:
			var m: Dictionary = protocol.messages[dir][mname]
			var spec := {"name": mname, "id": int(m.id), "fields": m.fields}
			_by_name[dir][mname] = spec
			_by_id[dir][int(m.id)] = spec


func encode(dir: String, msg_name: String, msg: Dictionary) -> PackedByteArray:
	var spec: Dictionary = _by_name[dir].get(msg_name, {})
	assert(not spec.is_empty(), "unknown message " + msg_name)
	var b := StreamPeerBuffer.new()
	b.put_u8(spec.id)
	_write_fields(b, spec.fields, msg)
	return b.data_array


func decode(dir: String, data: PackedByteArray) -> Dictionary:
	_err = ""
	var b := StreamPeerBuffer.new()
	b.data_array = data
	if not _need(b, 1):
		return {"error": _err}
	var id := b.get_u8()
	var spec: Dictionary = _by_id[dir].get(id, {})
	if spec.is_empty():
		return {"error": "unknown message id %d" % id}
	var msg := _read_fields(b, spec.fields)
	if _err == "" and b.get_available_bytes() != 0:
		_err = "%d trailing bytes" % b.get_available_bytes()
	if _err != "":
		return {"error": "%s: %s" % [spec.name, _err]}
	return {"name": spec.name, "msg": msg}


func _write_fields(b: StreamPeerBuffer, fields: Array, msg: Dictionary) -> void:
	for f in fields:
		_write_value(b, str(f[1]), msg[f[0]])


func _read_fields(b: StreamPeerBuffer, fields: Array) -> Dictionary:
	var out := {}
	for f in fields:
		out[f[0]] = _read_value(b, str(f[1]))
		if _err != "":
			break
	return out


func _write_value(b: StreamPeerBuffer, type: String, v: Variant) -> void:
	if type.begins_with("array"):
		var inner := type.get_slice(":", 1)
		var arr: Array = v
		if type.begins_with("array8:"):
			b.put_u8(arr.size())
		else:
			b.put_u16(arr.size())
		for item in arr:
			_write_value(b, inner, item)
		return
	if _structs.has(type):
		_write_fields(b, _structs[type], v)
		return
	match type:
		"u8": b.put_u8(int(v))
		"u16": b.put_u16(int(v))
		"u32": b.put_u32(int(v))
		"i8": b.put_8(int(v))
		"i16": b.put_16(int(v))
		"f32": b.put_float(float(v))
		"bool": b.put_u8(1 if v else 0)
		"varuint":
			var n := int(v)
			while true:
				var byte := n & 0x7f
				n = n >> 7
				if n > 0:
					byte |= 0x80
				b.put_u8(byte)
				if n == 0:
					break
		"str8", "str16":
			var bytes := str(v).to_utf8_buffer()
			if type == "str8":
				b.put_u8(bytes.size())
			else:
				b.put_u16(bytes.size())
			b.put_data(bytes)
		"bytes16":
			var raw: PackedByteArray = v if v is PackedByteArray else PackedByteArray(v)
			b.put_u16(raw.size())
			b.put_data(raw)
		"pos": b.put_16(clampi(roundi(float(v) * _pos_scale), -32768, 32767))
		"angle":
			var turns := float(v) / TWO_PI - floorf(float(v) / TWO_PI)
			b.put_u16(roundi(turns * 65536.0) & 0xffff)
		"pitch": b.put_16(clampi(roundi(float(v) / (PI / 2.0) * 32767.0), -32767, 32767))
		_: push_error("NetCodec: unknown type " + type)


func _read_value(b: StreamPeerBuffer, type: String) -> Variant:
	if type.begins_with("array"):
		var inner := type.get_slice(":", 1)
		var is8 := type.begins_with("array8:")
		if not _need(b, 1 if is8 else 2):
			return []
		var n := b.get_u8() if is8 else b.get_u16()
		var out := []
		for i in n:
			out.append(_read_value(b, inner))
			if _err != "":
				break
		return out
	if _structs.has(type):
		return _read_fields(b, _structs[type])
	match type:
		"u8", "i8", "bool":
			if not _need(b, 1):
				return 0
			if type == "u8":
				return b.get_u8()
			if type == "i8":
				return b.get_8()
			return b.get_u8() != 0
		"u16", "i16", "pos", "angle", "pitch":
			if not _need(b, 2):
				return 0
			match type:
				"u16": return b.get_u16()
				"i16": return b.get_16()
				"pos": return b.get_16() / _pos_scale
				"angle": return b.get_u16() / 65536.0 * TWO_PI
				_: return b.get_16() / 32767.0 * (PI / 2.0)
		"u32", "f32":
			if not _need(b, 4):
				return 0
			return b.get_u32() if type == "u32" else b.get_float()
		"varuint":
			var v := 0
			for i in 5:
				if not _need(b, 1):
					return 0
				var byte := b.get_u8()
				v |= (byte & 0x7f) << (7 * i)
				if byte & 0x80 == 0:
					return v
			_err = "varuint too long"
			return 0
		"str8", "str16":
			if not _need(b, 1 if type == "str8" else 2):
				return ""
			var n := b.get_u8() if type == "str8" else b.get_u16()
			if not _need(b, n):
				return ""
			var res: Array = b.get_data(n)
			return (res[1] as PackedByteArray).get_string_from_utf8()
		"bytes16":
			if not _need(b, 2):
				return PackedByteArray()
			var n := b.get_u16()
			if not _need(b, n):
				return PackedByteArray()
			var res: Array = b.get_data(n)
			return res[1] as PackedByteArray
	_err = "unknown type " + type
	return null


func _need(b: StreamPeerBuffer, n: int) -> bool:
	if b.get_available_bytes() < n:
		_err = "frame too short"
		return false
	return true
