class_name PlayerSetup
extends RefCounted
## One player's choices made in the menus: car, paint and lobby state.

## Sent over the network as an int: only add new patterns at the end.
enum Pattern { STRIPE, PLAIN, SIDE_BAND, TWO_TONE, CHECKER }

var stats: CarStats
## Name the player chose ("" = the default "Pelaaja N"). See GameState.get_player_name().
var display_name: String = ""
var color: Color = Color.WHITE
var pattern: Pattern = Pattern.STRIPE
## Whether this player slot takes part in the next race.
var joined: bool = false
var is_ready: bool = false
## Driven by the computer instead of a person.
var is_ai: bool = false
## Network game: a computer driver finishing the race for a player who
## disconnected. The slot is freed when the host returns to the lobby.
var stand_in: bool = false
## Network game: the peer that controls this slot (0 = nobody / local play).
var peer_id: int = 0


## A pattern for a computer driver, so the field does not look all the same.
static func random_pattern() -> Pattern:
	return randi_range(0, Pattern.size() - 1) as Pattern
