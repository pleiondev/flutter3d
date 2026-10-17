from core import P, NUL, E, law, table
from b01_pure_metals import TH, CP

R = 'recalled'
ICE_CP = law(CP, 'polynomial', 'CP2010', ver=R, form='152.5 + 7.122 T', validRange=[200.0, 273.15],
             note='J/(kg K), T in K; snow and firn take the ice value per kg')
ICE_K = law(TH, 'exponential', 'CP2010', ver=R, form='9.828 exp(-5.7e-3 T)', validRange=[200.0, 273.15],
            note='W/(m K), T in K; gives 2.07 at 273 K')
SNOW_K = law(TH, 'piecewisePolynomial', 'STURM97', ver=R, x='rho', xUnit='g/cm3',
             pieces=[{'range': [0.0, 0.156], 'form': '0.023 + 0.234 rho'},
                     {'range': [0.156, 0.6], 'form': '0.138 - 1.01 rho + 3.233 rho^2'}],
             note='effective conductivity of seasonal snow against its density, not temperature')


def snow(rho, rng, desc_id, name, desc):
    r = rho / 1000.0
    k = 0.023 + 0.234 * r if r < 0.156 else 0.138 - 1.01 * r + 3.233 * r * r
    return E(desc_id, name, 'granular', desc,
             ext={'CAS': '7732-18-5 (water)', 'physicallybased.info': 'Snow'},
             mech={'density': P(rho, 'PAT_SNOW', rng=rng, conf='estimate', ver=R, note='a representative density in the class\'s range'),
                   'youngsModulus': NUL('snow\'s modulus spans 0.1-1000 MPa with density and bonding; not read'),
                   'poissonRatio': NUL('not read'),
                   'staticFriction': NUL('snow on snow not read; waxed ski on snow in pairs'),
                   'kineticFriction': NUL('not read')},
             therm={'specificHeat': P(2097.0, 'CP2010', ver=R, note='ice at 273 K per kilogram of snow, from the law'),
                    'conductivity': P(round(k, 4), 'STURM97', ver=R, conf='estimate', note=f'Sturm 1997 at {r} g/cm3'),
                    'meltingPoint': P(273.15, 'CP2010', ver=R), 'latentHeatOfFusion': P(3.34e5, 'EXISTING', note='as f3d.ice'),
                    'emissivity': P(0.85, 'EMI', conf='estimate', rng=[0.80, 0.90],
                                    note='Cengel A-18 at 273 K; Engineering ToolBox gives 0.96-0.98 and thermal-infrared measurements of snow are usually 0.97-0.99: check before use')},
             acou={'absorption': NUL('Engineering ToolBox gives a single 0.75 for snow, no octave bands')},
             opt={'refractiveIndex': P(1.3098, 'PBI', note='of the ice grains')},
             laws=[SNOW_K, ICE_CP])


ENTRIES = [
    E('sand', 'sand (dry)', 'granular', 'Dry sand as it piles: bulk density with its air.', catalogId='f3d.sand',
      ext={'IFC4.Category': 'earth', 'CAS': '14808-60-7 (quartz)', 'physicallybased.info': 'Sand'},
      mech={'density': P(1515.0, 'MISC', note='as f3d.sand; Cremer & Heckl dry sand 1500'),
            'youngsModulus': P(3.0e7, 'CH', note='bulk dry sand, small strain; strongly pressure dependent'),
            'staticFriction': NUL('a granular bed\'s friction is its internal friction angle (about 30-35 deg, tan 0.6-0.7) and grain-on-grain about 0.5; neither read here'),
            'kineticFriction': NUL('not read')},
      therm={'specificHeat': P(800.0, 'MISC'), 'conductivity': P(0.27, 'EXISTING', note='Incropera A.3 (f3d.sand); Cengel A-8 gives 0.2-1.0 with moisture'),
             'emissivity': P(0.90, 'EMI')},
      acou={'rodWaveSpeed': P(135.0, 'CH', conf='estimate', rng=[100.0, 170.0])},
      opt={'refractiveIndex': NUL('grains are quartz, 1.544; a bed is a scatterer')},
      inel={'damping': {'lossFactor': P(0.09, 'CH', conf='estimate', rng=[0.06, 0.12], note='dry sand')}}),

    E('soil', 'soil (moist, generic)', 'granular', 'Soil as Incropera tabulates it.', catalogId='f3d.soil',
      ext={'IFC4.Category': 'earth'},
      mech={'density': P(2050.0, 'INC_A3', ver=R, note='as f3d.soil')},
      therm={'specificHeat': P(1840.0, 'INC_A3', ver=R), 'conductivity': P(0.52, 'INC_A3', ver=R),
             'emissivity': P(0.945, 'EMI', conf='estimate', rng=[0.93, 0.96], note='soil, earth')},
      notes=['dry and wet soils below carry the moisture dependence']),

    E('soilDry', 'soil (dry)', 'granular', 'Dry soil.', ext={'IFC4.Category': 'earth'},
      mech={'density': P(1500.0, 'MISC')},
      therm={'specificHeat': P(1900.0, 'MISC'), 'conductivity': P(1.0, 'MISC', note='high for a dry soil; mineral soils range 0.2-1 dry'),
             'emissivity': P(0.945, 'EMI', conf='estimate', rng=[0.93, 0.96])}),

    E('soilWet', 'soil (wet)', 'granular', 'Wet soil.', ext={'IFC4.Category': 'earth'},
      mech={'density': P(1900.0, 'MISC')},
      therm={'specificHeat': P(2200.0, 'MISC'), 'conductivity': P(2.0, 'MISC'),
             'emissivity': P(0.945, 'EMI', conf='estimate', rng=[0.93, 0.96])}),

    E('clayDry', 'clay (dry)', 'granular', 'Dry clay.', ext={'IFC4.Category': 'earth'},
      mech={'density': P(1550.0, 'MISC')},
      therm={'conductivity': P(0.930, 'MISC'), 'emissivity': P(0.91, 'ETB_EMI')}),

    E('clayWet', 'clay (wet)', 'granular', 'Wet clay.', ext={'IFC4.Category': 'earth'},
      mech={'density': P(1495.0, 'MISC', note='as tabulated: lower than the dry row')},
      therm={'conductivity': P(1.675, 'MISC'), 'emissivity': P(0.91, 'ETB_EMI')}),

    snow(100.0, [50.0, 200.0], 'snowFresh', 'snow (fresh)', 'New-fallen snow.'),
    snow(375.0, [350.0, 400.0], 'snowPacked', 'snow (wind-packed)', 'Wind-packed or groomed snow.'),

    E('ice', 'ice (Ih)', 'solid', 'Ordinary ice Ih; its reference state is 273.15 K, below its 20 C reference.', catalogId='f3d.ice',
      ext={'CAS': '7732-18-5 (water)', 'physicallybased.info': 'Ice'},
      mech={'density': P(920.0, 'MISC', note='273 K; 253 K: 922; 173 K: 928'),
            'youngsModulus': P(9.3e9, 'PW99', ver=R, conf='estimate', note='polycrystalline, near 263 K, high-frequency; creep makes it far softer under sustained load'),
            'poissonRatio': P(0.33, 'PW99', ver=R, conf='estimate'),
            'tensileStrength': P(1.0e6, 'PW99', ver=R, conf='estimate', rng=[0.7e6, 3.1e6]),
            'compressiveStrength': P(1.0e7, 'PW99', ver=R, conf='estimate', rng=[5e6, 2.5e7], note='rate and temperature dependent'),
            'staticFriction': P(0.1, 'ETB_FR', note='clean, 0 C; as f3d.ice (Serway)'),
            'kineticFriction': P(0.02, 'ETB_FR', note='clean, 0 C; f3d.ice has 0.03 (Serway)'),
            'restitution': NUL('speed and temperature dependent; see the law (frost-covered ice at 165 K)')},
      therm={'specificHeat': P(2040.0, 'MISC', note='273 K'), 'conductivity': P(1.88, 'MISC', note='273 K; the Cuffey-Paterson law gives 2.07'),
             'meltingPoint': P(273.15, 'CP2010', ver=R), 'latentHeatOfFusion': P(3.34e5, 'EXISTING', note='CRC (f3d.ice)'),
             'linearExpansion': P(51e-6, 'ETB_CTE', note='at 0 C'),
             'emissivity': P(0.97, 'EMI', conf='estimate', rng=[0.95, 0.99], note='Engineering ToolBox: smooth 0.966, rough 0.985')},
      opt={'refractiveIndex': P(1.3098, 'PBI', note='f3d.ice has 1.309 (CRC)')},
      laws=[table('mechanical.density', 'MISC', [173, 253, 273], [928, 922, 920]),
            table(TH, 'MISC', [173, 253, 273], [3.49, 2.03, 1.88]),
            table(CP, 'MISC', [173, 253, 273], [1460, 1945, 2040]),
            ICE_K, ICE_CP,
            table('mechanical.staticFriction', 'ETB_FR', [193.15, 261.15, 273.15], [0.5, 0.3, 0.1], note='clean ice on ice at -80, -12 and 0 C'),
            table('mechanical.kineticFriction', 'ETB_FR', [193.15, 261.15, 273.15], [0.09, 0.035, 0.02], note='clean ice on ice at -80, -12 and 0 C'),
            law('mechanical.restitution', 'power', 'BRIDGES84', ver=R, conf='measured', x='v', xUnit='m/s',
                form='e = (v / 7.7e-5)^(-0.234), capped at 1', validRange=[1e-5, 0.05],
                note='frost-covered ice spheres at about 165 K: low speeds only; not a game-speed bounce')]),

    E('rockSalt', 'rock salt (halite)', 'solid', 'Sodium chloride crystal.',
      ext={'CAS': '7647-14-5', 'physicallybased.info': 'Salt'},
      mech={'density': P(2170.0, 'PBI')},
      opt={'refractiveIndex': P(1.5441, 'PBI')},
      therm={'meltingPoint': P(1074.0, 'CRC_MP', ver=R, note='801 C')}),
]
