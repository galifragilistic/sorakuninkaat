class_name DebugTuningStore
extends RefCounted
## Keeps what the debug tuning panels change in user://debug_tuning.cfg, so
## tuning survives a restart. Each panel owns one section of key -> value.

const PATH: String = "user://debug_tuning.cfg"


static func load_section(section: String) -> Dictionary:
	var config: ConfigFile = ConfigFile.new()
	var values: Dictionary = {}
	if config.load(PATH) != OK or not config.has_section(section):
		return values
	for key: String in config.get_section_keys(section):
		values[key] = config.get_value(section, key)
	return values


## Replaces a section with the given values (an empty dictionary removes it).
static func save_section(section: String, values: Dictionary) -> void:
	var config: ConfigFile = ConfigFile.new()
	config.load(PATH)
	if config.has_section(section):
		config.erase_section(section)
	for key: String in values:
		config.set_value(section, key, values[key])
	config.save(PATH)
