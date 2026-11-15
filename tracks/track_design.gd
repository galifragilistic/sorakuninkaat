class_name TrackDesign
extends RefCounted
## A track made in the track editor: control points with road heights,
## bridges, tunnels and jumps, and a theme. Saved as JSON (see CustomTracks)
## and turned into a Track node when a race or a preview needs one.

## What a control point carries. Bridges and tunnels span `spans[i]` metres
## centred on the point; a jump sits on the point.
enum Feature { NONE, BRIDGE, TUNNEL, JUMP }
## Objects placed by hand in the editor.
enum Prop { TREE, BALE, CONTAINER, HOUSE, ROCK, TIRES }

const PROP_NAMES: Array[String] = ["Puu", "Heinäpaali", "Kontti", "Talo", "Kivi", "Rengaspino"]
## Size of each prop in metres (width, height, depth); TrackScenery builds them
## at this size and the editor draws their footprint.
const PROP_SIZES: Array[Vector3] = [
	Vector3(3.0, 6.0, 3.0), Vector3(1.9, 1.1, 1.2), Vector3(6.1, 2.6, 2.4),
	Vector3(8.0, 5.0, 6.0), Vector3(3.2, 1.8, 3.2), Vector3(1.0, 1.05, 1.0),
]
const MAX_PROPS: int = 250
const PROP_ROTATION_STEP: float = PI / 12.0
## Amount of randomly placed trees, as a share of the theme's tree count.
const FOREST_LEVELS: Array[float] = [0.0, 0.4, 1.0, 1.6]
const FOREST_NAMES: Array[String] = ["Ei puita", "Vähän", "Normaali", "Paljon"]
const DEFAULT_FOREST: int = 2

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
## Map sizes: control points and objects stay inside +-size (metres).
const AREA_SIZES: Array[Vector2] = [
	Vector2(110.0, 85.0), Vector2(150.0, 120.0), Vector2(200.0, 160.0), Vector2(260.0, 210.0),
]
const AREA_NAMES: Array[String] = ["Pieni", "Normaali", "Suuri", "Valtava"]
const DEFAULT_AREA: int = 1
## Surfaces a stretch of road can have. In `surfaces`, 0 means the theme's
## road surface and n means ROAD_SURFACES[n - 1].
const ROAD_SURFACES: Array[SurfaceData] = [
	preload("res://tracks/surfaces/asphalt.tres"),
	preload("res://tracks/surfaces/gravel.tres"),
	preload("res://tracks/surfaces/sand.tres"),
	preload("res://tracks/surfaces/snow.tres"),
	preload("res://tracks/surfaces/ice.tres"),
]
## A road this much higher than a road it crosses gets a bridge automatically.
const BRIDGE_CLEARANCE: float = 3.5
## Crossings with a height difference between this and BRIDGE_CLEARANCE are
## too low to drive under and too high to drive across.
const LOW_CROSSING: float = 1.0
const CROSSING_SAMPLE_SPACING: float = 3.0
## Roads cross where their centre lines come closer than this share of the road width.
const CROSSING_DISTANCE_SHARE: float = 0.9
## Samples closer than this many road widths along the lap are the same stretch.
const CROSSING_NEIGHBOUR_WIDTHS: float = 3.0
## Automatic bridges reach this far past the crossed road's edge (metres).
const AUTO_BRIDGE_MARGIN: float = 15.0
const HEIGHT_RANGE: Vector2 = Vector2(-8.0, 14.0)
const HEIGHT_STEP: float = 0.5
const ROAD_WIDTH_RANGE: Vector2 = Vector2(6.0, 16.0)
const DEFAULT_ROAD_WIDTH: float = 10.0
const SPAN_RANGE: Vector2 = Vector2(20.0, 90.0)
const SPAN_STEP: float = 5.0
const DEFAULT_SPAN: float = 40.0
## Ground reaches this far past the edge of the map area.
const GROUND_BORDER: float = 35.0
## Bridges and tunnels keep this far from the start line (metres).
const START_CLEARANCE: float = 6.0
## Raises the second half of the lap a little so roads crossing at the same
## height do not flicker.
const CROSSING_LIFT: float = 0.02
## Track lights: first one at this share of the lap, then every LAMP_SPACING.
const LAMP_START: float = 0.02
const LAMP_SPACING: float = 0.16
## Lights keep this share of the lap away from jumps.
const JUMP_CLEARANCE: float = 0.03
const SEED_RANGE: int = 100000

var display_name: String = ""
var theme_index: int = 0
var road_width: float = DEFAULT_ROAD_WIDTH
## x and z are the position, y is the road height.
var points: PackedVector3Array = PackedVector3Array()
var features: PackedByteArray = PackedByteArray()
var spans: PackedFloat32Array = PackedFloat32Array()
## Surface of the road from each point to the next (see ROAD_SURFACES).
var surfaces: PackedByteArray = PackedByteArray()
## Index into AREA_SIZES.
var area: int = DEFAULT_AREA
## Placed objects: (Prop, x, z, yaw in radians).
var props: PackedVector4Array = PackedVector4Array()
## Index into FOREST_LEVELS.
var forest: int = DEFAULT_FOREST
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


func get_half_area() -> Vector2:
	return AREA_SIZES[clampi(area, 0, AREA_SIZES.size() - 1)]


## True if every point and object fits inside the given map size.
func fits_area(area_index: int) -> bool:
	var half: Vector2 = AREA_SIZES[area_index]
	for point: Vector3 in points:
		if absf(point.x) > half.x or absf(point.z) > half.y:
			return false
	for prop: Vector4 in props:
		if absf(prop.y) > half.x or absf(prop.z) > half.y:
			return false
	return true


## Surface of the road from point index to the next point.
func get_surface(index: int) -> SurfaceData:
	var choice: int = surfaces[index]
	return get_theme().road_surface if choice == 0 else ROAD_SURFACES[choice - 1]


## A new point keeps the surface of the stretch it was added to.
func add_point(index: int, point: Vector3) -> void:
	var surface: int = surfaces[index - 1] if index > 0 and index <= surfaces.size() else 0
	points.insert(index, clamp_point(point))
	features.insert(index, Feature.NONE)
	spans.insert(index, DEFAULT_SPAN)
	surfaces.insert(index, surface)


func remove_point(index: int) -> void:
	points.remove_at(index)
	features.remove_at(index)
	spans.remove_at(index)
	surfaces.remove_at(index)


## Adds a prop and returns its index, or -1 when there are too many.
func add_prop(kind: Prop, x: float, z: float, yaw: float) -> int:
	if props.size() >= MAX_PROPS:
		return -1
	props.append(clamp_prop(Vector4(kind, x, z, yaw)))
	return props.size() - 1


func clamp_prop(prop: Vector4) -> Vector4:
	return Vector4(
		clampi(roundi(prop.x), 0, Prop.size() - 1),
		clampf(prop.y, -get_half_area().x, get_half_area().x),
		clampf(prop.z, -get_half_area().y, get_half_area().y),
		fposmod(prop.w, TAU)
	)


func clamp_point(point: Vector3) -> Vector3:
	return Vector3(
		clampf(point.x, -get_half_area().x, get_half_area().x),
		snappedf(clampf(point.y, HEIGHT_RANGE.x, HEIGHT_RANGE.y), HEIGHT_STEP),
		clampf(point.z, -get_half_area().y, get_half_area().y)
	)


## Makes the given point the start line; the lap order is kept.
func set_start(index: int) -> void:
	for i: int in index:
		points.append(points[0])
		features.append(features[0])
		spans.append(spans[0])
		surfaces.append(surfaces[0])
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
	# Stretch k now runs the old stretch count - 1 - k backwards.
	var new_surfaces: PackedByteArray = PackedByteArray()
	for k: int in count:
		new_surfaces.append(surfaces[count - 1 - k])
	surfaces = new_surfaces


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
	return (get_half_area() + Vector2.ONE * GROUND_BORDER) * 2.0


## Where the road crosses itself. "bridges" holds lap offset ranges (x..y)
## where the road passes high enough over another stretch to get a bridge;
## "low" holds the positions of crossings too low to drive under.
func find_crossings(curve: Curve3D) -> Dictionary:
	var length: float = curve.get_baked_length()
	var count: int = maxi(1, ceili(length / CROSSING_SAMPLE_SPACING))
	var step: float = length / float(count)
	var samples: PackedVector3Array = PackedVector3Array()
	# Samples bucketed by map cell so each one is only compared with its neighbours.
	var cell_size: float = road_width
	var cells: Dictionary = {}
	for i: int in count:
		var sample: Vector3 = curve.sample_baked(float(i) * step)
		samples.append(sample)
		var cell: Vector2i = Vector2i(floori(sample.x / cell_size), floori(sample.z / cell_size))
		# Packed arrays are values: append to the stored copy and put it back.
		var bucket: PackedInt32Array = cells.get(cell, PackedInt32Array())
		bucket.append(i)
		cells[cell] = bucket

	var limit: float = road_width * CROSSING_DISTANCE_SHARE
	var neighbour_gap: float = road_width * CROSSING_NEIGHBOUR_WIDTHS
	var over: PackedFloat32Array = PackedFloat32Array()
	var low: PackedVector3Array = PackedVector3Array()
	for i: int in count:
		var sample: Vector3 = samples[i]
		var cell: Vector2i = Vector2i(floori(sample.x / cell_size), floori(sample.z / cell_size))
		var is_over: bool = false
		var is_low: bool = false
		for dx: int in range(-1, 2):
			for dz: int in range(-1, 2):
				for j: int in cells.get(cell + Vector2i(dx, dz), PackedInt32Array()):
					var gap: float = absf(float(i - j)) * step
					if minf(gap, length - gap) < neighbour_gap:
						continue
					var other: Vector3 = samples[j]
					if Vector2(sample.x - other.x, sample.z - other.z).length() >= limit:
						continue
					var rise: float = sample.y - other.y
					if rise >= BRIDGE_CLEARANCE:
						is_over = true
					elif rise > LOW_CROSSING:
						is_low = true
		if is_over:
			over.append(float(i) * step)
		elif is_low:
			low.append(sample)

	var ranges: Array[Vector2] = []
	var reach: float = road_width * 0.5 + AUTO_BRIDGE_MARGIN
	for offset: float in over:
		var span: Vector2 = Vector2(offset - reach, offset + reach)
		if not ranges.is_empty() and span.x <= ranges[-1].y:
			ranges[-1].y = span.y
		else:
			ranges.append(span)
	return {"bridges": ranges, "low": low}


## Every bridge on the track as lap offset ranges: the ones marked on points
## and the automatic ones over crossings, merged and kept off the start line.
func get_bridge_ranges(curve: Curve3D, offsets: PackedFloat32Array) -> Array[Vector2]:
	var length: float = curve.get_baked_length()
	var ranges: Array[Vector2] = []
	for i: int in points.size():
		if features[i] == Feature.BRIDGE:
			ranges.append(get_structure_range(i, offsets, length) + Vector2.ONE * offsets[i])
	ranges.append_array(find_crossings(curve)["bridges"])
	ranges.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.x < b.x)
	var merged: Array[Vector2] = []
	for span: Vector2 in ranges:
		var clamped: Vector2 = Vector2(maxf(span.x, START_CLEARANCE), minf(span.y, length - START_CLEARANCE))
		if clamped.y <= clamped.x:
			continue
		if not merged.is_empty() and clamped.x <= merged[-1].y:
			merged[-1].y = maxf(merged[-1].y, clamped.y)
		else:
			merged.append(clamped)
	return merged


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
	# Track bridge entries are (point index, start, end) relative to that point.
	for span: Vector2 in get_bridge_ranges(curve, offsets):
		var base: int = 0
		for i: int in points.size():
			if offsets[i] <= span.x:
				base = i
		bridges.append(Vector3(float(base), span.x - offsets[base], span.y - offsets[base]))
		busy.append(span / length)
	for i: int in points.size():
		match features[i]:
			Feature.TUNNEL:
				var span: Vector2 = get_structure_range(i, offsets, length)
				if span.y <= span.x:
					continue
				tunnels.append(Vector3(float(i), span.x, span.y))
				busy.append((Vector2.ONE * offsets[i] + span) / length)
			Feature.JUMP:
				var fraction: float = offsets[i] / length
				jumps.append(fraction)
				busy.append(Vector2(fraction - JUMP_CLEARANCE, fraction + JUMP_CLEARANCE))
	track.bridges = bridges
	track.tunnels = tunnels
	# One road section per run of stretches with the same surface.
	var sections: Array[SurfaceData] = []
	var starts: PackedFloat32Array = PackedFloat32Array()
	for i: int in points.size():
		var surface: SurfaceData = get_surface(i)
		if sections.is_empty() or sections[-1] != surface:
			sections.append(surface)
			starts.append(offsets[i] / length)
	track.road_sections = sections
	track.road_section_starts = starts
	track.road_surface = sections[0]

	var scenery: TrackScenery = TrackScenery.new()
	scenery.name = "Scenery"
	scenery.scenery_seed = look_seed
	scenery.lake_enabled = false
	# The theme's tree count is for the normal map size; bigger maps get more.
	var default_ground: Vector2 = (AREA_SIZES[DEFAULT_AREA] + Vector2.ONE * GROUND_BORDER) * 2.0
	var ground: Vector2 = get_ground_size()
	var area_scale: float = (ground.x * ground.y) / (default_ground.x * default_ground.y)
	var forest_share: float = FOREST_LEVELS[clampi(forest, 0, FOREST_LEVELS.size() - 1)]
	scenery.tree_count = roundi(float(theme.tree_count) * forest_share * area_scale)
	scenery.props = props
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
	# Hay bales are placed by hand in the editor.
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
	var prop_list: Array = []
	for prop: Vector4 in props:
		prop_list.append([roundi(prop.x), prop.y, prop.z, prop.w])
	return {
		"version": FORMAT_VERSION, "name": display_name, "theme": theme_index, "road_width": road_width,
		"points": point_list, "features": Array(features), "spans": Array(spans),
		"props": prop_list, "forest": forest, "surfaces": Array(surfaces), "area": area,
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
	# The map size first: points and objects are clamped to it.
	design.area = clampi(int(data.get("area", DEFAULT_AREA)), 0, AREA_SIZES.size() - 1)
	var feature_list: Variant = data.get("features", [])
	var span_list: Variant = data.get("spans", [])
	var surface_list: Variant = data.get("surfaces", [])
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
		if surface_list is Array and i < (surface_list as Array).size():
			design.surfaces[i] = clampi(int((surface_list as Array)[i]), 0, ROAD_SURFACES.size())
	if design.points.size() < MIN_POINTS:
		return null
	design.features[0] = Feature.NONE
	design.forest = clampi(int(data.get("forest", DEFAULT_FOREST)), 0, FOREST_LEVELS.size() - 1)
	var prop_list: Variant = data.get("props", [])
	if prop_list is Array:
		for raw: Variant in prop_list:
			if raw is Array and (raw as Array).size() == 4:
				var values: Array = raw
				var kind: int = clampi(int(values[0]), 0, Prop.size() - 1)
				design.add_prop(kind as Prop, float(values[1]), float(values[2]), float(values[3]))
	return design


func _is_busy(fraction: float, busy: Array[Vector2]) -> bool:
	for span: Vector2 in busy:
		if fraction >= span.x and fraction <= span.y:
			return true
	return false
