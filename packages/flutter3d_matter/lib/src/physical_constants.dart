/// The constants of nature the engine uses, each written once.
///
/// **A law's constant, not a world's.** Gravity, the air and the sea belong
/// to a world and are in `standard_world.dart`, as the values a world starts
/// with; a substance's density or heat belongs to the substance and is in the
/// material catalogue (`Materials`). What is here is the same in every world
/// and every substance: the Stefan–Boltzmann constant does not change on the
/// Moon.
///
/// The C core has the same numbers in its generated header,
/// `csrc/src/f3d_materials.g.h`, written from these by
/// `flutter3d_physics_native`'s `tool/gen_materials.dart`, and a structure rule
/// holds the header to them.
library;

/// The Stefan–Boltzmann constant, W/(m²·K⁴): what a black surface at a
/// temperature T radiates a square metre, σT⁴. Exact since the 2019
/// redefinition of the SI, which fixed the Boltzmann and Planck constants it
/// is made of (CODATA 2018).
const double stefanBoltzmann = 5.670374419e-8;

/// The Boltzmann constant, J/K. Exact by the SI's definition (2019).
const double boltzmannConstant = 1.380649e-23;

/// The molar gas constant, J/(mol·K): the Boltzmann constant times
/// Avogadro's, both exact since 2019 (CODATA 2018).
const double molarGasConstant = 8.314462618;

/// Dry air's molar mass, kg/mol: 0.028 964 7 (Picard and colleagues,
/// "Revised formula for the density of moist air (CIPM-2007)", Metrologia 45,
/// 2008).
const double molarMassOfDryAir = 0.0289647;

/// Dry air's ratio of specific heats, γ = c_p / c_v: 1.4, a diatomic gas's,
/// to the three figures it holds from the freezing point to a few hundred
/// degrees (CRC Handbook of Chemistry and Physics). No unit.
const double airHeatCapacityRatio = 1.4;

/// Water's freezing point at one standard atmosphere, K: the zero of the
/// Celsius scale. What a temperature in °C is offset by.
const double zeroCelsius = 273.15;
