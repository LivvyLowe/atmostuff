extends Node3D

@onready var sim_manager = get_parent()
@onready var planet_mesh = $MeshInstance3D
@onready var planet_column_grid = $MeshInstance3D/SectorGrid

const ENGINE_METERS_PER_EARTH_RADIUS:float = 0.5
const R_IDEAL_GAS = 8.314462618 # J / (mol * K) - Universal Gas Constant
const MIN_PRESSURE_STEP_FACTOR = 1e-5 # Safety factor for integration dP step

# --- Planet Physical Properties ---
@export var mass:float = 1.0
@export var radius:float = 1.0
var surface_gravity:float = 9.81 # m/s^2 - Will be calculated

# --- Orbital / Flux Properties ---
var star_distance:float = 149597870700.0
var L_sun: float = 3.828e26
var global_flux:float = L_sun / (4.0 * PI * star_distance**2)

# --- Atmosphere Generation Parameters ---
@export var lat_bands: int = 15
@export var lon_bands: int = 15
@export var atmos_layers: int = 10 
@export var initial_surface_temp: float = 288.0 # K - Can be made spatially variable later
@export var initial_surface_pressure: float = 101325.0 # Pascals - The key "amount" parameter
@export var initial_lapse_rate: float = -0.0065 # K/m - Initial assumption for T(z) profile during setup

# Default initial composition (adjust as needed)
@export var initial_composition: Dictionary = { "N2": 0.75, "O2": 0.21, "Ar": 0.009, "CO2": 0.0004, "H2O": 0.03 }


# --- Simulation State ---
var columns: Array = [] # 2D array [lat][lon] of Column objects


func _ready() -> void:
	# Calculate initial surface gravity based on mass and radius
	set_planet_size(mass, radius) # This calculates gravity and calls regen_planet



func _process(delta: float) -> void:
	pass


func simulate(dt):
	if sim_manager == null:
		printerr("Planet3D: sim_manager not ready!")
		return
	if sim_manager.day_length <= 0:
		printerr("Planet3D: Invalid day_length!")
		return

	var dr = 360.0 / sim_manager.day_length * dt
	do_rotation(dr)

	if columns.is_empty():
		printerr("Planet3D: Columns not generated!")
		return

	# Parallelize column simulation if beneficial (requires Godot 4 threads/tasks)
	# For simplicity, running sequentially now:
	for lat_array in columns:
		if lat_array is Array:
			for col in lat_array:
				if col is Column:
					col.simulate_column(dt)
				# else: print warning?


# WARNING: THIS RESETS THE PLANET ATMOSPHERE
func set_planet_size(m, r):
	if r <= 0:
		printerr("Planet3D: Invalid radius provided.")
		r = 1.0 # Prevent division by zero

	mass = m
	radius = r
	surface_gravity = get_gravity(mass, r) # Calculate actual gravity

	# Update visual mesh size
	var mesh_radius_engine_units = radius * ENGINE_METERS_PER_EARTH_RADIUS
	if planet_mesh.mesh is SphereMesh:
		planet_mesh.mesh.radius = mesh_radius_engine_units
		planet_mesh.mesh.height = mesh_radius_engine_units * 2.0
	elif planet_mesh.mesh is CapsuleMesh: # Or whatever mesh type you use
		planet_mesh.mesh.radius = mesh_radius_engine_units
		planet_mesh.mesh.height = mesh_radius_engine_units * 2.0
	else:
		printerr("Planet3D: Mesh type not handled for resizing.")


	# Regenerate everything dependent on size/gravity
	regen_planet()

# Regenerates the grid visualization AND the atmospheric columns
func regen_planet():
	# 1. Update the visual grid geometry
	if planet_column_grid == null:
		printerr("Planet3D: planet_column_grid node not ready!")
		return
	planet_column_grid.setup_columns_grid(radius, lat_bands, lon_bands)

	# 2. Generate the physical atmosphere columns based on current parameters
	generate_grid(lat_bands, lon_bands, atmos_layers)


func get_gravity(m_earth_masses, r_earth_radii):
	# G * M_earth / R_earth^2
	var G = 6.67430e-11 # m^3 kg^-1 s^-2
	var M_earth = 5.972e24 # kg
	var R_earth = 6.371e6  # m
	if r_earth_radii <= 0: return 0.0
	return (G * (m_earth_masses * M_earth)) / pow(r_earth_radii * R_earth, 2)

func do_rotation(degrees):
	# Use rotate_y for axial tilt = 0, or apply full rotation for obliquity
	# Assuming simple Y rotation for now. Need to implement obliquity correctly if needed.
	rotation_degrees.y += degrees
	# rotation_degrees.y += degrees # This can lead to gimbal lock / imprecision over time
	# global_rotate(Vector3.UP, deg_to_rad(degrees)) # More robust

# --- Core Atmosphere Generation Logic ---
func generate_grid(lat_count, lon_count, layer_count):
	if surface_gravity <= 0:
		printerr("Planet3D: Cannot generate grid with zero or negative gravity (%f)" % surface_gravity)
		return
	if initial_surface_pressure <= 0:
		printerr("Planet3D: Cannot generate grid with zero or negative surface pressure (%f)" % initial_surface_pressure)
		return
	if layer_count <= 0:
		printerr("Planet3D: Cannot generate grid with zero or negative layers (%d)" % layer_count)
		return

	lat_bands = lat_count
	lon_bands = lon_count
	atmos_layers = layer_count

	columns.clear()
	columns.resize(lat_bands)

	# --- Pre-calculate constants for this generation ---
	var effective_molar_mass = _calculate_effective_molar_mass(initial_composition)
	if effective_molar_mass <= 1e-9:
		printerr("Planet3D: Effective molar mass is near zero, cannot generate atmosphere.")
		return

	# --- Determine Pressure Interfaces (Equal pressure drop per layer) ---
	var P_surf = initial_surface_pressure
	var delta_P_layer = P_surf / float(atmos_layers)
	var pressure_interfaces: Array[float] = []
	pressure_interfaces.resize(atmos_layers + 1)
	for i in range(atmos_layers + 1):
		pressure_interfaces[i] = P_surf - i * delta_P_layer
		pressure_interfaces[i] = max(pressure_interfaces[i], 1e-3) # Prevent zero/negative pressure


	# --- Integrate Hydrostatic Equilibrium to find Altitude Interfaces ---
	var altitude_interfaces: Array[float] = []
	altitude_interfaces.resize(atmos_layers + 1)
	altitude_interfaces[0] = 0.0 # Surface altitude is 0

	var current_z = 0.0
	var current_P = P_surf
	var integration_steps_per_layer = 100 # More steps = more accuracy, more time

	for i in range(atmos_layers): # Integrate up to find the top altitude of layer i
		var P_bottom = pressure_interfaces[i]
		var P_top = pressure_interfaces[i+1]
		var layer_delta_P = P_bottom - P_top # Should be positive

		# Use a small, fixed negative pressure step for integration
		var dp_step = -layer_delta_P / float(integration_steps_per_layer)
		# Safety check for extremely small delta_P
		if abs(dp_step) < P_bottom * MIN_PRESSURE_STEP_FACTOR:
			if layer_delta_P > 1e-6 : # Avoid division by zero if delta_P is truly tiny
				dp_step = - (P_bottom * MIN_PRESSURE_STEP_FACTOR)
			else:
				# Cannot integrate further if pressure isn't changing
				altitude_interfaces[i+1] = current_z # Layer has zero thickness
				printerr("Planet3D: Near-zero pressure drop in layer %d, setting zero thickness." % i)
				continue # Skip integration for this effectively non-existent layer


		var layer_dz_total = 0.0
		var P_integration = P_bottom # Start integration from the bottom pressure

		# Integrate using Euler method from P_bottom down to P_top
		while P_integration > P_top:
			# Ensure we don't overshoot P_top in the last step
			var actual_dp = max(dp_step, P_top - P_integration) # actual_dp is negative or zero
			if abs(actual_dp) < 1e-9: break # Avoid infinite loop if stuck

			# Calculate T at current altitude z (using initial assumption)
			var T_at_z = initial_surface_temp + initial_lapse_rate * current_z
			T_at_z = max(T_at_z, 1.0) # Clamp temperature

			# Calculate density using Ideal Gas Law at the midpoint pressure of the step
			var P_mid_step = P_integration + actual_dp / 2.0
			var rho = (P_mid_step * effective_molar_mass) / (R_IDEAL_GAS * T_at_z)
			rho = max(rho, 1e-9) # Prevent division by zero

			# Calculate altitude change for this pressure step
			var dz_step = -(actual_dp) / (rho * surface_gravity) # dz = -dP / (rho * g)
			dz_step = max(dz_step, 0.0) # Ensure altitude increases or stays same

			layer_dz_total += dz_step
			current_z += dz_step # Update total altitude
			P_integration += actual_dp # Move pressure down for next step


		altitude_interfaces[i+1] = current_z # Store altitude of the top interface

	# --- Create Column and Layer Instances ---
	for lat in range(lat_bands):
		var lon_array: Array = []
		lon_array.resize(lon_bands)
		columns[lat] = lon_array

		for lon in range(lon_bands):
			var col = Column.new()
			col.lat_index = lat
			col.lon_index = lon
			col.planet = self
			col.sim = sim_manager
			col.linked_area = get_column_grid_area3D(lat, lon)
			col.linked_mesh = get_column_grid_mesh(lat, lon)

			if not is_instance_valid(col.linked_area) or not is_instance_valid(col.linked_mesh):
				printerr("Planet3D: Failed to link mesh/area for column %d, %d" % [lat, lon])
				# Handle error: maybe skip this column or use defaults?
				lon_array[lon] = null # Mark as invalid
				continue

			# Get pre-calculated center normal for this grid cell
			if lat < planet_column_grid.column_center_matrix.size() and \
			   lon < planet_column_grid.column_center_matrix[lat].size():
				col.center_normal = planet_column_grid.column_center_matrix[lat][lon]
			else:
				printerr("Planet3D: Column center normal not found for %d, %d" % [lat, lon])
				col.center_normal = Vector3.UP # Fallback


			# Create atmosphere layers for this column using the calculated structure
			if atmos_layers > 0:
				col.layers.resize(atmos_layers)
				for v in range(atmos_layers):
					var layer = AtmosLayer.new()

					var alt_min = altitude_interfaces[v]
					var alt_max = altitude_interfaces[v+1]
					var alt_range = Vector2(alt_min, alt_max)

					# Initial layer state based on integration results & assumptions
					var layer_center_alt = (alt_min + alt_max) / 2.0
					var initial_layer_temp = initial_surface_temp + initial_lapse_rate * layer_center_alt
					initial_layer_temp = max(initial_layer_temp, 1.0) # Clamp

					var initial_layer_press = (pressure_interfaces[v] + pressure_interfaces[v+1]) / 2.0
					initial_layer_press = max(initial_layer_press, 1e-3) # Clamp

					layer.initialize_layer(initial_composition, initial_layer_temp, initial_layer_press, alt_range)
					layer.column = col
					layer.sim = sim_manager

					# Link layers
					if v > 0:
						var prev_layer = col.layers[v-1]
						if prev_layer is AtmosLayer: # Check instance validity
							layer.below_layer = prev_layer
							prev_layer.above_layer = layer

					col.layers[v] = layer

			lon_array[lon] = col


# --- Helper Functions ---

func get_column_grid_area3D(lat, lon):
	if planet_column_grid and \
	   lat >= 0 and lat < planet_column_grid.column_instances.size() and \
	   lon >= 0 and lon < planet_column_grid.column_instances[lat].size():
		var area = planet_column_grid.column_instances[lat][lon]
		if is_instance_valid(area):
			return area
	# printerr("Planet3D: Area3D not found for column %d, %d" % [lat, lon])
	return null

func get_column_grid_mesh(lat, lon):
	var area = get_column_grid_area3D(lat, lon)
	if is_instance_valid(area) and area.get_child_count() > 0:
		# Assuming the MeshInstance3D is the first child
		var mesh_instance = area.get_child(0)
		if mesh_instance is MeshInstance3D:
			return mesh_instance
	# printerr("Planet3D: MeshInstance3D not found for column %d, %d" % [lat, lon])
	return null

func find_global_flux(distance, luminosity):
	if distance <= 0: return 0.0
	# LUMINOSITY SHOULD BE IN SOLAR LUMINOSITY UNITS (e.g., 1.0 for Sun-like)
	var actual_luminosity = luminosity * L_sun # Convert to Watts
	var flux = actual_luminosity / (4.0 * PI * distance * distance)
	return flux

# Centralized update function for surface properties
func global_surface_column_parameter_update(temp = null, albedo = null, density = null, conductivity = null, c = null, emissivity = null):
	if columns.is_empty(): return

	for lat_array in columns:
		if lat_array is Array:
			for col in lat_array:
				if col is Column:
					if temp != null: col.surface_temp = temp
					if albedo != null: col.surface_albedo = albedo
					if density != null: col.surface_density = density
					if conductivity != null: col.surface_thermal_conductivity = conductivity
					if c != null: col.surface_heat_capacity = c
					if emissivity != null: col.surface_emissivity = emissivity
					# Trigger recalculation if needed (e.g., surface heat capacity per area)
					# Currently, surface heat capacity per area is recalculated in simulate_column

# Helper to calculate effective molar mass (can be cached)
func _calculate_effective_molar_mass(comp: Dictionary) -> float:
	var total_molar_mass = 0.0
	var total_fraction = 0.0
	for gas in comp:
		if typeof(comp[gas]) in [TYPE_INT, TYPE_FLOAT] and comp[gas] >= 0:
			total_fraction += comp[gas]
		else:
			printerr("Planet3D: Invalid composition value for gas '%s'" % gas)

	if total_fraction < 1e-9:
		printerr("Planet3D: Composition sum is near zero.")
		# Return a default like N2 to prevent errors downstream
		var n2_data = GasData.get_gas_data("N2")
		return n2_data.get("molar_mass", 0.028)


	for gas in comp:
		var gas_data = GasData.get_gas_data(gas)
		if not gas_data.is_empty():
			# Use normalized mole fraction
			var mole_fraction = comp[gas] / total_fraction
			total_molar_mass += mole_fraction * gas_data.molar_mass
		# else: Warning printed by GasData

	return max(total_molar_mass, 1e-9) # Avoid zero molar mass


# --- Functions callable from UI/SimulationManager ---

# Call this when parameters affecting the fundamental structure change
func trigger_regen():
	regen_planet()

# Specific setters that trigger regeneration
func set_lat_bands(value: int):
	lat_bands = max(value, 1)
	regen_planet()

func set_lon_bands(value: int):
	lon_bands = max(value, 1)
	regen_planet()

func set_atmos_layers(value: int):
	atmos_layers = max(value, 1)
	regen_planet()

func set_initial_surface_pressure(value: float):
	initial_surface_pressure = max(value, 0.0) # Allow zero pressure (vacuum)
	regen_planet()

func set_initial_surface_temp(value: float):
	initial_surface_temp = max(value, 1.0) # Keep temperature positive
	regen_planet() # Temperature profile assumption changes structure

func set_initial_lapse_rate(value: float):
	initial_lapse_rate = value
	regen_planet() # Temperature profile assumption changes structure

func set_initial_composition(value: Dictionary):
	initial_composition = value.duplicate(true)
	regen_planet() # Composition changes molar mass, affecting structure
