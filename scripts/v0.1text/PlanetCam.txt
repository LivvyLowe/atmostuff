extends Node3D

@export var camera_sensitivity = 100
@export var camera_zoom = 0.5
@export var zoom_min = 0.5
@export var zoom_max = 20
@export var zoom_in_factor = 0.9
@export var zoom_out_factor = 1.1
@export var zoom_tween_duration = 0.3
@onready var cam = $Camera3D
@onready var planet = get_node("/root/SimulationManager/Planet3D")


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	global_position = planet.global_position
	
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom_camera(zoom_in_factor)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom_camera(zoom_out_factor)

func zoom_camera(zoom_factor):
	var zoom_target = clamp(cam.position * zoom_factor, Vector3(0,0,zoom_min), Vector3(0,0,zoom_max))
	var tween = get_tree().create_tween()
	tween.tween_property(cam,"position",zoom_target,zoom_tween_duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

func _input(event: InputEvent) -> void:
	if Input.is_action_pressed("pan"):
		if event is InputEventMouseMotion:
			
			var newry = rotation.y - (event.relative.x / camera_sensitivity)
			var newrx = rotation.x - (event.relative.y / camera_sensitivity)
			rotation.y = newry
			rotation.x = newrx
			
	
