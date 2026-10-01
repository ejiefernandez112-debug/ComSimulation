extends Node
## The game's one clock (plan.md §3.1 rule 3).
## Every script asks TimeService.now() instead of reading the system clock,
## so the dev menu can warp time and Phase 4 can switch to server time here alone.

var _offset_seconds: float = 0.0


## Current game time as unix seconds.
func now() -> float:
	return Time.get_unix_time_from_system() + _offset_seconds


## Dev-menu only: jump the clock forward to test offline production.
func warp(seconds: float) -> void:
	_offset_seconds += maxf(seconds, 0.0)
