extends Node
## Global user settings. Persistence and the settings menu arrive in a later phase.

signal changed

enum Quality { LOW, MEDIUM, HIGH }

var quality: Quality = Quality.HIGH:
	set(value):
		quality = value
		changed.emit()

var damage_enabled: bool = true:
	set(value):
		damage_enabled = value
		changed.emit()
