class_name PlayerSetup
extends RefCounted
## One player's choices made in the menus: car, paint and lobby state.

enum Pattern { STRIPE, PLAIN }

var stats: CarStats
var color: Color = Color.WHITE
var pattern: Pattern = Pattern.STRIPE
## Whether this player slot takes part in the next race.
var joined: bool = false
var is_ready: bool = false
## Driven by the computer instead of a person.
var is_ai: bool = false
