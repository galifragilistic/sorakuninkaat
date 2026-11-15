class_name RacerState
extends RefCounted
## Race bookkeeping for one car. Owned and updated by RaceManager.

const NO_TIME: float = -1.0

var car: Car
var player_index: int = 0
var display_name: String = ""
var is_ai: bool = false
var setup: PlayerSetup
## Lap offset from the previous tick; the starting point of the next search.
var track_offset: float = 0.0

var laps_completed: int = 0
## False until the car crosses the start line for the first time after the start.
var crossed_start: bool = false
var next_checkpoint: int = 0
## Race clock value when the current lap began.
var lap_start_time: float = 0.0
var last_lap_time: float = NO_TIME
var best_lap_time: float = NO_TIME
## Lap-relative times at each checkpoint passed on the current lap.
var current_splits: Array[float] = []
## The same for the best lap; the reference for split deltas.
var best_splits: Array[float] = []

## Distance driven along the track since the start line, including full laps.
var progress: float = 0.0
## 1 = leader.
var position: int = 1
## Estimated seconds behind the leader.
var gap_to_leader: float = 0.0
var finished: bool = false
var finish_time: float = 0.0
## True when the race ended before this racer completed all laps.
var did_not_finish: bool = false


## Short label for chips and tags: "P1" for players, "AI" for computer drivers.
func get_tag() -> String:
	return "AI" if is_ai else "P%d" % (player_index + 1)


func has_best_lap() -> bool:
	return best_lap_time >= 0.0
