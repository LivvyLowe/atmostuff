extends Node3D



var sim_time = 0.0
var sim_time_step = 17280 #seconds
var sim_is_paused = true

const ENGINE_METERS_PER_AU:float = 10.0
const METERS_PER_AU:float = 149597870700.0
const SECONDS_IN_DAY:float = 86400.0
const SECONDS_IN_YEAR:float = 31557600.0
var day_length:float = SECONDS_IN_DAY
var orbital_obliquity:float = 0.0
var orbit_semimajor_axis:float = 10.0
var orbit_eccentricity:float = 0.0
var orbit_solstice_longitude:float = 0.0
var orbit_period:float = SECONDS_IN_YEAR
var orbit_periapsis_argument:float = 0.0
var orbit_inclination:float = 0.0

const MIN_LUMINOSITY:float = 0.1
const MAX_LUMINOSITY:float = 20000.0
const MIN_STAR_MESH_SIZE:float = 0.1
const MAX_STAR_MESH_SIZE:float = 100
var star_luminosity:float = 1.0
var star_mass:float = 1.0



@export var K_mass_scaling: float = 3.5
@export var K_heat_transfer: float = 4.0

@onready var star = $Star
@onready var planet = $Planet3D
@onready var planet_mesh = $Planet3D/MeshInstance3D
@onready var gridcellmarker = $GridCellMarker

@onready var orbit_mesh = $OrbitMesh

func reset_sim():
	reset_orbit()
	sim_time = 0.0

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	var settings_menu = preload("res://SettingsMenu.tscn").instantiate()
	var column_menu = preload("res://column_viewer.tscn").instantiate()
	add_child(settings_menu)
	add_child(column_menu)
	settings_menu.set_pause_button(sim_is_paused)
	
	update_orbit_mesh(orbit_semimajor_axis, orbit_eccentricity, orbit_periapsis_argument, orbit_inclination)


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	
	if !sim_is_paused:
		var dt = sim_time_step*delta
		sim_time += dt
		planet.simulate(dt)
		update_planet_position(planet)
	

func update_planet_position(body):
	var M = 2.0*PI*fmod(sim_time, orbit_period)/orbit_period
	
	var E = solve_kepler(M, orbit_eccentricity)
	var true_anomaly = 2.0 * atan2(sqrt(1 + orbit_eccentricity) * sin(E / 2), sqrt(1 - orbit_eccentricity) * cos(E / 2))
	
	var r = orbit_semimajor_axis * (1 - orbit_eccentricity * cos(E))
	var x = r * cos(true_anomaly)
	var z = -1*r * sin(true_anomaly)
	
	var rotation_rad = deg_to_rad(orbit_periapsis_argument)
	var rotated_x = x * cos(rotation_rad) - z * sin(rotation_rad)
	var rotated_z = x * sin(rotation_rad) + z * cos(rotation_rad)
	
	#Apply inclination
	#But should we even care?
	
	var y = 0.0
	if orbit_inclination != 0.0:
		y = z*sin(deg_to_rad(orbit_inclination))
		rotated_z = z * cos(deg_to_rad(orbit_inclination))
		
	
	var vec = Vector3(rotated_x, y, rotated_z)
	body.position = vec
	body.star_distance = (vec.length()/ENGINE_METERS_PER_AU)*METERS_PER_AU
	body.global_flux = body.find_global_flux(body.star_distance, star_luminosity)

func solve_kepler(M: float, e: float, tolerance: float = 1e-6) -> float:
	var E = M #inital guess
	var delta = 1.0
	while abs(delta) > tolerance:
		delta = (E - e * sin(E) - M) / (1 - e * cos(E))
		E -= delta
	return E



func set_time_step(value):
	sim_time_step = value

func set_day_length(value):
	day_length = value*SECONDS_IN_DAY
	

func set_obliquity(value):
	orbital_obliquity = value
	planet.rotation_degrees.z = orbital_obliquity
	

func set_semimajor_axis(value):
	orbit_semimajor_axis = value*ENGINE_METERS_PER_AU
	planet.position = Vector3(0,0,-1*orbit_semimajor_axis)
	reset_orbit()

func set_eccentricity(value):
	orbit_eccentricity = value
	reset_orbit()

func set_solstice_longitude(value):
	orbit_solstice_longitude = value
	planet.rotation_degrees.y = orbit_solstice_longitude

func set_luminosity(value):
	star_luminosity = value

func set_star_mass(value):
	star_mass = value
	

func set_orbit_period(value):
	orbit_period = value*86400
	reset_orbit()





func set_pause(is_paused: bool):
	sim_is_paused = is_paused
	

func draw_orbit_mesh(a: float, e: float, steps: int = 180,
	argument_of_periapsis := 0.0, inclination := 0.0) -> Mesh:
	var mesh = ImmediateMesh.new()
	
	mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
	
	for i in range(steps + 1):
		var theta = 2.0 * PI * float(i % steps) / steps
		var r = a * (1.0 - e * e) / (1.0 + e * cos(theta))
		
		var x = r * cos(theta)
		var z = -1* r * sin(theta)
		
		var rot = deg_to_rad(argument_of_periapsis)
		var rotated_x = x * cos(rot) - z * sin(rot)
		var rotated_z = x * sin(rot) + z * cos(rot)
		
		var y = rotated_z * sin(deg_to_rad(inclination))
		rotated_z *= cos(deg_to_rad(inclination))
		
		mesh.surface_add_vertex(Vector3(rotated_x, y, rotated_z))
	
	mesh.surface_end()
	return mesh

func update_orbit_mesh(a,e,arg_peri,incl):
	var new_mesh = draw_orbit_mesh(a,e,180,arg_peri,incl)
	$OrbitMesh.mesh = new_mesh

func reset_orbit():
	update_orbit_mesh(orbit_semimajor_axis,orbit_eccentricity,orbit_periapsis_argument,orbit_inclination)
	update_planet_position(planet)

func kepler_period_from_mass(mass: float, a: float):
	#4pi/g in sim units
	var k = ((365.25)**2)/(ENGINE_METERS_PER_AU**3)
	var t = sqrt((k/mass)*(a**3))
	print(t)
	return t



func _unhandled_input(event):
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		
		var camera = $PlanetCam/Camera3D
		var from = camera.project_ray_origin(event.position)
		var to = from + camera.project_ray_normal(event.position) * 1000

		var space_state = get_world_3d().direct_space_state

		# Create the parameters object
		var params = PhysicsRayQueryParameters3D.create(from, to)
		params.collide_with_areas = true
		params.collision_mask = 1  # or whatever layer your grid cells are on

		var result = space_state.intersect_ray(params)
		
		if result:
			
			var collider = result["collider"]
			if collider and collider.has_meta("lat_index"):
				var lat = collider.get_meta("lat_index")
				var lon = collider.get_meta("lon_index")
				var column = planet.columns[lat][lon]
				
				if gridcellmarker == null:
					gridcellmarker = preload("res://grid_cell_marker.tscn").instantiate()
				else:
					gridcellmarker.get_parent().remove_child(gridcellmarker)
				
				collider.add_child(gridcellmarker)
				gridcellmarker.position = column.center_normal
				
				
				$ColumnViewer.update_selected_column(column)
