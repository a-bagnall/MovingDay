extends Resource
class_name FurnitureData
## Per-object gameplay and physics configuration. Create one .tres per
## furniture type, or build them in code (see test_house.gd).

enum Handling { STANDARD, HEAVY, FRAGILE, AWKWARD, OVERSIZED }

@export var display_name: String = "Box"
@export var mass: float = 10.0
## Collision box size in metres. Only used for the placeholder mesh; furniture
## with a model takes its size from the model bounds.
@export var size: Vector3 = Vector3(0.6, 0.5, 0.6)
## 0 = indestructible, 1 = extremely fragile.
@export_range(0.0, 1.0) var fragility: float = 0.3
@export var value: float = 100.0
## Players required to lift (1 or 2).
@export_range(1, 2) var players_required: int = 1
@export var handling: Handling = Handling.STANDARD
## Optional custom grip points in local space. Empty = auto-generated from size.
@export var grip_points: PackedVector3Array = PackedVector3Array()
## Carry feel. Higher stiffness = snappier, higher damping = less swing.
@export var carry_stiffness: float = 55.0
@export var carry_damping: float = 11.0
## Impact speed (m/s) below which contact does no damage.
@export var damage_threshold: float = 2.0
