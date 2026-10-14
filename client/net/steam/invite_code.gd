class_name InviteCode
extends RefCounted
## STM-02's invite codes (GDD §13.8): net.invite_code_length characters of Crockford base32 (0-9 and
## A-Z without I, L, O and U) from the OS's secure random source. Entry ignores case, spaces and
## dashes, and reads O as 0 and I or L as 1.

const ALPHABET: String = "0123456789ABCDEFGHJKMNPQRSTVWXYZ"
const READ_AS: Dictionary = {"O": "0", "I": "1", "L": "1"}


static func size() -> int:
	return Tuning.i(&"net.invite_code_length")


## A fresh code. `random`: test bytes (one per character); empty draws from the OS.
static func generate(random: PackedByteArray = PackedByteArray()) -> String:
	var n: int = size()
	var bytes: PackedByteArray = random if random.size() >= n else Crypto.new().generate_random_bytes(n)
	var out: String = ""
	for i: int in n:
		out += ALPHABET[bytes[i] & 31]  # 32 symbols: the low five bits are uniform
	return out


## The code someone typed, as stored; "" when it cannot be a code.
static func normalise(typed: String) -> String:
	var out: String = ""
	for c: String in typed.to_upper():
		if c == " " or c == "-":
			continue
		var read: String = str(READ_AS.get(c, c))
		if not ALPHABET.contains(read):
			return ""
		out += read
	return out if out.length() == size() else ""


## For streamer mode (GDD §14.3): the code hidden on screen.
static func masked(code: String) -> String:
	return "•".repeat(code.length())
