class_name ExitCode
## Process exit codes shared by every role (FND-03). STM-04 and STM-09 rely on them.

const OK: int = 0
const BAD_ARGUMENTS: int = 2
const VERSION_MISMATCH: int = 3
const STEAM_INIT_FAILED: int = 4
const BIND_FAILED: int = 5
const DRAINED: int = 10
## A bot lost its connection before its script ended (FND-09's soaks count it as a failure).
const UNSCRIPTED_DISCONNECT: int = 11
const FATAL: int = 70
