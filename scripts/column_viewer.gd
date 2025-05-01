extends PanelContainer

@onready var lat_label = $VBoxContainer/HBoxContainer/Label
@onready var lon_label = $VBoxContainer/HBoxContainer/Label2
@onready var layers_cont = $VBoxContainer/ScrollContainer/LayersContainer
@onready var sim_manager = get_parent()
@onready var planet = get_node("/root/SimulationManager/Planet3D")

var current_col: Column

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	
	if current_col is Column:
		$VBoxContainer/GlobalFluxLabel.text = "Global Flux: %.2f" % [planet.global_flux]
		$VBoxContainer/TempLabel.text = "Temperature: %.2f K" % [current_col.surface_temp]
		$VBoxContainer/ColumnFluxLabel.text = "Column Flux: %.2f" % [current_col.current_flux_angled()]
		for i in range(current_col.layers.size()):
			var layer : AtmosLayer = current_col.layers[i]
			var layer_label = layers_cont.get_child(i)
			layer_label.text = "Layer %d Temp: %.1f K, Thickness: %dm 
(P: %.0f Pa, Rho: %.3f)" % [i, layer.temperature, layer.layer_thickness, layer.pressure, layer.density]

func update_selected_column(col: Column):
	current_col = col
	lat_label.text = "Lat: " + str(col.lat_index)
	lon_label.text = "Lon: " + str(col.lon_index)
	for n in layers_cont.get_children():
		n.queue_free()
	for i in range(current_col.layers.size()):
		var layer : AtmosLayer = current_col.layers[i]
		var layer_label = Label.new()
		layer_label.text = "Layer %d Temp: %.1f K (P: %.0f Pa, Rho: %.3f)" % [i, layer.temperature, layer.pressure, layer.density]
		
		layers_cont.add_child(layer_label)
	
