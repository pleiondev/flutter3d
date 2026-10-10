/*
 * Heat and fire on bodies — P9: what a body is made of, its temperature,
 * the heat and water the bus brings it, and the fire it can carry.
 *
 * A body is one temperature throughout — a lumped mass, which is right
 * while heat crosses it faster than it leaves its surface (a Biot number
 * under a tenth) and is what a game's crate, log or tyre needs. Bodies that
 * touch pass heat across the contact.
 *
 * A fire is a patch of the surface at its ignition temperature giving off
 * fuel gas, with a flame over it. The patch keeps its own heat balance: its
 * flame's heat and what reaches it from outside, less what it radiates and
 * what soaks into the solid under it, pays for the gas at the material's
 * heat of gasification, ṁ'' = q''_net / L (Tewarson), and a patch that
 * cannot give off the least a flame needs goes out (Rasbash). Its edge
 * creeps sideways at the opposed-flow rate Φ / (kρc (T_ig − T_s)²) and
 * climbs as its own flame heats the surface above it (Quintiere). The flame
 * gives off ṁ''·ΔH_c a square metre, a radiant share of it as light and the
 * rest in a buoyant plume, as long and as hot as Heskestad's correlations
 * say; what stands in the plume takes from its gas no more than flows past
 * it.
 *
 * What of a body stands in a liquid gives the liquid heat by convection
 * with the liquid's own properties, and boils water off where it is hotter
 * than water boils at; it does not burn there, and a fire wholly under
 * goes out.
 */
#include "f3d_internal.h"

/* Defaults of the material's fire, for a material that leaves them at
 * nought. Douglas fir's heat of gasification, 1.81 MJ/kg (Tewarson, "Generation
 * of heat and chemical compounds in fires", SFPE Handbook, table of
 * ΔH_g); the critical mass flux at wood's firepoint, 2.5 g/(m² s) (Rasbash,
 * Drysdale and Deepak, Fire Safety Journal 10, 1986; Drysdale, An
 * Introduction to Fire Dynamics, §6.3); plywood's flame spread parameter,
 * 12.9 kW²/m³ (Quintiere and Harkleroad, ASTM STP 882, 1985); and pine's
 * modulus across its grain, 0.068 of Douglas fir's 13.4 GPa along it (Wood
 * Handbook, FPL-GTR-190, tables 5-1 and 5-2), with its Poisson's ratio. */
#define F3D_GASIFICATION F3D_R(1.81e6)
#define F3D_CRITICAL_MASS_FLUX F3D_R(2.5e-3)
#define F3D_FLAME_SPREAD F3D_R(12.9e6)

/* Wood's char: what is left of what burns, 0.18 (the FDS User's Guide's
 * wood, after its sources); how thick the char stands against the wood it
 * came from, 0.7, the middle of the 0.52 to 0.86 the Wood Handbook
 * measured across eight species (FPL-GTR-190, table 18-3); its thermal
 * diffusivity, 2.3e-7 m²/s between 250 and 550 °C, and its specific heat,
 * carbon's c = 1430 + 0.355 T − 7.32e7 / T² J/(kg K) (Parker, Fire Safety
 * Science 2, 1989); and its emissivity, one (Parker, idem). */
#define F3D_CHAR_YIELD F3D_R(0.18)
#define F3D_CHAR_CONTRACTION F3D_R(0.7)
#define F3D_CHAR_DIFFUSIVITY F3D_R(2.3e-7)
#define F3D_CHAR_EMISSIVITY F3D_R(1.0)
/* Wood giving off gas in depth, first order in what is left of it: pine's
 * A = 1.4e10 /s, E = 150 kJ/mol, measured from 300 to 600 °C under fast
 * heating (Wagenaar, Prins and van Swaaij, Fuel Processing Technology 36,
 * 1993); and what it draws doing so, 430 kJ/kg (the FDS User's Guide's
 * wood). */
#define F3D_PYROLYSIS_A F3D_R(1.4e10)
#define F3D_PYROLYSIS_E F3D_R(150e3)
#define F3D_PYROLYSIS_HEAT F3D_R(430e3)
/* The coolest surface a wood's flame edge creeps over: plywood's 120 °C,
 * whose spread parameter wood takes (Quintiere and Harkleroad, NBSIR
 * 84-2943, table 2). */
#define F3D_SPREAD_MINIMUM_WOOD F3D_R(393.15)

/* What every wood and cellulosic preset below shares. The mean gas of a
 * buoyant flame's continuous zone, 797 K above a 20 °C room, 1090 K
 * (McCaffrey, NBSIR 79-1910, table 1): the same whatever burns. A wood
 * fire's radiant share, 0.30 ± 0.03 (dry Douglas-fir trees, NIST TN
 * 2327r1, table 10). Rasbash's firepoint for wood, F3D_CRITICAL_MASS_FLUX,
 * as a heat release per square metre: 2.5 g/(m² s) times the mean of red
 * oak's and southern pine's effective heats of combustion, 12.4 and 13.9
 * MJ/kg (Tran and White, Fire and Materials 16, 1992, table 4), 32.9
 * kW/m², which another cellulosic fuel's critical mass flux is that over
 * its own heat of combustion (doc/derivations/firepoint.md). */
#define F3D_FLAME_MEAN_GAS F3D_R(1090.15)
#define F3D_FIREPOINT_RELEASE F3D_R(32875.0)

int f3d_material_preset(F3dMaterialKind kind, F3dMaterial *out) {
  F3dMaterial m;
  f3d_zero(&m, sizeof m);
  m.emissivity = F3D_R(0.9);
  m.conductivity = F3D_R(1.0);
  /* A stiff solid's, of the order of glass and stone (Ashby, Materials
   * Selection in Mechanical Design, chart 1). */
  m.modulus = F3D_R(5e10);
  m.poisson_ratio = F3D_R(0.25);
  /* What a preset says of its heat, its burning and its stiffness —
   * specific heat, conductivity, emissivity, where it catches, its heat of
   * combustion, its flame's radiant share, its modulus and Poisson's ratio
   * — is its entry in flutter3d_physics' material catalogue, read from
   * f3d_materials.g.h (F3D_MAT_<NAME>_*), with that entry's sources; STONE
   * is f3d.granite. What only the fire model reads stays here, with its
   * own. */
  switch (kind) {
    case F3D_MATERIAL_INERT:
      m.specific_heat = F3D_R(1000.0);
      break;
    case F3D_MATERIAL_WOOD:
      /* A generic wood, as plain plywood 1.27 cm thick: how it catches and
       * how its flame creeps are that plywood's, from one row of the LIFT
       * tests, so they agree with each other — piloted ignition at 390 °C,
       * kρc 0.54 (kW/m² K)² s, Φ 12.91 kW²/m³ and the coolest surface a
       * flame creeps over 120 °C (Quintiere and Harkleroad, NBSIR 84-2943,
       * table 2). The rest is a wood's in general: about fifteen
       * megajoules a kilogram, and a burning surface losing about eleven
       * grams a second per square metre. OAK and PINE are those species'
       * own measurements. */
      m.specific_heat = F3D_MAT_WOOD_SPECIFIC_HEAT;
      m.conductivity = F3D_MAT_WOOD_CONDUCTIVITY;
      m.ignition_temperature = F3D_MAT_WOOD_IGNITION_TEMPERATURE;
      m.ignition_inertia = F3D_R(0.54e6);
      m.heat_of_combustion = F3D_MAT_WOOD_HEAT_OF_COMBUSTION;
      m.burn_rate = F3D_R(0.011);
      m.fuel_fraction = F3D_R(0.8);
      m.flame_feedback = F3D_R(0.3);
      /* A wood fire's continuous flame at the mean gas of a buoyant
       * flame's continuous zone, F3D_FLAME_MEAN_GAS (McCaffrey), as OAK's
       * and PINE's; its radiant share f3d.wood's; and its gas absorbing 0.8
       * per metre (Babrauskas). Its
       * gas passes 25 W/(m² K) to a wall it stands on, the top of the
       * 10–30 a turbulent wall flame's convection is measured at
       * (Quintiere, Fundamentals of Fire Phenomena, §8.6). */
      m.flame_temperature = F3D_FLAME_MEAN_GAS;
      m.flame_convection = F3D_R(25.0);
      m.flame_radiant = F3D_MAT_WOOD_RADIANT_FRACTION;
      m.flame_absorption = F3D_R(0.8);
      /* Douglas fir's, Rasbash's wood and plywood's, as F3D_GASIFICATION
       * and its fellows say; across the grain (Wood Handbook). */
      m.heat_of_gasification = F3D_GASIFICATION;
      m.critical_mass_flux = F3D_CRITICAL_MASS_FLUX;
      m.flame_spread = F3D_FLAME_SPREAD;
      m.modulus = F3D_MAT_WOOD_YOUNGS_MODULUS;
      m.poisson_ratio = F3D_MAT_WOOD_POISSON_RATIO;
      /* A cellulosic flame's soot by two-colour pyrometry, 1305 K (Thomsen
       * and colleagues, NASA Saffire IV, NTRS 20220012861): a
       * thin cotton fabric's, the nearest measured to wood's. */
      m.soot_temperature = F3D_R(1300.0);
      m.char_yield = F3D_CHAR_YIELD;
      m.spread_minimum = F3D_SPREAD_MINIMUM_WOOD;
      /* Wood's soot yield in small, well-ventilated fires, 0.015 (Tewarson,
       * SFPE Handbook, as the FDS User's Guide, NIST SP 1019, eq. 13.18,
       * gives it). Large free-burning wood fires measure 3 to 7 times less
       * (doc/derivations/soot_yield.md); OAK and PINE take theirs. */
      m.soot_yield = F3D_R(0.015);
      m.emissivity = F3D_MAT_WOOD_EMISSIVITY;
      break;
    case F3D_MATERIAL_PAPER:
      /* It catches at 451 °F. */
      m.specific_heat = F3D_MAT_PAPER_SPECIFIC_HEAT;
      m.conductivity = F3D_MAT_PAPER_CONDUCTIVITY;
      m.ignition_temperature = F3D_MAT_PAPER_IGNITION_TEMPERATURE;
      m.heat_of_combustion = F3D_MAT_PAPER_HEAT_OF_COMBUSTION;
      m.burn_rate = F3D_R(0.02);
      m.fuel_fraction = F3D_R(0.9);
      m.flame_feedback = F3D_R(0.3);
      /* A thin, clean flame: as hot as wood's, and seen through hardly
       * glowing. */
      m.flame_temperature = F3D_R(1050.0);
      m.flame_convection = F3D_R(25.0);
      m.flame_radiant = F3D_MAT_PAPER_RADIANT_FRACTION;
      m.flame_absorption = F3D_R(0.5);
      /* Cellulose as wood is: no separate measurement is used, so wood's
       * gasification, firepoint and spread parameter stand. A sheet's
       * modulus in its plane, 2–8 GPa (Mark and Borch, Handbook of
       * Physical Testing of Paper): the low end. */
      m.heat_of_gasification = F3D_GASIFICATION;
      m.critical_mass_flux = F3D_CRITICAL_MASS_FLUX;
      m.flame_spread = F3D_FLAME_SPREAD;
      m.modulus = F3D_MAT_PAPER_YOUNGS_MODULUS;
      m.poisson_ratio = F3D_MAT_PAPER_POISSON_RATIO;
      m.soot_temperature = F3D_R(1300.0);
      m.char_yield = F3D_CHAR_YIELD;
      m.spread_minimum = F3D_SPREAD_MINIMUM_WOOD;
      /* Corrugated boxes filled with crinkled kraft paper burning freely
       * under a hood, 0.0014 ± 0.0003 (McGrattan, NIST TN 2102, table 1). */
      m.soot_yield = F3D_R(0.0014);
      m.emissivity = F3D_MAT_PAPER_EMISSIVITY;
      break;
    case F3D_MATERIAL_RUBBER:
      m.specific_heat = F3D_MAT_RUBBER_SPECIFIC_HEAT;
      m.conductivity = F3D_MAT_RUBBER_CONDUCTIVITY;
      m.emissivity = F3D_MAT_RUBBER_EMISSIVITY;
      m.ignition_temperature = F3D_MAT_RUBBER_IGNITION_TEMPERATURE;
      m.heat_of_combustion = F3D_MAT_RUBBER_HEAT_OF_COMBUSTION;
      m.burn_rate = F3D_R(0.03);
      m.fuel_fraction = F3D_R(0.9);
      m.flame_feedback = F3D_R(0.3);
      /* A sooty flame: hotter, nearly half its heat radiated, and dark
       * with soot that absorbs a few times what wood's does. */
      m.flame_temperature = F3D_R(1200.0);
      m.flame_convection = F3D_R(25.0);
      m.flame_radiant = F3D_MAT_RUBBER_RADIANT_FRACTION;
      m.flame_absorption = F3D_R(2.5);
      /* Polyisoprene's heat of gasification, 2.0 MJ/kg (Tewarson, SFPE
       * Handbook); the firepoint of a polyolefin, 2 g/(m² s) (Drysdale,
       * table 6.6, polyethylene and polypropylene); PMMA's spread
       * parameter, 14.4 kW²/m³ (Quintiere and Harkleroad), the nearest
       * charless polymer measured. Soft and all but incompressible: a few
       * megapascals (Gent, Engineering with Rubber, ch. 1). */
      m.heat_of_gasification = F3D_R(2.0e6);
      m.critical_mass_flux = F3D_R(2.0e-3);
      m.flame_spread = F3D_R(14.4e6);
      m.modulus = F3D_MAT_RUBBER_YOUNGS_MODULUS;
      m.poisson_ratio = F3D_MAT_RUBBER_POISSON_RATIO;
      /* A sooty polymer fire's radiation temperature over a 0.3 m pool,
       * polystyrene's 1190 K (Markstein, 17th Symp. on Combustion, 1979). */
      m.soot_temperature = F3D_R(1190.0);
      /* PMMA's, the nearest charless polymer measured, as its spread
       * parameter is: 90 °C (Quintiere and Harkleroad, NBSIR 84-2943,
       * table 2). */
      m.spread_minimum = F3D_R(363.15);
      /* A tyre burning in the open: its particulate, 0.097 kg/kg, of which
       * 10.6 % extracts as organics (EPA-600/R-97-115, table 5), counted
       * at the extinction its carbon share gives, 8.6 (EC/TC)^0.36 m²/g
       * (Widmann and colleagues, J. Aerosol Sci. 36, 2005), against the
       * 8.7 m²/g a soot yield is read with: 0.092
       * (doc/derivations/soot_yield.md). */
      m.soot_yield = F3D_R(0.092);
      break;
    case F3D_MATERIAL_OAK:
      /* Red oak, dry; water on it is the bus's. Its specific heat is
       * Parker's wood's, c = 1.11 + 0.0037 T(°C) kJ/(kg K) (Fire Safety
       * Science 2, 1989, eq. 6), meant from the room to where it catches,
       * and its conductivity the Wood Handbook's for northern red oak
       * oven-dry (FPL-GTR-190, table 4-7). How it catches is one paper's:
       * a surface thermocouple at 315 °C, kρc 0.360 (kW/m² K)² s, and 12.4
       * MJ/kg burnt; 0.26 of it left as char (Tran and White, Fire and
       * Materials 16, 1992, tables 3 to 5). Its surface's emissivity 0.9,
       * and its burning 4.1 g/(m² s) under 18 kW/m² (Wood Handbook, tables
       * 18-2 and 18-3). Its heat of gasification is the heat to its
       * ignition temperature with pyrolysis's, not the whole-test slope
       * that counts the char's insulation too
       * (doc/derivations/heat_of_gasification.md); its flame's spread
       * plywood's, the same wood flame over a surface that catches as it
       * does (doc/derivations/flame_spread.md). Its soot, 0.003 at 50
       * kW/m² in the cone (UL FSRI Materials and Products Database, Oak
       * Flooring). */
      m.specific_heat = F3D_MAT_OAK_SPECIFIC_HEAT;
      m.conductivity = F3D_MAT_OAK_CONDUCTIVITY;
      m.emissivity = F3D_MAT_OAK_EMISSIVITY;
      m.ignition_temperature = F3D_MAT_OAK_IGNITION_TEMPERATURE;
      m.ignition_inertia = F3D_R(0.360e6);
      m.heat_of_combustion = F3D_MAT_OAK_HEAT_OF_COMBUSTION;
      m.burn_rate = F3D_R(0.0041);
      m.fuel_fraction = F3D_R(0.74);
      m.flame_temperature = F3D_FLAME_MEAN_GAS;
      m.flame_convection = F3D_R(25.0);
      m.flame_radiant = F3D_MAT_OAK_RADIANT_FRACTION;
      m.flame_absorption = F3D_R(0.8);
      m.heat_of_gasification = F3D_R(0.940e6);
      m.critical_mass_flux = F3D_CRITICAL_MASS_FLUX;
      m.flame_spread = F3D_R(12.91e6);
      m.spread_minimum = F3D_SPREAD_MINIMUM_WOOD;
      /* Across the grain as WOOD's: no open measurement of oak's was read. */
      m.modulus = F3D_MAT_OAK_YOUNGS_MODULUS;
      m.poisson_ratio = F3D_MAT_OAK_POISSON_RATIO;
      m.soot_temperature = F3D_R(1300.0);
      m.char_yield = F3D_R(0.26);
      m.soot_yield = F3D_R(0.003);
      break;
    case F3D_MATERIAL_PINE:
      /* Southern pine boards, dry, from the same sources as OAK: Parker's
       * specific heat to where it catches; loblolly pine's conductivity
       * oven-dry (Wood Handbook, table 4-7); a surface thermocouple at
       * 320 °C, kρc 0.183 (kW/m² K)² s, 13.9 MJ/kg burnt and 0.24 left as
       * char (Tran and White, tables 3 to 5); its emissivity 0.88 and its
       * burning 3.8 g/(m² s) under 18 kW/m² (Wood Handbook, tables 18-2 and
       * 18-3). Its soot, a pine crib's burning freely, 0.0020 ± 0.0003
       * (McGrattan, NIST TN 2102, table 1). */
      m.specific_heat = F3D_MAT_PINE_SPECIFIC_HEAT;
      m.conductivity = F3D_MAT_PINE_CONDUCTIVITY;
      m.emissivity = F3D_MAT_PINE_EMISSIVITY;
      m.ignition_temperature = F3D_MAT_PINE_IGNITION_TEMPERATURE;
      m.ignition_inertia = F3D_R(0.183e6);
      m.heat_of_combustion = F3D_MAT_PINE_HEAT_OF_COMBUSTION;
      m.burn_rate = F3D_R(0.0038);
      m.fuel_fraction = F3D_R(0.76);
      m.flame_temperature = F3D_FLAME_MEAN_GAS;
      m.flame_convection = F3D_R(25.0);
      m.flame_radiant = F3D_MAT_PINE_RADIANT_FRACTION;
      m.flame_absorption = F3D_R(0.8);
      m.heat_of_gasification = F3D_R(0.952e6);
      m.critical_mass_flux = F3D_CRITICAL_MASS_FLUX;
      m.flame_spread = F3D_R(12.91e6);
      m.spread_minimum = F3D_SPREAD_MINIMUM_WOOD;
      m.modulus = F3D_MAT_PINE_YOUNGS_MODULUS;
      m.poisson_ratio = F3D_MAT_PINE_POISSON_RATIO;
      m.soot_temperature = F3D_R(1300.0);
      m.char_yield = F3D_R(0.24);
      m.soot_yield = F3D_R(0.0020);
      break;
    case F3D_MATERIAL_CARDBOARD:
      /* Corrugated board, dry: specific heat 1800 J/(kg K), conductivity
       * 0.10 W/(m K) and emissivity 0.70 of its virgin layers (Semmes and
       * colleagues, Fire Safety Science 11, 2014, table 2); it catches at
       * 350 °C, what its 8.5 kW/m² critical flux gives a black surface
       * (Khan, de Ris and Ogden, Fire Safety Science 9, 2008), its kρc
       * what its times to catch at 25, 50 and 75 kW/m² fit past that
       * critical flux (doc/derivations/flame_spread.md); 14.03 MJ/kg burnt (UL FSRI,
       * Corrugated Cardboard), 0.18 of it left as char and a radiant share
       * of 0.20 to 0.28 as the flux on it rises (Zeng and colleagues, Fire
       * Safety Science 11, 2014). Its flame creeps as over thin plywood,
       * 0.635 cm: Φ 7.49 kW²/m³, no colder than 170 °C (Quintiere and
       * Harkleroad, table 2). A sheet's modulus as PAPER's; its soot as
       * PAPER's, boxes burning freely. */
      m.specific_heat = F3D_MAT_CARDBOARD_SPECIFIC_HEAT;
      m.conductivity = F3D_MAT_CARDBOARD_CONDUCTIVITY;
      m.emissivity = F3D_MAT_CARDBOARD_EMISSIVITY;
      m.ignition_temperature = F3D_MAT_CARDBOARD_IGNITION_TEMPERATURE;
      m.ignition_inertia = F3D_R(0.170e6);
      m.heat_of_combustion = F3D_MAT_CARDBOARD_HEAT_OF_COMBUSTION;
      m.fuel_fraction = F3D_R(0.82);
      m.flame_temperature = F3D_FLAME_MEAN_GAS;
      m.flame_convection = F3D_R(25.0);
      m.flame_radiant = F3D_MAT_CARDBOARD_RADIANT_FRACTION;
      m.flame_absorption = F3D_R(0.8);
      m.heat_of_gasification = F3D_R(1.024e6);
      m.critical_mass_flux = F3D_FIREPOINT_RELEASE / F3D_MAT_CARDBOARD_HEAT_OF_COMBUSTION;
      m.flame_spread = F3D_R(7.49e6);
      m.spread_minimum = F3D_R(443.15);
      m.modulus = F3D_MAT_CARDBOARD_YOUNGS_MODULUS;
      m.poisson_ratio = F3D_MAT_CARDBOARD_POISSON_RATIO;
      m.soot_temperature = F3D_R(1300.0);
      m.char_yield = F3D_R(0.18);
      m.soot_yield = F3D_R(0.0014);
      break;
    case F3D_MATERIAL_THATCH:
      /* Dry wheat and rye straw, as Rossa, Davim and Fernandes burnt it in
       * beds (Fire 9, 94, 2026, table 1): its stalks' surface over their
       * volume 5265 /m and their own density 285 kg/m³ — hollow, against
       * the 513 Rothermel's fuel models give every fuel — 0.88 of it gone
       * by the time its flame is out, and 0.0277 of a 0.39 kg/m² bed
       * burnt a second while it flames. It catches at 320 °C, the heat to
       * there 581 kJ/kg (Rothermel, USDA INT-115, 1972, eq. 12), which is
       * its specific heat; 10.1 MJ/kg burnt and an emissivity of 0.846
       * (UL FSRI, Straw); its conductivity a straw bale's, 0.0444 +
       * 2.72·10⁻⁴ ρ W/(m K), at Rossa's 15 kg/m³ bed (Costes and
       * colleagues, Buildings 7, 11, 2017). Its flame creeps at the rate
       * Rothermel's model gives that bed with no wind, 2.7 mm/s, and over
       * cold straw too (doc/derivations/flame_spread.md); its
       * gasification 581 kJ/kg and grass's 416 kJ/kg of pyrolysis (Mell
       * and colleagues, Int. J. Wildland Fire 16, 2007, table 1). A
       * grass's soot, little bluestem's 0.00503 (NIST TN 2314, table 7).
       * No measurement of a straw bed's stiffness was found: its modulus is
       * left to the default. */
      m.specific_heat = F3D_MAT_THATCH_SPECIFIC_HEAT;
      m.conductivity = F3D_MAT_THATCH_CONDUCTIVITY;
      m.emissivity = F3D_MAT_THATCH_EMISSIVITY;
      m.ignition_temperature = F3D_MAT_THATCH_IGNITION_TEMPERATURE;
      m.ignition_inertia = F3D_R(1410.0);
      m.heat_of_combustion = F3D_MAT_THATCH_HEAT_OF_COMBUSTION;
      m.burn_rate = F3D_R(0.0108);
      m.fuel_fraction = F3D_R(0.88);
      m.flame_temperature = F3D_FLAME_MEAN_GAS;
      m.flame_convection = F3D_R(25.0);
      m.flame_radiant = F3D_MAT_THATCH_RADIANT_FRACTION;
      m.flame_absorption = F3D_R(0.8);
      m.heat_of_gasification = F3D_R(0.9975e6);
      m.critical_mass_flux = F3D_FIREPOINT_RELEASE / F3D_MAT_THATCH_HEAT_OF_COMBUSTION;
      m.flame_spread = F3D_R(3.40e5);
      m.modulus = F3D_R(0.0);
      m.poisson_ratio = F3D_MAT_THATCH_POISSON_RATIO;
      m.soot_temperature = F3D_R(1300.0);
      m.char_yield = F3D_R(0.12);
      m.element_surface = F3D_R(5265.0);
      m.element_density = F3D_R(285.0);
      m.soot_yield = F3D_R(0.00503);
      break;
    case F3D_MATERIAL_CHARCOAL:
      /* Eucalyptus charcoal's specific heat 1017 J/(kg K) and conductivity
       * 0.030 W/(m K) (Santos and colleagues, CERNE 26, 2020); its surface
       * 0.77 emissive (Vanaparti, Auburn University, 2016); the ash in good
       * charcoal 0.5 to 5 % (Antal and Grønli, Ind. Eng. Chem. Res. 42,
       * 2003), what is left; 30 MJ/kg as char burns (Zeng and colleagues,
       * 29.5 to 30.5). It has no flame: it glows at 931 °C (Kim and
       * Sunderland, Fire Safety Journal 106, 2019), its light that
       * surface's and 0.88 of its heat radiated. It burns at the rate
       * oxygen reaches it, and catches no cooler than where that rate's
       * heat holds a lump on its own: 861 K; its heat of gasification and
       * least burning as doc/derivations/charcoal_glow.md derives them, so
       * a coal glows on in a flame as hot as a glowing heap and goes out
       * out of one. No soot. */
      m.specific_heat = F3D_MAT_CHARCOAL_SPECIFIC_HEAT;
      m.conductivity = F3D_MAT_CHARCOAL_CONDUCTIVITY;
      m.emissivity = F3D_MAT_CHARCOAL_EMISSIVITY;
      m.ignition_temperature = F3D_MAT_CHARCOAL_IGNITION_TEMPERATURE;
      m.heat_of_combustion = F3D_MAT_CHARCOAL_HEAT_OF_COMBUSTION;
      m.burn_rate = F3D_R(1.02e-3);
      m.fuel_fraction = F3D_R(0.9725);
      m.flame_temperature = F3D_R(1204.15);
      m.flame_radiant = F3D_MAT_CHARCOAL_RADIANT_FRACTION;
      m.heat_of_gasification = F3D_R(66.6e6);
      m.critical_mass_flux = F3D_R(0.79e-3);
      /* No open measurement of charcoal's stiffness was found: the
       * default's, as THATCH's. */
      m.modulus = F3D_R(0.0);
      m.poisson_ratio = F3D_MAT_CHARCOAL_POISSON_RATIO;
      m.soot_temperature = F3D_R(1204.15);
      break;
    case F3D_MATERIAL_PARAFFIN:
      /* Paraffin wax, a burner's fuel: a candle burns 1.75 mg/s of it at
       * 43.8 MJ/kg, 77 W, radiating 0.17 of it from a flame whose hottest
       * gas is 1673 K; solid, its specific heat 2604 J/(kg K) and
       * conductivity 0.23 W/(m K) (Hamins, Bundy and Dillon, J. Fire
       * Protection Eng. 15, 2005); a wax pool's soot 0.035 to 0.045 (idem,
       * in the cone). It flashes at 199 °C (NOAA CAMEO Chemicals; NIOSH);
       * its fire point is not published openly, and this is what catches
       * it. Its flame passes a surface in it what the 145 kW/m² measured at
       * a candle's tip says, and absorbs what its radiant share over a
       * flame as wide as the candle says (doc/derivations/burners.md). A
       * body of it holds no fuel of its own: wax melts and runs, which the
       * core does not follow, so it burns only as a burner's fuel. */
      m.specific_heat = F3D_MAT_PARAFFIN_SPECIFIC_HEAT;
      m.conductivity = F3D_MAT_PARAFFIN_CONDUCTIVITY;
      m.ignition_temperature = F3D_MAT_PARAFFIN_IGNITION_TEMPERATURE;
      m.heat_of_combustion = F3D_MAT_PARAFFIN_HEAT_OF_COMBUSTION;
      m.flame_temperature = F3D_R(1673.15);
      m.flame_convection = F3D_R(105.0);
      m.flame_radiant = F3D_MAT_PARAFFIN_RADIANT_FRACTION;
      m.flame_absorption = F3D_R(0.51);
      m.soot_temperature = F3D_R(1673.15);
      m.soot_yield = F3D_R(0.04);
      /* Its surface's emissivity and its stiffness were not found openly:
       * the 0.9 every preset starts from, and the default modulus. */
      m.modulus = F3D_R(0.0);
      m.poisson_ratio = F3D_MAT_PARAFFIN_POISSON_RATIO;
      m.emissivity = F3D_MAT_PARAFFIN_EMISSIVITY;
      break;
    case F3D_MATERIAL_STEEL:
      /* Weathered, not polished: a polished surface is a tenth of this. */
      m.specific_heat = F3D_MAT_STEEL_SPECIFIC_HEAT;
      m.conductivity = F3D_MAT_STEEL_CONDUCTIVITY;
      m.emissivity = F3D_MAT_STEEL_EMISSIVITY;
      m.modulus = F3D_MAT_STEEL_YOUNGS_MODULUS;
      m.poisson_ratio = F3D_MAT_STEEL_POISSON_RATIO;
      break;
    case F3D_MATERIAL_STONE:
      /* Granite. */
      m.specific_heat = F3D_MAT_GRANITE_SPECIFIC_HEAT;
      m.conductivity = F3D_MAT_GRANITE_CONDUCTIVITY;
      m.emissivity = F3D_MAT_GRANITE_EMISSIVITY;
      m.modulus = F3D_MAT_GRANITE_YOUNGS_MODULUS;
      m.poisson_ratio = F3D_MAT_GRANITE_POISSON_RATIO;
      break;
    default:
      return 0;
  }
  *out = m;
  return 1;
}

/* The material's fire as the step reads it: its own values, or the
 * defaults above for those it leaves at nought. */
static f3d_real gasification_of(const F3dMaterial *m) {
  return m->heat_of_gasification > F3D_R(0.0) ? m->heat_of_gasification
                                               : F3D_GASIFICATION;
}

static f3d_real firepoint_of(const F3dMaterial *m) {
  return m->critical_mass_flux > F3D_R(0.0) ? m->critical_mass_flux
                                             : F3D_CRITICAL_MASS_FLUX;
}

static f3d_real spread_of(const F3dMaterial *m) {
  return m->flame_spread > F3D_R(0.0) ? m->flame_spread : F3D_FLAME_SPREAD;
}

/* (1 − ν²) / E: how far a pressed surface gives, Hertz's compliance. */
static f3d_real compliance_of(const F3dMaterial *m) {
  const f3d_real e = m->modulus > F3D_R(0.0) ? m->modulus : F3D_MAT_WOOD_YOUNGS_MODULUS;
  return (F3D_R(1.0) - m->poisson_ratio * m->poisson_ratio) / e;
}

static f3d_real capacity_of(const F3dSlot *s);
static int ensure_lumps(F3dWorld *world);
static void body_from_lumps(F3dWorld *world, F3dSlot *s);

/* A compound's parts' heat, made now if it has none yet; null for any
 * other body, or when memory ran out. */
static F3dLump *lumps_of(F3dWorld *world, F3dSlot *s) {
  if (s->shape != F3D_SHAPE_COMPOUND) return NULL;
  if (!ensure_lumps(world) || s->lumps == 0) return NULL;
  return &world->lumps[s->lumps - 1u];
}

static int in_range(f3d_real x, f3d_real low, f3d_real high) {
  return f3d_finite(x) && x >= low && x <= high;
}

/* Whether [m] is a material a step can burn: in range, and with a flame
 * hotter than it catches at when it burns. */
static int material_ok(const F3dMaterial *material) {
  const F3dMaterial m = *material;
  const f3d_real big = F3D_R(1e30);
  if (!(f3d_finite(m.specific_heat) && m.specific_heat > F3D_R(0.0))) return 0;
  if (!in_range(m.emissivity, F3D_R(0.0), F3D_R(1.0))) return 0;
  if (!in_range(m.ignition_temperature, F3D_R(0.0), big)) return 0;
  if (!in_range(m.heat_of_combustion, F3D_R(0.0), big)) return 0;
  if (!in_range(m.burn_rate, F3D_R(0.0), big)) return 0;
  /* Below one: a body that burnt all of itself would have no mass left to
   * move. */
  if (!(in_range(m.fuel_fraction, F3D_R(0.0), F3D_R(1.0)) &&
        m.fuel_fraction < F3D_R(1.0))) {
    return 0;
  }
  if (!in_range(m.flame_feedback, F3D_R(0.0), F3D_R(1.0))) return 0;
  if (!(f3d_finite(m.conductivity) && m.conductivity > F3D_R(0.0))) return 0;
  /* A material that burns has a flame hotter than it catches at. */
  if (m.ignition_temperature > F3D_R(0.0) &&
      !(f3d_finite(m.flame_temperature) &&
        m.flame_temperature > m.ignition_temperature)) {
    return 0;
  }
  if (!in_range(m.flame_convection, F3D_R(0.0), big)) return 0;
  if (!in_range(m.flame_radiant, F3D_R(0.0), F3D_R(1.0))) return 0;
  if (!in_range(m.flame_absorption, F3D_R(0.0), big)) return 0;
  if (!in_range(m.heat_of_gasification, F3D_R(0.0), big)) return 0;
  if (!in_range(m.critical_mass_flux, F3D_R(0.0), big)) return 0;
  if (!in_range(m.flame_spread, F3D_R(0.0), big)) return 0;
  if (!in_range(m.modulus, F3D_R(0.0), big)) return 0;
  /* Past a half a solid would grow when squeezed. */
  if (!in_range(m.poisson_ratio, F3D_R(0.0), F3D_R(0.5))) return 0;
  if (!in_range(m.soot_temperature, F3D_R(0.0), big)) return 0;
  if (!(in_range(m.char_yield, F3D_R(0.0), F3D_R(1.0)) && m.char_yield < F3D_R(1.0))) {
    return 0;
  }
  if (!in_range(m.spread_minimum, F3D_R(0.0), big)) return 0;
  if (!in_range(m.ignition_inertia, F3D_R(0.0), big)) return 0;
  if (!in_range(m.element_surface, F3D_R(0.0), big)) return 0;
  if (!in_range(m.element_density, F3D_R(0.0), big)) return 0;
  /* A bed's elements have a density of their own. */
  if (m.element_surface > F3D_R(0.0) && !(m.element_density > F3D_R(0.0))) return 0;
  /* Soot is some of what burns, never more. */
  if (!in_range(m.soot_yield, F3D_R(0.0), F3D_R(1.0))) return 0;
  return 1;
}

/* A patch no longer alight: none of it involved, and nothing laid under
 * it. */
static void patch_out(F3dLump *l) {
  l->burning &= ~F3D_LUMP_OWN;
  l->involved = F3D_R(0.0);
  l->spread = F3D_R(0.0);
  l->rise = F3D_R(0.0);
  l->patch = F3D_R(0.0);
  l->edge = 0;
}

int f3d_body_set_material(F3dWorld *world, F3dBody body,
                          const F3dMaterial *material) {
  F3dSlot *s = f3d_slot_of(world, body);
  if (s == NULL || material == NULL || !material_ok(material)) return 0;
  const F3dMaterial m = *material;
  s->material = m;
  const int burns = m.ignition_temperature > F3D_R(0.0);
  F3dLump *l = lumps_of(world, s);
  for (uint32_t i = 0; l != NULL && i < s->lump_count; i++) {
    l[i].fuel = l[i].mass * m.fuel_fraction;
    if (l[i].fuel <= F3D_R(0.0) || !burns) {
      patch_out(&l[i]);
      l[i].exposure = F3D_R(0.0);
      if (!(l[i].burning & F3D_LUMP_BURNER)) l[i].heat_release = F3D_R(0.0);
    }
  }
  if (l != NULL) {
    body_from_lumps(world, s);
    return 1;
  }
  s->fuel = s->mass * m.fuel_fraction;
  if (s->fuel <= F3D_R(0.0) || !burns) {
    if (!(s->feed > F3D_R(0.0))) {
      s->flags &= (uint8_t)~F3D_FLAG_BURNING;
      s->heat_release = F3D_R(0.0);
    }
    s->flags &= (uint8_t)~F3D_FLAG_OWN_FIRE;
    s->involved = F3D_R(0.0);
    s->spread = F3D_R(0.0);
    s->rise = F3D_R(0.0);
    s->patch = F3D_R(0.0);
    s->exposure = F3D_R(0.0);
  }
  return 1;
}

int f3d_body_set_burner(F3dWorld *world, F3dBody body, f3d_real kg_per_second,
                        const F3dMaterial *fuel) {
  F3dSlot *s = f3d_slot_of(world, body);
  if (s == NULL || !in_range(kg_per_second, F3D_R(0.0), F3D_R(1e30))) return 0;
  const F3dMaterial f = fuel != NULL ? *fuel : s->material;
  if (kg_per_second > F3D_R(0.0) &&
      !(material_ok(&f) && f.heat_of_combustion > F3D_R(0.0) &&
        f.flame_temperature > F3D_R(0.0))) {
    return 0;
  }
  s->feed = kg_per_second;
  s->burner = f;
  return 1;
}

int f3d_body_set_temperature(F3dWorld *world, F3dBody body, f3d_real kelvin) {
  F3dSlot *s = f3d_slot_of(world, body);
  if (s == NULL || !(f3d_finite(kelvin) && kelvin > F3D_R(0.0))) return 0;
  F3dLump *l = lumps_of(world, s);
  for (uint32_t i = 0; l != NULL && i < s->lump_count; i++) {
    l[i].temperature = kelvin;
    l[i].interior = kelvin;
    l[i].reached = F3D_R(0.0);
    l[i].skin = kelvin;
  }
  s->temperature = kelvin;
  s->interior = kelvin;
  s->reached = F3D_R(0.0);
  s->skin = kelvin;
  return 1;
}

/* The part [part] of [body]'s heat, or null: a compound's part, or part
 * nought of any other body, which is the body. */
static int part_ok(const F3dSlot *s, uint32_t part) {
  if (s->shape == F3D_SHAPE_COMPOUND) return 1;
  return part == 0;
}

int f3d_body_get_part_temperature(F3dWorld *world, F3dBody body, uint32_t part,
                                  f3d_real *out) {
  F3dSlot *s = f3d_slot_of(world, body);
  if (s == NULL || out == NULL || !part_ok(s, part)) return 0;
  F3dLump *l = lumps_of(world, s);
  if (l == NULL) {
    if (s->shape == F3D_SHAPE_COMPOUND) return 0;
    *out = s->temperature;
    return 1;
  }
  if (part >= s->lump_count) return 0;
  *out = l[part].temperature;
  return 1;
}

int f3d_body_set_part_temperature(F3dWorld *world, F3dBody body, uint32_t part,
                                  f3d_real kelvin) {
  F3dSlot *s = f3d_slot_of(world, body);
  if (s == NULL || !part_ok(s, part) ||
      !(f3d_finite(kelvin) && kelvin > F3D_R(0.0))) {
    return 0;
  }
  F3dLump *l = lumps_of(world, s);
  if (l == NULL) {
    if (s->shape == F3D_SHAPE_COMPOUND) return 0;
    return f3d_body_set_temperature(world, body, kelvin);
  }
  if (part >= s->lump_count) return 0;
  l[part].temperature = kelvin;
  l[part].interior = kelvin;
  l[part].reached = F3D_R(0.0);
  l[part].skin = kelvin;
  body_from_lumps(world, s);
  return 1;
}

int f3d_body_is_part_burning(F3dWorld *world, F3dBody body, uint32_t part,
                             int *out) {
  F3dSlot *s = f3d_slot_of(world, body);
  if (s == NULL || out == NULL || !part_ok(s, part)) return 0;
  F3dLump *l = lumps_of(world, s);
  if (l == NULL) {
    if (s->shape == F3D_SHAPE_COMPOUND) return 0;
    *out = (s->flags & F3D_FLAG_BURNING) != 0;
    return 1;
  }
  if (part >= s->lump_count) return 0;
  *out = l[part].burning != 0;
  return 1;
}

int f3d_body_add_heat_at(F3dWorld *world, F3dBody body, f3d_real x, f3d_real y,
                         f3d_real z, f3d_real joules) {
  F3dSlot *s = f3d_slot_of(world, body);
  if (s == NULL || !(f3d_finite(x) && f3d_finite(y) && f3d_finite(z) &&
                     f3d_finite(joules))) {
    return 0;
  }
  F3dLump *l = lumps_of(world, s);
  if (l == NULL) {
    s->heat += joules;
    return 1;
  }
  /* Into the part whose centre is nearest the point. */
  const F3dPlaced whole = f3d_placed_of(world, s);
  const F3dVec3 p = f3d_v3(x, y, z);
  uint32_t best = 0;
  f3d_real d2 = F3D_R(-1.0);
  for (uint32_t i = 0; i < s->lump_count; i++) {
    const F3dVec3 d = f3d_sub(f3d_placed_part(&whole, i).at, p);
    const f3d_real e = f3d_dot(d, d);
    if (d2 < F3D_R(0.0) || e < d2) {
      d2 = e;
      best = i;
    }
  }
  l[best].heat += joules;
  return 1;
}

int f3d_body_hold_flame(F3dWorld *world, F3dBody body, f3d_real x, f3d_real y,
                        f3d_real z, f3d_real flux, f3d_real area,
                        f3d_real temperature) {
  F3dSlot *s = f3d_slot_of(world, body);
  if (s == NULL || !(f3d_finite(x) && f3d_finite(y) && f3d_finite(z)) ||
      !in_range(flux, F3D_R(0.0), F3D_R(1e30)) || !in_range(area, F3D_R(0.0), F3D_R(1e30)) ||
      !(f3d_finite(temperature) && temperature > F3D_R(0.0))) {
    return 0;
  }
  s->held_at = f3d_v3(x, y, z);
  s->held_flux = flux;
  s->held_area = area;
  s->held_temperature = temperature;
  if (flux > F3D_R(0.0) && area > F3D_R(0.0)) f3d_wake(world, s);
  return 1;
}

int f3d_body_get_temperature(const F3dWorld *world, F3dBody body,
                             f3d_real *out) {
  const F3dSlot *s = f3d_slot_of(world, body);
  if (s == NULL) return 0;
  *out = s->temperature;
  return 1;
}

int f3d_body_get_surface_temperature(const F3dWorld *world, F3dBody body,
                                     f3d_real *out) {
  const F3dSlot *s = f3d_slot_of(world, body);
  if (s == NULL || out == NULL) return 0;
  /* Where it burns, its char's; elsewhere the wood's, by area. */
  const f3d_real alight = (s->flags & F3D_FLAG_OWN_FIRE) && s->surface > F3D_R(0.0) &&
                                  s->charred > F3D_R(0.0)
                              ? f3d_min(s->involved / s->surface, F3D_R(1.0))
                              : F3D_R(0.0);
  *out = s->skin + alight * (s->char_skin - s->skin);
  return 1;
}

int f3d_body_add_heat(F3dWorld *world, F3dBody body, f3d_real joules) {
  F3dSlot *s = f3d_slot_of(world, body);
  if (s == NULL || !f3d_finite(joules)) return 0;
  s->heat += joules;
  return 1;
}

int f3d_body_add_water(F3dWorld *world, F3dBody body, f3d_real kg) {
  F3dSlot *s = f3d_slot_of(world, body);
  if (s == NULL || !f3d_finite(kg)) return 0;
  F3dLump *l = lumps_of(world, s);
  if (l != NULL) {
    /* Over a compound's parts by their surfaces. */
    f3d_real surface = F3D_R(0.0);
    const F3dCompound *c = &world->compounds[s->hull - 1u];
    for (uint32_t i = 0; i < s->lump_count; i++) {
      surface += f3d_shape_surface(world, world->compound_parts[c->first_part + i].kind,
                                   world->compound_parts[c->first_part + i].size,
                                   world->compound_parts[c->first_part + i].rounding,
                                   world->compound_parts[c->first_part + i].hull);
    }
    for (uint32_t i = 0; i < s->lump_count; i++) {
      const F3dCompoundPart *p = &world->compound_parts[c->first_part + i];
      const f3d_real share =
          surface > F3D_R(0.0)
              ? f3d_shape_surface(world, p->kind, p->size, p->rounding, p->hull) / surface
              : F3D_R(1.0) / (f3d_real)s->lump_count;
      const f3d_real add = kg * share;
      if (add > F3D_R(0.0)) {
        const f3d_real held = l[i].mass * s->material.specific_heat +
                              l[i].water * F3D_MAT_WATER_SPECIFIC_HEAT;
        const f3d_real added = add * F3D_MAT_WATER_SPECIFIC_HEAT;
        const f3d_real was = l[i].temperature;
        l[i].temperature = (held * l[i].temperature +
                            added * world->s.air_temperature) /
                           (held + added);
        /* Mixed all through: the whole of it moves alike. */
        l[i].interior += l[i].temperature - was;
        l[i].skin += l[i].temperature - was;
      }
      l[i].water = f3d_max(l[i].water + add, F3D_R(0.0));
    }
    body_from_lumps(world, s);
    return 1;
  }
  if (kg > F3D_R(0.0)) {
    /* It lands at the air's temperature and mixes with what is there:
     * counted at the body's own, it would bring heat from nowhere. Taken
     * off, it leaves at the body's, and the body's temperature stays. */
    const f3d_real body_heat = capacity_of(s);
    const f3d_real added = kg * F3D_MAT_WATER_SPECIFIC_HEAT;
    const f3d_real was = s->temperature;
    s->temperature = (body_heat * s->temperature +
                      added * world->s.air_temperature) /
                     (body_heat + added);
    /* Mixed all through: the whole of it moves alike. */
    s->interior += s->temperature - was;
    s->skin += s->temperature - was;
  }
  s->water = f3d_max(s->water + kg, F3D_R(0.0));
  return 1;
}

int f3d_body_get_water(const F3dWorld *world, F3dBody body, f3d_real *out) {
  const F3dSlot *s = f3d_slot_of(world, body);
  if (s == NULL) return 0;
  *out = s->water;
  return 1;
}

int f3d_body_get_fuel(const F3dWorld *world, F3dBody body, f3d_real *out) {
  const F3dSlot *s = f3d_slot_of(world, body);
  if (s == NULL) return 0;
  *out = s->fuel;
  return 1;
}

int f3d_body_is_burning(const F3dWorld *world, F3dBody body, int *out) {
  const F3dSlot *s = f3d_slot_of(world, body);
  if (s == NULL) return 0;
  *out = (s->flags & F3D_FLAG_BURNING) != 0;
  return 1;
}

int f3d_body_get_heat_release(const F3dWorld *world, F3dBody body,
                              f3d_real *out) {
  const F3dSlot *s = f3d_slot_of(world, body);
  if (s == NULL) return 0;
  *out = s->heat_release;
  return 1;
}

int f3d_body_get_char(const F3dWorld *world, F3dBody body, f3d_real *share,
                      f3d_real *depth, f3d_real *temperature) {
  const F3dSlot *s = f3d_slot_of(world, body);
  if (s == NULL) return 0;
  if (share != NULL) {
    *share = s->surface > F3D_R(0.0) ? f3d_min(s->charred / s->surface, F3D_R(1.0))
                                     : F3D_R(0.0);
  }
  if (depth != NULL) *depth = s->charred > F3D_R(0.0) ? s->char_depth : F3D_R(0.0);
  if (temperature != NULL) {
    *temperature = (s->flags & F3D_FLAG_OWN_FIRE) && s->charred > F3D_R(0.0)
                       ? s->char_skin
                       : s->skin;
  }
  return 1;
}

int f3d_body_get_submerged(const F3dWorld *world, F3dBody body, f3d_real *volume,
                           F3dShallow *water) {
  const F3dSlot *s = f3d_slot_of(world, body);
  if (s == NULL) return 0;
  if (volume != NULL) *volume = s->submerged;
  if (water != NULL) *water = s->liquid;
  return 1;
}

/* ------------------------------------------------------------ the maths */

/* x^(1/3), x^(2/5), ln x and e^y, by Newton's method and series: the
 * core's own, so the same bits everywhere. */
static f3d_real cube_root(f3d_real x) {
  if (!(x > F3D_R(0.0))) return F3D_R(0.0);
  if (!f3d_finite(x)) return x;
  f3d_real scale = F3D_R(1.0);
  while (x >= F3D_R(8.0)) {
    x *= F3D_R(0.125);
    scale *= F3D_R(2.0);
  }
  while (x < F3D_R(1.0)) {
    x *= F3D_R(8.0);
    scale *= F3D_R(0.5);
  }
  f3d_real y = F3D_R(1.0) + (x - F3D_R(1.0)) / F3D_R(7.0);
  for (int i = 0; i < 40; i++) {
    const f3d_real next = y - (y * y * y - x) / (F3D_R(3.0) * y * y);
    if (i > 0 && !(next < y)) break;
    y = next;
  }
  return y * scale;
}

static f3d_real two_fifths(f3d_real x) {
  if (!(x > F3D_R(0.0))) return F3D_R(0.0);
  const f3d_real x2 = x * x;
  f3d_real y = f3d_sqrt(f3d_sqrt(x));
  for (int i = 0; i < 12; i++) {
    const f3d_real y4 = y * y * y * y;
    y -= (y4 * y - x2) / (F3D_R(5.0) * y4);
  }
  return y;
}

static f3d_real natural_log(f3d_real x) {
  if (!(x > F3D_R(0.0))) return F3D_R(0.0);
  if (!f3d_finite(x)) return x;
  int k = 0;
  while (x >= F3D_R(2.0)) {
    x *= F3D_R(0.5);
    k++;
  }
  while (x < F3D_R(1.0)) {
    x *= F3D_R(2.0);
    k--;
  }
  const f3d_real t = (x - F3D_R(1.0)) / (x + F3D_R(1.0));
  const f3d_real t2 = t * t;
  f3d_real term = t, sum = F3D_R(0.0);
  for (int n = 1; n < 30; n += 2) {
    sum += term / (f3d_real)n;
    term *= t2;
  }
  return F3D_R(2.0) * sum + (f3d_real)k * F3D_R(0.69314718055994531);
}

static f3d_real natural_exp(f3d_real y) {
  const f3d_real ln2 = F3D_R(0.69314718055994531);
  if (!(y > F3D_R(-700.0))) return F3D_R(0.0);
  if (y > F3D_R(700.0)) return y;
  int k = 0;
  while (y >= ln2) {
    y -= ln2;
    k++;
  }
  while (y < F3D_R(0.0)) {
    y += ln2;
    k--;
  }
  f3d_real term = F3D_R(1.0), sum = F3D_R(1.0);
  for (int n = 1; n < 20; n++) {
    term *= y / (f3d_real)n;
    sum += term;
  }
  for (; k > 0; k--) sum *= F3D_R(2.0);
  for (; k < 0; k++) sum *= F3D_R(0.5);
  return sum;
}

/* x^a for x > 0; nought otherwise. */
static f3d_real power(f3d_real x, f3d_real a) {
  if (!(x > F3D_R(0.0))) return F3D_R(0.0);
  return natural_exp(a * natural_log(x));
}

/* e^(−x) for x ≥ 0. */
static f3d_real decay(f3d_real x) {
  return natural_exp(-f3d_max(x, F3D_R(0.0)));
}

/* ---------------------------------------------------------- convection */

/* Dry air at one atmosphere (Incropera and DeWitt, Fundamentals of Heat
 * and Mass Transfer, table A.4): by temperature, K, its kinematic
 * viscosity, m²/s, conductivity, W/(m K), and Prandtl number. */
#define F3D_AIR_ROWS 16u
static const f3d_real air_t[F3D_AIR_ROWS] = {
    F3D_R(250.0),  F3D_R(300.0),  F3D_R(350.0),  F3D_R(400.0),
    F3D_R(450.0),  F3D_R(500.0),  F3D_R(600.0),  F3D_R(700.0),
    F3D_R(800.0),  F3D_R(900.0),  F3D_R(1000.0), F3D_R(1100.0),
    F3D_R(1200.0), F3D_R(1300.0), F3D_R(1400.0), F3D_R(1500.0)};
static const f3d_real air_nu[F3D_AIR_ROWS] = {
    F3D_R(11.44e-6), F3D_R(15.89e-6), F3D_R(20.92e-6), F3D_R(26.41e-6),
    F3D_R(32.39e-6), F3D_R(38.79e-6), F3D_R(52.69e-6), F3D_R(68.10e-6),
    F3D_R(84.93e-6), F3D_R(102.9e-6), F3D_R(121.9e-6), F3D_R(141.8e-6),
    F3D_R(162.9e-6), F3D_R(185.1e-6), F3D_R(213.0e-6), F3D_R(240.0e-6)};
static const f3d_real air_k[F3D_AIR_ROWS] = {
    F3D_R(22.3e-3), F3D_R(26.3e-3), F3D_R(30.0e-3), F3D_R(33.8e-3),
    F3D_R(37.3e-3), F3D_R(40.7e-3), F3D_R(46.9e-3), F3D_R(52.4e-3),
    F3D_R(57.3e-3), F3D_R(62.0e-3), F3D_R(66.7e-3), F3D_R(71.5e-3),
    F3D_R(76.3e-3), F3D_R(82.0e-3), F3D_R(91.0e-3), F3D_R(100.0e-3)};
static const f3d_real air_pr[F3D_AIR_ROWS] = {
    F3D_R(0.720), F3D_R(0.707), F3D_R(0.700), F3D_R(0.690),
    F3D_R(0.686), F3D_R(0.684), F3D_R(0.685), F3D_R(0.695),
    F3D_R(0.709), F3D_R(0.716), F3D_R(0.726), F3D_R(0.728),
    F3D_R(0.728), F3D_R(0.719), F3D_R(0.703), F3D_R(0.685)};
/* Dry air's specific gas constant, J / (kg K): the molar gas constant over
 * dry air's molar mass, both from f3d_materials.g.h. */
#define F3D_DRY_AIR_R (F3D_GAS_CONSTANT / F3D_MOLAR_MASS_OF_DRY_AIR)

typedef struct Air {
  f3d_real nu, k, pr;
} Air;

/* Air at [t] K, read between the table's rows and held at its ends. Its
 * viscosity μ does not change with pressure but ν = μ/ρ does: the world's
 * air, as dense as it is set, has ν by its density against an
 * atmosphere's at its temperature. */
static Air air_at(const F3dWorld *world, f3d_real t) {
  uint32_t i = 0;
  while (i + 2u < F3D_AIR_ROWS && t > air_t[i + 1u]) i++;
  const f3d_real f = f3d_clamp((t - air_t[i]) / (air_t[i + 1u] - air_t[i]),
                               F3D_R(0.0), F3D_R(1.0));
  Air a;
  a.nu = air_nu[i] + f * (air_nu[i + 1u] - air_nu[i]);
  a.k = air_k[i] + f * (air_k[i + 1u] - air_k[i]);
  a.pr = air_pr[i] + f * (air_pr[i + 1u] - air_pr[i]);
  const f3d_real ta = world->s.air_temperature;
  if (world->s.air_density > F3D_R(0.0) && ta > F3D_R(0.0)) {
    a.nu *= F3D_STANDARD_ATMOSPHERE / (F3D_DRY_AIR_R * ta) / world->s.air_density;
  }
  return a;
}

/* W / (m² K) from a body [d] across, as a ball of its surface, at [ts] to
 * a gas at [tg] moving past it at [u] m/s. Forced: Whitaker's sphere,
 * Nu = 2 + (0.4 Re^½ + 0.06 Re^⅔) Pr^0.4 (Whitaker, AIChE J. 18, 1972),
 * with the properties at the film's temperature in place of his viscosity
 * ratio. Natural: Churchill's sphere, Nu = 2 + 0.589 Ra^¼ /
 * (1 + (0.469/Pr)^(9/16))^(4/9) (Churchill, 1983; Incropera eq. 9.35).
 * Together, past the conduction both start from, as the cube root of the
 * sum of their cubes, Churchill's rule for flows that help each other
 * (Incropera eq. 9.36). In still air a big hot body cools by its
 * buoyancy, a small one by conduction, and wind takes over from both. */
static f3d_real nusselt(f3d_real re, f3d_real ra, f3d_real pr) {
  const f3d_real third = cube_root(re);
  const f3d_real forced = (F3D_R(0.4) * f3d_sqrt(re) + F3D_R(0.06) * third * third) *
                          power(pr, F3D_R(0.4));
  const f3d_real natural =
      F3D_R(0.589) * f3d_sqrt(f3d_sqrt(ra)) /
      power(F3D_R(1.0) + power(F3D_R(0.469) / pr, F3D_R(0.5625)),
            F3D_R(4.0) / F3D_R(9.0));
  return F3D_R(2.0) + cube_root(forced * forced * forced + natural * natural * natural);
}

static f3d_real gravity_of(const F3dWorld *world) {
  return f3d_sqrt(f3d_dot(world->s.gravity, world->s.gravity));
}

static f3d_real convection(const F3dWorld *world, f3d_real d, f3d_real u,
                           f3d_real ts, f3d_real tg) {
  if (!(d > F3D_R(0.0))) return F3D_R(0.0);
  const f3d_real film = f3d_max(F3D_R(0.5) * (ts + tg), F3D_R(1.0));
  const Air air = air_at(world, film);
  const f3d_real re = f3d_abs(u) * d / air.nu;
  /* Ra = gβΔT d³ / (να), a gas's β its 1/T and α its ν/Pr. */
  const f3d_real ra = gravity_of(world) * f3d_abs(ts - tg) * d * d * d * air.pr /
                      (film * air.nu * air.nu);
  return nusselt(re, ra, air.pr) * air.k / d;
}

/* The same from a body [d] across at [ts] to the liquid of [w], moving
 * past it at [u]: with the liquid's own viscosity ν = μ/ρ, diffusivity
 * α = k/(ρc), Prandtl number ν/α and expansion β. */
static f3d_real liquid_convection(const F3dWorld *world, const F3dShallowSlot *w,
                                  f3d_real d, f3d_real u, f3d_real ts) {
  if (!(d > F3D_R(0.0))) return F3D_R(0.0);
  const f3d_real nu = w->viscosity / w->density;
  const f3d_real alpha = w->conductivity / (w->density * w->specific_heat);
  const f3d_real re = f3d_abs(u) * d / nu;
  const f3d_real ra = gravity_of(world) * w->expansion * f3d_abs(ts - w->temperature) *
                      d * d * d / (nu * alpha);
  return nusselt(re, ra, nu / alpha) * w->conductivity / d;
}

/* ------------------------------------------------------------- boiling */

/* Saturated water at one atmosphere, 373.15 K (Incropera and DeWitt,
 * table A.6): the liquid's density, specific heat, viscosity and Prandtl
 * number, its surface tension, the heat of vaporisation, and the vapour's
 * density. A table at the boiling point, not water at 20 °C: its
 * temperature and its heat of vaporisation are the catalogue's water's
 * boiling point and latent heat, so the one-atmosphere point is one
 * number. The boiling model assumes one atmosphere throughout. */
#define F3D_SAT_T F3D_MAT_WATER_BOILING_POINT
#define F3D_SAT_RHO_L F3D_R(957.9)
#define F3D_SAT_C_L F3D_R(4217.0)
#define F3D_SAT_MU_L F3D_R(279e-6)
#define F3D_SAT_PR_L F3D_R(1.76)
#define F3D_SAT_SIGMA F3D_R(58.9e-3)
#define F3D_SAT_HFG F3D_MAT_WATER_LATENT_HEAT_OF_VAPORIZATION
#define F3D_SAT_RHO_V F3D_R(0.5955)
/* Rohsenow's surface constant for water, and his exponent of its Prandtl
 * number for water (Incropera, table 10.1 and eq. 10.5). */
#define F3D_ROHSENOW_C F3D_R(0.013)

/* Steam at one atmosphere (Incropera and DeWitt, table A.4): by
 * temperature, K, its density, kg/m³, specific heat, J/(kg K), viscosity,
 * Pa·s, and conductivity, W/(m K). */
#define F3D_STEAM_ROWS 11u
static const f3d_real steam_t[F3D_STEAM_ROWS] = {
    F3D_R(380.0), F3D_R(400.0), F3D_R(450.0), F3D_R(500.0), F3D_R(550.0), F3D_R(600.0),
    F3D_R(650.0), F3D_R(700.0), F3D_R(750.0), F3D_R(800.0), F3D_R(850.0)};
static const f3d_real steam_rho[F3D_STEAM_ROWS] = {
    F3D_R(0.5863), F3D_R(0.5542), F3D_R(0.4902), F3D_R(0.4405), F3D_R(0.4005), F3D_R(0.3652),
    F3D_R(0.3380), F3D_R(0.3140), F3D_R(0.2931), F3D_R(0.2739), F3D_R(0.2579)};
static const f3d_real steam_c[F3D_STEAM_ROWS] = {
    F3D_R(2060.0), F3D_R(2014.0), F3D_R(1980.0), F3D_R(1985.0), F3D_R(1997.0), F3D_R(2026.0),
    F3D_R(2056.0), F3D_R(2085.0), F3D_R(2119.0), F3D_R(2152.0), F3D_R(2186.0)};
static const f3d_real steam_mu[F3D_STEAM_ROWS] = {
    F3D_R(127.1e-7), F3D_R(134.4e-7), F3D_R(152.5e-7), F3D_R(170.4e-7), F3D_R(188.4e-7),
    F3D_R(206.7e-7), F3D_R(224.7e-7), F3D_R(242.6e-7), F3D_R(260.4e-7), F3D_R(278.6e-7),
    F3D_R(296.9e-7)};
static const f3d_real steam_k[F3D_STEAM_ROWS] = {
    F3D_R(24.6e-3), F3D_R(26.1e-3), F3D_R(29.9e-3), F3D_R(33.9e-3), F3D_R(37.9e-3),
    F3D_R(42.2e-3), F3D_R(46.4e-3), F3D_R(50.5e-3), F3D_R(54.9e-3), F3D_R(59.2e-3),
    F3D_R(63.7e-3)};

/* W/m² nucleate boiling carries at [excess] K over saturation (Rohsenow,
 * 1952; Incropera eq. 10.5). */
static f3d_real nucleate(f3d_real excess, f3d_real g) {
  const f3d_real x = F3D_SAT_C_L * f3d_max(excess, F3D_R(0.0)) /
                     (F3D_ROHSENOW_C * F3D_SAT_HFG * F3D_SAT_PR_L);
  return F3D_SAT_MU_L * F3D_SAT_HFG *
         f3d_sqrt(g * (F3D_SAT_RHO_L - F3D_SAT_RHO_V) / F3D_SAT_SIGMA) * x * x * x;
}

/* W/m² film boiling carries from a body [d] across of emissivity [e] at
 * [excess] K over saturation: Bromley's, Nu = 0.67 (g (ρ_l − ρ_v) h'_fg d³
 * / (ν_v k_v ΔT))^¼ with h'_fg = h_fg + 0.8 c_v ΔT and the vapour at the
 * film's temperature, and the radiation across the film added as
 * h = h_conv + ¾ h_rad (Incropera eqs. 10.9 to 10.12). */
static f3d_real film_boiling(f3d_real excess, f3d_real d, f3d_real e, f3d_real g) {
  if (!(excess > F3D_R(0.0) && d > F3D_R(0.0))) return F3D_R(0.0);
  const f3d_real film = F3D_SAT_T + F3D_R(0.5) * excess;
  uint32_t i = 0;
  while (i + 2u < F3D_STEAM_ROWS && film > steam_t[i + 1u]) i++;
  const f3d_real f = f3d_clamp((film - steam_t[i]) / (steam_t[i + 1u] - steam_t[i]),
                               F3D_R(0.0), F3D_R(1.0));
  const f3d_real rho = steam_rho[i] + f * (steam_rho[i + 1u] - steam_rho[i]);
  const f3d_real c = steam_c[i] + f * (steam_c[i + 1u] - steam_c[i]);
  const f3d_real mu = steam_mu[i] + f * (steam_mu[i + 1u] - steam_mu[i]);
  const f3d_real k = steam_k[i] + f * (steam_k[i + 1u] - steam_k[i]);
  const f3d_real hfg = F3D_SAT_HFG + F3D_R(0.8) * c * excess;
  const f3d_real ra = g * (F3D_SAT_RHO_L - rho) * hfg * d * d * d / (mu / rho * k * excess);
  const f3d_real h_conv = F3D_R(0.67) * f3d_sqrt(f3d_sqrt(ra)) * k / d;
  const f3d_real ts = F3D_SAT_T + excess;
  const f3d_real h_rad = e * F3D_STEFAN_BOLTZMANN * (ts * ts + F3D_SAT_T * F3D_SAT_T) *
                         (ts + F3D_SAT_T);
  return (h_conv + F3D_R(0.75) * h_rad) * excess;
}

/* W/m² boiling water carries from a body [d] across of emissivity [e] at
 * [excess] K over saturation, along the boiling curve: nucleate up to the
 * critical flux, q_max = 0.149 h_fg ρ_v (σ g (ρ_l − ρ_v) / ρ_v²)^¼ (Zuber);
 * film past the Leidenfrost point, where film boiling falls to its least,
 * q_min = 0.09 ρ_v h_fg (g σ (ρ_l − ρ_v) / (ρ_l + ρ_v)²)^¼ (Zuber, Berenson);
 * and between them the transition, straight between the two in log q and
 * log ΔT. */
static f3d_real boiling(f3d_real excess, f3d_real d, f3d_real e, f3d_real g) {
  if (!(excess > F3D_R(0.0) && g > F3D_R(0.0))) return F3D_R(0.0);
  const f3d_real drho = F3D_SAT_RHO_L - F3D_SAT_RHO_V;
  const f3d_real q_max =
      F3D_R(0.149) * F3D_SAT_HFG * F3D_SAT_RHO_V *
      f3d_sqrt(f3d_sqrt(F3D_SAT_SIGMA * g * drho / (F3D_SAT_RHO_V * F3D_SAT_RHO_V)));
  /* Nucleate boiling goes as ΔT³: where it reaches the critical flux. */
  const f3d_real at_max = cube_root(q_max / nucleate(F3D_R(1.0), g));
  if (excess <= at_max) return nucleate(excess, g);
  const f3d_real sum = F3D_SAT_RHO_L + F3D_SAT_RHO_V;
  const f3d_real q_min = F3D_R(0.09) * F3D_SAT_RHO_V * F3D_SAT_HFG *
                         f3d_sqrt(f3d_sqrt(g * F3D_SAT_SIGMA * drho / (sum * sum)));
  /* Past Leidenfrost's point the film is all there is — from the critical
   * point on, for a film that holds there already. */
  const f3d_real film = film_boiling(excess, d, e, g);
  if (film >= q_min) return film;
  /* Leidenfrost's point, where film boiling carries q_min: past [excess],
   * found by halving — film boiling grows with the excess. */
  f3d_real lo = excess, hi = excess * F3D_R(2.0);
  while (film_boiling(hi, d, e, g) < q_min && hi < F3D_R(1e5)) {
    lo = hi;
    hi *= F3D_R(2.0);
  }
  for (int k = 0; k < 48; k++) {
    const f3d_real mid = F3D_R(0.5) * (lo + hi);
    if (film_boiling(mid, d, e, g) < q_min) {
      lo = mid;
    } else {
      hi = mid;
    }
  }
  const f3d_real at_min = hi;
  const f3d_real t = natural_log(excess / at_max) / natural_log(at_min / at_max);
  return natural_exp(natural_log(q_max) + t * (natural_log(q_min) - natural_log(q_max)));
}

/* J/K the body holds: its own and its water's. */
static f3d_real capacity_of(const F3dSlot *s) {
  return s->mass * s->material.specific_heat + s->water * F3D_MAT_WATER_SPECIFIC_HEAT;
}

/* ------------------------------------------------------------- contact */

/* Twice the area of the polygon a, b, c, d in that order, seen along n. */
static f3d_real quad2(F3dVec3 a, F3dVec3 b, F3dVec3 c, F3dVec3 d, F3dVec3 n) {
  return f3d_abs(f3d_dot(f3d_cross(f3d_sub(c, a), f3d_sub(d, b)), n));
}

/* The area two bodies touch over, m². A face on a face — three points or
 * four — touches over the polygon its points span; of four points in
 * whatever order, the largest of the three ways round is the convex one.
 * Anything curved touches as Hertz says, pressed by [load], N, with the
 * surfaces' radii [ra] and [rb] there — nought for flat — and their
 * compliances (1 − ν²)/E summed in [compliance]: a point over a circle of
 * radius a = (3 F R / 4E*)^(1/3), a line of length ℓ over a strip
 * 2b wide with b = (4 F R / (π ℓ E*))^(1/2), R the two radii in series
 * (Johnson, Contact Mechanics, §4.2 and §4.3). Two flat faces meeting at
 * a point or an edge touch over nothing, unless rounded. */
static f3d_real contact_area(const F3dManifold *m, f3d_real load, f3d_real ra,
                             f3d_real rb, f3d_real compliance) {
  const F3dVec3 n = m->normal;
  const F3dContactPoint *p = m->points;
  if (m->count == 3) {
    return F3D_R(0.5) * f3d_abs(f3d_dot(f3d_cross(f3d_sub(p[1].point, p[0].point),
                                                  f3d_sub(p[2].point, p[0].point)),
                                        n));
  }
  if (m->count >= 4) {
    const f3d_real a = quad2(p[0].point, p[1].point, p[2].point, p[3].point, n);
    const f3d_real b = quad2(p[0].point, p[1].point, p[3].point, p[2].point, n);
    const f3d_real c = quad2(p[0].point, p[2].point, p[1].point, p[3].point, n);
    return F3D_R(0.5) * f3d_max(a, f3d_max(b, c));
  }
  const f3d_real curvature = (ra > F3D_R(0.0) ? F3D_R(1.0) / ra : F3D_R(0.0)) +
                             (rb > F3D_R(0.0) ? F3D_R(1.0) / rb : F3D_R(0.0));
  if (!(curvature > F3D_R(0.0) && load > F3D_R(0.0) && compliance > F3D_R(0.0))) {
    return F3D_R(0.0);
  }
  const f3d_real r = F3D_R(1.0) / curvature;
  if (m->count == 2) {
    const F3dVec3 d = f3d_sub(p[1].point, p[0].point);
    const f3d_real length = f3d_sqrt(f3d_dot(d, d));
    if (length > F3D_R(0.0)) {
      const f3d_real b = f3d_sqrt(F3D_R(4.0) * load * r * compliance / (F3D_PI * length));
      return F3D_R(2.0) * b * length;
    }
  }
  const f3d_real a = cube_root(F3D_R(0.75) * load * r * compliance);
  return F3D_PI * a * a;
}

/* ------------------------------------------------------------- lumps */

/* A compound's own record, or null for any other body. */
static const F3dCompound *compound_of(const F3dWorld *world, const F3dSlot *s) {
  if (s->shape != F3D_SHAPE_COMPOUND || s->hull == 0 ||
      s->hull > world->s.compound_count) {
    return NULL;
  }
  return &world->compounds[s->hull - 1u];
}

static const F3dCompoundPart *part_of(const F3dWorld *world,
                                      const F3dCompound *c, uint32_t i) {
  return &world->compound_parts[c->first_part + i];
}

static f3d_real part_volume(const F3dWorld *world, const F3dCompoundPart *p) {
  return f3d_shape_volume(world, p->kind, p->size, p->rounding, p->hull);
}

static f3d_real part_surface(const F3dWorld *world, const F3dCompoundPart *p) {
  return f3d_shape_surface(world, p->kind, p->size, p->rounding, p->hull);
}

/* Whether a body's own fuel burns: its flag, or, from a snapshot taken
 * before burners, its burning with none feeding it. */
static int own_fire(const F3dSlot *s) {
  if (s->flags & F3D_FLAG_OWN_FIRE) return 1;
  return (s->flags & F3D_FLAG_BURNING) != 0 && !(s->feed > F3D_R(0.0));
}

/* A compound's parts' heat, made from the body's: each part as hot as the
 * body, with its share of the mass and fuel by volume and of the water and
 * fire by surface. */
static void lumps_from_body(const F3dWorld *world, const F3dSlot *s,
                            const F3dCompound *c, F3dLump *out) {
  f3d_real volume = F3D_R(0.0), surface = F3D_R(0.0);
  for (uint32_t i = 0; i < c->part_count; i++) {
    volume += part_volume(world, part_of(world, c, i));
    surface += part_surface(world, part_of(world, c, i));
  }
  for (uint32_t i = 0; i < c->part_count; i++) {
    const F3dCompoundPart *p = part_of(world, c, i);
    const f3d_real by_volume = volume > F3D_R(0.0)
                                   ? part_volume(world, p) / volume
                                   : F3D_R(1.0) / (f3d_real)c->part_count;
    const f3d_real by_surface = surface > F3D_R(0.0)
                                    ? part_surface(world, p) / surface
                                    : F3D_R(1.0) / (f3d_real)c->part_count;
    F3dLump *l = &out[i];
    f3d_zero(l, sizeof *l);
    l->temperature = s->temperature;
    l->interior = s->interior;
    l->reached = s->reached;
    l->skin = s->skin;
    l->mass = s->mass * by_volume;
    l->fuel = s->fuel * by_volume;
    l->water = s->water * by_surface;
    if (own_fire(s) && s->involved > F3D_R(0.0)) {
      l->burning = F3D_LUMP_OWN;
      l->involved = s->involved * by_surface;
      l->spread = f3d_sqrt(l->involved / F3D_PI);
      l->patch = s->patch;
    }
    l->char_depth = s->char_depth;
    l->char_skin = s->char_skin;
    l->charred = s->charred * by_surface;
  }
}

/* Gives every live compound its parts' heat and drops what no live
 * compound holds: the world's lumps rebuilt in slot order when they no
 * longer match, a part's kept where its body kept its shape. 0 when memory
 * ran out. */
static int ensure_lumps(F3dWorld *world) {
  uint32_t need = 0;
  int fits = 1;
  for (uint32_t i = 0; i < world->s.used; i++) {
    const F3dSlot *s = &world->slots[i];
    const F3dCompound *c = s->live ? compound_of(world, s) : NULL;
    if (c == NULL) {
      if (s->lumps != 0) fits = 0;
      continue;
    }
    if (s->lumps == 0 || s->lump_count != c->part_count ||
        s->lumps - 1u + s->lump_count > world->s.lump_count ||
        s->lumps - 1u != need) {
      fits = 0;
    }
    need += c->part_count;
  }
  if (fits && need == world->s.lump_count) return 1;
  F3dLump *made = need > 0 ? (F3dLump *)f3d_alloc((size_t)need * sizeof(F3dLump))
                           : NULL;
  if (need > 0 && made == NULL) return 0;
  uint32_t at = 0;
  for (uint32_t i = 0; i < world->s.used; i++) {
    F3dSlot *s = &world->slots[i];
    const F3dCompound *c = s->live ? compound_of(world, s) : NULL;
    if (c == NULL) {
      s->lumps = 0;
      s->lump_count = 0;
      continue;
    }
    const int kept = s->lumps != 0 && s->lump_count == c->part_count &&
                     s->lumps - 1u + s->lump_count <= world->s.lump_count;
    if (kept) {
      f3d_copy(&made[at], &world->lumps[s->lumps - 1u],
               (size_t)c->part_count * sizeof(F3dLump));
    } else {
      lumps_from_body(world, s, c, &made[at]);
    }
    s->lumps = at + 1u;
    s->lump_count = c->part_count;
    at += c->part_count;
  }
  f3d_free(world->lumps);
  world->lumps = made;
  world->s.lump_count = need;
  return 1;
}

/* A compound body's whole from its parts: its temperature the parts'
 * weighted by what they hold, and its water, fuel, fire and mass theirs
 * summed. */
static void body_from_lumps(F3dWorld *world, F3dSlot *s) {
  if (s->lumps == 0) return;
  const F3dLump *l = &world->lumps[s->lumps - 1u];
  f3d_real held = F3D_R(0.0), warm = F3D_R(0.0), water = F3D_R(0.0);
  f3d_real fuel = F3D_R(0.0), release = F3D_R(0.0), mass = F3D_R(0.0);
  f3d_real involved = F3D_R(0.0), char_heat = F3D_R(0.0), char_depth = F3D_R(0.0);
  f3d_real charred = F3D_R(0.0);
  f3d_real inside = F3D_R(0.0), reached = F3D_R(0.0), skin = F3D_R(0.0);
  uint32_t burning = 0;
  for (uint32_t i = 0; i < s->lump_count; i++) {
    const f3d_real c = l[i].mass * s->material.specific_heat +
                       l[i].water * F3D_MAT_WATER_SPECIFIC_HEAT;
    held += c;
    warm += c * l[i].temperature;
    inside += c * l[i].interior;
    reached += c * l[i].reached;
    skin += c * l[i].skin;
    water += l[i].water;
    fuel += l[i].fuel;
    release += l[i].heat_release;
    involved += l[i].involved;
    char_heat += l[i].involved * l[i].char_skin;
    char_depth = f3d_max(char_depth, l[i].char_depth);
    charred += l[i].charred;
    mass += l[i].mass;
    burning |= l[i].burning;
  }
  if (held > F3D_R(0.0)) {
    s->temperature = warm / held;
    s->interior = inside / held;
    s->reached = reached / held;
    s->skin = skin / held;
  }
  s->water = water;
  s->fuel = fuel;
  s->heat_release = release;
  s->involved = involved;
  s->char_depth = char_depth;
  s->charred = charred;
  if (involved > F3D_R(0.0)) s->char_skin = char_heat / involved;
  s->flags &= (uint8_t)~(F3D_FLAG_BURNING | F3D_FLAG_OWN_FIRE);
  if (burning != 0) s->flags |= F3D_FLAG_BURNING;
  if (burning & F3D_LUMP_OWN) s->flags |= F3D_FLAG_OWN_FIRE;
  if (mass != s->mass) {
    s->mass = mass;
    f3d_refresh_mass(world, s);
  }
}

/* ---------------------------------------------------------- the step's */

/* How a body was heated where it was heated most this step, for whether
 * that spot catches: by what it touches, by a flame's gas, by radiation. */
enum { EXPOSED_NONE = 0, EXPOSED_CONTACT, EXPOSED_GAS, EXPOSED_RADIATION };

/* What heat sees for a step: a whole body, or one part of a compound,
 * worked on as a copy and written back at the end. */
typedef struct Heat {
  F3dLump l;
  uint32_t slot;
  F3dVec3 at;
  f3d_real surface;
  /* How big its cross-section is where a compound's parts meet. */
  f3d_real touch;
  /* How far it reaches from [at], for a compound's parts. */
  f3d_real reach;
  /* m³; and how many times further from the interior's temperature its
   * surface is than its mean, this step. */
  f3d_real volume;
  f3d_real gain;
  /* The diameter of the ball of its surface, m: what convection and
   * radiation see of it; its girth about its longest axis, m; how tall it
   * stands, m; and the radius its surface curves with where it touches,
   * nought for a flat face. */
  f3d_real size, girth, height, curve;
  /* The spot heated hardest this step: W/m² into it, over m², never past
   * the temperature [exposed_cap], and how (EXPOSED_*). */
  f3d_real exposed_flux, exposed_area, exposed_cap;
  uint32_t exposed;
  /* J given it on the bus for this step, apart from what other bodies
   * send it. */
  f3d_real bus;
  /* A burner's kg/s, and the fuel; and the material its flame is of. */
  f3d_real feed;
  const F3dMaterial *fuel;
  const F3dMaterial *flame;
  /* The liquid it stands in, null for none, and how fast it moves past;
   * the share of it under the surface is its lump's [immersed]. */
  const F3dShallowSlot *liquid;
  f3d_real liquid_speed;
  /* The coldest it gives heat to: the air, or a liquid it stands in. */
  f3d_real coldest;
} Heat;

/* Every live body's entries, and where each body's start. */
typedef struct Heats {
  Heat *h;
  uint32_t count;
  uint32_t *first, *many;
} Heats;

static f3d_real held_by(const F3dWorld *world, const Heat *h) {
  return h->l.mass * world->slots[h->slot].material.specific_heat +
         h->l.water * F3D_MAT_WATER_SPECIFIC_HEAT;
}

/* Its surface's temperature: as far from the interior's as the gain says. */
static f3d_real skin_of(const Heat *h) {
  /* Never colder than both the coldest thing it gives heat to and its own
   * insides: the parabola's tip, extrapolated from a layer only just begun,
   * can overshoot what a surface cooled by the air ever reaches. */
  const f3d_real floor =
      f3d_min(h->coldest, f3d_min(h->l.interior, h->l.temperature));
  return f3d_max(h->l.interior + h->gain * (h->l.temperature - h->l.interior), floor);
}

/* kρc, J² / (m⁴ K² s), its thermal inertia, with its density its mass
 * over its volume; nought for one with no volume. */
static f3d_real inertia_of(const F3dWorld *world, const Heat *h) {
  const F3dMaterial *m = &world->slots[h->slot].material;
  if (!(h->l.mass > F3D_R(0.0) && h->volume > F3D_R(0.0))) return F3D_R(0.0);
  return m->conductivity * (h->l.mass / h->volume) * m->specific_heat;
}

/* kρc as how soon it catches and how fast a flame's edge creeps over it
 * answer to: the material's measured one, or its own k, ρ and c. */
static f3d_real catching_inertia(const F3dWorld *world, const Heat *h) {
  const F3dMaterial *m = &world->slots[h->slot].material;
  return m->ignition_inertia > F3D_R(0.0) ? m->ignition_inertia : inertia_of(world, h);
}

/* How deep heat reaches into a porous bed, m: as far as radiation passes
 * between its elements, whose shadows over a unit of volume cover βσ/4 of
 * a plane — a mean free path of 4/(βσ), β the bed's packing, its density
 * over its elements' (Rothermel, USDA INT-115, 1972; Albini's radiant
 * penetration of fuel beds). Nought for a solid, or a bed with no mass;
 * never past its own thickness. */
static f3d_real bed_depth(const F3dWorld *world, const Heat *h) {
  const F3dMaterial *m = &world->slots[h->slot].material;
  if (!(m->element_surface > F3D_R(0.0) && m->element_density > F3D_R(0.0) &&
        h->volume > F3D_R(0.0) && h->surface > F3D_R(0.0) && h->l.mass > F3D_R(0.0))) {
    return F3D_R(0.0);
  }
  const f3d_real packing =
      f3d_min(h->l.mass / h->volume / m->element_density, F3D_R(1.0));
  return f3d_min(F3D_R(4.0) / (packing * m->element_surface), h->volume / h->surface);
}

/* s for a surface to rise [ahead] K under a net [flux] W/m². A solid's
 * surface: a thick solid's, t = (π/4) kρc (ΔT / q'')² (Quintiere,
 * Fundamentals of Fire Phenomena, §7.5). A porous bed's: its elements are
 * thermally thin and heat through, t = ρ_p c (V/A) ΔT / q'' with V/A =
 * 1/σ (Quintiere, §7.4). */
static f3d_real ignition_time(const F3dWorld *world, const Heat *h, f3d_real ahead,
                              f3d_real flux) {
  const F3dMaterial *m = &world->slots[h->slot].material;
  if (bed_depth(world, h) > F3D_R(0.0)) {
    return m->element_density * m->specific_heat * ahead / (m->element_surface * flux);
  }
  return F3D_R(0.25) * F3D_PI * catching_inertia(world, h) * (ahead / flux) * (ahead / flux);
}

/* Records a spot heated at [flux] over [area], never past [cap], when it
 * is the hardest heated this step. */
static void expose(Heat *h, uint32_t how, f3d_real flux, f3d_real area,
                   f3d_real cap) {
  if (!(flux > h->exposed_flux && area > F3D_R(0.0))) return;
  h->exposed = how;
  h->exposed_flux = flux;
  h->exposed_area = f3d_min(area, h->surface);
  h->exposed_cap = cap;
}

/* How heat lies in a body, by the heat balance integral (Goodman): from
 * the surface heat reaches in over a layer that thickens as δ² = 6αt
 * whatever warms or cools it, α = k/(ρc), and across the layer the
 * temperature falls off as a parabola to the interior's. A parabola holds a
 * third of its surface's excess, so the mean's excess over the interior is
 * the surface's times Aδ/3V, and the surface is 3V/(Aδ) times as far from
 * the interior as the mean is. Once the layer is as deep as the body is
 * thick, V/A, the interior warms too, at its slowest mode's rate (π/2)²α/L²,
 * and a body that is all one temperature again has no layer. A small or
 * conductive body gets there within a step and is one temperature
 * throughout; a log of wood takes hours, and its surface catches long
 * before its middle has warmed.
 *
 * The layer grows by this step's [dt] here; the gain is the step's. */
static void lay_heat(const F3dWorld *world, Heat *h, f3d_real dt) {
  const F3dMaterial *m = &world->slots[h->slot].material;
  h->gain = F3D_R(1.0);
  if (!(h->volume > F3D_R(0.0) && h->surface > F3D_R(0.0) &&
        h->l.mass > F3D_R(0.0) && m->specific_heat > F3D_R(0.0))) {
    return;
  }
  const f3d_real thick = h->volume / h->surface;
  /* A porous bed: what reaches it heats its elements through as deep as
   * radiation passes between them, alike, the bed below that as it was;
   * the surface's excess over the interior is the mean's times V/(Aδ). */
  const f3d_real bed = bed_depth(world, h);
  if (bed > F3D_R(0.0)) {
    h->l.reached = bed * bed;
    h->gain = thick / bed;
    return;
  }
  const f3d_real alpha =
      m->conductivity * h->volume / (h->l.mass * m->specific_heat);
  h->l.reached = f3d_min(h->l.reached + F3D_R(6.0) * alpha * dt, thick * thick);
  if (h->l.reached > F3D_R(0.0)) {
    h->gain = F3D_R(3.0) * thick / f3d_sqrt(h->l.reached);
  }
}

/* After the step: the interior warming once the layer is through, and a
 * body all one temperature, within a hundredth of a kelvin, starting a new
 * layer when it is next warmed or cooled. */
static void settle_heat(const F3dWorld *world, Heat *h, f3d_real dt) {
  F3dLump *l = &h->l;
  const F3dMaterial *m = &world->slots[h->slot].material;
  if (h->volume > F3D_R(0.0) && h->surface > F3D_R(0.0) &&
      l->mass > F3D_R(0.0) && m->specific_heat > F3D_R(0.0)) {
    const f3d_real thick = h->volume / h->surface;
    if (l->reached >= thick * thick) {
      const f3d_real alpha =
          m->conductivity * h->volume / (l->mass * m->specific_heat);
      const f3d_real x = F3D_R(0.25) * F3D_PI * F3D_PI * alpha * dt /
                         (thick * thick);
      l->interior += (l->temperature - l->interior) * x / (F3D_R(1.0) + x);
    }
  }
  if (f3d_abs(l->temperature - l->interior) <= F3D_R(0.01)) {
    l->interior = l->temperature;
    l->reached = F3D_R(0.0);
  }
}

/* The entry of a body that is nearest [p]: its only one, or the part. */
static Heat *nearest(Heats *hs, uint32_t slot, F3dVec3 p) {
  Heat *best = &hs->h[hs->first[slot]];
  f3d_real d2 = F3D_R(-1.0);
  for (uint32_t k = 0; k < hs->many[slot]; k++) {
    Heat *h = &hs->h[hs->first[slot] + k];
    const F3dVec3 d = f3d_sub(h->at, p);
    const f3d_real e = f3d_dot(d, d);
    if (d2 < F3D_R(0.0) || e < d2) {
      d2 = e;
      best = h;
    }
  }
  return best;
}

/* How readily [h]'s surface takes heat from a sudden touch, √(kρc); −1 for
 * one with no thermal mass or no volume to hold it — a reservoir, whose
 * surface a touch does not move. */
static f3d_real effusivity(const F3dWorld *world, const Heat *h) {
  const f3d_real e = inertia_of(world, h);
  return e > F3D_R(0.0) ? f3d_sqrt(e) : F3D_R(-1.0);
}

/* Heat across every contact that touches, each side's part nearest the
 * contact. The two press together with the push the solver gave them this
 * step and touch over the area Hertz gives that push (contact_area). The
 * conductance is Holm's constriction of two bodies meeting over a spot of
 * radius a, G = 4a / (1/k₁ + 1/k₂), a the radius of a circle of that area,
 * between their surfaces; and the exchange is taken implicitly for the
 * pair, each surface moving by its gain over its thermal mass, so it
 * carries the surfaces towards one temperature and never past it. In key
 * order, so the same world passes the same heat. */
static void conduct(F3dWorld *world, Heats *hs, f3d_real dt) {
  const f3d_real per_second = (f3d_real)world->s.substeps / dt;
  for (uint32_t i = 0; i < world->s.manifold_count; i++) {
    const F3dManifold *m = &world->manifolds[i];
    if (!m->touching || m->count == 0) continue;
    F3dSlot *sa = f3d_slot_of(world, m->a);
    F3dSlot *sb = f3d_slot_of(world, m->b);
    if (sa == NULL || sb == NULL) continue;
    const uint32_t ia_slot = (uint32_t)(m->a & 0xffffffffu);
    const uint32_t ib_slot = (uint32_t)(m->b & 0xffffffffu);
    if (hs->many[ia_slot] == 0 || hs->many[ib_slot] == 0) continue;
    F3dVec3 centre = f3d_v3(F3D_R(0.0), F3D_R(0.0), F3D_R(0.0));
    f3d_real push = F3D_R(0.0);
    for (uint32_t k = 0; k < m->count; k++) {
      centre = f3d_add(centre, m->points[k].point);
      push += m->points[k].normal_impulse;
    }
    centre = f3d_scale(centre, F3D_R(1.0) / (f3d_real)m->count);
    Heat *a = nearest(hs, ia_slot, centre);
    Heat *b = nearest(hs, ib_slot, centre);
    /* Where they meet, the two surfaces are at once at the temperature
     * their effusivities e = √(kρc) weigh them to — straw on a red-hot
     * stone is at nearly the stone's. That is as hot as the contact can
     * make the colder side's spot, however long it lasts. A side with no
     * thermal mass, or none it fills, holds the spot at its own. */
    const f3d_real ta = skin_of(a), tb = skin_of(b);
    const f3d_real ea = effusivity(world, a), eb = effusivity(world, b);
    const f3d_real meet = ea < F3D_R(0.0)   ? ta
                          : eb < F3D_R(0.0) ? tb
                                            : (ea * ta + eb * tb) / (ea + eb);
    const f3d_real ca = held_by(world, a), cb = held_by(world, b);
    /* No thermal mass: a fixed one is a reservoir, and nothing else can
     * have none. */
    const f3d_real ia = ca > F3D_R(0.0) ? F3D_R(1.0) / ca : F3D_R(0.0);
    const f3d_real ib = cb > F3D_R(0.0) ? F3D_R(1.0) / cb : F3D_R(0.0);
    if (ia == F3D_R(0.0) && ib == F3D_R(0.0)) continue;
    /* What a joule does to each surface. */
    const f3d_real sa_k = ia * a->gain, sb_k = ib * b->gain;
    const f3d_real area =
        contact_area(m, f3d_max(push, F3D_R(0.0)) * per_second, a->curve,
                     b->curve,
                     compliance_of(&sa->material) + compliance_of(&sb->material));
    if (!(area > F3D_R(0.0))) continue;
    const f3d_real spot = f3d_sqrt(area / F3D_PI);
    const f3d_real g = F3D_R(4.0) * spot /
                       (F3D_R(1.0) / sa->material.conductivity +
                        F3D_R(1.0) / sb->material.conductivity);
    const f3d_real gdt = g * dt;
    const f3d_real q = gdt * (tb - ta) /
                       (F3D_R(1.0) + gdt * (sa_k + sb_k));
    a->l.temperature += q * ia;
    b->l.temperature -= q * ib;
    /* The colder side's spot, heated at what crossed over the area. */
    const f3d_real flux = f3d_abs(q) / (dt * area);
    if (q > F3D_R(0.0)) {
      expose(a, EXPOSED_CONTACT, flux, area, meet);
    } else if (q < F3D_R(0.0)) {
      expose(b, EXPOSED_CONTACT, flux, area, meet);
    }
  }
}

/* Heat between a compound's own parts where they meet: Holm's
 * constriction again, G = 2ak for one material, over a spot as wide as the
 * narrower part's cross-section — a table's leg into its top. Parts whose
 * reaches do not meet do not touch. Implicit a pair at a time, in part
 * order. */
static void conduct_within(F3dWorld *world, Heats *hs, f3d_real dt) {
  for (uint32_t i = 0; i < world->s.used; i++) {
    if (hs->many[i] < 2u) continue;
    const f3d_real k = world->slots[i].material.conductivity;
    for (uint32_t p = 0; p < hs->many[i]; p++) {
      for (uint32_t q = p + 1u; q < hs->many[i]; q++) {
        Heat *a = &hs->h[hs->first[i] + p];
        Heat *b = &hs->h[hs->first[i] + q];
        const F3dVec3 d = f3d_sub(a->at, b->at);
        if (f3d_dot(d, d) > (a->reach + b->reach) * (a->reach + b->reach)) continue;
        const f3d_real spot = f3d_min(a->touch, b->touch);
        if (!(spot > F3D_R(0.0))) continue;
        const f3d_real ca = held_by(world, a), cb = held_by(world, b);
        if (!(ca > F3D_R(0.0) && cb > F3D_R(0.0))) continue;
        const f3d_real gdt = F3D_R(2.0) * spot * k * dt;
        const f3d_real flow = gdt * (b->l.temperature - a->l.temperature) /
                              (F3D_R(1.0) + gdt * (F3D_R(1.0) / ca + F3D_R(1.0) / cb));
        /* Through the body, not across a surface: each part moves alike
         * all through. */
        a->l.temperature += flow / ca;
        a->l.interior += flow / ca;
        b->l.temperature -= flow / cb;
        b->l.interior -= flow / cb;
      }
    }
  }
}

/* ------------------------------------------------------------- flames */

/* Less than this, W, a body is not worth radiating to: a kilogram of wood
 * it warms by a fifth of a kelvin an hour. It decides how far a source
 * looks, from how strongly it radiates, and nothing else is cut. */
#define F3D_RADIANT_LEAST F3D_R(0.1)
/* Nor is one it would warm by less than this, K/s — a third of a kelvin
 * an hour: what a big body takes from a distant source is not worth the
 * rays that would decide how much of it the source sees. */
#define F3D_RADIANT_SLOWEST F3D_R(1e-4)
/* A body that looks smaller than this, its radius over its distance, is
 * seen whole or not at all: one ray, to its centre, decides. */
#define F3D_RADIANT_SMALL F3D_R(0.15)
/* How many rays decide how much of a body a source sees past what stands
 * between them: its centre and four points around it. */
#define F3D_RADIANT_RAYS 5u
/* A buoyant plume spreads by this much of its height on each side
 * (Heskestad: b = 0.12 (z − z₀)). */
#define F3D_PLUME_SPREAD F3D_R(0.12)
/* A plume is followed up to where its centreline is this much above the
 * air, K: a cut for the cost of looking, as the radiant ones are. */
#define F3D_PLUME_LEAST F3D_R(1.0)

/* Up: against gravity, or y in a world without it. */
static F3dVec3 up_of(const F3dWorld *world) {
  const f3d_real g2 = f3d_dot(world->s.gravity, world->s.gravity);
  return g2 > F3D_R(0.0)
             ? f3d_scale(world->s.gravity, F3D_R(-1.0) / f3d_sqrt(g2))
             : f3d_v3(F3D_R(0.0), F3D_R(1.0), F3D_R(0.0));
}

/* The radius of the ball with an entry's surface: what radiation sees of
 * it. */
static f3d_real seen_radius(const Heat *h) {
  return f3d_sqrt(h->surface / (F3D_R(4.0) * F3D_PI));
}

/* The diameter of the ball whose surface is [area]: how wide a fire's base
 * is over that much burning surface. */
static f3d_real across_of(f3d_real area) {
  return F3D_R(2.0) * f3d_sqrt(f3d_max(area, F3D_R(0.0)) / (F3D_R(4.0) * F3D_PI));
}

/* The share of everything a point sends out that a ball of radius [r] at
 * [d] from it catches: its solid angle over the whole sphere's. Never more
 * than (r/d)² / 2. */
static f3d_real caught(f3d_real r, f3d_real d) {
  if (d <= r) return F3D_R(0.5);
  const f3d_real s = r / d;
  return F3D_R(0.5) * (F3D_R(1.0) - f3d_sqrt(F3D_R(1.0) - s * s));
}

/* How long a fire's flame is, m, from the heat it gives off [q], W, over a
 * base of diameter [d], m: Heskestad's L = 0.235·Q^(2/5) − 1.02·D with Q in
 * kW, never shorter than the base. */
static f3d_real flame_length(f3d_real q, f3d_real d) {
  return f3d_max(F3D_R(0.235) * two_fifths(q * F3D_R(1e-3)) - F3D_R(1.02) * d,
                 d);
}

f3d_real f3d_flame_of(const F3dWorld *world, F3dVec3 at, f3d_real surface,
                      f3d_real involved, f3d_real release, F3dVec3 *axis) {
  const f3d_real g = f3d_sqrt(f3d_dot(world->s.gravity, world->s.gravity));
  const F3dVec3 up = up_of(world);
  *axis = up;
  if (!(release > F3D_R(0.0) && surface > F3D_R(0.0) && involved > F3D_R(0.0))) {
    return F3D_R(0.0);
  }
  /* Heskestad's length over a base as wide as the part of the body that
   * is alight — the whole body's width once the flame has spread over it —
   * from its middle; leaning with the wind where it stands by the buoyant
   * speed (g·Q / (ρ c_p Tₐ D))^(1/3). */
  const f3d_real r = f3d_sqrt(surface / (F3D_R(4.0) * F3D_PI));
  const f3d_real across = across_of(f3d_min(involved, surface));
  const f3d_real rise = cube_root(
      g * release / (world->s.air_density * F3D_MAT_AIR_SPECIFIC_HEAT *
                     world->s.air_temperature * across));
  f3d_real wind[3];
  f3d_world_sample_wind(world, at.x, at.y, at.z, wind);
  F3dVec3 blow = f3d_v3(wind[0], wind[1], wind[2]);
  blow = f3d_sub(blow, f3d_scale(up, f3d_dot(blow, up)));
  const F3dVec3 lean = f3d_add(f3d_scale(up, rise), blow);
  const f3d_real len = f3d_sqrt(f3d_dot(lean, lean));
  if (len > F3D_R(0.0)) *axis = f3d_scale(lean, F3D_R(1.0) / len);
  return flame_length(release, across) + r;
}

/* W/m² a flame of [f] over a base [d] across gives a surface of emissivity
 * [e] at [ts] standing in it: its gas's convection h_f (T_f − T_s), and its
 * radiation e·(1 − e^(−κd))·σT_f⁴, a flame's emissivity over its own
 * thickness (the pool-fire feedback of Quintiere, Fundamentals of Fire
 * Phenomena, §9.4). What the surface radiates back is its own loss, taken
 * where it is. */
static f3d_real flame_flux(const F3dMaterial *f, f3d_real d, f3d_real ts,
                           f3d_real e) {
  const f3d_real tf = f->flame_temperature;
  if (!(tf > F3D_R(0.0))) return F3D_R(0.0);
  const f3d_real tf4 = tf * tf * tf * tf;
  return f->flame_convection * f3d_max(tf - ts, F3D_R(0.0)) +
         e * (F3D_R(1.0) - decay(f->flame_absorption * d)) *
             F3D_STEFAN_BOLTZMANN * tf4;
}

/* W/m² a surface of [m] at its ignition temperature radiates above the
 * room's. */
static f3d_real reradiation(const F3dMaterial *m, f3d_real ta) {
  const f3d_real t = m->ignition_temperature;
  return m->emissivity * F3D_STEFAN_BOLTZMANN * (t * t * t * t - ta * ta * ta * ta);
}

/* Heskestad's plume over a fire giving off [q] W, [qc] of it convected,
 * over a base [d] across (Heskestad, "Fire Plumes, Flame Height, and Air
 * Entrainment", SFPE Handbook): its virtual origin z₀ = 0.083 Q^(2/5) −
 * 1.02 D, Q in kW; along its axis the gas above the air by ΔT₀ =
 * 9.1 (Tₐ / (g c_p² ρₐ²))^(1/3) Q_c^(2/3) (z − z₀)^(−5/3), never past the
 * flame's own temperature; and rising at u₀ = 3.4 (g / (c_p ρₐ Tₐ))^(1/3)
 * Q_c^(1/3) (z − z₀)^(−1/3), no faster within the flame than at its tip. */
typedef struct Plume {
  f3d_real origin, excess, speed, tip, top;
} Plume;

static Plume plume_of(const F3dWorld *world, f3d_real q, f3d_real qc,
                      f3d_real d) {
  Plume p;
  f3d_zero(&p, sizeof p);
  const f3d_real g = f3d_sqrt(f3d_dot(world->s.gravity, world->s.gravity));
  const f3d_real ta = world->s.air_temperature;
  const f3d_real rho = world->s.air_density;
  if (!(qc > F3D_R(0.0) && g > F3D_R(0.0) && rho > F3D_R(0.0))) return p;
  p.origin = F3D_R(0.083) * two_fifths(q * F3D_R(1e-3)) - F3D_R(1.02) * d;
  const f3d_real third = cube_root(qc);
  p.excess = F3D_R(9.1) *
             cube_root(ta / (g * F3D_MAT_AIR_SPECIFIC_HEAT * F3D_MAT_AIR_SPECIFIC_HEAT * rho * rho)) *
             third * third;
  p.speed = F3D_R(3.4) * cube_root(g / (F3D_MAT_AIR_SPECIFIC_HEAT * rho * ta)) * third;
  p.tip = flame_length(q, d);
  /* ΔT₀ = excess (z − z₀)^(−5/3) falls to F3D_PLUME_LEAST at
   * z − z₀ = (excess / least)^(3/5). */
  p.top = f3d_max(p.origin + power(p.excess / F3D_PLUME_LEAST, F3D_R(0.6)), p.tip);
  return p;
}

/* The plume's gas on its axis [z] above the fire's middle, K over the air,
 * never past [most]. */
static f3d_real plume_excess(const Plume *p, f3d_real z, f3d_real most) {
  const f3d_real above = z - p->origin;
  if (!(above > F3D_R(0.0))) return most;
  const f3d_real c = cube_root(above);
  return f3d_min(p->excess / (c * c * c * c * c), most);
}

static f3d_real plume_speed(const Plume *p, f3d_real z) {
  const f3d_real above = f3d_max(z, p->tip) - p->origin;
  if (!(above > F3D_R(0.0))) return F3D_R(0.0);
  return p->speed / cube_root(above);
}

/* Whether a body's entries radiate and are radiated to: not a mesh — a
 * level's floor is the room, already the air's temperature everything
 * radiates against. */
static int radiates(const F3dSlot *s) {
  return s->live && s->shape != F3D_SHAPE_MESH;
}

/* What can be heated: an entry with a surface and a thermal mass. */
static int receives(const F3dWorld *world, const Heat *h) {
  return radiates(&world->slots[h->slot]) && h->surface > F3D_R(0.0) &&
         held_by(world, h) > F3D_R(0.0);
}

/* What one plume gives one entry standing in it: W, over the m² of it the
 * gas touches, at the gas's temperature. */
typedef struct Bathed {
  Heat *b;
  f3d_real give, area, gas;
} Bathed;

typedef struct Near {
  const F3dWorld *world;
  uint32_t count, capacity;
  uint32_t *slots;
  Bathed *bathed;
  uint32_t bathed_count, bathed_capacity;
  int failed;
} Near;

static int near_body(void *context, int32_t leaf) {
  Near *n = (Near *)context;
  const uint32_t slot = n->world->tree.nodes[leaf].slot;
  if (n->count == n->capacity) {
    const uint32_t grown = n->capacity == 0 ? 64u : n->capacity * 2u;
    uint32_t *more = (uint32_t *)f3d_realloc(n->slots, (size_t)grown * sizeof(uint32_t));
    if (more == NULL) {
      n->failed = 1;
      return 0;
    }
    n->slots = more;
    n->capacity = grown;
  }
  n->slots[n->count++] = slot;
  return 1;
}

static int bathe(Near *n, Bathed b) {
  if (n->bathed_count == n->bathed_capacity) {
    const uint32_t grown = n->bathed_capacity == 0 ? 16u : n->bathed_capacity * 2u;
    Bathed *more = (Bathed *)f3d_realloc(n->bathed, (size_t)grown * sizeof(Bathed));
    if (more == NULL) {
      n->failed = 1;
      return 0;
    }
    n->bathed = more;
    n->bathed_capacity = grown;
  }
  n->bathed[n->bathed_count++] = b;
  return 1;
}

/* How much of [b], a ball of radius [rb], is seen from [a]'s centre past
 * every other body: the share of F3D_RADIANT_RAYS rays that reach it, to
 * its centre and to four points around it at √½ of its radius — the circle
 * that halves the disc it shows; or, when it looks small, whether the one
 * to its centre does. */
static f3d_real seen(F3dWorld *world, F3dVec3 from, F3dBody ha, F3dVec3 to,
                     F3dBody hb, f3d_real rb) {
  const F3dVec3 line = f3d_sub(to, from);
  const f3d_real d = f3d_sqrt(f3d_dot(line, line));
  if (!(d > F3D_R(0.0))) return F3D_R(1.0);
  const F3dVec3 n = f3d_scale(line, F3D_R(1.0) / d);
  /* Two directions across the line, the same however it points. */
  const F3dVec3 helper = f3d_abs(n.y) < F3D_R(0.9)
                             ? f3d_v3(F3D_R(0.0), F3D_R(1.0), F3D_R(0.0))
                             : f3d_v3(F3D_R(1.0), F3D_R(0.0), F3D_R(0.0));
  F3dVec3 e1 = f3d_cross(n, helper);
  e1 = f3d_scale(e1, F3D_R(1.0) / f3d_sqrt(f3d_dot(e1, e1)));
  const F3dVec3 e2 = f3d_cross(n, e1);
  const f3d_real off = F3D_R(0.70710678) * rb;
  const F3dVec3 aims[F3D_RADIANT_RAYS] = {
      to, f3d_madd(to, e1, off), f3d_madd(to, e1, -off), f3d_madd(to, e2, off),
      f3d_madd(to, e2, -off)};
  const uint32_t rays = rb < F3D_RADIANT_SMALL * d ? 1u : F3D_RADIANT_RAYS;
  uint32_t open = 0;
  for (uint32_t k = 0; k < rays; k++) {
    if (!f3d_world_segment_blocked(world, from, aims[k], ha, hb)) open++;
  }
  return (f3d_real)open / (f3d_real)rays;
}

/* Heat across the air between bodies apart, from every body hotter or
 * colder than the air and every fire, to the bodies near it.
 *
 * Every body already gives the air εσA(T⁴ − Tₐ⁴), as if all it saw were at
 * the air's temperature. What it sees of another body is not: that body
 * catches the share of the excess its solid angle is, as much of it as its
 * emissivity takes in, and as much as nothing stands in the way. A fire's
 * flame sends its radiant share of the heat it gives off out from its
 * centre the same way. So a body at the air's temperature gives nothing, a
 * cold one draws heat from what sees it, and what is caught was already
 * given up: no heat is made, and no source gives away more than it sends.
 *
 * And a fire's plume stands over it — as wide as the patch alight,
 * spreading as a plume does, leaning with the wind by the speed of its own
 * buoyancy, its gas as hot and as fast as Heskestad says. A body standing
 * in it takes heat from that gas by forced and free convection
 * (convection), over the half of it that faces the plume as far as the
 * plume covers it; but never more than the share of the plume's convected
 * heat that flows through the cross-section it blocks, and all of them
 * together never more than that heat. A seed of a fire warms the crate over
 * it by what the seed gives off, not by a flame's temperature.
 *
 * A source looks as far as its radiation could still give the largest body
 * F3D_RADIANT_LEAST, and up its plume as far as its gas is
 * F3D_PLUME_LEAST over the air. Sources in slot order and what they find
 * sorted, so the same world passes the same heat. */
static void radiate(F3dWorld *world, Heats *hs, f3d_real dt) {
  const f3d_real ta = world->s.air_temperature;
  const f3d_real ta4 = ta * ta * ta * ta;
  /* The largest thing that can be heated, as radiation sees it. */
  f3d_real largest = F3D_R(0.0);
  for (uint32_t e = 0; e < hs->count; e++) {
    if (receives(world, &hs->h[e])) largest = f3d_max(largest, seen_radius(&hs->h[e]));
  }
  if (!(largest > F3D_R(0.0))) return;
  /* Where every body stands now, for the rays that decide what sees what. */
  f3d_update_proxies(world, F3D_R(0.0));
  f3d_build_mesh_trees(world);
  Near n;
  f3d_zero(&n, sizeof n);
  n.world = world;
  for (uint32_t e = 0; e < hs->count && !n.failed; e++) {
    const Heat *a = &hs->h[e];
    const F3dSlot *sa = &world->slots[a->slot];
    if (!radiates(sa) || !(a->surface > F3D_R(0.0))) continue;
    const F3dMaterial *ma = &sa->material;
    const F3dMaterial *fm = a->flame;
    const f3d_real t = skin_of(a);
    /* What its surface sends out above the room, and its flame's: the
     * char over its fire at the char's own temperature, which its patch
     * has already given up, and the rest of it at its own. */
    const f3d_real charred =
        (a->l.burning & F3D_LUMP_OWN) && a->l.char_depth > F3D_R(0.0)
            ? f3d_min(a->l.involved, a->surface)
            : F3D_R(0.0);
    const f3d_real tc = a->l.char_skin;
    const f3d_real excess =
        ma->emissivity * F3D_STEFAN_BOLTZMANN * (a->surface - charred) *
            (t * t * t * t - ta4) +
        F3D_CHAR_EMISSIVITY * F3D_STEFAN_BOLTZMANN * charred * (tc * tc * tc * tc - ta4);
    const f3d_real q = a->l.burning != 0 ? a->l.heat_release : F3D_R(0.0);
    const int alight = q > F3D_R(0.0);
    const f3d_real chi = alight ? fm->flame_radiant : F3D_R(0.0);
    const f3d_real sent = excess + chi * q;
    const f3d_real hottest = alight ? f3d_max(t, fm->flame_temperature) : t;
    const f3d_real ra = seen_radius(a);
    /* The plume the flame stands in. */
    F3dVec3 axis;
    f3d_flame_of(world, a->at, a->surface, a->l.involved, q, &axis);
    const f3d_real base = across_of(f3d_min(a->l.involved, a->surface));
    const f3d_real qc = (F3D_R(1.0) - chi) * q;
    const Plume plume = plume_of(world, q, qc, base);
    if (f3d_abs(sent) < F3D_RADIANT_LEAST && plume.top == F3D_R(0.0)) continue;
    /* caught ≤ (r/d)²/2: past this, the largest thing catches less than
     * the least worth sending. */
    const f3d_real far =
        f3d_max(largest * f3d_sqrt(f3d_abs(sent) / (F3D_R(2.0) * F3D_RADIANT_LEAST)),
                ra + largest);
    F3dBox box;
    box.lo = f3d_sub(a->at, f3d_v3(far, far, far));
    box.hi = f3d_add(a->at, f3d_v3(far, far, far));
    if (plume.top > F3D_R(0.0)) {
      const f3d_real pad =
          F3D_R(0.5) * base + F3D_PLUME_SPREAD * plume.top + largest;
      const F3dVec3 end = f3d_madd(a->at, axis, plume.top);
      box.lo.x = f3d_min(box.lo.x, f3d_min(a->at.x, end.x) - pad);
      box.lo.y = f3d_min(box.lo.y, f3d_min(a->at.y, end.y) - pad);
      box.lo.z = f3d_min(box.lo.z, f3d_min(a->at.z, end.z) - pad);
      box.hi.x = f3d_max(box.hi.x, f3d_max(a->at.x, end.x) + pad);
      box.hi.y = f3d_max(box.hi.y, f3d_max(a->at.y, end.y) + pad);
      box.hi.z = f3d_max(box.hi.z, f3d_max(a->at.z, end.z) + pad);
    }
    n.count = 0;
    n.bathed_count = 0;
    f3d_tree_query(&world->tree, box, near_body, &n);
    if (n.failed) break;
    for (uint32_t p = 1; p < n.count; p++) {
      const uint32_t v = n.slots[p];
      uint32_t k = p;
      while (k > 0 && n.slots[k - 1u] > v) {
        n.slots[k] = n.slots[k - 1u];
        k--;
      }
      n.slots[k] = v;
    }
    const F3dBody ha = f3d_handle_of(world, sa);
    f3d_real given = F3D_R(0.0);
    for (uint32_t k = 0; k < n.count && !n.failed; k++) {
      const uint32_t other = n.slots[k];
      if (other >= world->s.used) continue;
      const F3dBody hb = f3d_handle_of(world, &world->slots[other]);
      for (uint32_t j = 0; j < hs->many[other]; j++) {
        Heat *b = &hs->h[hs->first[other] + j];
        /* Not itself; but another part of its own body, yes: a beam's
         * burning end heats the part beside it. */
        if (b == a || !receives(world, b)) continue;
        const F3dSlot *sb = &world->slots[b->slot];
        const F3dVec3 between = f3d_sub(b->at, a->at);
        const f3d_real d = f3d_sqrt(f3d_dot(between, between));
        const f3d_real rb = seen_radius(b);
        const f3d_real tb = skin_of(b);
        /* In the plume. */
        if (plume.top > F3D_R(0.0)) {
          const f3d_real along =
              f3d_clamp(f3d_dot(between, axis), F3D_R(0.0), plume.top);
          const F3dVec3 off = f3d_sub(between, f3d_scale(axis, along));
          const f3d_real apart = f3d_sqrt(f3d_dot(off, off));
          const f3d_real width = F3D_R(0.5) * base + F3D_PLUME_SPREAD * along;
          const f3d_real inside = f3d_clamp((width + rb - apart) / (F3D_R(2.0) * rb),
                                            F3D_R(0.0), F3D_R(1.0));
          const f3d_real gas =
              ta + plume_excess(&plume, along, fm->flame_temperature - ta);
          if (inside > F3D_R(0.0) && gas > tb && width > F3D_R(0.0)) {
            const f3d_real hc = convection(world, b->size, plume_speed(&plume, along),
                                           tb, gas);
            const f3d_real area = F3D_R(0.5) * b->surface * inside;
            /* Never past the gas in one step. */
            const f3d_real most = held_by(world, b) / b->gain * (gas - tb) / dt;
            const f3d_real want = f3d_min(hc * area * (gas - tb), most);
            /* The share of the plume's cross-section it stands across. */
            const f3d_real blocked =
                f3d_min(F3D_R(1.0), rb * rb * inside / (width * width));
            Bathed bt;
            bt.b = b;
            bt.give = f3d_min(want, blocked * qc);
            bt.area = area;
            bt.gas = gas;
            if (bt.give > F3D_R(0.0)) bathe(&n, bt);
          }
        }
        /* By radiation, from the source's centre. */
        if (d > far) continue;
        const f3d_real share = sb->material.emissivity * caught(rb, d);
        const f3d_real worth =
            f3d_max(F3D_RADIANT_LEAST, F3D_RADIANT_SLOWEST * held_by(world, b));
        if (f3d_abs(sent) * share < worth) continue;
        f3d_real got = sent * share * seen(world, a->at, ha, b->at, hb, rb);
        /* Never more, all of them together, than it sends. */
        const f3d_real left = f3d_abs(sent) - f3d_abs(given);
        if (f3d_abs(got) > left) got = sent < F3D_R(0.0) ? -left : left;
        given += got;
        b->l.heat += got * dt;
        if (got > F3D_R(0.0)) {
          expose(b, EXPOSED_RADIATION, got / (F3D_R(0.5) * b->surface),
                 F3D_R(0.5) * b->surface, hottest);
        }
      }
    }
    /* What the plume gives, shared out when all it is asked for is more
     * than it carries. */
    f3d_real asked = F3D_R(0.0);
    for (uint32_t k = 0; k < n.bathed_count; k++) asked += n.bathed[k].give;
    const f3d_real scale = asked > qc ? qc / asked : F3D_R(1.0);
    for (uint32_t k = 0; k < n.bathed_count; k++) {
      Bathed *bt = &n.bathed[k];
      const f3d_real give = bt->give * scale;
      bt->b->l.heat += give * dt;
      expose(bt->b, EXPOSED_GAS, give / bt->area, bt->area, bt->gas);
    }
  }
  f3d_free(n.slots);
  f3d_free(n.bathed);
}

/* ------------------------------------------------------------ the patch */

/* m² of a burning patch whose edge has crept [w] from where it started and
 * climbed [rise] past that, on an entry [girth] round: a disc until it
 * wraps round, then a band; and the strip it has climbed. A patch started
 * at an [edge] — where a neighbouring part's flame crossed — spreads one
 * way only. */
static f3d_real patch_area(f3d_real w, f3d_real rise, f3d_real girth, uint32_t edge) {
  const f3d_real ways = edge ? F3D_R(1.0) : F3D_R(2.0);
  const f3d_real disc = F3D_R(0.5) * ways * F3D_PI * w * w;
  const f3d_real band = girth > F3D_R(0.0) ? ways * w * girth : disc;
  const f3d_real across = girth > F3D_R(0.0) ? f3d_min(ways * w, girth) : ways * w;
  return f3d_min(disc, band) + across * rise;
}

/* The edge a patch of [area] has: as far as makes a disc, or a band once
 * wrapped round, that large. */
static f3d_real edge_of(f3d_real area, f3d_real girth) {
  const f3d_real disc = f3d_sqrt(f3d_max(area, F3D_R(0.0)) / F3D_PI);
  return girth > F3D_R(0.0) ? f3d_max(disc, area / (F3D_R(2.0) * girth)) : disc;
}

/* Lights an entry's own fuel over [area], heat [patch] deep under it. */
static void light(Heat *h, f3d_real area, f3d_real patch) {
  F3dLump *l = &h->l;
  l->burning |= F3D_LUMP_OWN;
  l->edge = 0;
  l->rise = F3D_R(0.0);
  l->involved = f3d_min(area, h->surface);
  l->spread = edge_of(l->involved, h->girth);
  l->patch = patch;
  l->exposure = F3D_R(0.0);
}

enum { CAUGHT = 1, WENT_OUT = 2, BURNT_OUT = 4, DOUSED = 8 };

/* Less of its surface than this share above a liquid, and a part is wholly
 * under: what the water's sampling of a shape can tell from none. */
#define F3D_DROWNED F3D_R(1e-3)

/* The char's conductivity for a wood of [density] at [t] K: its
 * diffusivity times its density — χ of the wood, at the char's
 * contraction of the depth it came from — times its specific heat there. */
static f3d_real char_conductivity(const F3dMaterial *m, f3d_real density, f3d_real t) {
  const f3d_real c = F3D_R(1430.0) + F3D_R(0.355) * t - F3D_R(7.32e7) / (t * t);
  return F3D_CHAR_DIFFUSIVITY * m->char_yield * density / F3D_CHAR_CONTRACTION *
         f3d_max(c, F3D_R(0.0));
}

/* W/m² that reaches the front of a burning patch of [m], its flame [d]
 * across, given [heated] W/m² from outside: over [char_depth] of char of
 * a wood of [density], what crosses the char from its surface, which
 * sits where f(T) = flame(T) + heated − σ(T⁴ − Tₐ⁴) − k_c (T − T_ig)/x_c
 * is nought, f falling with T, found by halving between the front's
 * temperature and the flame's; with no char, the surface's own balance at
 * the ignition temperature. The flame gives no more than [cap] W/m²: no
 * more than it makes. The char's surface into [surface_t]. */
static f3d_real front_flux(const F3dMaterial *m, f3d_real d, f3d_real heated,
                           f3d_real char_depth, f3d_real density, f3d_real ta,
                           f3d_real cap, f3d_real *surface_t) {
  const f3d_real ignition = m->ignition_temperature;
  *surface_t = ignition;
  if (!(m->char_yield > F3D_R(0.0) && char_depth > F3D_R(0.0) && density > F3D_R(0.0))) {
    return f3d_min(flame_flux(m, d, ignition, m->emissivity), cap) + heated -
           reradiation(m, ta);
  }
  const f3d_real ta4 = ta * ta * ta * ta;
  f3d_real lo = ignition, hi = f3d_max(m->flame_temperature, ignition);
  for (int k = 0; k < 40; k++) {
    const f3d_real mid = F3D_R(0.5) * (lo + hi);
    const f3d_real m4 = mid * mid * mid * mid;
    const f3d_real k = char_conductivity(m, density, F3D_R(0.5) * (mid + ignition));
    const f3d_real f = f3d_min(flame_flux(m, d, mid, F3D_CHAR_EMISSIVITY), cap) + heated -
                       F3D_CHAR_EMISSIVITY * F3D_STEFAN_BOLTZMANN * (m4 - ta4) -
                       k * (mid - ignition) / char_depth;
    if (f > F3D_R(0.0)) {
      lo = mid;
    } else {
      hi = mid;
    }
  }
  *surface_t = lo;
  return char_conductivity(m, density, F3D_R(0.5) * (lo + ignition)) * (lo - ignition) /
         char_depth;
}

/* kg/(m² s) a front given [front] W/m² gasifies, the solid under it
 * drawing [drawn] W/m² from it to warm by [rise] K. The heat of
 * gasification [lv] counts warming what goes from the room's temperature
 * to the front's (Tewarson), and in steady burning what the solid draws is
 * just that: ṁ'' = q'' / L (Mikkola's integral model). Only what it draws
 * past warming the wood that goes — the soak of a cold body under a fresh
 * fire — comes off the front besides, at what is left of L once the
 * warming is paid: ṁ'' = (q'' − drawn) / (L − c ΔT). */
static f3d_real gasified(const F3dMaterial *m, f3d_real front, f3d_real drawn, f3d_real lv,
                         f3d_real rise) {
  if (!(front > F3D_R(0.0))) return F3D_R(0.0);
  const f3d_real steady = front / lv;
  const f3d_real warming = m->specific_heat * f3d_max(rise, F3D_R(0.0));
  if (drawn <= steady * warming || !(lv > warming)) return steady;
  return f3d_max(front - drawn, F3D_R(0.0)) / (lv - warming);
}

/* kg/(m² s) of gas the wood under a front at [front_t] gives off in depth:
 * ρ (1 − χ) ∫ A e^(−E/RT(x)) dx over the parabola from the front's
 * temperature to [under] across [patch]'s depth, by the midpoint rule on
 * eight slices. Nought for a material that does not char. */
static f3d_real in_depth_flux(const F3dMaterial *m, f3d_real density, f3d_real front_t,
                              f3d_real under, f3d_real patch) {
  if (!(m->char_yield > F3D_R(0.0) && patch > F3D_R(0.0))) return F3D_R(0.0);
  f3d_real sum = F3D_R(0.0);
  for (int k = 0; k < 8; k++) {
    const f3d_real u = (F3D_R(k) + F3D_R(0.5)) / F3D_R(8.0);
    const f3d_real t_x = under + (front_t - under) * (F3D_R(1.0) - u) * (F3D_R(1.0) - u);
    sum += natural_exp(-F3D_PYROLYSIS_E / (F3D_GAS_CONSTANT * t_x));
  }
  return density * (F3D_R(1.0) - m->char_yield) * F3D_PYROLYSIS_A * sum / F3D_R(8.0) *
         f3d_sqrt(patch);
}

/* Whether a patch of [area] lit now, heat [patch] deep under it, would give
 * off the firepoint's least and so hold a flame (Rasbash): its own flame's
 * flux and [heated] W/m² more from outside, less its radiation and what the
 * solid under it draws, over the heat of gasification, with what the wood
 * gives off in depth. A surface that reaches its ignition temperature with
 * too little heat behind it flashes and does not catch. */
static int holds_flame(const F3dWorld *world, const Heat *h, f3d_real area,
                       f3d_real patch, f3d_real heated) {
  const F3dMaterial *m = &world->slots[h->slot].material;
  const f3d_real ignition = m->ignition_temperature;
  if (!(area > F3D_R(0.0))) return 0;
  const f3d_real under = f3d_min(h->l.interior, h->l.temperature);
  /* A porous bed's elements under the front heat through as it comes:
   * nothing draws on a cold solid beneath. */
  const f3d_real drawn = patch > F3D_R(0.0) && !(bed_depth(world, h) > F3D_R(0.0))
                             ? F3D_R(2.0) * m->conductivity * (ignition - under) / f3d_sqrt(patch)
                             : F3D_R(0.0);
  const f3d_real density = h->volume > F3D_R(0.0) ? h->l.mass / h->volume : F3D_R(0.0);
  /* The wood under the front no cooler than its layer says: a surface
   * driven past its ignition temperature faster than it could catch holds
   * that much more gas in reach. */
  const f3d_real top = f3d_max(ignition, skin_of(h));
  const f3d_real depth_gas = in_depth_flux(m, density, top, under, patch);
  f3d_real cap = flame_flux(m, across_of(area), ignition, m->emissivity), flux = F3D_R(0.0);
  for (int k = 0; k < 4; k++) {
    f3d_real surface_t;
    const f3d_real front =
        front_flux(m, across_of(area), heated, h->l.char_depth, density,
                   world->s.air_temperature, cap, &surface_t);
    flux = gasified(m, front, drawn, gasification_of(m), ignition - under) + depth_gas;
    cap = flux * m->heat_of_combustion;
  }
  return flux >= firepoint_of(m);
}

/* One entry's step: its fire, its heat, what it gives the air, its water
 * and whether it is alight. Returns what changed, as CAUGHT, WENT_OUT and
 * BURNT_OUT. */
static uint32_t step_entry(F3dWorld *world, const F3dSlot *s, Heat *h,
                           f3d_real dt) {
  const f3d_real ta = world->s.air_temperature;
  const F3dMaterial *m = &s->material;
  F3dLump *l = &h->l;
  uint32_t said = 0;
  /* What reached it from outside: radiation, plumes, the bus. */
  const f3d_real outside = l->heat / dt;
  f3d_real power = outside;
  const f3d_real released_before = l->heat_release;
  l->heat = F3D_R(0.0);
  l->heat_release = F3D_R(0.0);
  const f3d_real ignition = m->ignition_temperature;
  const f3d_real inertia = inertia_of(world, h);
  /* How soon it catches and how fast its flame creeps answer to this. */
  const f3d_real catching = catching_inertia(world, h);
  const f3d_real thick =
      h->volume > F3D_R(0.0) && h->surface > F3D_R(0.0) ? h->volume / h->surface
                                                         : F3D_R(0.0);
  /* α = k / (ρc) = k² / (kρc). */
  const f3d_real alpha =
      inertia > F3D_R(0.0) ? m->conductivity * m->conductivity / inertia : F3D_R(0.0);
  /* m² at the ignition temperature under its own flame: what it loses from
   * there is the patch's, not the surface's. */
  f3d_real at_ignition = F3D_R(0.0);
  /* m² of it under a liquid, its share of the surface as of the volume;
   * and what stands above, the most of it that can burn. A part that is
   * wholly under has no flame. */
  const f3d_real wet = h->liquid != NULL ? h->l.immersed * h->surface : F3D_R(0.0);
  const f3d_real open = f3d_max(h->surface - wet, F3D_R(0.0));
  const int drowned = h->liquid != NULL && !(open > F3D_DROWNED * h->surface);

  /* A burner's flame stands over the whole of it above any liquid and
   * gives it what a flame gives a surface standing in it, out of what the
   * fuel releases; under, it goes out. */
  if (h->feed > F3D_R(0.0) && h->fuel != NULL && drowned) {
    l->burning &= ~F3D_LUMP_BURNER;
    said |= DOUSED;
  } else if (h->feed > F3D_R(0.0) && h->fuel != NULL) {
    l->burning |= F3D_LUMP_BURNER;
    const f3d_real q = h->feed * h->fuel->heat_of_combustion;
    const f3d_real back =
        f3d_min(flame_flux(h->fuel, h->size, l->skin, m->emissivity) * open, q);
    power += back;
    l->heat_release += q - back;
    l->involved = open;
  } else {
    l->burning &= ~F3D_LUMP_BURNER;
  }

  /* Its own fire: the patch spreads, then keeps its heat balance — over
   * no more than stands above a liquid, and out once all of it is under. */
  if ((l->burning & F3D_LUMP_OWN) && drowned) {
    patch_out(l);
    said |= WENT_OUT;
  }
  if (l->burning & F3D_LUMP_OWN) {
    if ((l->burning & F3D_LUMP_BURNER) || l->skin >= ignition) {
      /* A surface already at its ignition temperature is alight wherever
       * it is: all of it, as one temperature. */
      l->involved = open;
      l->spread = edge_of(open, h->girth);
    } else if (inertia > F3D_R(0.0)) {
      /* Sideways and down, against the air the flame draws in: the opposed
       * spread Φ / (kρc (T_ig − T_s)²) (Quintiere and Harkleroad) — over a
       * porous bed too, with the bed's own kρc, for want of a measured
       * spread over thatch. Up,
       * with it: the flame heats the surface above the patch for as far as
       * it reaches past it, at its own flux, and that surface catches in
       * the time a thick solid takes under that flux, t = (π/4) kρc
       * ((T_ig − T_s) / q'')² — V = (x_f − x_p) / t_ig (Quintiere,
       * Fundamentals of Fire Phenomena, §8.4). */
      const f3d_real ahead = ignition - l->skin;
      const f3d_real sideways = spread_of(m) / (catching * ahead * ahead);
      const f3d_real d = across_of(l->involved);
      const f3d_real heats = flame_flux(m, d, l->skin, m->emissivity) -
                             reradiation(m, ta);
      f3d_real climb = F3D_R(0.0);
      if (heats > F3D_R(0.0)) {
        const f3d_real t_ig = ignition_time(world, h, ahead, heats);
        const f3d_real past =
            flame_length(released_before, d) - l->rise - l->spread;
        climb = f3d_max(past, F3D_R(0.0)) / t_ig;
      }
      l->spread += sideways * dt;
      l->rise = f3d_min(l->rise + climb * dt, h->height);
      l->involved = f3d_min(patch_area(l->spread, l->rise, h->girth, l->edge), open);
    }
    if (thick > F3D_R(0.0)) {
      l->patch = f3d_min(l->patch + F3D_R(6.0) * alpha * dt, thick * thick);
    }
    /* Its balance, a square metre of it. Over a material that chars, the
     * flame stands on a char layer that grows as it burns: the char's
     * surface sits where the flame's flux and what reaches it from outside
     * in balance its own radiation and what crosses the char by conduction
     * to the front beneath, which stays at the ignition temperature. With
     * no char yet, or for a material that does not char, the front is the
     * surface. At the front what the solid under it draws, k·∂T/∂x =
     * 2k (T_ig − T_i) / δ across the parabola heat lies in (lay_heat), is
     * taken from what arrives, and the rest gives off fuel at
     * ṁ'' = q''_net / L (Tewarson). The wood under the front, warm but not
     * yet at it, gives off gas of its own at the rate its kinetics give
     * across that parabola. A patch whose gas all told is less than the
     * firepoint's least goes out (Rasbash). The flame's heat to it comes
     * out of what the fire releases. */
    const f3d_real lv = gasification_of(m);
    const f3d_real area = l->involved;
    const f3d_real d_flame = across_of(area);
    /* What other bodies and their fires send it, per m² — never, with its
     * own flame's, more than a surface wholly inside a flame takes: its
     * gas's convection and the radiation of a flame too thick to see
     * through, h_f (T_f − T_ig) + εσT_f⁴. Flames round it do not add past
     * that; it is as engulfed as a surface gets. Without the bound two
     * fires standing in each other feed each other without end, each
     * joule into a burning surface giving off ΔH_c / L joules more. What
     * the bus gives it is apart: heat said to go in, goes in. */
    const f3d_real per_m2 = F3D_R(1.0) / f3d_max(h->surface, F3D_R(1e-12));
    /* Spread over its surface, or as hard as its hardest-heated spot where
     * that is harder — but never more over the patch than it was given:
     * a contact's flux is over the contact, not over the whole fire. */
    const f3d_real from_others = f3d_max(outside - h->bus / dt, F3D_R(0.0));
    const f3d_real from_fires =
        area > F3D_R(0.0)
            ? f3d_max(from_others * per_m2, f3d_min(h->exposed_flux, from_others / area))
            : F3D_R(0.0);
    const f3d_real tf = m->flame_temperature;
    const f3d_real fed_front = flame_flux(m, d_flame, ignition, m->emissivity);
    const f3d_real engulfed =
        m->flame_convection * f3d_max(tf - ignition, F3D_R(0.0)) +
        m->emissivity * F3D_STEFAN_BOLTZMANN * tf * tf * tf * tf;
    const f3d_real taken =
        f3d_max(f3d_min(fed_front + from_fires, engulfed) - fed_front, F3D_R(0.0));
    const f3d_real from_outside = taken + h->bus / dt * per_m2;
    /* What the patch was sent past that never reaches it: its own flame's
     * gas takes it, and it leaves with the plume. */
    const f3d_real sent_here = from_others * per_m2;
    power -= f3d_max(sent_here - taken, F3D_R(0.0)) * l->involved;
    /* The virgin solid's density, and its char's: what is left, χ of what
     * goes, standing at the char's contraction of the depth it came from;
     * and the char's conductivity from its diffusivity, α ρ c. */
    const f3d_real density =
        h->volume > F3D_R(0.0) ? l->mass / h->volume : F3D_R(0.0);
    const f3d_real chi = m->char_yield;
    const f3d_real ta4 = ta * ta * ta * ta;
    /* The solid under it at its interior's temperature — but no warmer
     * than the body as a whole is: a body heated through and cooling holds
     * no more heat under its fire than its mean says, and drawing on an
     * interior it no longer has would cool it past the room's. */
    const f3d_real under = f3d_min(l->interior, l->temperature);
    /* A porous bed's elements under the front heat through as it comes:
     * the warming is in L, and nothing draws on a cold solid beneath. */
    const f3d_real bed = bed_depth(world, h);
    const f3d_real drawn =
        l->patch > F3D_R(0.0) && !(bed > F3D_R(0.0))
            ? F3D_R(2.0) * m->conductivity * (ignition - under) / f3d_sqrt(l->patch)
            : F3D_R(0.0);
    /* Under the front, the wood at its ignition temperature or at what its
     * layer holds, if that is hotter: heated faster than it burns, the
     * wood beneath gives off its gas in depth, and pays for it from that
     * heat. */
    const f3d_real top = f3d_max(ignition, skin_of(h));
    const f3d_real in_depth = in_depth_flux(m, density, top, under, l->patch);
    /* The flame gives back no more than it makes, ṁ''·ΔH_c a square metre:
     * what it makes depends on what it is given, so the two are settled
     * together, a few rounds from the flame's own flux down. */
    f3d_real cap = fed_front, surface_t = ignition, front = F3D_R(0.0);
    f3d_real at_front = F3D_R(0.0), flux = F3D_R(0.0);
    for (int k = 0; k < 4; k++) {
      front = front_flux(m, d_flame, from_outside, l->char_depth, density, ta, cap, &surface_t);
      at_front = gasified(m, front, drawn, lv, ignition - under);
      flux = at_front + in_depth;
      cap = flux * m->heat_of_combustion;
    }
    const f3d_real e_surface = chi > F3D_R(0.0) && l->char_depth > F3D_R(0.0)
                                   ? F3D_CHAR_EMISSIVITY
                                   : m->emissivity;
    const f3d_real s4 = surface_t * surface_t * surface_t * surface_t;
    const f3d_real fed = f3d_min(flame_flux(m, d_flame, surface_t, e_surface), cap);
    const f3d_real lost = e_surface * F3D_STEFAN_BOLTZMANN * (s4 - ta4);
    if (!(area > F3D_R(0.0)) || flux < firepoint_of(m)) {
      patch_out(l);
      said |= WENT_OUT;
    } else {
      const f3d_real burnt = f3d_min(flux * area * dt, l->fuel);
      const f3d_real share = flux > F3D_R(0.0) ? burnt / (flux * area * dt) : F3D_R(0.0);
      const f3d_real released = burnt * m->heat_of_combustion / dt;
      const f3d_real back = f3d_min(fed * area, released);
      power += back - lost * area - share * area * (at_front * lv + in_depth * F3D_PYROLYSIS_HEAT);
      l->heat_release += released - back;
      l->fuel -= burnt;
      l->mass -= burnt;
      at_ignition = area;
      /* The char thickens by the depth of wood that went, χ of it left at
       * its contraction; never past the body's own thickness. A bed's
       * elements char apart, each its own, and close over nothing. */
      if (chi > F3D_R(0.0) && density > F3D_R(0.0) && !(bed > F3D_R(0.0))) {
        const f3d_real gone = burnt / (area * density * (F3D_R(1.0) - chi));
        l->char_depth = f3d_min(l->char_depth + gone * F3D_CHAR_CONTRACTION, thick);
      }
      l->char_skin = surface_t;
      /* What char covers: all it has burnt over, never more than the
       * surface it has. */
      if (l->char_depth > F3D_R(0.0) || (bed > F3D_R(0.0) && chi > F3D_R(0.0))) {
        l->charred = f3d_min(f3d_max(l->charred, area), h->surface);
      }
      if (l->fuel <= F3D_R(0.0)) {
        l->fuel = F3D_R(0.0);
        patch_out(l);
        said |= BURNT_OUT;
      }
    }
  }
  if (l->burning == 0) l->involved = F3D_R(0.0);

  const f3d_real dry = l->mass * m->specific_heat;
  const f3d_real capacity = dry + l->water * F3D_MAT_WATER_SPECIFIC_HEAT;
  if (!(capacity > F3D_R(0.0))) return said;
  const f3d_real gain = h->gain;
  const f3d_real inner = l->interior;
  /* The surface as the step found it. */
  const f3d_real was = l->skin;
  /* What the surface gives the air, but where its own fire's patch is:
   * convection to the air moving past it (convection), and radiation
   * εσ(T⁴ − Tₐ⁴), written exactly as εσ(T² + Tₐ²)(T + Tₐ)·(T − Tₐ) so both
   * are a conductance times the difference — at the surface's temperature,
   * which moves by the gain times the mean's. Taken implicitly with the
   * conductance as it is, the step cannot carry the surface past the air's
   * temperature, however small the body or long the step. */
  f3d_real conductance = F3D_R(0.0);
  if (h->surface > F3D_R(0.0)) {
    f3d_real wind[3];
    f3d_world_sample_wind(world, h->at.x, h->at.y, h->at.z, wind);
    const f3d_real ux = s->velocity.x - wind[0];
    const f3d_real uy = s->velocity.y - wind[1];
    const f3d_real uz = s->velocity.z - wind[2];
    const f3d_real u = f3d_sqrt(ux * ux + uy * uy + uz * uz);
    const f3d_real t = skin_of(h);
    conductance = f3d_max(h->surface - at_ignition - wet, F3D_R(0.0)) *
                  (convection(world, h->size, u, t, ta) +
                   m->emissivity * F3D_STEFAN_BOLTZMANN * (t * t + ta * ta) * (t + ta));
  }
  /* And what is under a liquid gives it heat by convection with the
   * liquid's own properties, or, hotter than water boils at, by boiling,
   * whichever carries more — as a conductance to the liquid's temperature,
   * taken implicitly with the air's. */
  f3d_real wetted = F3D_R(0.0);
  const f3d_real tl = h->liquid != NULL ? h->liquid->temperature : ta;
  if (wet > F3D_R(0.0)) {
    const f3d_real t = skin_of(h);
    const f3d_real hc = liquid_convection(world, h->liquid, h->size, h->liquid_speed, t);
    wetted = wet * hc;
    if (h->liquid->boils && t > F3D_SAT_T && t > tl) {
      const f3d_real q = boiling(t - F3D_SAT_T, h->size, m->emissivity, gravity_of(world));
      wetted = wet * f3d_max(hc, q / (t - tl));
    }
  }
  f3d_real next = (capacity * l->temperature +
                   dt * (power - conductance * (inner * (F3D_R(1.0) - gain) - ta) -
                         wetted * (inner * (F3D_R(1.0) - gain) - tl))) /
                  (capacity + dt * (conductance + wetted) * gain);
  /* Water on it holds its surface at the boiling point: what would heat
   * the surface past it boils water off instead, and only once the water
   * has gone does it heat on. */
  const f3d_real boiling_mean = inner + (F3D_MAT_WATER_BOILING_POINT - inner) / gain;
  int boiling = 0;
  if (l->water > F3D_R(0.0) && next > boiling_mean) {
    const f3d_real excess = (next - boiling_mean) * capacity;
    const f3d_real boils = excess / F3D_MAT_WATER_LATENT_HEAT_OF_VAPORIZATION;
    if (boils < l->water) {
      l->water -= boils;
      next = boiling_mean;
      boiling = 1;
    } else {
      const f3d_real left = excess - l->water * F3D_MAT_WATER_LATENT_HEAT_OF_VAPORIZATION;
      l->water = F3D_R(0.0);
      next = dry > F3D_R(0.0) ? boiling_mean + left / dry : boiling_mean;
    }
  }
  l->temperature = f3d_max(next, F3D_R(1e-3));
  settle_heat(world, h, dt);
  l->skin = boiling ? F3D_MAT_WATER_BOILING_POINT : f3d_max(skin_of(h), F3D_R(1e-3));
  if (!(ignition > F3D_R(0.0))) return said;
  /* Water on its fire lands on char hotter than water boils at, and boils
   * off it at once as far as the char's heat above the boiling point goes,
   * ρ_c c_c (T_c − 100 °C) x_c a square metre of the patch: a splash
   * hisses and the fire burns on. Water left past that holds its surface
   * below any ignition temperature here: it puts its fire out and keeps it
   * from catching. */
  if (l->water > F3D_R(0.0) && (l->burning & F3D_LUMP_OWN) && l->char_depth > F3D_R(0.0) &&
      l->char_skin > F3D_MAT_WATER_BOILING_POINT && h->volume > F3D_R(0.0)) {
    const f3d_real density = l->mass / h->volume;
    const f3d_real tc = l->char_skin;
    const f3d_real char_density = m->char_yield * density / F3D_CHAR_CONTRACTION;
    const f3d_real t_mid = F3D_R(0.5) * (tc + F3D_MAT_WATER_BOILING_POINT);
    const f3d_real c = F3D_R(1430.0) + F3D_R(0.355) * t_mid - F3D_R(7.32e7) / (t_mid * t_mid);
    const f3d_real held = char_density * f3d_max(c, F3D_R(0.0)) * (tc - F3D_MAT_WATER_BOILING_POINT) *
                          l->char_depth * l->involved;
    const f3d_real per_kg =
        F3D_MAT_WATER_LATENT_HEAT_OF_VAPORIZATION + F3D_MAT_WATER_SPECIFIC_HEAT * f3d_max(F3D_MAT_WATER_BOILING_POINT - ta, F3D_R(0.0));
    const f3d_real boiled = f3d_min(l->water, held / per_kg);
    l->water -= boiled;
    if (held > F3D_R(0.0)) {
      l->char_skin = tc - (tc - F3D_MAT_WATER_BOILING_POINT) * boiled * per_kg / held;
    }
    if (capacity > F3D_R(0.0)) l->temperature -= boiled * per_kg / capacity;
  }
  if (l->water > F3D_R(0.0)) {
    if (l->burning & F3D_LUMP_OWN) {
      patch_out(l);
      said |= WENT_OUT;
    }
    l->exposure = F3D_R(0.0);
  } else if (!(l->burning & F3D_LUMP_OWN) && l->fuel > F3D_R(0.0) && !drowned) {
    const f3d_real whole_depth = l->reached > F3D_R(0.0) ? l->reached : thick * thick;
    const f3d_real heated_by = h->exposed != EXPOSED_NONE ? h->exposed_flux : F3D_R(0.0);
    if (f3d_max(was, l->skin) >= ignition &&
        holds_flame(world, h, open, whole_depth, heated_by)) {
      /* Its surface reached ignition with heat enough behind it to hold a
       * flame: all of it, as one temperature. */
      light(h, open, whole_depth);
      said |= CAUGHT;
    } else if (h->exposed == EXPOSED_CONTACT && h->exposed_cap >= ignition) {
      /* Where something hot touches it, the spot is at once at the
       * temperature their effusivities weigh the two to, and stays there
       * while the touch lasts (two semi-infinite solids brought together,
       * Carslaw and Jaeger §2.15): at ignition or past it, it catches
       * there once the heat laid under it, √(6αt) deep after t seconds of
       * the touch, holds a flame. */
      l->exposure += dt;
      const f3d_real bed = bed_depth(world, h);
      const f3d_real depth =
          bed > F3D_R(0.0)     ? bed * bed
          : thick > F3D_R(0.0) ? f3d_min(F3D_R(6.0) * alpha * l->exposure, thick * thick)
                               : F3D_R(0.0);
      const f3d_real area = f3d_min(h->exposed_area, open);
      if (holds_flame(world, h, area, depth, heated_by)) {
        light(h, area, depth);
        said |= CAUGHT;
      }
    } else if (h->exposed != EXPOSED_NONE && h->exposed_cap >= ignition &&
               inertia > F3D_R(0.0)) {
      /* A spot heated harder than the rest — in a flame's gas, facing a
       * fire — catches in the time a thick solid takes to reach ignition
       * under that flux, t = (π/4) kρc ((T_ig − T_s) / q'')² (Quintiere,
       * Fundamentals of Fire Phenomena, §7.5), or a porous bed's thin
       * elements, ρ_p c ΔT / (σ q'') (ignition_time), less what its surface loses
       * at ignition: its radiation in a gas, and radiation and convection
       * to the air facing a fire — the critical flux below which it never
       * catches. A flux that varies is counted by the share of the time it
       * would take that each step is. */
      f3d_real loss = F3D_R(0.0);
      if (h->exposed == EXPOSED_GAS) loss = reradiation(m, ta);
      if (h->exposed == EXPOSED_RADIATION) {
        loss = reradiation(m, ta) +
               convection(world, h->size, F3D_R(0.0), ignition, ta) * (ignition - ta);
      }
      const f3d_real net = h->exposed_flux - loss;
      const f3d_real ahead = ignition - l->skin;
      if (net > F3D_R(0.0)) {
        const f3d_real t_ig = ignition_time(world, h, ahead, net);
        l->exposure += dt / t_ig;
        if (l->exposure >= F3D_R(1.0)) {
          /* At ignition, it catches once the heat laid under it — √(6αt)
           * deep after t of the flux (Goodman) — holds a flame; until then
           * the flux goes on heating it deeper. */
          const f3d_real bed = bed_depth(world, h);
          const f3d_real depth =
              bed > F3D_R(0.0)     ? bed * bed
              : thick > F3D_R(0.0) ? f3d_min(F3D_R(6.0) * alpha * t_ig * l->exposure, thick * thick)
                                   : F3D_R(0.0);
          const f3d_real area = f3d_min(h->exposed_area, open);
          if (holds_flame(world, h, area, depth, heated_by)) {
            light(h, area, depth);
            said |= CAUGHT;
          }
        }
      } else {
        l->exposure = F3D_R(0.0);
      }
    } else {
      l->exposure = F3D_R(0.0);
    }
  }
  return said;
}

/* A compound's flame crossing from part to part where they meet, two ways.
 * Sideways, its creeping edge carries on across the joint as it would
 * across one surface — once a part is alight all over, or its edge,
 * started at its other end, has crept the length between — but only onto a
 * neighbour whose surface is warm enough for an edge to creep over at all
 * (spread_minimum); there it catches over its cross-section, with the heat
 * laid as deep under it as under the burning one. Upwards, the flame of a
 * part alight all over, or climbed to the joint, stands over the part above
 * and heats it at the flame's flux, and that part catches in the time a
 * thick solid takes to reach its ignition temperature under that flux,
 * t = (π/4) kρc ((T_ig − T_s) / q'')², counted as any heated spot's is. So
 * a beam on end burns upwards a part at a time, and one on its side only
 * as far as its surface beside the fire has warmed. In part order, from
 * the parts alight when the step's fires were done. */
static void cross(const F3dWorld *world, Heats *hs, uint32_t slot, f3d_real dt) {
  const uint32_t many = hs->many[slot];
  const F3dSlot *s = &world->slots[slot];
  const F3dMaterial *m = &s->material;
  if (many < 2u || !(m->ignition_temperature > F3D_R(0.0))) return;
  const f3d_real ta = world->s.air_temperature;
  const f3d_real ignition = m->ignition_temperature;
  const F3dVec3 up = up_of(world);
  uint64_t lit = 0;
  f3d_real heated[64];
  for (uint32_t q = 0; q < many && q < 64u; q++) heated[q] = F3D_R(0.0);
  for (uint32_t p = 0; p < many; p++) {
    const Heat *a = &hs->h[hs->first[slot] + p];
    if (!(a->l.burning & F3D_LUMP_OWN)) continue;
    for (uint32_t q = 0; q < many && q < 64u; q++) {
      Heat *b = &hs->h[hs->first[slot] + q];
      if (q == p || (b->l.burning & F3D_LUMP_OWN) || !(b->l.fuel > F3D_R(0.0)) ||
          b->l.water > F3D_R(0.0)) {
        continue;
      }
      const F3dVec3 d = f3d_sub(b->at, a->at);
      const f3d_real gap2 = f3d_dot(d, d);
      if (gap2 > (a->reach + b->reach) * (a->reach + b->reach)) continue;
      const f3d_real gap = f3d_sqrt(gap2);
      const f3d_real upward =
          gap > F3D_R(0.0) ? f3d_max(f3d_dot(d, up) / gap, F3D_R(0.0)) : F3D_R(0.0);
      const int all_over = a->l.involved >= a->surface;
      if ((all_over || (a->l.edge && a->l.spread >= gap)) &&
          b->l.skin >= m->spread_minimum) {
        lit |= (uint64_t)1u << q;
        continue;
      }
      if (upward > F3D_R(0.0) && (all_over || (a->l.edge && a->l.spread + a->l.rise >= gap))) {
        const f3d_real flux = flame_flux(m, across_of(a->l.involved), b->l.skin, m->emissivity) -
                              reradiation(m, ta);
        heated[q] = f3d_max(heated[q], flux);
      }
    }
  }
  for (uint32_t q = 0; q < many && q < 64u; q++) {
    Heat *b = &hs->h[hs->first[slot] + q];
    if (!(lit & ((uint64_t)1u << q)) && heated[q] > F3D_R(0.0)) {
      const f3d_real inertia = catching_inertia(world, b);
      const f3d_real ahead = ignition - b->l.skin;
      if (!(inertia > F3D_R(0.0))) continue;
      if (ahead <= F3D_R(0.0)) {
        lit |= (uint64_t)1u << q;
        continue;
      }
      const f3d_real t_ig = ignition_time(world, b, ahead, heated[q]);
      b->l.joint += dt / t_ig;
      if (b->l.joint >= F3D_R(1.0)) lit |= (uint64_t)1u << q;
    } else if (!(lit & ((uint64_t)1u << q))) {
      b->l.joint = F3D_R(0.0);
    }
    if (!(lit & ((uint64_t)1u << q))) continue;
    /* Under the joint as deep as under whichever burning neighbour is
     * nearest. */
    f3d_real patch = F3D_R(0.0), best = F3D_R(-1.0);
    for (uint32_t p = 0; p < many; p++) {
      const Heat *a = &hs->h[hs->first[slot] + p];
      if (!(a->l.burning & F3D_LUMP_OWN) || p == q) continue;
      const F3dVec3 d = f3d_sub(b->at, a->at);
      const f3d_real e = f3d_dot(d, d);
      if (best < F3D_R(0.0) || e < best) {
        best = e;
        patch = a->l.patch;
      }
    }
    b->l.burning |= F3D_LUMP_OWN;
    b->l.edge = 1;
    b->l.rise = F3D_R(0.0);
    b->l.spread = b->touch;
    b->l.involved =
        f3d_min(patch_area(b->l.spread, F3D_R(0.0), b->girth, 1), b->surface);
    b->l.patch = patch;
    b->l.exposure = F3D_R(0.0);
    b->l.joint = F3D_R(0.0);
  }
}

/* ------------------------------------------------------------- gather */

/* How big a shape of [kind] and [size] is where a compound's parts meet:
 * a ball's radius, a capsule's, a box's least half extent. */
static f3d_real touch_radius(uint32_t kind, F3dVec3 size) {
  switch (kind) {
    case F3D_SHAPE_SPHERE:
    case F3D_SHAPE_CAPSULE:
    case F3D_SHAPE_CYLINDER:
    case F3D_SHAPE_CONE:
      return size.x;
    case F3D_SHAPE_BOX:
      return f3d_min(size.x, f3d_min(size.y, size.z));
    default:
      return F3D_R(0.0);
  }
}

/* An entry's shape as fire and contact see it, from where it stands: its
 * girth about its longest axis, its height along [up], and how its surface
 * curves where it touches — a ball's or a capsule's radius, or for a flat
 * face its rounding. */
static void shape_of(Heat *h, const F3dPlaced *p, F3dVec3 up) {
  const f3d_real r = p->rounding;
  const F3dVec3 z = p->size;
  const f3d_real cx = f3d_abs(f3d_dot(p->axes.c[0], up));
  const f3d_real cy = f3d_abs(f3d_dot(p->axes.c[1], up));
  const f3d_real cz = f3d_abs(f3d_dot(p->axes.c[2], up));
  h->size = F3D_R(2.0) * seen_radius(h);
  h->curve = r;
  h->girth = F3D_PI * h->size;
  h->height = h->size;
  switch (p->kind) {
    case F3D_SHAPE_SPHERE:
      h->curve = z.x + r;
      h->girth = F3D_R(2.0) * F3D_PI * (z.x + r);
      h->height = F3D_R(2.0) * (z.x + r);
      break;
    case F3D_SHAPE_CAPSULE:
      h->curve = z.x + r;
      h->girth = F3D_R(2.0) * F3D_PI * (z.x + r);
      h->height = F3D_R(2.0) * (z.x + z.y * cy + r);
      break;
    case F3D_SHAPE_CYLINDER:
    case F3D_SHAPE_CONE:
      h->girth = F3D_R(2.0) * F3D_PI * (z.x + r);
      h->height = F3D_R(2.0) * (z.y * cy +
                                z.x * f3d_sqrt(f3d_max(F3D_R(1.0) - cy * cy, F3D_R(0.0))) + r);
      break;
    case F3D_SHAPE_BOX: {
      /* About its longest axis: the perimeter round the other two. */
      const f3d_real most = f3d_max(z.x, f3d_max(z.y, z.z));
      const f3d_real others = z.x + z.y + z.z - most;
      h->girth = F3D_R(4.0) * others + F3D_R(2.0) * F3D_PI * r;
      h->height = F3D_R(2.0) * (z.x * cx + z.y * cy + z.z * cz + r);
      break;
    }
    default:
      break;
  }
}

/* The liquid [s] stands in, for its entry [h]: none where it stands in
 * none, or none of the entry is under. */
static void wet_in(const F3dWorld *world, const F3dSlot *s, Heat *h) {
  h->liquid = NULL;
  h->liquid_speed = F3D_R(0.0);
  h->coldest = world->s.air_temperature;
  if (s->liquid == 0 || s->liquid > world->s.shallow_count) {
    h->l.immersed = F3D_R(0.0);
    return;
  }
  const F3dShallowSlot *w = &world->shallows[s->liquid - 1u];
  if (!w->live || !(h->l.immersed > F3D_R(0.0))) {
    h->l.immersed = F3D_R(0.0);
    return;
  }
  h->liquid = w;
  h->liquid_speed = s->liquid_speed;
  h->coldest = f3d_min(h->coldest, w->temperature);
}

/* Every live body's entries for the step: a body's own, or a compound's
 * parts', where they stand, with the heat laid in them grown by [dt]; heat
 * the body was given as a whole shared out by what each part holds. */
static int gather(F3dWorld *world, Heats *hs, f3d_real dt) {
  const uint32_t used = world->s.used;
  const F3dVec3 up = up_of(world);
  uint32_t total = 0;
  for (uint32_t i = 0; i < used; i++) {
    const F3dSlot *s = &world->slots[i];
    if (!s->live) continue;
    total += s->lumps != 0 ? s->lump_count : 1u;
  }
  hs->count = total;
  hs->h = (Heat *)f3d_alloc((size_t)total * sizeof(Heat) + 8u);
  hs->first = (uint32_t *)f3d_alloc((size_t)used * 2u * sizeof(uint32_t) + 8u);
  if (hs->h == NULL || hs->first == NULL) return 0;
  hs->many = hs->first + used;
  uint32_t at = 0;
  for (uint32_t i = 0; i < used; i++) {
    F3dSlot *s = &world->slots[i];
    hs->first[i] = at;
    hs->many[i] = 0;
    if (!s->live) continue;
    const int fed = s->feed > F3D_R(0.0);
    if (s->lumps == 0) {
      Heat *h = &hs->h[at++];
      f3d_zero(h, sizeof *h);
      h->l.temperature = s->temperature;
      h->l.interior = s->interior;
      h->l.reached = s->reached;
      h->l.skin = s->skin;
      h->l.heat = s->heat;
      h->bus = s->heat;
      h->l.water = s->water;
      h->l.fuel = s->fuel;
      h->l.mass = s->mass;
      h->l.heat_release = s->heat_release;
      h->l.involved = s->involved;
      h->l.spread = s->spread;
      h->l.rise = s->rise;
      h->l.patch = s->patch;
      h->l.exposure = s->exposure;
      h->l.char_depth = s->char_depth;
      h->l.char_skin = s->char_skin;
      h->l.charred = s->charred;
      h->l.burning = (own_fire(s) ? F3D_LUMP_OWN : 0u) |
                     ((s->flags & F3D_FLAG_BURNING) && fed ? F3D_LUMP_BURNER : 0u);
      h->slot = i;
      h->at = s->position;
      h->surface = s->surface;
      h->touch = touch_radius(s->shape, s->size);
      h->volume = s->shape == F3D_SHAPE_MESH
                      ? F3D_R(0.0)
                      : f3d_shape_volume(world, s->shape, s->size, s->rounding, s->hull);
      const F3dPlaced placed = f3d_placed_of(world, s);
      shape_of(h, &placed, up);
      h->feed = s->feed;
      h->fuel = fed ? &s->burner : NULL;
      h->flame = fed && !own_fire(s) ? &s->burner : &s->material;
      h->l.immersed = h->volume > F3D_R(0.0)
                          ? f3d_clamp(s->submerged / h->volume, F3D_R(0.0), F3D_R(1.0))
                          : F3D_R(0.0);
      wet_in(world, s, h);
      lay_heat(world, h, dt);
      hs->many[i] = 1;
      continue;
    }
    const F3dCompound *c = compound_of(world, s);
    const F3dPlaced whole = f3d_placed_of(world, s);
    f3d_real held = F3D_R(0.0);
    for (uint32_t k = 0; k < s->lump_count; k++) {
      const F3dLump *l = &world->lumps[s->lumps - 1u + k];
      held += l->mass * s->material.specific_heat + l->water * F3D_MAT_WATER_SPECIFIC_HEAT;
    }
    for (uint32_t k = 0; k < s->lump_count; k++) {
      const F3dCompoundPart *part = part_of(world, c, k);
      Heat *h = &hs->h[at++];
      f3d_zero(h, sizeof *h);
      h->l = world->lumps[s->lumps - 1u + k];
      const f3d_real mine = h->l.mass * s->material.specific_heat +
                            h->l.water * F3D_MAT_WATER_SPECIFIC_HEAT;
      if (held > F3D_R(0.0)) h->l.heat += s->heat * mine / held;
      /* Its part's own heat held to it, and its share of the body's. */
      h->bus = h->l.heat;
      h->slot = i;
      const F3dPlaced placed = f3d_placed_part(&whole, k);
      h->at = placed.at;
      h->surface = part_surface(world, part);
      h->touch = touch_radius(part->kind, part->size);
      h->reach = part->reach;
      h->volume = part_volume(world, part);
      shape_of(h, &placed, up);
      /* A burner feeds the first part. */
      const int here = fed && k == 0;
      h->feed = here ? s->feed : F3D_R(0.0);
      h->fuel = here ? &s->burner : NULL;
      h->flame = here && !(h->l.burning & F3D_LUMP_OWN) ? &s->burner : &s->material;
      wet_in(world, s, h);
      lay_heat(world, h, dt);
    }
    s->heat = F3D_R(0.0);
    hs->many[i] = s->lump_count;
  }
  return 1;
}

void f3d_step_heat(F3dWorld *world, f3d_real dt) {
  if (!ensure_lumps(world)) return;
  Heats hs;
  f3d_zero(&hs, sizeof hs);
  if (!gather(world, &hs, dt)) {
    f3d_free(hs.h);
    f3d_free(hs.first);
    return;
  }
  conduct(world, &hs, dt);
  conduct_within(world, &hs, dt);
  radiate(world, &hs, dt);
  /* Flames held to bodies: into the part nearest, a spot heated as a
   * flame's gas heats one, and let go. */
  for (uint32_t i = 0; i < world->s.used; i++) {
    F3dSlot *s = &world->slots[i];
    if (!s->live || hs.many[i] == 0 || !(s->held_flux > F3D_R(0.0))) continue;
    Heat *h = nearest(&hs, i, s->held_at);
    const f3d_real area = f3d_min(s->held_area, h->surface);
    h->l.heat += s->held_flux * area * dt;
    expose(h, EXPOSED_GAS, s->held_flux, area, s->held_temperature);
    s->held_flux = F3D_R(0.0);
  }
  for (uint32_t i = 0; i < world->s.used; i++) {
    F3dSlot *s = &world->slots[i];
    if (!s->live || hs.many[i] == 0) continue;
    const F3dBody handle = f3d_handle_of(world, s);
    const int was = (s->flags & F3D_FLAG_BURNING) != 0;
    uint32_t said = 0;
    for (uint32_t k = 0; k < hs.many[i]; k++) {
      said |= step_entry(world, s, &hs.h[hs.first[i] + k], dt);
    }
    if (s->lumps == 0) {
      /* A body: its fields back. */
      const F3dLump *l = &hs.h[hs.first[i]].l;
      s->temperature = l->temperature;
      s->interior = l->interior;
      s->reached = l->reached;
      s->skin = l->skin;
      s->heat = F3D_R(0.0);
      s->water = l->water;
      s->fuel = l->fuel;
      s->heat_release = l->heat_release;
      s->involved = l->involved;
      s->spread = l->spread;
      s->rise = l->rise;
      s->patch = l->patch;
      s->exposure = l->exposure;
      s->char_depth = l->char_depth;
      s->char_skin = l->char_skin;
      s->charred = l->charred;
      if (l->mass != s->mass) {
        s->mass = l->mass;
        f3d_refresh_mass(world, s);
      }
      s->flags &= (uint8_t)~(F3D_FLAG_BURNING | F3D_FLAG_OWN_FIRE);
      if (l->burning != 0) s->flags |= F3D_FLAG_BURNING;
      if (l->burning & F3D_LUMP_OWN) s->flags |= F3D_FLAG_OWN_FIRE;
    } else {
      /* A compound: the flame across its joints, its parts back, and the
       * body from them. */
      cross(world, &hs, i, dt);
      for (uint32_t k = 0; k < hs.many[i]; k++) {
        world->lumps[s->lumps - 1u + k] = hs.h[hs.first[i] + k].l;
      }
      body_from_lumps(world, s);
    }
    /* A burner gone under is out for good: its feed off. */
    if (said & DOUSED) {
      s->feed = F3D_R(0.0);
      f3d_push_event(world, handle, F3D_EVENT_BURNER_OUT);
    }
    /* What happened to the body as a whole: alight when it first burns,
     * out when it stops — burnt out when the fuel went, put out otherwise. */
    const int is = (s->flags & F3D_FLAG_BURNING) != 0;
    if (!was && is) {
      f3d_push_event(world, handle, F3D_EVENT_IGNITED);
    } else if (was && !is) {
      f3d_push_event(world, handle,
                     (said & BURNT_OUT) || s->fuel <= F3D_R(0.0)
                         ? F3D_EVENT_BURNT_OUT
                         : F3D_EVENT_EXTINGUISHED);
    }
  }
  f3d_free(hs.h);
  f3d_free(hs.first);
}

/* ---------------------------------------------------------- explosions */

/* The energy of a kilogram of TNT, J: the definition of the TNT
 * equivalent. */
#define F3D_TNT F3D_R(4.184e6)
/* The share of a charge's energy its products carry as motion: TNT's
 * Gurney energy, half its Gurney velocity 2.44 km/s squared, over the
 * energy above (Cooper, Explosives Engineering, table 27.1). */
#define F3D_GURNEY_SHARE F3D_R(2.977e6 / 4.184e6)
/* A body the blast would move by less than this, m/s, and warm by less than
 * F3D_RADIANT_LEAST over a second, is not worth the rays. */
#define F3D_BLAST_SLOWEST F3D_R(1e-3)

uint32_t f3d_world_explode(F3dWorld *world, f3d_real x, f3d_real y, f3d_real z,
                           f3d_real joules, f3d_real kg) {
  if (world == NULL || !(f3d_finite(x) && f3d_finite(y) && f3d_finite(z)) ||
      !(f3d_finite(joules) && joules > F3D_R(0.0)) || !f3d_finite(kg) ||
      kg < F3D_R(0.0)) {
    return 0;
  }
  const f3d_real mass = kg > F3D_R(0.0) ? kg : joules / F3D_TNT;
  const f3d_real moving = F3D_GURNEY_SHARE * joules;
  const f3d_real momentum = f3d_sqrt(F3D_R(2.0) * moving * mass);
  const f3d_real heat = joules - moving;
  const F3dVec3 at = f3d_v3(x, y, z);
  f3d_update_proxies(world, F3D_R(0.0));
  f3d_build_mesh_trees(world);
  uint32_t reached = 0;
  for (uint32_t i = 0; i < world->s.used; i++) {
    F3dSlot *s = &world->slots[i];
    if (!radiates(s) || !(s->surface > F3D_R(0.0))) continue;
    const F3dVec3 between = f3d_sub(s->position, at);
    const f3d_real d = f3d_sqrt(f3d_dot(between, between));
    const f3d_real r = f3d_sqrt(s->surface / (F3D_R(4.0) * F3D_PI));
    const f3d_real share = caught(r, d);
    const f3d_real push = momentum * share;
    const f3d_real warm = heat * share * s->material.emissivity;
    if (push * s->inverse_mass < F3D_BLAST_SLOWEST && warm < F3D_RADIANT_LEAST) {
      continue;
    }
    const F3dBody hb = f3d_handle_of(world, s);
    const f3d_real open = seen(world, at, 0, s->position, hb, r);
    if (!(open > F3D_R(0.0))) continue;
    reached++;
    if (d > F3D_R(0.0)) {
      const F3dVec3 away = f3d_scale(between, push * open / d);
      f3d_body_apply_impulse(world, hb, away.x, away.y, away.z);
    }
    /* Into the side that faces it. */
    const F3dVec3 facing =
        d > F3D_R(0.0) ? f3d_madd(s->position, between, -r / d) : s->position;
    f3d_body_add_heat_at(world, hb, facing.x, facing.y, facing.z, warm * open);
  }
  return reached;
}
