extends GutTest
## STM-02's admission rule (applied by the server from M2): members who used the code, the owner, and
## vouched friends are seated; a non-member, an unvouched non-friend without the code, and a sixth
## player are refused.

const OWNER: int = 76561198000000001
const CODER: int = 76561198000000002
const FRIEND: int = 76561198000000003
const STRANGER: int = 76561198000000004
const OUTSIDER: int = 76561198000000009


func _judge(id: int, seated: PackedInt64Array = PackedInt64Array()) -> LobbyAdmission.Verdict:
	var members: PackedInt64Array = PackedInt64Array([OWNER, CODER, FRIEND, STRANGER])
	return LobbyAdmission.judge(id, OWNER, members, {CODER: true}, {FRIEND: true}, seated, 5)


func test_the_rule() -> void:
	assert_eq(_judge(OWNER), LobbyAdmission.Verdict.SEAT, "the host")
	assert_eq(_judge(CODER), LobbyAdmission.Verdict.SEAT, "entered the code")
	assert_eq(_judge(FRIEND), LobbyAdmission.Verdict.SEAT, "a seated member vouched")
	assert_eq(_judge(STRANGER), LobbyAdmission.Verdict.NOT_INVITED, "a member who neither used the code nor was vouched")
	assert_eq(_judge(OUTSIDER), LobbyAdmission.Verdict.NOT_MEMBER, "not in the lobby")


func test_a_sixth_is_refused_but_a_seated_one_reconnects() -> void:
	var five: PackedInt64Array = PackedInt64Array([1, 2, 3, 4, OWNER])
	assert_eq(_judge(CODER, five), LobbyAdmission.Verdict.FULL, "the sixth seat")
	assert_eq(_judge(OWNER, five), LobbyAdmission.Verdict.SEAT, "already seated: no new seat")
