class_name CustomTracks
extends RefCounted
## Tracks made in the track editor, stored as JSON files in the user folder.

const DIRECTORY: String = "user://tracks"
const EXTENSION: String = "json"
## The design open in the editor, kept between visits and test drives.
const DRAFT_PATH: String = "user://track_editor_draft.json"
## Characters replaced when a track name becomes a file name.
const FILE_NAME_REPLACEMENTS: Dictionary = {"ä": "a", "ö": "o", "å": "a"}

## File name -> [modified time, TrackInfo]. Unchanged files give back the
## same TrackInfo, so menus can compare the selected track by identity.
static var _cache: Dictionary = {}


## Every saved track, sorted by name.
static func get_tracks() -> Array[TrackInfo]:
	var tracks: Array[TrackInfo] = []
	var directory: DirAccess = DirAccess.open(DIRECTORY)
	if directory == null:
		return tracks
	for file: String in directory.get_files():
		if file.get_extension() != EXTENSION:
			continue
		var info: TrackInfo = _load_info(file)
		if info != null:
			tracks.append(info)
	tracks.sort_custom(func(a: TrackInfo, b: TrackInfo) -> bool:
		return a.display_name.naturalnocasecmp_to(b.display_name) < 0)
	return tracks


## Saves the design under its file name, picking a new one from the track
## name the first time. Returns the TrackInfo of the saved track.
static func save(design: TrackDesign) -> TrackInfo:
	DirAccess.make_dir_recursive_absolute(DIRECTORY)
	if design.file_name.is_empty():
		design.file_name = _unused_file_name(design.display_name)
	if not _write_json(DIRECTORY.path_join(design.file_name), design.to_dict()):
		return null
	_cache.erase(design.file_name)
	return _load_info(design.file_name)


static func delete(file_name: String) -> void:
	DirAccess.remove_absolute(DIRECTORY.path_join(file_name))
	_cache.erase(file_name)


static func save_draft(design: TrackDesign) -> void:
	var data: Dictionary = design.to_dict()
	data["file"] = design.file_name
	_write_json(DRAFT_PATH, data)


## The design last open in the editor, or null.
static func load_draft() -> TrackDesign:
	var data: Dictionary = _read_json(DRAFT_PATH)
	var design: TrackDesign = TrackDesign.from_dict(data)
	if design != null:
		design.file_name = str(data.get("file", "")).get_file()
	return design


static func _load_info(file: String) -> TrackInfo:
	var path: String = DIRECTORY.path_join(file)
	var modified: int = FileAccess.get_modified_time(path)
	if _cache.has(file) and _cache[file][0] == modified:
		return _cache[file][1]
	var design: TrackDesign = TrackDesign.from_dict(_read_json(path))
	if design == null:
		return null
	design.file_name = file
	var info: TrackInfo = design.make_info()
	_cache[file] = [modified, info]
	return info


static func _unused_file_name(track_name: String) -> String:
	var base: String = ""
	for character: String in track_name.to_lower():
		character = FILE_NAME_REPLACEMENTS.get(character, character)
		base += character if character.is_valid_identifier() or character.is_valid_int() else "_"
	if base.is_empty():
		base = "rata"
	var file: String = "%s.%s" % [base, EXTENSION]
	var number: int = 2
	while FileAccess.file_exists(DIRECTORY.path_join(file)):
		file = "%s_%d.%s" % [base, number, EXTENSION]
		number += 1
	return file


static func _write_json(path: String, data: Dictionary) -> bool:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(data, "\t"))
	return true


static func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}
