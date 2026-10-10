/// The engine's own physical materials, `f3d.*`: the one place their
/// numbers are written.
///
/// **Every number here is read, never copied.** A liquid's preset
/// (`FluidMedium.water`, `NativeLiquidProperties.water`), the core's heat
/// presets (`NativeMaterial.oak`) and the C core's own defaults (the header
/// `tool/gen_materials.dart` writes from this file) are views of these
/// entries, and a structure rule holds the header to them. A value changed
/// here changes it everywhere, which is the point and also the warning:
/// what a recorded run, tape or golden was made under moves with it.
///
/// **Each group names its source.** Where a number is the engine's own
/// choice rather than a measurement, its source says so in as many words.
/// Values are at 20 °C and one standard atmosphere unless an entry's
/// `temperature` says otherwise.
library;

import '../standard_world.dart';
import 'material_catalog.dart';
import 'physical_material.dart';
import 'property_groups.dart';

/// The engine's built-in materials and the pairs measured between them —
/// what `MaterialCatalog.builtIn` holds.
abstract final class Materials {
  // ------------------------------------------------------------------ fluids

  /// Pure water at 20 °C.
  static const PhysicalMaterial water = PhysicalMaterial(
    id: 'f3d.water',
    name: 'water',
    phase: MaterialPhase.liquid,
    mechanical: MechanicalProperties(
      density: 998.2,
      source:
          'CRC Handbook of Chemistry and Physics, 97th ed. (2016), '
          '"Properties of water in the range 0–100 °C", at 20 °C',
    ),
    fluid: FluidProperties(
      viscosity: 1.002e-3,
      surfaceTension: 0.0728,
      bulkModulus: 2.18e9,
      source:
          'CRC Handbook (2016), at 20 °C: viscosity 1.002 mPa·s, surface '
          'tension 72.8 mN/m, and the bulk modulus from the isothermal '
          'compressibility, 4.59e-10 1/Pa',
    ),
    thermal: ThermalProperties(
      specificHeat: 4182.0,
      conductivity: 0.598,
      volumetricExpansion: 2.07e-4,
      meltingPoint: 273.15,
      boilingPoint: 373.15,
      latentHeatOfFusion: 3.34e5,
      latentHeatOfVaporization: 2.257e6,
      source:
          'CRC Handbook (2016), at 20 °C: specific heat 4.182 kJ/(kg·K), '
          'conductivity 0.598 W/(m·K), expansion 2.07e-4 1/K; melting and '
          'boiling at one atmosphere, and the latent heats there (IAPWS-95, '
          'as the Handbook tabulates it)',
    ),
    acoustic: AcousticProperties(
      absorption: <double>[0.008, 0.008, 0.013, 0.015, 0.020, 0.025],
      speedOfSound: 1482.3,
      source:
          'speed at 20 °C: Del Grosso and Mader, J. Acoust. Soc. Am. 52 '
          '(1972); absorption of a still water surface (a swimming pool): '
          'Everest and Pohlmann, Master Handbook of Acoustics, 5th ed. (2009), '
          'table of absorption coefficients',
    ),
    optical: OpticalProperties(
      refractiveIndex: 1.333,
      absorption: RgbValues(0.34, 0.0565, 0.0092),
      source:
          'n_D at 20 °C: CRC Handbook (2016); absorption of pure water at '
          '650, 550 and 450 nm: Pope and Fry, Applied Optics 36 (1997)',
    ),
  );

  /// The sea: salt water at 35 g/kg, 20 °C.
  static const PhysicalMaterial seawater = PhysicalMaterial(
    id: 'f3d.seawater',
    name: 'seawater',
    phase: MaterialPhase.liquid,
    mechanical: MechanicalProperties(
      density: 1025.0,
      source:
          'TEOS-10 (IOC, SCOR and IAPSO, 2010) at an absolute salinity of '
          '35 g/kg and 20 °C, 1024.8 kg/m³, to four figures',
    ),
    fluid: FluidProperties(
      viscosity: 1.08e-3,
      surfaceTension: 0.073,
      source:
          'Sharqawy, Lienhard and Zubair, "Thermophysical properties of '
          'seawater", Desalination and Water Treatment 16 (2010), at 35 g/kg '
          'and 20 °C, surface tension to two figures',
    ),
    thermal: ThermalProperties(
      specificHeat: 3993.0,
      conductivity: 0.596,
      meltingPoint: 271.24,
      source:
          'Sharqawy, Lienhard and Zubair (2010), at 35 g/kg and 20 °C; its '
          'freezing point at 35 g/kg, −1.91 °C (TEOS-10)',
    ),
    acoustic: AcousticProperties(
      speedOfSound: 1521.5,
      source:
          'Mackenzie, J. Acoust. Soc. Am. 70 (1981), at the surface, 35 '
          'parts per thousand and 20 °C',
    ),
    optical: OpticalProperties(
      refractiveIndex: 1.339,
      source: 'Quan and Fry, Applied Optics 34 (1995), at 35 ‰ and 20 °C',
    ),
  );

  /// Glycerol: heavy and fourteen hundred times as viscous as water.
  static const PhysicalMaterial glycerol = PhysicalMaterial(
    id: 'f3d.glycerol',
    name: 'glycerol',
    phase: MaterialPhase.liquid,
    mechanical: MechanicalProperties(
      density: 1261.0,
      source: 'CRC Handbook of Chemistry and Physics, 97th ed. (2016), 20 °C',
    ),
    fluid: FluidProperties(
      viscosity: 1.412,
      surfaceTension: 0.0634,
      source:
          'viscosity: Segur and Oberstar, Ind. Eng. Chem. 43 (1951), pure '
          'glycerol at 20 °C; surface tension: CRC Handbook (2016)',
    ),
    thermal: ThermalProperties(
      specificHeat: 2380.0,
      conductivity: 0.285,
      meltingPoint: 291.3,
      boilingPoint: 563.0,
      source:
          'CRC Handbook (2016): heat capacity 218.9 J/(mol·K) over 92.09 '
          'g/mol, conductivity, melting and boiling points',
    ),
    optical: OpticalProperties(
      refractiveIndex: 1.4746,
      source: 'CRC Handbook (2016), n_D at 20 °C',
    ),
  );

  /// Ethanol: wets glass completely and pulls weakly.
  static const PhysicalMaterial ethanol = PhysicalMaterial(
    id: 'f3d.ethanol',
    name: 'ethanol',
    phase: MaterialPhase.liquid,
    mechanical: MechanicalProperties(
      density: 789.3,
      source: 'CRC Handbook of Chemistry and Physics, 97th ed. (2016), 20 °C',
    ),
    fluid: FluidProperties(
      viscosity: 1.2e-3,
      surfaceTension: 0.0223,
      source: 'CRC Handbook (2016), 20 °C',
    ),
    thermal: ThermalProperties(
      specificHeat: 2440.0,
      conductivity: 0.167,
      volumetricExpansion: 1.09e-3,
      meltingPoint: 159.0,
      boilingPoint: 351.44,
      latentHeatOfVaporization: 8.37e5,
      source:
          'CRC Handbook (2016): heat capacity 112.3 J/(mol·K) over 46.07 '
          'g/mol, conductivity and expansion near 20 °C, the enthalpy of '
          'vaporization at the boiling point, 38.56 kJ/mol',
    ),
    optical: OpticalProperties(
      refractiveIndex: 1.3611,
      source: 'CRC Handbook (2016), n_D at 20 °C',
    ),
  );

  /// Olive oil: lighter than water, which it floats on.
  static const PhysicalMaterial oliveOil = PhysicalMaterial(
    id: 'f3d.oliveOil',
    name: 'olive oil',
    phase: MaterialPhase.liquid,
    mechanical: MechanicalProperties(
      density: 911.0,
      source:
          'Kaye and Laby, Tables of Physical and Chemical Constants, 16th ed. '
          '(1995), olive oil at 20 °C',
    ),
    fluid: FluidProperties(
      viscosity: 0.084,
      surfaceTension: 0.032,
      source:
          'Kaye and Laby (1995), olive oil at 20 °C: viscosity 84 mPa·s, '
          'surface tension 32 mN/m',
    ),
  );

  /// Honey: ten thousand times as thick as water.
  static const PhysicalMaterial honey = PhysicalMaterial(
    id: 'f3d.honey',
    name: 'honey',
    phase: MaterialPhase.liquid,
    mechanical: MechanicalProperties(
      density: 1420.0,
      source:
          'a honey of about 17 % water at 20 °C (Codex Alimentarius standard '
          'for honey, 12-1981, and Yanniotis, Skaltsi and Karaburnioti, J. '
          'Food Eng. 72, 2006)',
    ),
    fluid: FluidProperties(
      viscosity: 10.0,
      surfaceTension: 0.05,
      source:
          'viscosity: Yanniotis, Skaltsi and Karaburnioti (2006), 5 to 20 '
          'Pa·s at 20 °C across the honeys measured, the middle; surface '
          'tension: an estimate, no measurement having been read',
    ),
  );

  /// Mercury at 20 °C: does not wet glass, so its meniscus bulges and it
  /// sinks in a capillary rather than climbing it.
  static const PhysicalMaterial mercury = PhysicalMaterial(
    id: 'f3d.mercury',
    name: 'mercury',
    phase: MaterialPhase.liquid,
    mechanical: MechanicalProperties(
      density: 13546.0,
      source: 'CRC Handbook of Chemistry and Physics, 97th ed. (2016), 20 °C',
    ),
    fluid: FluidProperties(
      viscosity: 1.55e-3,
      surfaceTension: 0.4865,
      source: 'CRC Handbook (2016), 20 °C',
    ),
    thermal: ThermalProperties(
      specificHeat: 139.5,
      conductivity: 8.3,
      volumetricExpansion: 1.81e-4,
      meltingPoint: 234.32,
      boilingPoint: 629.88,
      latentHeatOfFusion: 1.14e4,
      latentHeatOfVaporization: 2.95e5,
      source: 'CRC Handbook (2016), near 20 °C and at its transitions',
    ),
    acoustic: AcousticProperties(
      speedOfSound: 1451.0,
      source: 'CRC Handbook (2016), "Speed of sound in various liquids", 20 °C',
    ),
    electrical: ElectricalProperties(
      resistivity: 9.58e-7,
      source: 'CRC Handbook (2016), 20 °C',
    ),
  );

  /// Molten basalt as it flows from a vent, near 1200 °C: a stone floats on
  /// it, and it creeps.
  static const PhysicalMaterial basaltMelt = PhysicalMaterial(
    id: 'f3d.basaltMelt',
    name: 'molten basalt',
    phase: MaterialPhase.liquid,
    temperature: 1473.15,
    mechanical: MechanicalProperties(
      density: 2700.0,
      source:
          'Lesher and Spera, "Thermodynamic and transport properties of '
          'silicate melts and magma", The Encyclopedia of Volcanoes, 2nd ed. '
          '(2015): a basaltic melt near 1200 °C',
    ),
    fluid: FluidProperties(
      viscosity: 100.0,
      surfaceTension: 0.35,
      source:
          'Lesher and Spera (2015): a basaltic melt\'s 10 to 1000 Pa·s as it '
          'flows, the middle in the logarithm, and a silicate melt\'s surface '
          'tension, about 0.35 N/m',
    ),
  );

  /// Dry air at 20 °C and one atmosphere: the medium a world nobody
  /// configured moves through. Its density is the standard air's, which a
  /// world's own air (`WorldProperties.airDensity`) replaces.
  static const PhysicalMaterial air = PhysicalMaterial(
    id: 'f3d.air',
    name: 'air',
    phase: MaterialPhase.gas,
    mechanical: MechanicalProperties(
      density: standardAirDensity,
      source: 'the ideal gas at 20 °C and 101 325 Pa (standard_world.dart)',
    ),
    fluid: FluidProperties(
      viscosity: 1.81e-5,
      source:
          'Kadoya, Matsunaga and Nagashima, J. Phys. Chem. Ref. Data 14 '
          '(1985), dry air at 20 °C',
    ),
    thermal: ThermalProperties(
      specificHeat: 1005.0,
      conductivity: 0.0257,
      source:
          'specific heat: Lemmon and colleagues, J. Phys. Chem. Ref. Data 29 '
          '(2000); conductivity: Kadoya, Matsunaga and Nagashima (1985); dry '
          'air at 20 °C',
    ),
    acoustic: AcousticProperties(
      speedOfSound: standardSpeedOfSound,
      source: 'an ideal diatomic gas at 20 °C (standard_world.dart)',
    ),
    optical: OpticalProperties(
      refractiveIndex: 1.000293,
      source: 'CRC Handbook (2016), dry air at 0 °C, 589 nm',
    ),
  );

  // ------------------------------------------------------------------ metals

  /// Plain carbon steel, weathered.
  static const PhysicalMaterial steel = PhysicalMaterial(
    id: 'f3d.steel',
    name: 'steel',
    phase: MaterialPhase.solid,
    mechanical: MechanicalProperties(
      density: 7854.0,
      youngsModulus: 2.0e11,
      poissonRatio: 0.3,
      yieldStrength: 2.5e8,
      tensileStrength: 4.0e8,
      staticFriction: 0.74,
      kineticFriction: 0.57,
      source:
          'density: Incropera and colleagues, Fundamentals of Heat and Mass '
          'Transfer, 6th ed. (2007), table A.1, plain carbon steel; modulus, '
          "Poisson's ratio and ASTM A36's least yield and tensile strength: "
          'Callister, Materials Science and Engineering, appendix B; mild '
          'steel on mild steel, dry: Serway and Jewett, Physics for '
          'Scientists and Engineers, table 5.1',
    ),
    thermal: ThermalProperties(
      specificHeat: 434.0,
      conductivity: 60.5,
      emissivity: 0.6,
      source:
          'Incropera and colleagues (2007), table A.1, plain carbon steel at '
          '300 K; emissivity a weathered surface\'s, between the polished '
          'and the heavily oxidised steels of table A.11',
    ),
    acoustic: AcousticProperties(
      speedOfSound: 5940.0,
      source:
          'Kinsler, Frey, Coppens and Sanders, Fundamentals of Acoustics, '
          '4th ed. (2000), table A10, steel, bulk longitudinal',
    ),
    optical: OpticalProperties(
      metalReflectance: RgbValues(0.562, 0.565, 0.578),
      source:
          'iron: Akenine-Möller and colleagues, Real-Time Rendering, 4th ed. '
          '(2018), table 9.2, after Hoffman',
    ),
  );

  /// Pure aluminium.
  static const PhysicalMaterial aluminum = PhysicalMaterial(
    id: 'f3d.aluminum',
    name: 'aluminium',
    phase: MaterialPhase.solid,
    mechanical: MechanicalProperties(
      density: 2702.0,
      youngsModulus: 7.0e10,
      poissonRatio: 0.33,
      source:
          'density: Incropera and colleagues (2007), table A.1, pure '
          "aluminium; modulus and Poisson's ratio: CRC Handbook (2016), "
          '"Elastic constants of metals"',
    ),
    thermal: ThermalProperties(
      specificHeat: 903.0,
      conductivity: 237.0,
      meltingPoint: 933.47,
      latentHeatOfFusion: 3.97e5,
      source:
          'Incropera and colleagues (2007), table A.1, pure aluminium at '
          '300 K; melting point and heat of fusion: CRC Handbook (2016)',
    ),
    acoustic: AcousticProperties(
      speedOfSound: 6420.0,
      source: 'Kinsler and colleagues (2000), table A10, bulk longitudinal',
    ),
    optical: OpticalProperties(
      metalReflectance: RgbValues(0.913, 0.922, 0.924),
      source: 'Real-Time Rendering, 4th ed. (2018), table 9.2',
    ),
    electrical: ElectricalProperties(
      resistivity: 2.65e-8,
      source: 'CRC Handbook (2016), 20 °C',
    ),
  );

  /// Pure copper.
  static const PhysicalMaterial copper = PhysicalMaterial(
    id: 'f3d.copper',
    name: 'copper',
    phase: MaterialPhase.solid,
    mechanical: MechanicalProperties(
      density: 8933.0,
      youngsModulus: 1.3e11,
      poissonRatio: 0.34,
      source:
          'density: Incropera and colleagues (2007), table A.1, pure copper; '
          "modulus and Poisson's ratio: CRC Handbook (2016), \"Elastic "
          'constants of metals"',
    ),
    thermal: ThermalProperties(
      specificHeat: 385.0,
      conductivity: 401.0,
      meltingPoint: 1357.77,
      source:
          'Incropera and colleagues (2007), table A.1, pure copper at 300 K; '
          'melting point: CRC Handbook (2016)',
    ),
    acoustic: AcousticProperties(
      speedOfSound: 4760.0,
      source: 'Kinsler and colleagues (2000), table A10, bulk longitudinal',
    ),
    optical: OpticalProperties(
      metalReflectance: RgbValues(0.955, 0.638, 0.538),
      source: 'Real-Time Rendering, 4th ed. (2018), table 9.2',
    ),
    electrical: ElectricalProperties(
      resistivity: 1.68e-8,
      source: 'CRC Handbook (2016), 20 °C',
    ),
  );

  /// Pure gold.
  static const PhysicalMaterial gold = PhysicalMaterial(
    id: 'f3d.gold',
    name: 'gold',
    phase: MaterialPhase.solid,
    mechanical: MechanicalProperties(
      density: 19300.0,
      youngsModulus: 7.9e10,
      poissonRatio: 0.42,
      source:
          'density: Incropera and colleagues (2007), table A.1, gold; '
          "modulus and Poisson's ratio: CRC Handbook (2016), \"Elastic "
          'constants of metals"',
    ),
    thermal: ThermalProperties(
      specificHeat: 129.0,
      conductivity: 317.0,
      meltingPoint: 1337.33,
      source:
          'Incropera and colleagues (2007), table A.1, gold at 300 K; '
          'melting point: CRC Handbook (2016)',
    ),
    optical: OpticalProperties(
      metalReflectance: RgbValues(1.0, 0.766, 0.336),
      source: 'Real-Time Rendering, 4th ed. (2018), table 9.2',
    ),
    electrical: ElectricalProperties(
      resistivity: 2.44e-8,
      source: 'CRC Handbook (2016), 20 °C',
    ),
  );

  // -------------------------------------------------------- building, stone

  /// Soda-lime plate glass: a window's.
  static const PhysicalMaterial glass = PhysicalMaterial(
    id: 'f3d.glass',
    name: 'glass',
    phase: MaterialPhase.solid,
    mechanical: MechanicalProperties(
      density: 2500.0,
      youngsModulus: 7.2e10,
      poissonRatio: 0.22,
      staticFriction: 0.94,
      kineticFriction: 0.4,
      source:
          'density: Incropera and colleagues (2007), table A.3, plate glass '
          "(soda lime); modulus and Poisson's ratio of soda-lime glass: "
          'Shelby, Introduction to Glass Science and Technology, 2nd ed. '
          '(2005); glass on glass, dry: Serway and Jewett, table 5.1',
    ),
    thermal: ThermalProperties(
      specificHeat: 750.0,
      conductivity: 1.4,
      emissivity: 0.92,
      source:
          'Incropera and colleagues (2007), table A.3, plate glass at 300 K; '
          'emissivity of smooth glass, 0.90–0.94, table A.11',
    ),
    acoustic: AcousticProperties(
      absorption: <double>[0.35, 0.25, 0.18, 0.12, 0.07, 0.04],
      source:
          'an ordinary window: Everest and Pohlmann, Master Handbook of '
          'Acoustics, 5th ed. (2009), table of absorption coefficients',
    ),
    optical: OpticalProperties(
      refractiveIndex: 1.52,
      source: 'Shelby (2005), soda-lime silica glass, n_D',
    ),
  );

  /// Concrete, stone mix.
  static const PhysicalMaterial concrete = PhysicalMaterial(
    id: 'f3d.concrete',
    name: 'concrete',
    phase: MaterialPhase.solid,
    mechanical: MechanicalProperties(
      density: 2300.0,
      youngsModulus: 3.0e10,
      poissonRatio: 0.2,
      source:
          'density: Incropera and colleagues (2007), table A.3, concrete '
          "(stone mix); modulus and Poisson's ratio of normal-weight concrete "
          'near 30 MPa: ACI 318-19, §19.2.2',
    ),
    thermal: ThermalProperties(
      specificHeat: 880.0,
      conductivity: 1.4,
      emissivity: 0.9,
      source:
          'Incropera and colleagues (2007), table A.3, concrete (stone mix) '
          'at 300 K; emissivity 0.88–0.93, table A.11',
    ),
    acoustic: AcousticProperties(
      absorption: <double>[0.01, 0.01, 0.015, 0.02, 0.02, 0.02],
      source:
          'a concrete floor: Everest and Pohlmann (2009), table of '
          'absorption coefficients',
    ),
  );

  /// Common brick.
  static const PhysicalMaterial brick = PhysicalMaterial(
    id: 'f3d.brick',
    name: 'brick',
    phase: MaterialPhase.solid,
    mechanical: MechanicalProperties(
      density: 1920.0,
      source: 'Incropera and colleagues (2007), table A.3, common brick',
    ),
    thermal: ThermalProperties(
      specificHeat: 835.0,
      conductivity: 0.72,
      emissivity: 0.93,
      source:
          'Incropera and colleagues (2007), table A.3, common brick at 300 K; '
          'red brick\'s emissivity, 0.93–0.96, table A.11',
    ),
    acoustic: AcousticProperties(
      absorption: <double>[0.03, 0.03, 0.03, 0.04, 0.05, 0.07],
      source:
          'unglazed brick: Everest and Pohlmann (2009), table of absorption '
          'coefficients',
    ),
  );

  /// Granite: the core's `STONE` heat preset.
  static const PhysicalMaterial granite = PhysicalMaterial(
    id: 'f3d.granite',
    name: 'granite',
    phase: MaterialPhase.solid,
    mechanical: MechanicalProperties(
      density: 2630.0,
      youngsModulus: 5.0e10,
      poissonRatio: 0.25,
      source:
          'density: Incropera and colleagues (2007), table A.3, Barre '
          "granite; modulus and Poisson's ratio of granite, 40–70 GPa and "
          '0.2–0.3: Ashby, Materials Selection in Mechanical Design, 4th ed. '
          '(2011), chart 1',
    ),
    thermal: ThermalProperties(
      specificHeat: 775.0,
      conductivity: 2.79,
      emissivity: 0.93,
      source:
          'Incropera and colleagues (2007), table A.3, Barre granite at '
          '300 K; emissivity a rough stone surface\'s, of the 0.90–0.96 '
          'emissivity tables give for unpolished rock',
    ),
  );

  /// Marble.
  static const PhysicalMaterial marble = PhysicalMaterial(
    id: 'f3d.marble',
    name: 'marble',
    phase: MaterialPhase.solid,
    mechanical: MechanicalProperties(
      density: 2680.0,
      source: 'Incropera and colleagues (2007), table A.3, Halston marble',
    ),
    thermal: ThermalProperties(
      specificHeat: 830.0,
      conductivity: 2.8,
      source:
          'Incropera and colleagues (2007), table A.3, Halston marble at '
          '300 K',
    ),
    acoustic: AcousticProperties(
      absorption: <double>[0.01, 0.01, 0.01, 0.01, 0.02, 0.02],
      source:
          'marble or glazed tile: Everest and Pohlmann (2009), table of '
          'absorption coefficients',
    ),
  );

  /// Ice at its melting point.
  static const PhysicalMaterial ice = PhysicalMaterial(
    id: 'f3d.ice',
    name: 'ice',
    phase: MaterialPhase.solid,
    temperature: 273.15,
    mechanical: MechanicalProperties(
      density: 920.0,
      staticFriction: 0.1,
      kineticFriction: 0.03,
      source:
          'density: Incropera and colleagues (2007), table A.3, ice at '
          '273 K; ice on ice: Serway and Jewett, table 5.1',
    ),
    thermal: ThermalProperties(
      specificHeat: 2040.0,
      conductivity: 1.88,
      meltingPoint: 273.15,
      latentHeatOfFusion: 3.34e5,
      source:
          'Incropera and colleagues (2007), table A.3, ice at 273 K; the '
          'latent heat of fusion: CRC Handbook (2016)',
    ),
    optical: OpticalProperties(
      refractiveIndex: 1.309,
      source: 'CRC Handbook (2016), ice, n_D',
    ),
  );

  // ------------------------------------------------- what burns (heat presets)

  /// A generic wood, as plain plywood 1.27 cm thick: the core's `WOOD` heat
  /// preset.
  static const PhysicalMaterial wood = PhysicalMaterial(
    id: 'f3d.wood',
    name: 'wood',
    phase: MaterialPhase.solid,
    mechanical: MechanicalProperties(
      density: 545.0,
      youngsModulus: 9.1e8,
      poissonRatio: 0.29,
      source:
          'density: Incropera and colleagues (2007), table A.3, plywood; '
          "modulus across the grain, what a contact presses, 0.068 of "
          "Douglas fir's 13.4 GPa along it, and Poisson's ratio (Wood "
          'Handbook, FPL-GTR-190, tables 5-1 and 5-2)',
    ),
    thermal: ThermalProperties(
      specificHeat: 1700.0,
      conductivity: 0.12,
      emissivity: 0.9,
      ignitionTemperature: 663.15,
      heatOfCombustion: 1.5e7,
      radiantFraction: 0.30,
      source:
          'piloted ignition at 390 °C: Quintiere and Harkleroad, NBSIR '
          '84-2943, table 2, plywood 1.27 cm; specific heat, conductivity and '
          'about fifteen megajoules a kilogram, a wood\'s in general; a wood '
          'fire\'s radiant share, 0.30 ± 0.03 (dry Douglas-fir trees, NIST TN '
          '2327r1, table 10)',
    ),
  );

  /// Red oak, dry: the core's `OAK` heat preset.
  static const PhysicalMaterial oak = PhysicalMaterial(
    id: 'f3d.oak',
    name: 'oak',
    phase: MaterialPhase.solid,
    mechanical: MechanicalProperties(
      density: 545.0,
      youngsModulus: 9.1e8,
      poissonRatio: 0.29,
      source:
          'density: Incropera and colleagues (2007), table A.3, oak across '
          'the grain; modulus and Poisson\'s ratio across the grain as '
          'f3d.wood\'s, no open measurement of oak\'s having been read',
    ),
    thermal: ThermalProperties(
      specificHeat: 1730.0,
      conductivity: 0.14,
      emissivity: 0.9,
      ignitionTemperature: 588.15,
      heatOfCombustion: 12.4e6,
      radiantFraction: 0.30,
      source:
          "specific heat: Parker's wood, Fire Safety Science 2 (1989), eq. 6, "
          'from the room to where it catches; conductivity of northern red '
          'oak oven-dry: Wood Handbook, FPL-GTR-190, table 4-7; a surface '
          'thermocouple at 315 °C and 12.4 MJ/kg burnt: Tran and White, Fire '
          'and Materials 16 (1992), tables 3 to 5; emissivity: Wood Handbook, '
          'table 18-2; radiant share as f3d.wood\'s',
    ),
  );

  /// Southern pine boards, dry: the core's `PINE` heat preset.
  static const PhysicalMaterial pine = PhysicalMaterial(
    id: 'f3d.pine',
    name: 'pine',
    phase: MaterialPhase.solid,
    mechanical: MechanicalProperties(
      density: 640.0,
      youngsModulus: 9.1e8,
      poissonRatio: 0.29,
      source:
          'density: Incropera and colleagues (2007), table A.3, yellow pine '
          'across the grain; modulus and Poisson\'s ratio as f3d.wood\'s',
    ),
    thermal: ThermalProperties(
      specificHeat: 1739.0,
      conductivity: 0.12,
      emissivity: 0.88,
      ignitionTemperature: 593.15,
      heatOfCombustion: 13.9e6,
      radiantFraction: 0.30,
      source:
          "specific heat: Parker's (1989); loblolly pine's conductivity "
          'oven-dry: Wood Handbook, table 4-7; a surface thermocouple at '
          '320 °C and 13.9 MJ/kg burnt: Tran and White (1992), tables 3 to 5; '
          'emissivity: Wood Handbook, table 18-2; radiant share as '
          'f3d.wood\'s',
    ),
  );

  /// Paper: catches at 451 °F. The core's `PAPER` heat preset.
  static const PhysicalMaterial paper = PhysicalMaterial(
    id: 'f3d.paper',
    name: 'paper',
    phase: MaterialPhase.solid,
    mechanical: MechanicalProperties(
      density: 930.0,
      youngsModulus: 2.0e9,
      poissonRatio: 0.3,
      source:
          'density: Incropera and colleagues (2007), table A.3, paper; a '
          'sheet\'s modulus in its plane, 2–8 GPa, the low end (Mark and '
          'Borch, Handbook of Physical Testing of Paper)',
    ),
    thermal: ThermalProperties(
      specificHeat: 1340.0,
      conductivity: 0.05,
      emissivity: 0.9,
      ignitionTemperature: 506.15,
      heatOfCombustion: 1.6e7,
      radiantFraction: 0.3,
      source:
          'specific heat: Incropera and colleagues (2007), table A.3; '
          'conductivity a stack\'s across its sheets with the air between '
          'them, the engine\'s choice (a solid sheet\'s is 0.18); it catches '
          'at 451 °F; sixteen megajoules a kilogram and a third radiated, a '
          'cellulosic fuel\'s in general',
    ),
  );

  /// Corrugated board, dry: the core's `CARDBOARD` heat preset.
  static const PhysicalMaterial cardboard = PhysicalMaterial(
    id: 'f3d.cardboard',
    name: 'cardboard',
    phase: MaterialPhase.solid,
    mechanical: MechanicalProperties(
      youngsModulus: 2.0e9,
      poissonRatio: 0.3,
      source: 'a sheet\'s modulus in its plane, as f3d.paper\'s',
    ),
    thermal: ThermalProperties(
      specificHeat: 1800.0,
      conductivity: 0.10,
      emissivity: 0.70,
      ignitionTemperature: 623.15,
      heatOfCombustion: 14.03e6,
      radiantFraction: 0.24,
      source:
          'specific heat, conductivity and emissivity of its virgin layers: '
          'Semmes and colleagues, Fire Safety Science 11 (2014), table 2; it '
          'catches at 350 °C, what its 8.5 kW/m² critical flux gives a black '
          'surface (Khan, de Ris and Ogden, Fire Safety Science 9, 2008); '
          '14.03 MJ/kg burnt (UL FSRI, Corrugated Cardboard); a radiant share '
          'of 0.20 to 0.28 (Zeng and colleagues, Fire Safety Science 11, 2014)',
    ),
  );

  /// Dry wheat and rye straw: the core's `THATCH` heat preset.
  static const PhysicalMaterial thatch = PhysicalMaterial(
    id: 'f3d.thatch',
    name: 'thatch',
    phase: MaterialPhase.solid,
    mechanical: MechanicalProperties(
      poissonRatio: 0.29,
      source:
          'no measurement of a straw bed\'s stiffness was found: its modulus '
          'is left to the core\'s default',
    ),
    thermal: ThermalProperties(
      specificHeat: 1938.0,
      conductivity: 0.0485,
      emissivity: 0.846,
      ignitionTemperature: 593.15,
      heatOfCombustion: 10.1e6,
      radiantFraction: 0.30,
      source:
          'Rossa, Davim and Fernandes, Fire 9, 94 (2026), table 1; the heat '
          'to 320 °C, 581 kJ/kg (Rothermel, USDA INT-115, 1972, eq. 12); 10.1 '
          'MJ/kg and an emissivity of 0.846 (UL FSRI, Straw); a straw bale\'s '
          'conductivity at 15 kg/m³ (Costes and colleagues, Buildings 7, 11, '
          '2017); radiant share as f3d.wood\'s',
    ),
  );

  /// Eucalyptus charcoal: the core's `CHARCOAL` heat preset. It glows, with
  /// no flame.
  static const PhysicalMaterial charcoal = PhysicalMaterial(
    id: 'f3d.charcoal',
    name: 'charcoal',
    phase: MaterialPhase.solid,
    mechanical: MechanicalProperties(
      poissonRatio: 0.29,
      source:
          'no open measurement of charcoal\'s stiffness was found: its '
          'modulus is left to the core\'s default',
    ),
    thermal: ThermalProperties(
      specificHeat: 1017.0,
      conductivity: 0.030,
      emissivity: 0.77,
      ignitionTemperature: 860.8,
      heatOfCombustion: 30.0e6,
      radiantFraction: 0.88,
      source:
          'Santos and colleagues, CERNE 26 (2020); emissivity: Vanaparti, '
          'Auburn University (2016); 30 MJ/kg (Zeng and colleagues); it '
          'catches where its glow holds a lump on its own, and radiates 0.88 '
          '(Kim and Sunderland, Fire Safety Journal 106, 2019; '
          'doc/derivations/charcoal_glow.md)',
    ),
  );

  /// Paraffin wax, a burner's fuel: the core's `PARAFFIN` heat preset.
  static const PhysicalMaterial paraffin = PhysicalMaterial(
    id: 'f3d.paraffin',
    name: 'paraffin wax',
    phase: MaterialPhase.solid,
    mechanical: MechanicalProperties(
      density: 900.0,
      poissonRatio: 0.29,
      source:
          'density: Incropera and colleagues (2007), table A.3, paraffin; its '
          'stiffness was not found openly and is left to the core\'s default',
    ),
    thermal: ThermalProperties(
      specificHeat: 2604.0,
      conductivity: 0.23,
      emissivity: 0.9,
      ignitionTemperature: 472.15,
      heatOfCombustion: 43.8e6,
      radiantFraction: 0.17,
      source:
          'Hamins, Bundy and Dillon, J. Fire Protection Eng. 15 (2005): a '
          'candle\'s 43.8 MJ/kg, 0.17 radiated, the solid\'s specific heat and '
          'conductivity; it flashes at 199 °C (NOAA CAMEO Chemicals); its '
          'surface\'s emissivity not found openly, the 0.9 every preset starts '
          'from',
    ),
  );

  /// Soft vulcanized rubber: a tyre's, the core's `RUBBER` heat preset.
  static const PhysicalMaterial rubber = PhysicalMaterial(
    id: 'f3d.rubber',
    name: 'rubber',
    phase: MaterialPhase.solid,
    mechanical: MechanicalProperties(
      density: 1100.0,
      youngsModulus: 2.0e6,
      poissonRatio: 0.49,
      source:
          'density: Incropera and colleagues (2007), table A.3, soft '
          'vulcanized rubber; soft and all but incompressible, a few '
          'megapascals (Gent, Engineering with Rubber, ch. 1)',
    ),
    thermal: ThermalProperties(
      specificHeat: 2010.0,
      conductivity: 0.16,
      emissivity: 0.92,
      ignitionTemperature: 623.15,
      heatOfCombustion: 3.2e7,
      radiantFraction: 0.45,
      source:
          'specific heat of soft and conductivity of hard vulcanized rubber: '
          'Incropera and colleagues (2007), table A.3; its emissivity, '
          'ignition, heat of combustion and a sooty flame\'s radiant share '
          'are the engine\'s, of the order a tyre fire is measured at',
    ),
  );

  // ---------------------------------------------------------------- plastics

  /// ABS: a moulded plastic's.
  static const PhysicalMaterial abs = PhysicalMaterial(
    id: 'f3d.abs',
    name: 'ABS',
    phase: MaterialPhase.solid,
    mechanical: MechanicalProperties(
      density: 1050.0,
      youngsModulus: 2.3e9,
      poissonRatio: 0.35,
      tensileStrength: 4.0e7,
      source:
          'Ashby, Materials Selection in Mechanical Design, 4th ed. (2011), '
          'appendix C, ABS: typical values within its ranges',
    ),
    thermal: ThermalProperties(
      specificHeat: 1400.0,
      conductivity: 0.17,
      source: 'Ashby (2011), appendix C, ABS',
    ),
  );

  /// High-density polyethylene.
  static const PhysicalMaterial polyethylene = PhysicalMaterial(
    id: 'f3d.polyethylene',
    name: 'polyethylene',
    phase: MaterialPhase.solid,
    mechanical: MechanicalProperties(
      density: 950.0,
      youngsModulus: 8.0e8,
      poissonRatio: 0.42,
      source:
          'Ashby, Materials Selection in Mechanical Design, 4th ed. (2011), '
          'appendix C, high-density polyethylene: typical values within its '
          'ranges',
    ),
    thermal: ThermalProperties(
      specificHeat: 1900.0,
      conductivity: 0.45,
      source: 'Ashby (2011), appendix C, high-density polyethylene',
    ),
  );

  // ----------------------------------------------------- grains and fibres

  /// Dry sand, as it piles.
  static const PhysicalMaterial sand = PhysicalMaterial(
    id: 'f3d.sand',
    name: 'sand',
    phase: MaterialPhase.granular,
    mechanical: MechanicalProperties(
      density: 1515.0,
      source: 'Incropera and colleagues (2007), table A.3, sand',
    ),
    thermal: ThermalProperties(
      specificHeat: 800.0,
      conductivity: 0.27,
      source: 'Incropera and colleagues (2007), table A.3, sand at 300 K',
    ),
  );

  /// Soil.
  static const PhysicalMaterial soil = PhysicalMaterial(
    id: 'f3d.soil',
    name: 'soil',
    phase: MaterialPhase.granular,
    mechanical: MechanicalProperties(
      density: 2050.0,
      source: 'Incropera and colleagues (2007), table A.3, soil',
    ),
    thermal: ThermalProperties(
      specificHeat: 1840.0,
      conductivity: 0.52,
      source: 'Incropera and colleagues (2007), table A.3, soil at 300 K',
    ),
  );

  /// Cotton, as fibre batting.
  static const PhysicalMaterial cotton = PhysicalMaterial(
    id: 'f3d.cotton',
    name: 'cotton',
    phase: MaterialPhase.solid,
    mechanical: MechanicalProperties(
      density: 80.0,
      source: 'Incropera and colleagues (2007), table A.3, cotton',
    ),
    thermal: ThermalProperties(
      specificHeat: 1300.0,
      conductivity: 0.06,
      source: 'Incropera and colleagues (2007), table A.3, cotton at 300 K',
    ),
  );

  /// Every built-in material, in the order the catalogue lists them.
  static const List<PhysicalMaterial> all = <PhysicalMaterial>[
    water,
    seawater,
    glycerol,
    ethanol,
    oliveOil,
    honey,
    mercury,
    basaltMelt,
    air,
    steel,
    aluminum,
    copper,
    gold,
    glass,
    concrete,
    brick,
    granite,
    marble,
    ice,
    wood,
    oak,
    pine,
    paper,
    cardboard,
    thatch,
    charcoal,
    paraffin,
    rubber,
    abs,
    polyethylene,
    sand,
    soil,
    cotton,
  ];

  /// How the built-ins meet where a pair was measured, or where a liquid
  /// meets a wall.
  static const List<MaterialPair> pairs = <MaterialPair>[
    MaterialPair(
      'f3d.rubber',
      'f3d.concrete',
      friction: 0.8,
      source:
          'rubber on dry concrete, μ_s 1.0 and μ_k 0.8: Serway and Jewett, '
          'Physics for Scientists and Engineers, table 5.1 — the kinetic, the '
          'engine\'s one μ',
    ),
    MaterialPair(
      'f3d.water',
      'f3d.glass',
      contactAngle: 0.35,
      source:
          'about 20°: laboratory glass as it is used, not freshly cleaned — '
          'a freshly cleaned glass wets completely (Adamson and Gast, '
          'Physical Chemistry of Surfaces, 6th ed., 1997, ch. X)',
    ),
    MaterialPair(
      'f3d.glycerol',
      'f3d.glass',
      contactAngle: 0.45,
      source:
          'about 26°: the engine\'s, of the order glycerol on laboratory '
          'glass is measured at',
    ),
    MaterialPair(
      'f3d.oliveOil',
      'f3d.glass',
      contactAngle: 0.2,
      source: 'about 11°: the engine\'s; an oil wets glass all but completely',
    ),
    MaterialPair(
      'f3d.ethanol',
      'f3d.glass',
      contactAngle: 0.0,
      source: 'ethanol wets clean glass completely (Adamson and Gast, 1997)',
    ),
    MaterialPair(
      'f3d.mercury',
      'f3d.glass',
      contactAngle: 2.44,
      source: 'about 140°: Adamson and Gast (1997), mercury on glass, 128–148°',
    ),
  ];
}
