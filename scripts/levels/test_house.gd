extends Node3D
## Handcrafted MVP test house, assembled in code so the project has no
## hand-authored .tscn files to get out of sync. Two rooms joined by a narrow
## doorway, an exit on the east wall, and a truck bay outside.
##
## Replace placeholder players/furniture with the real models by setting
## PLAYER_MODELS and FURNITURE_MODELS below (res:// paths to .glb files).

const WALL_HEIGHT := 1.2   # low walls keep the iso view readable until cutaways exist
const WALL_THICKNESS := 0.3

## Optional: map to your imported models, e.g. {1: "res://assets/characters/models/raccoon.glb"}
const PLAYER_MODELS := {}
## Optional: furniture key -> model path, e.g. {"sofa": "res://assets/furniture/residential/sofa.glb"}
const FURNITURE_MODELS := {}


func _ready() -> void:
	_build_environment()
	_build_house()
	var zone := _build_truck()
	add_child(IsoCamera.new())
	var items := _spawn_furniture()

	if InputSetup.assigned_count() >= InputSetup.MAX_PLAYERS:
		_start_job(zone, items)
		return
	var join := JoinScreen.new()
	join.all_joined.connect(_start_job.bind(zone, items))
	add_child(join)


func _start_job(zone: DeliveryZone, items: Array[Furniture]) -> void:
	_spawn_players()
	var tracker := ContractTracker.new()
	add_child(tracker)
	tracker.setup(zone, items)


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


func _add_static_box(center: Vector3, size: Vector3, color: Color) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.position = center

	var shape := BoxShape3D.new()
	shape.size = size
	var col := CollisionShape3D.new()
	col.shape = shape
	body.add_child(col)

	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mesh.material_override = mat
	body.add_child(mesh)
	add_child(body)


func _wall_x(x: float, z_from: float, z_to: float) -> void:
	var length := z_to - z_from
	_add_static_box(Vector3(x, WALL_HEIGHT * 0.5, (z_from + z_to) * 0.5),
		Vector3(WALL_THICKNESS, WALL_HEIGHT, length), Color(0.9, 0.88, 0.8))


func _wall_z(z: float, x_from: float, x_to: float) -> void:
	var length := x_to - x_from
	_add_static_box(Vector3((x_from + x_to) * 0.5, WALL_HEIGHT * 0.5, z),
		Vector3(length, WALL_HEIGHT, WALL_THICKNESS), Color(0.9, 0.88, 0.8))


func _build_house() -> void:
	# Ground top sits 2cm below the house floor top (y=0) to avoid z-fighting.
	_add_static_box(Vector3(5, -0.22, 0), Vector3(40, 0.4, 24), Color(0.45, 0.65, 0.4))
	_add_static_box(Vector3(0, -0.15, 0), Vector3(12, 0.3, 8), Color(0.78, 0.65, 0.5))

	# Outer walls: house spans x -6..6, z -4..4.
	_wall_z(-4.0, -6.15, 6.15)
	_wall_z(4.0, -6.15, 6.15)
	_wall_x(-6.0, -4.0, 4.0)
	# East wall has a 2.0m exit gap centred on z = 0.
	_wall_x(6.0, -4.0, -1.0)
	_wall_x(6.0, 1.0, 4.0)

	# Interior wall at x = 0 with a deliberately tight 1.4m doorway.
	_wall_x(0.0, -4.0, -0.7)
	_wall_x(0.0, 0.7, 4.0)


func _build_truck() -> DeliveryZone:
	var zone := DeliveryZone.new()
	zone.size = Vector3(4.5, 2.2, 3.0)
	zone.position = Vector3(9.5, 0.0, 0.0)
	add_child(zone)

	# Cargo bay: a flush pale floor patch plus back/side walls, open on the
	# house side. Kept at ground level so no ramp is needed for the prototype.
	_add_static_box(Vector3(9.5, -0.04, 0), Vector3(4.5, 0.08, 3.0), Color(0.6, 0.6, 0.65))
	_add_static_box(Vector3(11.85, 0.6, 0), Vector3(0.2, 1.2, 3.2), Color(0.9, 0.9, 0.95))
	_add_static_box(Vector3(9.5, 0.6, -1.6), Vector3(4.5, 1.2, 0.2), Color(0.9, 0.9, 0.95))
	_add_static_box(Vector3(9.5, 0.6, 1.6), Vector3(4.5, 1.2, 0.2), Color(0.9, 0.9, 0.95))
	return zone


# --- actors ---------------------------------------------------------------

func _spawn_players() -> void:
	var spawns := [Vector3(-3.0, 0.1, 2.5), Vector3(-2.0, 0.1, 2.5)]
	for i in 2:
		var p := Player.new()
		p.player_id = i + 1
		if PLAYER_MODELS.has(i + 1):
			p.model_scene = load(PLAYER_MODELS[i + 1])
		p.position = spawns[i]
		add_child(p)


func _spawn_furniture() -> Array[Furniture]:
	var items: Array[Furniture] = []
	items.append(_make("sofa", "Sofa", Vector3(2.0, 0.8, 0.9), 45.0, 0.15, 400.0, 2,
		FurnitureData.Handling.OVERSIZED, Vector3(-3.5, 0.5, -2.5)))
	items.append(_make("fridge", "Fridge", Vector3(0.8, 1.8, 0.8), 70.0, 0.25, 600.0, 2,
		FurnitureData.Handling.HEAVY, Vector3(-4.8, 1.0, 0.5)))
	items.append(_make("tv", "TV", Vector3(1.0, 0.7, 0.2), 12.0, 0.8, 300.0, 1,
		FurnitureData.Handling.FRAGILE, Vector3(3.0, 0.5, -2.5)))
	items.append(_make("box", "Box", Vector3(0.5, 0.5, 0.5), 8.0, 0.2, 40.0, 1,
		FurnitureData.Handling.STANDARD, Vector3(3.5, 0.4, 2.0)))
	items.append(_make("chair", "Chair", Vector3(0.5, 0.9, 0.5), 6.0, 0.3, 80.0, 1,
		FurnitureData.Handling.AWKWARD, Vector3(4.5, 0.6, 0.0)))
	return items


func _make(key: String, label: String, size: Vector3, mass: float, fragility: float,
		value: float, players: int, handling: FurnitureData.Handling, pos: Vector3) -> Furniture:
	var d := FurnitureData.new()
	d.display_name = label
	d.size = size
	d.mass = mass
	d.fragility = fragility
	d.value = value
	d.players_required = players
	d.handling = handling

	var f := Furniture.new()
	f.data = d
	if FURNITURE_MODELS.has(key):
		f.model_scene = load(FURNITURE_MODELS[key])
	f.position = pos
	add_child(f)
	return f
