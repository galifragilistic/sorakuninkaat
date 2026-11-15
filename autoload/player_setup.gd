class_name PlayerSetup
extends RefCounted
## One player's choices made in the menus: car, paint and lobby state.

enum Pattern { STRIPE, PLAIN }

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
## Network game: the peer that controls this slot (0 = nobody / local play).
var peer_id: int = 0
