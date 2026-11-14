extends Node
## Global race/session state shared between scenes.

const MAX_PLAYERS: int = 4

## Player colors P1-P4 (SPEC.md section 6).
const PLAYER_COLORS: Array[Color] = [
	Color("#ff7a1a"),
	Color("#3fd8ff"),
	Color("#b6f03c"),
	Color("#ff4fa3"),
]

var player_count: int = 1
## Laps per race; chosen in the lobby in a later phase.
var lap_count: int = 3


func get_player_color(player_index: int) -> Color:
	return PLAYER_COLORS[clampi(player_index, 0, MAX_PLAYERS - 1)]
