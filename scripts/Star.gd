extends Node3D

@onready var planet = get_node("/root/SimulationManager/Planet3D")

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	$DirectionalLight3D.look_at(planet.position)
