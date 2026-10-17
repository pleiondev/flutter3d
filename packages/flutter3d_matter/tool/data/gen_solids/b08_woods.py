from core import P, NUL, E, law, table
from b01_pure_metals import TH, CP

R = 'recalled'
M = 12.0  # moisture content, %
CP12 = 1620.0  # Wood Handbook eqs. 4-16a, 4-17, 4-18 at 293.15 K and 12 % MC (computed)

WOOD_CP_LAW = law(CP, 'formula', 'WH4', form=('cp0 = 103.1 + 3.867 T (J/(kg K), dry); cp = (cp0 + 4180 x/100)/(1 + x/100) '
                                           '+ 1000 x (b1 + b2 T + b3 x), b1 = -0.06191, b2 = 2.36e-4, b3 = -1.33e-4; '
                                           'x = moisture content %, T in K'),
                  validRange=[280.0, 420.0], coefficients={'x': M},
                  note='valid below fibre saturation; gives 1620 J/(kg K) at 293 K and 12 %, table 4-8 says 1.6 kJ/(kg K) at 290 K')
WOOD_K_T = law(TH, 'linear', 'WH4', conf='estimate', form='k(T) = k20 (1 + 0.0025 (T - 293.15))', validRange=[250.0, 370.0],
               note='the handbook says conductivity rises 2-3 % per 10 C; 2.5 % taken')
WOOD_FR = {'staticFriction': P(0.375, 'ETB_FR', conf='estimate', rng=[0.25, 0.5], note='clean dry wood on wood, midpoint; wet wood 0.2'),
           'kineticFriction': NUL('wood on wood kinetic not read; the Wood Handbook gives smooth dry wood on hard smooth surfaces 0.3-0.5, 0.5-0.7 at intermediate moisture, 0.7-0.9 near fibre saturation')}
WOOD_ELEC = {'resistivity': P(1e15, 'WIKI_RES', conf='estimate', rng=[1e14, 1e16],
                              note='oven-dry; damp wood 1e3-1e4: resistivity falls steeply with moisture')}


def wood(id, name, desc, sg, mor, moe, comp, ratios, mu_lr, k12, hard=None, catalogId=None, ext=None,
         therm_extra=None, mech_extra=None, notes=None, acou=None, sg_k=None):
    rho = round(1000.0 * sg * (1 + M / 100.0), 0)
    er = round(ratios[1] * moe * 1e9, -6) if ratios else None
    g0 = sg_k or sg
    mech = {'density': P(rho, 'WH5', conf='handbook', note=f'1000 G (1 + MC) with G = {sg} at 12 % MC (table 5-3a); the 12 % density'),
            'youngsModulus': (P(er, 'WH5', note=f'radial, across the grain: ER/EL {ratios[1]} (table 5-1) x EL {moe} GPa (table 5-3a); along the grain {moe} GPa; bending MOE, +10 % for shear') if er
                              else NUL(f'no elastic ratios in table 5-1; along the grain {moe} GPa')),
            'youngsModulusAlongGrain': P(moe * 1e9, 'WH5', note='static bending, 12 % MC'),
            'poissonRatio': (P(mu_lr, 'WH5', note='mu_LR, table 5-2') if mu_lr else NUL('not in table 5-2')),
            'flexuralStrength': P(mor * 1e6, 'WH5', note='modulus of rupture, 12 % MC'),
            'compressiveStrength': P(comp * 1e6, 'WH5', note='parallel to grain, maximum crushing strength'),
            **WOOD_FR}
    if hard:
        mech['jankaHardness'] = P(hard, 'WH5', note='side hardness, N (a force, not a pressure)')
    if mech_extra:
        mech.update(mech_extra)
    therm = {'specificHeat': P(CP12, 'WH4', conf='handbook', note='computed from eqs. 4-16a..4-18 at 293 K, 12 % MC'),
             'conductivity': P(k12, 'WH4', note='table 4-7, 12 % MC, across the grain; along the grain about 1.8x'),
             'linearExpansion': P(round((32.4 * g0 + 18.4) * 1e-6, 9), 'WH4', conf='estimate',
                                  note=f'tangential, oven-dry, eq. 4-20a with G0 = {g0}; radial (32.4 G0 + 9.9)e-6; along the grain 3.1-4.5e-6'),
             'emissivity': P(0.90, 'EMI', note='oak 300 K; beech 0.94; Engineering ToolBox planed oak 0.885, pine 0.84-0.95')}
    if therm_extra:
        therm.update(therm_extra)
    return E(id, name, 'solid', desc, catalogId=catalogId, ext=dict({'IFC4.Category': 'wood'}, **(ext or {})),
             mech=mech, therm=therm, acou=acou or {'speedOfSound': P(3960.0, 'ETB_SND', note='"wood (hard)", unlabelled column; parallel to grain 3300-5000')},
             elec=WOOD_ELEC, inel={'damping': {'lossFactor': P(1e-2, 'CH', note='oak; fir 8e-3')}},
             laws=[WOOD_CP_LAW, WOOD_K_T], notes=(notes or []) + ['12 % moisture content, the air-dry state'])


ENTRIES = [
    wood('oak', 'oak (northern red)', 'Northern red oak, 12 % moisture.', 0.63, 99, 12.5, 46.6, (0.082, 0.154), 0.350, 0.18,
         hard=5700, catalogId='f3d.oak', sg_k=0.65,
         therm_extra={'specificHeat': P(1730.0, 'EXISTING', note="Parker's (1989) value kept by f3d.oak; the Wood Handbook law gives 1620 at 12 % MC"),
                      'ignitionTemperature': P(588.15, 'EXISTING', note='Tran & White (1992), as f3d.oak'),
                      'heatOfCombustion': P(12.4e6, 'EXISTING', note='as f3d.oak')},
         notes=['f3d.oak has density 545 (Incropera A.3 oak across the grain), E 0.91 GPa and nu 0.29 taken from Douglas-fir; the oak-specific numbers here replace them']),
    wood('pine', 'pine (loblolly, southern yellow)', 'Loblolly pine, 12 % moisture.', 0.51, 88, 12.3, 49.2, (0.078, 0.113), 0.328, 0.15,
         hard=3100, catalogId='f3d.pine', sg_k=0.54,
         therm_extra={'ignitionTemperature': P(593.15, 'EXISTING', note='Tran & White (1992), as f3d.pine'),
                      'heatOfCombustion': P(13.9e6, 'EXISTING', note='as f3d.pine')},
         notes=['f3d.pine has density 640 (Incropera A.3 yellow pine); loblolly at 12 % MC is 571']),
    wood('pineEasternWhite', 'pine (eastern white)', 'Eastern white pine, 12 % moisture.', 0.35, 59, 8.5, 33.1, None, None, 0.11, hard=1700, sg_k=0.37),
    wood('birch', 'birch (yellow)', 'Yellow birch, 12 % moisture.', 0.62, 114, 13.9, 56.3, (0.050, 0.078), 0.426, 0.18, hard=5600, sg_k=0.66),
    wood('maple', 'maple (sugar, hard maple)', 'Sugar maple, 12 % moisture.', 0.63, 109, 12.6, 54.0, (0.065, 0.132), 0.424, 0.18, hard=6400, sg_k=0.66),
    wood('douglasFir', 'Douglas-fir (coast)', 'Coast Douglas-fir, 12 % moisture.', 0.48, 85, 13.4, 49.9, (0.050, 0.068), 0.292, 0.14, hard=3200, sg_k=0.51,
         acou={'speedOfSound': P(3960.0, 'ETB_SND', note='"wood (hard)"'), 'rodWaveSpeed': P(2500.0, 'CH', note='fir')}),
    wood('spruce', 'spruce (Sitka)', 'Sitka spruce, 12 % moisture: the tonewood.', 0.40, 70, 10.8, 38.7, (0.043, 0.078), 0.372, 0.12, hard=2300, sg_k=0.42),
    wood('balsa', 'balsa', 'Balsa (Ochroma pyramidale), 12 % moisture.', 0.16, 21.6, 3.4, 14.9, (0.015, 0.046), 0.229, 0.055,
         therm_extra={'conductivity': P(0.055, 'MISC', note='balsa across the grain at 140 kg/m3')},
         notes=['strength from table 5-5a (imported woods); thermal from Cengel A-8']),

    E('wood', 'wood (plywood, Douglas-fir)', 'solid', 'Plain plywood, as f3d.wood: the generic wood.', catalogId='f3d.wood',
      ext={'IFC4.Category': 'wood', 'MaterialX': 'standard_surface_wood_tiled'},
      mech={'density': P(545.0, 'ASHRAE', note='plywood (Douglas fir); Cremer & Heckl plywood 600'),
            'youngsModulus': P(9.1e8, 'EXISTING', note='across the grain from Douglas-fir ratios (f3d.wood); Cremer & Heckl plywood in-plane 5.4 GPa'),
            'youngsModulusInPlane': P(5.4e9, 'CH'),
            'poissonRatio': P(0.29, 'EXISTING', note='Douglas-fir mu_LR (f3d.wood)'), **WOOD_FR},
      therm={'specificHeat': P(1210.0, 'ASHRAE', note='plywood; f3d.wood uses 1700'), 'conductivity': P(0.12, 'ASHRAE'),
             'emissivity': P(0.90, 'EMI', note='oak 300 K'),
             'ignitionTemperature': P(663.15, 'EXISTING', note='Quintiere & Harkleroad, plywood 1.27 cm (f3d.wood)'),
             'heatOfCombustion': P(1.5e7, 'EXISTING', conf='estimate', note='"about fifteen megajoules a kilogram, a wood\'s in general" (f3d.wood)')},
      acou={'rodWaveSpeed': P(3000.0, 'CH', note='plywood'),
            'absorption': P([0.42, 0.21, 0.10, 0.08, 0.06, 0.06], 'PRA', note='thin plywood panelling; a panel absorbs by its mounting, so this is a construction\'s value; the classic 3/8 in plywood panel row reads 0.28 0.22 0.17 0.09 0.10 0.11 (sengpielaudio.com/calculator-RT60Coeff.htm, seen in a search summary only)')},
      elec=WOOD_ELEC, inel={'damping': {'lossFactor': P(1.3e-2, 'CH', note='plywood')}}),

    E('hardwoodGeneric', 'hardwood (generic: maple, oak)', 'solid', 'Generic hardwood as ASHRAE tabulates it.', ext={'IFC4.Category': 'wood'},
      mech={'density': P(721.0, 'ASHRAE'), **WOOD_FR},
      therm={'specificHeat': P(1260.0, 'ASHRAE'), 'conductivity': P(0.159, 'ASHRAE'), 'emissivity': P(0.90, 'EMI', note='oak')},
      acou={'absorption': P([0.15, 0.11, 0.10, 0.07, 0.06, 0.07], 'AKU', note='wooden floor on joists')}),

    E('softwoodGeneric', 'softwood (generic: fir, pine)', 'solid', 'Generic softwood as ASHRAE tabulates it.', ext={'IFC4.Category': 'wood'},
      mech={'density': P(513.0, 'ASHRAE'), **WOOD_FR},
      therm={'specificHeat': P(1380.0, 'ASHRAE'), 'conductivity': P(0.115, 'ASHRAE'), 'emissivity': P(0.90, 'EMI', note='oak; pine 0.84-0.95')}),

    E('hardboard', 'hardboard / MDF (high density)', 'solid', 'High-density hardboard (standard tempered); MDF is close.', ext={'IFC4.Category': 'wood'},
      mech={'density': P(1010.0, 'ASHRAE'), 'youngsModulus': P(4.6e9, 'CH', note='pressed-wood panels, 600-700 kg/m3'), **WOOD_FR},
      therm={'specificHeat': P(1340.0, 'ASHRAE'), 'conductivity': P(0.14, 'ASHRAE')},
      acou={'rodWaveSpeed': P(2700.0, 'CH', note='pressed-wood panels')},
      inel={'damping': {'lossFactor': P(2e-2, 'CH', conf='estimate', rng=[1e-2, 3e-2], note='pressed-wood panels')}}),

    E('particleboard', 'particleboard (medium density)', 'solid', 'Medium-density particleboard (chipboard).', ext={'IFC4.Category': 'wood'},
      mech={'density': P(800.0, 'ASHRAE'), **WOOD_FR},
      therm={'specificHeat': P(1300.0, 'ASHRAE'), 'conductivity': P(0.14, 'ASHRAE')},
      acou={'absorption': P([0.20, 0.25, 0.20, 0.20, 0.15, 0.20], 'AKU', note='chipboard on 16 mm battens, 20 mm')}),

    E('cork', 'cork (board)', 'solid', 'Cork board.', ext={'IFC4.Category': None},
      mech={'density': P(120.0, 'ASHRAE', note='Cremer & Heckl 120-250; Cengel A-8 cork 86'),
            'youngsModulus': P(2.5e7, 'CH'),
            'poissonRatio': NUL('cork\'s Poisson ratio is near zero (Gibson & Ashby, Cellular Solids) but no number was read')},
      therm={'specificHeat': P(1800.0, 'ASHRAE', note='Cengel A-8: 2030'), 'conductivity': P(0.039, 'ASHRAE', note='Cengel A-8: 0.048')},
      acou={'speedOfSound': P(518.0, 'ETB_SND', note='unlabelled column; Cremer & Heckl rod speed 430'), 'rodWaveSpeed': P(430.0, 'CH'),
            'absorption': P([0.03, 0.05, 0.17, 0.52, 0.50, 0.52], 'AKU', note='cork board 25 mm on solid backing')},
      inel={'damping': {'lossFactor': P(0.15, 'CH', conf='estimate', rng=[0.13, 0.17])}}),
]
