extends Node3D
## Handcrafted MVP test house, assembled in code so the project has no
## hand-authored .tscn files to get out of sync. Two rooms joined by a narrow
## doorway, an exit on the east wall, a loft over the west room, a basement
## under the east room, and a truck bay outside.
##
## Replace placeholder players/furniture with the real models by setting
## PLAYER_MODELS and FURNITURE_MODELS below (res:// paths to .glb files).

const WALL_HEIGHT := 1.2   # low walls keep the iso view readable until cutaways exist
const WALL_THICKNESS := 0.3

## Optional: map to your imported models, e.g. {1: "res://assets/characters/models/raccoon.glb"}
const PLAYER_MODELS := {}
## Furniture key -> model path.
const FURNITURE_MODELS := {
	"sofa": "res://assets/furniture/residential/couch.gltf",
	"fridge": "res://assets/furniture/restaurant/fridge_B.gltf",
	"box": "res://assets/furniture/restaurant/crate.gltf",
	"chair": "res://assets/furniture/residential/chair_A.gltf",
	"lamp": "res://assets/furniture/residential/lamp_standing.gltf",
	"cabinet": "res://assets/furniture/residential/cabinet_medium.gltf",
}
## KayKit models are oversized relative to the 1.3m player capsule.
const FURNITURE_MODEL_SCALE := 0.6

## World x of the truck ramp's foot, just outside the east exit.
const TRUCK_FOOT_X := 7.0

## Seconds after the job loads before furniture can take damage (spawn settling is free).
const SETTLE_TIME := 1.5

## Spawn point per player id (index = id - 1).
const PLAYER_SPAWNS := [
	Vector3(-3.0, 0.1, 2.5), Vector3(-2.0, 0.1, 2.5),
	Vector3(-4.0, 0.1, 2.5), Vector3(-5.0, 0.1, 2.5),
]

## Floor-to-floor height, floor slab thickness, and the clear height under the loft.
const FLOOR_HEIGHT := 2.4
const SLAB := 0.3
const UNDER_LOFT := FLOOR_HEIGHT - SLAB
## Stairs are visual steps over a solid sloped wedge: the character controller
## and the carrying physics cannot climb real steps.
const STAIR_STEPS := 12
const STAIR_WIDTH := 1.45
const MAX_STAIR_ANGLE := 40.0
## Clear floor kept in line with each stair end, and the headroom above the stairs.
const STAIR_LANDING := 1.0
const STAIR_CLEAR_HEIGHT := 2.0
## Added around keep-clear areas so an item's own size is covered.
const FURNITURE_CLEARANCE := 0.6

const FLOOR_COLOR := Color(0.78, 0.65, 0.5)
const LOFT_COLOR := Color(0.7, 0.6, 0.5)
const BASEMENT_COLOR := Color(0.55, 0.55, 0.6)
const STAIR_COLOR := Color(0.6, 0.5, 0.4)

## Stair approaches that furniture must not be placed in.
var _keep_clear: Array[AABB] = []
## Numbers furniture in spawn order, so every machine agrees what "item 3" is.
var _next_net_id := 0


func _ready() -> void:
	assert(SaveManager.run != null, "Job started with no active run; start from the main menu")
	_build_environment()
	_build_house()
	var zone := _build_truck()
	add_child(IsoCamera.new())
	add_child(DebugOverlay.new())
	var items := _spawn_furniture()

	for player_id in InputSetup.local_player_ids():
		_spawn_player(player_id, true)
	for player_id in NetworkManager.remote_player_ids():
		_spawn_player(player_id, false)
	SaveManager.begin_day()
	_start_job(zone, items)   # trims `items` to the job's furniture before it first waits
	if NetworkManager.is_online():
		var sync := JobSync.new()
		sync.name = "JobSync"
		add_child(sync)
		sync.setup(items, zone)


func _start_job(zone: DeliveryZone, items: Array[Furniture]) -> void:
	zone.active = true
	var tracker := ContractTracker.new()
	add_child(tracker)
	tracker.setup(zone, items)
	# Items drop onto the floor when spawned; let them settle before impacts cost money.
	await get_tree().create_timer(SETTLE_TIME).timeout
	for item in items:
		item.damage_enabled = true


# --- world ----------------------------------------------------------------

func _build_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.55, 0.75, 0.9)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.85, 0.85, 0.95)
	env.ambient_light_energy = 0.7
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, 30, 0)
	sun.shadow_enabled = true
	add_child(sun)


func _add_static_box(center: Vector3, size: Vector3, color: Color, cutaway: CutawayReveal = null) -> void:
	var material: Material
	if cutaway:
		material = cutaway.material
	else:
		var standard := StandardMaterial3D.new()
		standard.albedo_color = color
		material = standard
	_add_box(Transform3D(Basis.IDENTITY, center), size, material, true)


## A null material makes the box collision-only.
func _add_box(xform: Transform3D, size: Vector3, material: Material, collide: bool) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.transform = xform
	if collide:
		var shape := BoxShape3D.new()
		shape.size = size
		var col := CollisionShape3D.new()
		col.shape = shape
		body.add_child(col)
	if material:
		var mesh := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = size
		mesh.mesh = box
		mesh.material_override = material
		if material is ShaderMaterial:
			mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		body.add_child(mesh)
	add_child(body)


func _wall_x(x: float, z_from: float, z_to: float, y0 := 0.0, height := WALL_HEIGHT) -> void:
	var length := z_to - z_from
	_add_static_box(Vector3(x, y0 + height * 0.5, (z_from + z_to) * 0.5),
		Vector3(WALL_THICKNESS, height, length), Color(0.9, 0.88, 0.8))


func _wall_z(z: float, x_from: float, x_to: float, y0 := 0.0, height := WALL_HEIGHT) -> void:
	var length := x_to - x_from
	_add_static_box(Vector3((x_from + x_to) * 0.5, y0 + height * 0.5, z),
		Vector3(length, height, WALL_THICKNESS), Color(0.9, 0.88, 0.8))


## `from` is the bottom and `to` the top of the stair's centre line, both on the
## floors they join. Collision is a solid wedge, so there is nothing to walk under
## or snag on; STAIR_LANDING of floor beyond each end is registered as keep-clear.
func _add_stairs(from: Vector3, to: Vector3) -> void:
	var run := Vector3(to.x - from.x, 0.0, to.z - from.z)
	var direction := run.normalized()
	var angle := rad_to_deg(atan2(to.y - from.y, run.length()))
	assert(angle <= MAX_STAIR_ANGLE, "Stairs too steep to walk (%.0f degrees)" % angle)

	var step_run := run.length() / STAIR_STEPS
	var step_rise := (to.y - from.y) / STAIR_STEPS
	var yaw := Basis(Vector3.UP, atan2(-direction.z, direction.x))
	var tread := StandardMaterial3D.new()
	tread.albedo_color = STAIR_COLOR
	for k in STAIR_STEPS:
		var height := (k + 0.5) * step_rise
		var center := from + direction * (step_run * (k + 0.5))
		center.y = from.y + height * 0.5
		_add_box(Transform3D(yaw, center), Vector3(step_run, height, STAIR_WIDTH), tread, false)

	var half_width := Vector3(-direction.z, 0.0, direction.x) * (STAIR_WIDTH * 0.5)
	var base := Vector3(to.x, from.y, to.z)
	var shape := ConvexPolygonShape3D.new()
	shape.points = PackedVector3Array([
		from - half_width, from + half_width, to - half_width,
		to + half_width, base - half_width, base + half_width])
	var col := CollisionShape3D.new()
	col.shape = shape
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.add_child(col)
	add_child(body)

	var low := from - direction * STAIR_LANDING
	var high := to + direction * STAIR_LANDING
	var clear := AABB(low - half_width, Vector3.ZERO)
	clear = clear.expand(low + half_width).expand(high - half_width).expand(high + half_width)
	clear = clear.expand(Vector3(low.x, from.y - 0.1, low.z))
	clear = clear.expand(Vector3(low.x, to.y + STAIR_CLEAR_HEIGHT, low.z))
	_keep_clear.append(clear.grow(FURNITURE_CLEARANCE))


## The lawn is split around the basement pit (x 0..6, z -4..4).
func _build_lawn() -> void:
	var color := Color(0.45, 0.65, 0.4)
	_add_static_box(Vector3(-7.5, -0.22, 0.0), Vector3(15.0, 0.4, 24.0), color)
	_add_static_box(Vector3(15.5, -0.22, 0.0), Vector3(19.0, 0.4, 24.0), color)
	_add_static_box(Vector3(3.0, -0.22, -8.0), Vector3(6.0, 0.4, 8.0), color)
	_add_static_box(Vector3(3.0, -0.22, 8.0), Vector3(6.0, 0.4, 8.0), color)


## Pit under the east room, entered by stairs down along the north wall.
func _build_basement() -> void:
	var pit_floor := -FLOOR_HEIGHT
	_add_static_box(Vector3(3.0, pit_floor - SLAB * 0.5, 0.0), Vector3(6.0, SLAB, 8.0), BASEMENT_COLOR)
	var lining := Color(0.5, 0.5, 0.55)
	_add_static_box(Vector3(0.05, pit_floor * 0.5, 0.0), Vector3(0.1, FLOOR_HEIGHT, 8.0), lining)
	_add_static_box(Vector3(5.95, pit_floor * 0.5, 0.0), Vector3(0.1, FLOOR_HEIGHT, 8.0), lining)
	_add_static_box(Vector3(3.0, pit_floor * 0.5, -3.95), Vector3(6.0, FLOOR_HEIGHT, 0.1), lining)
	_add_static_box(Vector3(3.0, pit_floor * 0.5, 3.95), Vector3(6.0, FLOOR_HEIGHT, 0.1), lining)

	# Ground floor over the pit, with a stair hole at x 1..5, z -4..-2.4.
	var region := AABB(Vector3(0.0, pit_floor - 0.2, -4.0), Vector3(6.0, FLOOR_HEIGHT - 0.1, 8.0))
	var cutaway := CutawayReveal.create(self, region, FLOOR_COLOR)
	add_child(cutaway)
	_add_static_box(Vector3(3.0, -0.15, 0.8), Vector3(6.0, SLAB, 6.4), FLOOR_COLOR, cutaway)
	_add_static_box(Vector3(0.5, -0.15, -3.2), Vector3(1.0, SLAB, 1.6), FLOOR_COLOR, cutaway)
	_add_static_box(Vector3(5.5, -0.15, -3.2), Vector3(1.0, SLAB, 1.6), FLOOR_COLOR, cutaway)
	_add_stairs(Vector3(1.0, pit_floor, -3.125), Vector3(5.0, 0.0, -3.125))
	# Rail along the open side of the stair hole, stopping short of the top so the
	# stairs can be entered from the room.
	_wall_z(-2.25, 1.0, 4.0)


## Loft over the north end of the west room, reached by stairs up the west wall.
func _build_loft() -> void:
	var region := AABB(Vector3(-6.0, -0.2, -4.0), Vector3(6.0, FLOOR_HEIGHT, 2.4))
	var cutaway := CutawayReveal.create(self, region, LOFT_COLOR)
	add_child(cutaway)
	_add_static_box(Vector3(-3.0, FLOOR_HEIGHT - SLAB * 0.5, -2.875), Vector3(6.3, SLAB, 2.55), LOFT_COLOR, cutaway)
	_add_stairs(Vector3(-5.125, 0.0, 2.4), Vector3(-5.125, FLOOR_HEIGHT, -1.6))
	# Rails; the opening at the stair top (x -6..-4.4) is left clear.
	_wall_z(-4.0, -6.15, 0.15, FLOOR_HEIGHT)
	_wall_x(-6.0, -4.0, -1.6, FLOOR_HEIGHT)
	_wall_x(0.0, -4.0, -1.6, FLOOR_HEIGHT)
	_wall_z(-1.75, -4.4, 0.0, FLOOR_HEIGHT)


func _build_house() -> void:
	_build_lawn()
	# Ground top sits 2cm below the house floor top (y=0) to avoid z-fighting.
	_add_static_box(Vector3(-3.0, -0.15, 0.0), Vector3(6.0, SLAB, 8.0), FLOOR_COLOR)
	_build_basement()
	_build_loft()

	# Outer walls: house spans x -6..6, z -4..4. Walls under the loft run up to its slab.
	_wall_z(-4.0, -6.15, 0.15, 0.0, UNDER_LOFT)
	_wall_z(-4.0, 0.15, 6.15)
	_wall_z(4.0, -6.15, 6.15)
	_wall_x(-6.0, -4.0, -1.6, 0.0, UNDER_LOFT)
	_wall_x(-6.0, -1.6, 4.0)
	# East wall has a 2.0m exit gap centred on z = 0.
	_wall_x(6.0, -4.0, -1.0)
	_wall_x(6.0, 1.0, 4.0)

	# Interior wall at x = 0 with a deliberately tight 1.4m doorway.
	_wall_x(0.0, -4.0, -1.6, 0.0, UNDER_LOFT)
	_wall_x(0.0, -1.6, -0.7)
	_wall_x(0.0, 0.7, 4.0)


func _build_truck() -> DeliveryZone:
	var truck := MovingTruck.new()
	truck.position = Vector3(TRUCK_FOOT_X, 0.0, 0.0)
	add_child(truck)
	return truck.zone


# --- actors ---------------------------------------------------------------

func _spawn_player(player_id: int, local: bool) -> void:
	var p := Player.new()
	p.player_id = player_id
	p.is_local = local
	if PLAYER_MODELS.has(player_id):
		p.model_scene = load(PLAYER_MODELS[player_id])
	p.position = PLAYER_SPAWNS[player_id - 1]
	add_child(p)


func _spawn_furniture() -> Array[Furniture]:
	var items: Array[Furniture] = []
	items.append(_make("sofa", "Sofa", Vector3(2.0, 0.8, 0.9), 45.0, 0.15, 400.0, 2,
		FurnitureData.Handling.OVERSIZED, Vector3(-3.0, 0.5, 0.9)))
	items.append(_make("fridge", "Fridge", Vector3(0.8, 1.8, 0.8), 70.0, 0.25, 600.0, 2,
		FurnitureData.Handling.HEAVY, Vector3(-0.9, 1.0, 1.9)))
	items.append(_make("tv", "TV", Vector3(1.0, 0.7, 0.2), 12.0, 0.8, 300.0, 1,
		FurnitureData.Handling.FRAGILE, Vector3(3.0, 0.5, -1.2)))
	items.append(_make("box", "Box", Vector3(0.5, 0.5, 0.5), 8.0, 0.2, 40.0, 1,
		FurnitureData.Handling.STANDARD, Vector3(3.5, 0.4, 2.0)))
	items.append(_make("chair", "Chair", Vector3(0.5, 0.9, 0.5), 6.0, 0.3, 80.0, 1,
		FurnitureData.Handling.AWKWARD, Vector3(4.5, 0.6, 0.0)))
	# Upstairs and downstairs, to practise carrying along the stairs.
	items.append(_make("lamp", "Lamp", Vector3(0.6, 1.5, 0.6), 5.0, 0.6, 150.0, 1,
		FurnitureData.Handling.FRAGILE, Vector3(-3.0, FLOOR_HEIGHT + 0.9, -2.0)))
	items.append(_make("cabinet", "Cabinet", Vector3(1.2, 0.6, 0.6), 30.0, 0.2, 250.0, 1,
		FurnitureData.Handling.STANDARD, Vector3(3.0, -FLOOR_HEIGHT + 0.5, 0.5)))
	return items


func _make(key: String, label: String, size: Vector3, mass: float, fragility: float,
		value: float, players: int, handling: FurnitureData.Handling, pos: Vector3) -> Furniture:
	var d := FurnitureData.new()
	for area in _keep_clear:
		assert(not area.has_point(pos), "%s is placed in a stair approach" % label)
	d.display_name = label
	d.size = size
	d.mass = mass
	d.fragility = fragility
	d.value = value
	d.players_required = players
	d.handling = handling

	var f := Furniture.new()
	f.data = d
	f.damage_enabled = false
	f.net_id = _next_net_id
	_next_net_id += 1
	f.is_puppet = NetworkManager.mode == NetworkManager.Mode.CLIENT   # the host simulates
	if FURNITURE_MODELS.has(key):
		f.model_scene = load(FURNITURE_MODELS[key])
		f.model_scale = FURNITURE_MODEL_SCALE
	f.position = pos
	add_child(f)
	return f
