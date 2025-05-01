extends PanelContainer

@onready var sim_manager = get_node("/root/SimulationManager")
@onready var planet = get_node("/root/SimulationManager/Planet3D")


# --- References to UI Elements---
# Time/Pause
@onready var time_step_spinbox = $"ScrollContainer/VBoxContainer/TimeStepSpinBox" # Adjust path if needed
 # Adjust path if needed
@onready var sim_time_label = $"ScrollContainer/VBoxContainer/HBoxContainer2/Label2" # Adjust path if needed
@onready var pause_check = $"ScrollContainer/VBoxContainer/HBoxContainer/PauseCheck" # Adjust path if needed

# Planet Tab
@onready var lat_cells_spinner = $"ScrollContainer/VBoxContainer/TabContainer/Planet/LatCellsContainer/LatCellsSpinner" 
@onready var lon_cells_spinner = $"ScrollContainer/VBoxContainer/TabContainer/Planet/LonCellsContainer/LonCellsSpinner" 
@onready var planet_radius_spinner = $"ScrollContainer/VBoxContainer/TabContainer/Planet/RadiusContainer/PlanetRadiusSpinner" 
@onready var planet_mass_spinbox = $"ScrollContainer/VBoxContainer/TabContainer/Planet/MassContainer/PlanetMassSpinBox" 
@onready var surface_gravity_label = $"ScrollContainer/VBoxContainer/TabContainer/Planet/GravityLabel" 
@onready var albedo_spinner = $"ScrollContainer/VBoxContainer/TabContainer/Planet/AlbedoContainer/AlbedoSpinner" 
@onready var heat_capacity_spinner = $"ScrollContainer/VBoxContainer/TabContainer/Planet/HeatCapacityContainer/HeatCapacitySpinner" 
@onready var conductivity_spinner = $"ScrollContainer/VBoxContainer/TabContainer/Planet/ConductivityContainer/ConductivitySpinner" 
@onready var density_spinner = $"ScrollContainer/VBoxContainer/TabContainer/Planet/DensityContainer/DensitySpinner" # Example Path - Surface density

# Orbital Tab
@onready var day_length_spinbox = $"ScrollContainer/VBoxContainer/TabContainer/Orbital Parameters/DayLengthSpinBox"
@onready var semi_major_axis_spinbox = $"ScrollContainer/VBoxContainer/TabContainer/Orbital Parameters/SemiMajorAxisContainer/SemiMajorAxisSpinBox" # Example Path
@onready var eccentricity_spinbox = $"ScrollContainer/VBoxContainer/TabContainer/Orbital Parameters/EccentricityContainer/EccentricitySpinBox" # Example Path
@onready var solstice_longitude_spinbox = $"ScrollContainer/VBoxContainer/TabContainer/Orbital Parameters/SolsticeLongitudeContainer/SolsticeLongitudeSpinBox" # Example Path
@onready var obliquity_spinbox = $"ScrollContainer/VBoxContainer/TabContainer/Orbital Parameters/ObliquitySpinBox" # Example Path
@onready var period_label = $"ScrollContainer/VBoxContainer/TabContainer/Orbital Parameters/PeriodContainer/Label2" # Example Path - Label showing calculated period

# Star Tab
@onready var luminosity_spinbox = $"ScrollContainer/VBoxContainer/TabContainer/Star/LuminosityContainer/LuminositySpinBox" # Example Path
@onready var star_mass_spinbox = $"ScrollContainer/VBoxContainer/TabContainer/Star/StarMassContainer/StarMassSpinBox" # Example Path
@onready var star_period_label = $"ScrollContainer/VBoxContainer/TabContainer/Star/PeriodContainer/Label2" # Example Path


# Atmo Tab
@onready var layers_spinner = $"ScrollContainer/VBoxContainer/TabContainer/Atmosphere/LayersContainer/LayersSpinner" # Example Path
@onready var surface_pressure_spinner = $"ScrollContainer/VBoxContainer/TabContainer/Atmosphere/PressureContainer/PressureSpinner" # Example Path - ADD THIS NODE
@onready var lapse_rate_spinner = $"ScrollContainer/VBoxContainer/TabContainer/Atmosphere/LapseRateContainer/InitLapseSpinner" # Example Path - ADD THIS NODE
@onready var temp_spinner = $"ScrollContainer/VBoxContainer/TabContainer/Atmosphere/HBoxContainer3/InitTempSpinner"
@onready var KMass_spinner = $"ScrollContainer/VBoxContainer/TabContainer/Atmosphere/KMassContainer/KMassSpinner"
@onready var Kheat_spinner = $"ScrollContainer/VBoxContainer/TabContainer/Atmosphere/HBoxContainer/KheattransferSpinner"
@onready var gas_composition_container = $"ScrollContainer/VBoxContainer/TabContainer/Atmosphere/GasCompositionContainer"

#Handling gas composition
var gas_spinboxes: Dictionary = {}
var _is_normalizing = false # Flag to prevent signal loops during normalization

# Buttons
@onready var reset_button = $"ScrollContainer/VBoxContainer/HBoxContainer/ResetButton" # Example Path


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	if not is_instance_valid(sim_manager) or not is_instance_valid(planet):
		printerr("SettingsMenu: sim_manager or planet node not found!")
		set_process(false) # Disable processing if nodes are missing
		return

	# --- Initialize UI elements with current simulation values ---
	# Time/Pause
	time_step_spinbox.value = sim_manager.sim_time_step
	day_length_spinbox.value = sim_manager.day_length / sim_manager.SECONDS_IN_DAY # Convert back to days for UI
	set_pause_button(sim_manager.sim_is_paused)

	# Planet - Structural
	lat_cells_spinner.value = planet.lat_bands
	lon_cells_spinner.value = planet.lon_bands
	layers_spinner.value = planet.atmos_layers
	surface_pressure_spinner.value = planet.initial_surface_pressure
	lapse_rate_spinner.value = planet.initial_lapse_rate
	KMass_spinner.value = sim_manager.K_mass_scaling
	Kheat_spinner.value = sim_manager.K_heat_transfer

	# Planet - Physical
	planet_radius_spinner.value = planet.radius
	planet_mass_spinbox.value = planet.mass
	surface_gravity_label.text = "%.2f m/s^2" % planet.surface_gravity # Assuming gravity is in Earth gs initially
	if planet.columns.size() > 0 and planet.columns[0].size() > 0 and planet.columns[0][0] is Column:
		var sample_col = planet.columns[0][0] # Get initial values from a sample column
		albedo_spinner.value = sample_col.surface_albedo
		heat_capacity_spinner.value = sample_col.surface_heat_capacity
		conductivity_spinner.value = sample_col.surface_thermal_conductivity
		density_spinner.value = sample_col.surface_density
	else:
		# Set defaults if columns aren't ready (shouldn't happen if ready is called after planet)
		albedo_spinner.value = 0.3
		heat_capacity_spinner.value = 850
		conductivity_spinner.value = 2.5
		density_spinner.value = 2700


	# Orbital
	semi_major_axis_spinbox.value = sim_manager.orbit_semimajor_axis / sim_manager.ENGINE_METERS_PER_AU # Convert back to AU for UI
	eccentricity_spinbox.value = sim_manager.orbit_eccentricity
	solstice_longitude_spinbox.value = 0 
	obliquity_spinbox.value = sim_manager.orbital_obliquity
	_update_period_label() # Calculate and display initial period

	# Star
	luminosity_spinbox.value = sim_manager.star_luminosity
	star_mass_spinbox.value = sim_manager.star_mass
	
	_populate_gas_controls()
	_update_gas_controls_from_planet()
	


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	if is_instance_valid(sim_manager):
		sim_time_label.text = "%.1f days" % (sim_manager.sim_time / sim_manager.SECONDS_IN_DAY)


func set_pause_button(is_paused: bool):
	pause_check.set_pressed_no_signal(is_paused)


func _populate_gas_controls():
	# Clear any existing controls and references
	for child in gas_composition_container.get_children():
		child.queue_free()
	gas_spinboxes.clear()
	
	var gas_formulas = GasData.get_all_gas_formulas()
	gas_formulas.sort() # Optional: Display gases alphabetically
	
	for formula in gas_formulas:
		var gas_data = GasData.get_gas_data(formula)
		if gas_data.is_empty(): continue # Skip if data not found
	
		var hbox = HBoxContainer.new()
		hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	
		var label = Label.new()
		label.text = gas_data.get("name", formula) + " (%):"
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT

		var spinbox = SpinBox.new()
		spinbox.name = formula + "SpinBox" # Give it a unique name based on formula
		spinbox.min_value = 0.0
		spinbox.max_value = 100.0
		spinbox.step = 0.1 # Allow fractional percentages
		spinbox.value = 0.0 # Initial value
		spinbox.size_flags_horizontal = Control.SIZE_SHRINK_END # Align to the right
		spinbox.custom_minimum_size = Vector2(100, 0) # Ensure minimum width

		hbox.add_child(label)
		hbox.add_child(spinbox)
		gas_composition_container.add_child(hbox)

		# Store reference and connect signal
		gas_spinboxes[formula] = spinbox
		# Connect value_changed signal, binding the gas formula to the handler
		spinbox.value_changed.connect(_on_gas_spinbox_value_changed.bind(formula))
		

func _update_gas_controls_from_planet():
	if not is_instance_valid(planet): return

	_is_normalizing = true # Prevent updates during initialization load

	var current_composition = planet.initial_composition
	var total_fraction = 0.0
	# Calculate total fraction in current composition for normalization check
	for gas_formula in current_composition:
		total_fraction += current_composition[gas_formula]

	# Set values, normalizing if needed (though planet's should ideally be normalized)
	for formula in gas_spinboxes:
		var spinbox = gas_spinboxes[formula]
		var fraction = current_composition.get(formula, 0.0) # Get fraction, default to 0

		var percentage = 0.0
		if total_fraction > 1e-6: # Normalize if total isn't near zero
			percentage = (fraction / total_fraction) * 100.0
		elif formula == "N2": # Default to 100% N2 if composition was empty/zero
			percentage = 100.0

		spinbox.set_value_no_signal(percentage) # Use no_signal to avoid loop

	_is_normalizing = false

func _on_gas_spinbox_value_changed(new_value: float, formula: String):
	# Prevent recursive updates if we are already normalizing
	if _is_normalizing:
		return

	_is_normalizing = true # Set flag

	# --- Read all current values and normalize ---
	var current_percentages: Dictionary = {}
	var total_percentage = 0.0
	for gas_formula in gas_spinboxes:
		var value = gas_spinboxes[gas_formula].value
		current_percentages[gas_formula] = value
		total_percentage += value

	var normalized_composition: Dictionary = {}

	if total_percentage < 1e-6:
		# Handle case where user set everything to zero - default to N2
		printerr("SettingsMenu: Total composition set to zero. Defaulting to 100% N2.")
		for gas_formula in gas_spinboxes:
			var spinbox = gas_spinboxes[gas_formula]
			if gas_formula == "N2":
				spinbox.set_value_no_signal(100.0)
				normalized_composition["N2"] = 1.0
			else:
				spinbox.set_value_no_signal(0.0)
				normalized_composition[gas_formula] = 0.0
	else:
		# Normalize and update SpinBoxes visually
		for gas_formula in gas_spinboxes:
			var spinbox = gas_spinboxes[gas_formula]
			var current_percent = current_percentages[gas_formula]
			var normalized_percent = (current_percent / total_percentage) * 100.0
			# Update the spinbox value visually without triggering the signal again
			spinbox.set_value_no_signal(normalized_percent)
			# Store the normalized fraction for the planet
			normalized_composition[gas_formula] = normalized_percent / 100.0

	_is_normalizing = false # Clear flag

	# --- Update the planet ---
	if is_instance_valid(planet):
		planet.set_initial_composition(normalized_composition)

func _update_period_label():
	var period_seconds = sim_manager.orbit_period
	var period_days = period_seconds / sim_manager.SECONDS_IN_DAY
	period_label.text = "%.2f days" % period_days
	star_period_label.text = "%.2f days" % period_days

# --- Signal Handlers ---

func _on_time_step_spin_box_value_changed(value: float) -> void:
	sim_manager.set_time_step(value)

func _on_day_length_spin_box_value_changed(value: float) -> void:
	sim_manager.set_day_length(value) # set_day_length expects days input
	# Optional: Adjust max time step based on new day length?
	var max_step = value * sim_manager.SECONDS_IN_DAY * 0.5 # e.g., 10% of day length
	time_step_spinbox.max_value = max_step

func _on_obliquity_spin_box_value_changed(value: float) -> void:
	sim_manager.set_obliquity(value)

func _on_semi_major_axis_spin_box_value_changed(value: float) -> void:
	sim_manager.set_semimajor_axis(value) # Expects AU input
	var new_period_seconds = sim_manager.kepler_period_from_mass(sim_manager.star_mass, sim_manager.orbit_semimajor_axis)*sim_manager.SECONDS_IN_DAY
	sim_manager.orbit_period = new_period_seconds # Directly set the calculated period in seconds
	_update_period_label()

func _on_eccentricity_spin_box_value_changed(value: float) -> void:
	sim_manager.set_eccentricity(value)

func _on_solstice_longitude_spin_box_value_changed(value: float) -> void:
	sim_manager.set_solstice_longitude(value)

func _on_pause_check_toggled(toggled_on: bool) -> void:
	sim_manager.set_pause(toggled_on)

func _on_luminosity_spin_box_value_changed(value: float) -> void:
	sim_manager.set_luminosity(value)
	# Recalculate planet flux immediately if needed, or let sim_manager handle it
	sim_manager.update_planet_position(planet) # This recalculates flux

func _on_reset_button_pressed() -> void:
	sim_manager.reset_sim()
	# Maybe reset UI elements here too? Or let _ready handle it on scene reload?

func _on_star_mass_spin_box_value_changed(value: float) -> void:
	sim_manager.set_star_mass(value)
	var new_period_seconds = sim_manager.kepler_period_from_mass(sim_manager.star_mass, sim_manager.orbit_semimajor_axis)*sim_manager.SECONDS_IN_DAY
	sim_manager.orbit_period = new_period_seconds # Directly set the calculated period in seconds
	_update_period_label()

func _on_planet_radius_spinner_value_changed(value: float) -> void:
	if is_instance_valid(planet):
		planet.set_planet_size(planet.mass, value) # This now triggers regen_planet
		surface_gravity_label.text = "%.2f g_earth" % planet.surface_gravity

func _on_planet_mass_spin_box_value_changed(value: float) -> void:
	if is_instance_valid(planet):
		planet.set_planet_size(value, planet.radius) # This now triggers regen_planet
		surface_gravity_label.text = "%.2f g_earth" % planet.surface_gravity

# --- Surface Parameter Updates ---
func _on_albedo_spinner_value_changed(value: float) -> void:
	if is_instance_valid(planet):
		planet.global_surface_column_parameter_update(null, value)

func _on_heat_capacity_value_changed(value: float) -> void: # Surface Specific Heat
	if is_instance_valid(planet):
		planet.global_surface_column_parameter_update(null, null, null, null, value)

func _on_conductivity_spinner_value_changed(value: float) -> void: # Surface Conductivity
	if is_instance_valid(planet):
		planet.global_surface_column_parameter_update(null, null, null, value)

func _on_density_spinner_value_changed(value: float) -> void: # Surface Density
	if is_instance_valid(planet):
		planet.global_surface_column_parameter_update(null, null, value)


# --- Atmosphere Structural Parameter Updates ---
func _on_lat_cells_spinner_value_changed(value: float) -> void:
	if is_instance_valid(planet):
		planet.set_lat_bands(int(value)) # Calls regen_planet internally

func _on_lon_cells_spinner_value_changed(value: float) -> void:
	if is_instance_valid(planet):
		planet.set_lon_bands(int(value)) # Calls regen_planet internally

func _on_layers_spinner_value_changed(value: float) -> void: # Atmosphere Resolution
	if is_instance_valid(planet):
		planet.set_atmos_layers(int(value)) # Calls regen_planet internally

func _on_surface_pressure_spinner_value_changed(value: float) -> void:
	if is_instance_valid(planet):
		planet.set_initial_surface_pressure(value) # Calls regen_planet internally

func _on_lapse_rate_spinner_value_changed(value: float) -> void:
	if is_instance_valid(planet):
		planet.set_initial_lapse_rate(value) # Calls regen_planet internally


func _on_kheattransfer_spinner_value_changed(value: float) -> void:
	sim_manager.K_heat_transfer = value


func _on_k_mass_spinner_value_changed(value: float) -> void:
	sim_manager.K_mass_scaling = value


func _on_init_temp_spinner_value_changed(value: float) -> void:
	planet.set_initial_surface_temp(value)
