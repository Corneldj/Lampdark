class_name HandOrders
extends RefCounted
## MOD-08 (Gameplay §13.9): the order table. Orders are the callouts and lamp signals at normal
## range (§6.6, §6.7); nothing parses speech. A callout reaches a Hand when it would keep more than
## half of it (SND-11's kept_fraction_at, the same routing and seeded loss a listener gets); a lamp
## signal when it sees its maker with identity (SND-12's watchers). Any human's order counts
## (Proposed: the ticket's open question). Anything else (a whisper the Hand does not keep, a shout
## that is no callout, chalk, a tap, another line) changes nothing.

enum Order { NONE = 0, DOUSE = 1, LIGHT_UP = 2, QUIET = 3, COUNT_OFF = 4, STOP = 5, COME = 6, OK = 7, POINT = 8 }

## Callout lines that are orders (SND-11's wheel ids).
const CALLOUTS: Dictionary = {"douse": Order.DOUSE, "light_up": Order.LIGHT_UP, "quiet": Order.QUIET, "count_off": Order.COUNT_OFF}
## The share of a callout a Hand must keep to take it as an order.
const KEPT_MIN: float = 0.5


static func of_callout(line: String) -> Order:
	return int(Variants.number(CALLOUTS.get(line, Order.NONE))) as Order


static func of_signal(kind: LampSignalKind.Kind) -> Order:
	match kind:
		LampSignalKind.Kind.STOP:
			return Order.STOP
		LampSignalKind.Kind.COME:
			return Order.COME
		LampSignalKind.Kind.OK:
			return Order.OK
		LampSignalKind.Kind.POINT:
			return Order.POINT
	return Order.NONE  # HELP is for the crew


static func name_of(order: Order) -> String:
	return str(Order.find_key(order)).to_lower()
