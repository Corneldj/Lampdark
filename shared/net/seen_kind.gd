class_name SeenKind
extends RefCounted
## NET-04: what an identified entity is, as far as a client may know (identity needs 0.30 of
## light, VIS-03). Wire values: append only. The server maps its own entity kinds onto these.

enum Kind { UNKNOWN = 0, MINER = 1, STYTHE = 2, MOTH = 3, BESS = 4, TAPPER = 5, ITEM = 6, TRAP = 7, PHONE = 8, FIXTURE = 9, COAT_HEAP = 10 }

## The size classes of anonymous fringe tokens (VIS-03's): a token never says more than this.
enum Size { NONE = 0, MINER = 1, LARGE = 2, LARGE_MOTIONLESS = 3, SMALL = 4 }
