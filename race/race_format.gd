class_name RaceFormat
extends RefCounted
## Text formatting for race times, shared by the HUD and (later) the results screen.

const NO_TIME_TEXT: String = "–:––.––"
## Finnish decimal separator for gaps and deltas.
const DECIMAL_SEPARATOR: String = ","
const MINUS_SIGN: String = "−"


## 72.48 -> "1:12.48"
static func lap_time(seconds: float) -> String:
	if seconds < 0.0:
		return NO_TIME_TEXT
	var hundredths: int = roundi(seconds * 100.0)
	@warning_ignore("integer_division")
	var minutes: int = hundredths / 6000
	@warning_ignore("integer_division")
	var whole_seconds: int = (hundredths % 6000) / 100
	return "%d:%02d.%02d" % [minutes, whole_seconds, hundredths % 100]


## -0.42 -> "−0,42", 1.3 -> "+1,30"
static func delta(seconds: float, decimals: int = 2) -> String:
	var sign_text: String = MINUS_SIGN if seconds < 0.0 else "+"
	var number: String = ("%.*f" % [decimals, absf(seconds)]).replace(".", DECIMAL_SEPARATOR)
	return sign_text + number
