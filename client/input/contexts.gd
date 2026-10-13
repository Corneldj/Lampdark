class_name InputContexts
extends RefCounted
## MNR-15: the input contexts, matching STM-06's Steam Input action sets: the mine (play), an open
## wheel (facing held, the pick on the mouse or right stick) and a close-up (UI-02's map table,
## Pocket Book and board, where left mouse is the pencil or cord). InputRouter switches between them.

enum Context { MINE = 0, WHEEL = 1, CLOSE_UP = 2 }

## The actions each context reads; a close-up reads only its own table (Gameplay §4.8).
const CLOSE_UP_ACTIONS: Array[String] = ["close_up_open", "pencil", "rubber", "label", "page_prev",
	"page_next", "hold_out", "board_pick", "plug", "hold_line", "ring_line", "close"]


static func name_of(context: Context) -> String:
	return ["mine", "wheel", "close_up"][context]
