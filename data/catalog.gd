class_name Catalog
extends RefCounted
## Lists of the content shown in the menus (SPEC.md section 7).

const CARS: Array[CarStats] = [
	preload("res://cars/data/kuplakone.tres"),
	preload("res://cars/data/pikku_turbo.tres"),
	preload("res://cars/data/sora_gt.tres"),
	preload("res://cars/data/hirvi_4x4.tres"),
	preload("res://cars/data/lumikko.tres"),
	preload("res://cars/data/vanha_valtias.tres"),
]
## Index into CARS of the car every player starts with.
const DEFAULT_CAR_INDEX: int = 2
const LOCKED_CAR_COUNT: int = 6

const TRACKS: Array[TrackInfo] = [
	preload("res://tracks/data/soramonttu.tres"),
	preload("res://tracks/data/hiekkasarkka.tres"),
	preload("res://tracks/data/jainen_jarvi.tres"),
	preload("res://tracks/data/metsapolku.tres"),
	preload("res://tracks/data/satamakaarre.tres"),
	preload("res://tracks/data/tunturi.tres"),
]

## Paint colours offered in the car select screen (mockups/03_Autovalinta.png).
const CAR_COLORS: Array[Color] = [
	Color("#ff7a1a"), Color("#3fd8ff"), Color("#b6f03c"), Color("#ff4fa3"),
	Color("#f2f4fa"), Color("#ffc832"), Color("#7b5cff"), Color("#262b3d"),
]

const LAP_OPTIONS: Array[int] = [1, 2, 3, 5, 8, 10]
## Championship points for places 1-4.
const POINTS: Array[int] = [10, 8, 6, 5]


static func get_default_car() -> CarStats:
	return CARS[DEFAULT_CAR_INDEX]


static func get_default_track() -> TrackInfo:
	for track: TrackInfo in TRACKS:
		if track.is_available():
			return track
	return null


static func get_points(place: int) -> int:
	return POINTS[place - 1] if place >= 1 and place <= POINTS.size() else 0
