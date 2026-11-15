class_name TrackDesign
extends RefCounted
## A track made in the track editor: control points with road heights,
## bridges, tunnels and jumps, and a theme. Saved as JSON (see CustomTracks)
## and turned into a Track node when a race or a preview needs one.

## What a control point carries. Bridges and tunnels span `spans[i]` metres
## centred on the point; a jump sits on the point.
enum Feature { NONE, BRIDGE, TUNNEL, JUMP }

const THEMES: Array[TrackTheme] = [
	preload("res://tracks/themes/gravel.tres"),
	preload("res://tracks/themes/sand.tres"),
	preload("res://tracks/themes/snow.tres"),
	preload("res://tracks/themes/ice.tres"),
	preload("res://tracks/themes/asphalt.tres"),
]
const FORMAT_VERSION: int = 1
const MIN_POINTS: int = 4
const MAX_POINTS: int = 40
## Control points stay inside +-HALF_AREA (metres).
const HALF_AREA: Vector2 = Vector2(150.0, 120.0)
const HEIGHT_RANGE: Vector2 = Vector2(-8.0, 14.0)
const HEIGHT_STEP: float = 0.5
const ROAD_WIDTH_RANGE: Vector2 = Vector2(6.0, 16.0)
const DEFAULT_ROAD_WIDTH: float = 10.0
const SPAN_RANGE: Vector2 = Vector2(20.0, 90.0)
const SPAN_STEP: float = 5.0
const DEFAULT_SPAN: float = 40.0
## Ground reaches this far past the outermost control point.
const GROUND_BORDER: float = 35.0
const MIN_GROUND_SIZE: Vector2 = Vector2(200.0, 160.0)
## Bridges and tunnels keep this far from the start line (metres).
const START_CLEARANCE: float = 6.0
## Raises the second half of the lap a little so roads crossing at the same
## height do not flicker.
const CROSSING_LIFT: float = 0.02
## Track lights: first one at this share of the lap, then every LAMP_SPACING.
const LAMP_START: float = 0.02
const LAMP_SPACING: float = 0.16
## Hay bale rows (share of the lap) on the left side.
const BALE_ROWS: Array[float] = [0.3, 0.55, 0.8]
## Bales and lights keep this share of the lap away from jumps.
const JUMP_CLEARANCE: float = 0.03
const SEED_RANGE: int = 100000

var display_name: String = ""
var theme_index: int = 0
var road_width: float = DEFAULT_ROAD_WIDTH
## x and z are the position, y is the road height.
var points: PackedVector3Array = PackedVector3Array()
var features: PackedByteArray = PackedByteArray()
var spans: PackedFloat32Array = PackedFloat32Array()
## File in CustomTracks.DIRECTORY this design was loaded from or saved to.
var file_name: String = ""


## A small oval to start editing from.
static func create_default() -> TrackDesign:
	var design: TrackDesign = TrackDesign.new()
	var start: PackedVector3Array = PackedVector3Array([
		Vector3(-70.0, 0.0, 0.0), Vector3(-50.0, 0.0, -45.0), Vector3(0.0, 0.0, -55.0),
		Vector3(50.0, 0.0, -45.0), Vector3(70.0, 0.0, 0.0), Vector3(50.0, 0.0, 45.0),
		Vector3(0.0, 0.0, 55.0), Vector3(-50.0, 0.0, 45.0),
	])
	for point: Vector3 in start:
		design.add_point(design.points.size(), point)
	return design


static func get_tangent_scale() -> float:
	return (Track as Script).get_property_default_value("tangent_scale")


static func get_sample_spacing() -> float:
	return (Track as Script).get_property_default_value("sample_spacing")


func duplicate_design() -> TrackDesign:
	return TrackDesign.from_dict(to_dict())


func get_theme() -> TrackTheme:
	return THEMES[clampi(theme_index, 0, THEMES.size() - 1)]


func add_point(index: int, point: Vector3) -> void:
	points.insert(index, clamp_point(point))
	features.insert(index, Feature.NONE)
	spans.insert(index, DEFAULT_SPAN)


func remove_point(index: int) -> void:
	points.remove_at(index)
	features.remove_at(index)
	spans.remove_at(index)


func clamp_point(point: Vector3) -> Vector3:
	return Vector3(
		clampf(point.x, -HALF_AREA.x, HALF_AREA.x),
		snappedf(clampf(point.y, HEIGHT_RANGE.x, HEIGHT_RANGE.y), HEIGHT_STEP),
		clampf(point.z, -HALF_AREA.y, HALF_AREA.y)
	)


## Makes the given point the start line; the lap order is kept.
func set_start(index: int) -> void:
	for i: int in index:
		points.append(points[0])
		features.append(features[0])
		spans.append(spans[0])
		remove_point(0)
	# The start point cannot carry a structure.
	features[0] = Feature.NONE


## Drives the lap the other way round, keeping the same start point.
func reverse() -> void:
	var count: int = points.size()
	var new_points: PackedVector3Array = PackedVector3Array([points[0]])
	var new_features: PackedByteArray = PackedByteArray([features[0]])
	var new_spans: PackedFloat32Array = PackedFloat32Array([spans[0]])
	for i: int in range(count - 1, 0, -1):
		new_points.append(points[i])
		new_features.append(features[i])
		new_spans.append(spans[i])
	points = new_points
	features = new_features
	spans = new_spans


## Empty when the design can be raced, otherwise the reason it cannot.
func get_problem() -> String:
	if points.size() < MIN_POINTS:
		return tr("Radalla pitää olla vähintään %d pistettä.") % MIN_POINTS
	return ""


func make_curve(bake_interval: float) -> Curve3D:
	return Track.make_curve(points, get_tangent_scale(), bake_interval)


## Lap offset of every control point on the given curve.
func get_point_offsets(curve: Curve3D) -> PackedFloat32Array:
	var offsets: PackedFloat32Array = PackedFloat32Array()
	for point: Vector3 in points:
		offsets.append(curve.get_closest_offset(point))
	# The first point is both the start and the end of the closed curve.
	if not offsets.is_empty():
		offsets[0] = 0.0
	return offsets


## Lap offset range of a bridge or tunnel at point index, relative to the point.
func get_structure_range(index: int, offsets: PackedFloat32Array, length: float) -> Vector2:
	var half: float = spans[index] * 0.5
	var start: float = maxf(-half, START_CLEARANCE - offsets[index])
	var end: float = minf(half, length - START_CLEARANCE - offsets[index])
	return Vector2(start, end)


func get_ground_size() -> Vector2:
	var reach: Vector2 = Vector2.ZERO
	for point: Vector3 in points:
		reach.x = maxf(reach.x, absf(point.x))
		reach.y = maxf(reach.y, absf(point.z))
	var size: Vector2 = (reach + Vector2.ONE * (GROUND_BORDER + road_width * 0.5)) * 2.0
	return Vector2(maxf(size.x, MIN_GROUND_SIZE.x), maxf(size.y, MIN_GROUND_SIZE.y))


## Builds the track node; it builds its world when it enters the tree.
func build_track() -> Track:
	var theme: TrackTheme = get_theme()
	var track: Track = Track.new()
	track.name = "CustomTrack"
	track.track_name = display_name
	track.control_points = points
	track.road_width = road_width
	track.road_surface = theme.road_surface
	track.ground_surface = theme.ground_surface
	track.terrain_noise_height = theme.terrain_noise_height
	track.second_half_extra_lift = CROSSING_LIFT
	track.ground_size = get_ground_size()
	var look_seed: int = absi(display_name.hash()) % SEED_RANGE
	track.look_seed = look_seed

	var curve: Curve3D = make_curve(track.sample_spacing * 0.25)
	var length: float = curve.get_baked_length()
	var offsets: PackedFloat32Array = get_point_offsets(curve)
	var bridges: PackedVector3Array = PackedVector3Array()
	var tunnels: PackedVector3Array = PackedVector3Array()
	# Shares of the lap covered by structures and jumps, kept clear of props.
	var busy: Array[Vector2] = []
	var jumps: PackedFloat32Array = PackedFloat32Array()
	for i: int in points.size():
		match features[i]:
			Feature.BRIDGE, Feature.TUNNEL:
				var span: Vector2 = get_structure_range(i, offsets, length)
				if span.y <= span.x:
					continue
				var entry: Vector3 = Vector3(float(i), span.x, span.y)
				if features[i] == Feature.BRIDGE:
					bridges.append(entry)
				else:
					tunnels.append(entry)
				busy.append((Vector2.ONE * offsets[i] + span) / length)
			Feature.JUMP:
				var fraction: float = offsets[i] / length
				jumps.append(fraction)
				busy.append(Vector2(fraction - JUMP_CLEARANCE, fraction + JUMP_CLEARANCE))
	track.bridges = bridges
	track.tunnels = tunnels

	var scenery: TrackScenery = TrackScenery.new()
	scenery.name = "Scenery"
	scenery.scenery_seed = look_seed
	scenery.lake_enabled = false
	scenery.tree_count = theme.tree_count
	scenery.tree_color = theme.tree_color
	scenery.tree_top_color = theme.tree_top_color
	scenery.jumps = jumps
	var lamps: PackedVector2Array = PackedVector2Array()
	var side: float = 1.0
	var lamp: float = LAMP_START
	while lamp < 1.0:
		if not _is_busy(lamp, busy):
			lamps.append(Vector2(lamp, side))
			side = -side
		lamp += LAMP_SPACING
	scenery.lamps = lamps
	var bale_rows: PackedVector2Array = PackedVector2Array()
	for row: float in BALE_ROWS:
		if not _is_busy(row, busy):
			bale_rows.append(Vector2(row, -1.0))
	scenery.bale_rows = bale_rows
	track.add_child(scenery)
	return track


## Menu entry for this design.
func make_info() -> TrackInfo:
	var theme: TrackTheme = get_theme()
	var length: float = make_curve(get_sample_spacing()).get_baked_length()
	var info: TrackInfo = TrackInfo.new()
	info.display_name = display_name
	info.description = tr("Oma rata, tehty rataeditorilla. Pituus noin %d m.") % roundi(length)
	info.surface = theme.road_surface.kind
	info.surface_label = theme.surface_label
	info.summary = tr("%s · oma rata") % theme.display_name
	info.design = self
	return info


func to_dict() -> Dictionary:
	var point_list: Array = []
	for point: Vector3 in points:
		point_list.append([point.x, point.y, point.z])
	return {
		"version": FORMAT_VERSION, "name": display_name, "theme": theme_index, "road_width": road_width,
		"points": point_list, "features": Array(features), "spans": Array(spans),
	}


## Reads a saved or received design. Returns null if it is not usable;
## out-of-range values are clamped.
static func from_dict(data: Dictionary) -> TrackDesign:
	var point_list: Variant = data.get("points")
	if not point_list is Array:
		return null
	var design: TrackDesign = TrackDesign.new()
	design.display_name = GameState.sanitize_name(str(data.get("name", "")))
	design.theme_index = clampi(int(data.get("theme", 0)), 0, THEMES.size() - 1)
	design.road_width = clampf(float(data.get("road_width", DEFAULT_ROAD_WIDTH)), ROAD_WIDTH_RANGE.x, ROAD_WIDTH_RANGE.y)
	var feature_list: Variant = data.get("features", [])
	var span_list: Variant = data.get("spans", [])
	for i: int in mini((point_list as Array).size(), MAX_POINTS):
		var raw: Variant = (point_list as Array)[i]
		if not raw is Array or (raw as Array).size() != 3:
			return null
		var values: Array = raw
		design.add_point(i, Vector3(float(values[0]), float(values[1]), float(values[2])))
		if feature_list is Array and i < (feature_list as Array).size():
			design.features[i] = clampi(int((feature_list as Array)[i]), 0, Feature.size() - 1)
		if span_list is Array and i < (span_list as Array).size():
			design.spans[i] = clampf(float((span_list as Array)[i]), SPAN_RANGE.x, SPAN_RANGE.y)
	if design.points.size() < MIN_POINTS:
		return null
	design.features[0] = Feature.NONE
	return design


func _is_busy(fraction: float, busy: Array[Vector2]) -> bool:
	for span: Vector2 in busy:
		if fraction >= span.x and fraction <= span.y:
			return true
	return false
