# atmos_layer.gd
class_name AtmosLayer
extends RefCounted

# --- Constants ---
const R_IDEAL_GAS = 8.314462618         # J / (mol * K) - Universal Gas Constant
const STEFAN_BOLTZMANN = 5.670374419e-8 # W / (m^2 * K^4)
# --- Restore Reference Constants for Mass Scaling ---
const REFERENCE_DENSITY = 1.225          # kg/m^3 (Approx. Earth sea level standard air)
const REFERENCE_THICKNESS = 1000.0       # m (Arbitrary reference thickness)


var sim: Node3D = null


# --- Core Physical Properties ---
var altitude_range := Vector2(0, 0)
var layer_thickness: float = 0.0
var temperature: float = 288.0
var pressure: float = 101325.0 # Using standard pressure as initial value here, not reference
var composition: Dictionary = { "N2": 1.0 }
var wind_vector := Vector3.ZERO

# --- Links to other layers ---
var column: Column = null
var above_layer: AtmosLayer = null
var below_layer: AtmosLayer = null

# --- Calculated/Derived Properties (Updated via functions) ---
var density: float = 1.225
var effective_molar_mass: float = 0.02897
var effective_specific_heat: float = 1005.0
# --- These are now calculated using the new scaling method ---
var effective_thermal_absorptivity: float = 0.0 # Will be calculated
var effective_solar_absorptivity: float = 0.0 # Will be calculated
var column_heat_capacity_per_area: float = 1.23e6 # Will be calculated

# --- Initialization --- (No changes needed)
func _init(): pass

# --- initialize_layer --- (No changes needed)
func initialize_layer(initial_comp: Dictionary, initial_temp: float, initial_press: float, alt_range: Vector2):
	altitude_range = alt_range
	layer_thickness = altitude_range.y - altitude_range.x
	if layer_thickness < 0:
		layer_thickness = 0.0
		altitude_range.y = altitude_range.x
	elif layer_thickness <= 1e-6:
		layer_thickness = 0.0
	temperature = max(initial_temp, 1.0)
	pressure = max(initial_press, 1e-3)
	set_composition(initial_comp)

# --- set_composition --- (No changes needed)
func set_composition(new_composition: Dictionary):
	composition = new_composition.duplicate(true)
	var total_fraction = 0.0
	for gas in composition: # Basic validation and normalization
		if typeof(composition[gas]) in [TYPE_INT, TYPE_FLOAT] and composition[gas] >= 0: total_fraction += composition[gas]
		else: printerr("Invalid composition: %s" % gas)
	if total_fraction > 1e-6:
		for gas in composition:
			if typeof(composition[gas]) in [TYPE_INT, TYPE_FLOAT]: composition[gas] /= total_fraction
	else:
		composition = {"N2": 1.0}; total_fraction = 1.0
		for gas in composition: composition[gas] /= total_fraction
	effective_molar_mass = _calculate_effective_molar_mass()
	update_thermodynamics() # This now calls the modified absorptivity calc

# --- update_thermodynamics --- (No changes needed in logic, just calls the modified scaling)
func update_thermodynamics():
	if column == null:
		pass
	else:
		density = _calculate_density()
		effective_specific_heat = _calculate_effective_specific_heat()
		var column_mass_density = 0.0
		if layer_thickness > 0: column_mass_density = density * layer_thickness
		column_heat_capacity_per_area = column_mass_density * effective_specific_heat
		column_heat_capacity_per_area = max(column_heat_capacity_per_area, 1e-3)
		# --- Recalculate absorptivities using the NEW method ---
		effective_thermal_absorptivity = _calculate_scaled_absorptivity("thermal")
		effective_solar_absorptivity = _calculate_scaled_absorptivity("solar")


# --- Energy Balance Helper Functions --- (No changes needed)
func get_thermal_emission_flux() -> float:
	if temperature <= 0.0 or layer_thickness <= 0.0: return 0.0
	var emissivity = clamp(effective_thermal_absorptivity, 0.0, 1.0) # a = ε
	return emissivity * STEFAN_BOLTZMANN * pow(temperature, 4)

func get_absorbed_flux(incoming_flux: float, type: String) -> float:
	if layer_thickness <= 0.0: return 0.0
	var absorptivity = 0.0
	if type == "solar": absorptivity = effective_solar_absorptivity
	elif type == "thermal": absorptivity = effective_thermal_absorptivity
	else: printerr("Unknown flux type '%s'" % type); return 0.0
	return incoming_flux * clamp(absorptivity, 0.0, 1.0)


# --- Calculation Functions --- (Density, Molar Mass, Specific Heat unchanged)
func _calculate_density() -> float:
	if temperature < 1.0: temperature = 1.0
	if effective_molar_mass < 1e-9: printerr("Zero molar mass."); return 1e-6
	if pressure < 0: pressure = 1e-3
	return max(0.0, (pressure * effective_molar_mass) / (R_IDEAL_GAS * temperature))

func _calculate_effective_molar_mass() -> float:
	var total_molar_mass = 0.0
	for gas in composition:
		var gas_data = GasData.get_gas_data(gas)
		if not gas_data.is_empty(): total_molar_mass += composition[gas] * gas_data.molar_mass
	return max(total_molar_mass, 1e-9)

func _calculate_effective_specific_heat() -> float:
	var total_specific_heat = 0.0
	var current_molar_mass = effective_molar_mass
	if current_molar_mass < 1e-9: printerr("Zero molar mass for Cp calc."); return 1000.0
	var total_mass_fraction_check = 0.0
	for gas in composition:
		var gas_data = GasData.get_gas_data(gas)
		if not gas_data.is_empty():
			var mass_fraction = (composition[gas] * gas_data.molar_mass) / current_molar_mass
			total_specific_heat += mass_fraction * gas_data.specific_heat
			total_mass_fraction_check += mass_fraction
	if abs(total_mass_fraction_check - 1.0) > 0.01: pass
	return max(total_specific_heat, 1.0)


# --- *** MODIFIED Absorptivity Calculation *** ---
# Calculates effective absorptivity using exponential saturation based on layer MASS DENSITY.
func _calculate_scaled_absorptivity(type: String) -> float:
	# Cannot absorb if no thickness or density
	if layer_thickness <= 1e-6 or density <= 1e-6:
		return 0.0

	# 1. Calculate weighted average base absorptivity factor (using legacy 0-1 values for now)
	#    These base values represent some intrinsic absorption strength.
	var base_absorptivity_factor = 0.0
	# Use the legacy GasData property keys until kappa is revisited
	var property_key = "thermal_absorptivity" if type == "thermal" else "solar_absorptivity"

	for gas in composition:
		var gas_data = GasData.get_gas_data(gas)
		if not gas_data.is_empty():
			# Weight by mole fraction
			base_absorptivity_factor += composition[gas] * gas_data.get(property_key, 0.0)

	if base_absorptivity_factor <= 1e-6:
		return 0.0 # Transparent if components have no base absorption

	# --- Scaling based on Layer Mass Content ---
	# 2. Calculate column mass density of this layer (kg/m^2)
	var layer_column_mass_density = density * layer_thickness

	# 3. Calculate reference column mass density (kg/m^2)
	var reference_column_mass_density = REFERENCE_DENSITY * REFERENCE_THICKNESS
	if reference_column_mass_density < 1e-6: # Avoid division by zero
		reference_column_mass_density = 1.0 # Use a fallback denominator

	# 4. Calculate optical depth proxy based on mass ratio and base factor
	#    tau_proxy ~ base_factor * (layer_mass / reference_mass)
	#    The K_MASS_SCALING allows tuning the overall strength.
	var tau_proxy = sim.K_mass_scaling * base_absorptivity_factor * (layer_column_mass_density / reference_column_mass_density)

	# 5. Apply exponential saturation formula: a = 1 - exp(-tau)
	var effective_absorptivity = 1.0 - exp(-tau_proxy)

	# Return clamped result
	return clamp(effective_absorptivity, 0.0, 1.0)
