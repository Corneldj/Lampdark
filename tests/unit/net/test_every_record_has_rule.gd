extends GutTest
## NET-08: every record type names its audit rule. A message the protocol defines without an entry in
## tools/stream_audit/rules.gd fails here (and a message of an unknown type fails the audit itself),
## so each ticket that adds a record type adds its rule.

const Rules = preload("res://tools/stream_audit/rules.gd")
const StreamAudit = preload("res://tools/stream_audit/stream_audit.gd")
const KNOWN: Array[String] = ["client_only", "handshake", "frame", "voice", "inventory", "feel", "ring", "ambient", "deafened",
	"debug", "knocks", "closeup", "callout", "tile", "geometry", "entity", "glow", "audio", "visual", "dust"]


func test_every_message_has_a_rule() -> void:
	for name: String in Protocol.Msg.keys():
		assert_true(Rules.MESSAGES.has(name), "Protocol.Msg.%s has an audit rule in tools/stream_audit/rules.gd" % name)
		assert_true(KNOWN.has(str(Rules.MESSAGES.get(name, ""))), "%s's rule is one the audit applies" % name)
	for name: String in Rules.MESSAGES.keys():
		assert_true(Protocol.Msg.has(name), "the registry names no message the protocol lacks (%s)" % name)


func test_every_frame_record_has_a_rule() -> void:
	for kind: String in Rules.FRAME_RECORDS.keys():
		assert_true(KNOWN.has(str(Rules.FRAME_RECORDS[kind])), "%s is judged by a known rule" % kind)
	var source: String = FileAccess.get_file_as_string("res://tools/stream_audit/stream_audit.gd")
	for rule: String in KNOWN:
		if rule == "client_only":
			continue
		assert_true(source.contains('"%s"' % rule), "the audit applies the %s rule" % rule)


func test_an_unknown_type_is_a_violation() -> void:
	assert_eq(Rules.rule_of_message(250), "", "no rule for a type the protocol does not define")
	assert_eq(Rules.rule_of_message(Protocol.Msg.FRAME), "frame")
	assert_eq(Rules.rule_of_message(Protocol.Msg.HELLO), "client_only")
