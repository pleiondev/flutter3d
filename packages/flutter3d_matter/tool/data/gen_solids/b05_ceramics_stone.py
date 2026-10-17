from core import P, NUL, E, law, table
from b01_pure_metals import TH, CP, mrgb
from b04_glass_ceramics import nm

R = 'recalled'
EST = dict(conf='estimate', ver=R)


def rock(E_, Er, nu, nur, ucs=None, ucsr=None):
    d = {'youngsModulus': P(E_, 'ROCKS', rng=Er, **EST), 'poissonRatio': P(nu, 'ROCKS', rng=nur, **EST)}
    if ucs:
        d['compressiveStrength'] = P(ucs, 'ROCKS', rng=ucsr, **EST)
    return d


ENTRIES = [
    E('graphite', 'graphite (pyrolytic)', 'solid', 'Pyrolytic graphite: strongly anisotropic; extruded electrode graphite in the notes.',
      ext={'CAS': '7782-42-5'},
      mech={'density': P(2210.0, 'INC_NM', note='extruded graphite 1710 (Callister)'),
            'youngsModulus': P(1.1e10, 'CALL', ver=R, conf='estimate', note='extruded polycrystalline graphite, 11 GPa'),
            'staticFriction': P(0.1, 'ETB_FR', note='clean and dry; also 0.1 greased'),
            'kineticFriction': NUL('not in the table read')},
      therm={'specificHeat': P(709.0, 'INC_NM'),
             'conductivity': P(1950.0, 'INC_NM', note='parallel to the layers; across them 5.70'),
             'conductivityAcross': P(5.70, 'INC_NM'), 'meltingPoint': P(2273.0, 'INC_NM', note='as tabulated (sublimes near 3900 K)'),
             'emissivity': P(0.81, 'ETB_EMI', note='carbon, not oxidized')},
      elec={'resistivity': P(3.75e-6, 'WIKI_RES', conf='estimate', rng=[2.5e-6, 5e-6], note='parallel to the basal plane; perpendicular 3e-3')},
      laws=[table(TH, 'INC_NM', [100, 200, 300, 400, 600, 800, 1000], [4970, 3230, 1950, 1390, 892, 667, 534], note='parallel to layers'),
            table('thermal.conductivityAcross', 'INC_NM', [100, 200, 300, 400, 600, 800, 1000], [16.8, 9.23, 5.70, 4.09, 2.68, 2.01, 1.60]),
            table(CP, 'INC_NM', [100, 200, 300, 400, 600, 800, 1000], [136, 411, 709, 992, 1406, 1650, 1793])]),

    E('quartz', 'quartz (crystalline SiO2)', 'solid', 'Crystalline quartz.',
      ext={'CAS': '14808-60-7', 'physicallybased.info': 'Quartz'},
      mech={'density': P(2650.0, 'INC_NM', note='physicallybased.info 2600')},
      therm={'specificHeat': P(745.0, 'INC_NM'), 'conductivity': P(10.4, 'INC_NM', note='parallel to the c axis; across it 6.21'),
             'conductivityAcross': P(6.21, 'INC_NM'), 'meltingPoint': P(1883.0, 'INC_NM'),
             'linearExpansion': P(11e-6, 'ETB_CTE', conf='estimate', rng=[8e-6, 14e-6], note='quartz, mineral; anisotropic')},
      opt={'refractiveIndex': P(1.544, 'RII', ver=R, note='ordinary ray; physicallybased.info rounds to 1.54')},
      laws=[table(TH, 'INC_NM', [100, 200, 300, 400, 600, 800], [39, 16.4, 10.4, 7.6, 5.0, 4.2], note='parallel to c axis'),
            table(CP, 'INC_NM', [300, 400, 600, 800], [745, 885, 1075, 1250])]),

    E('glassCeramic', 'glass-ceramic (Pyroceram 9606)', 'solid', 'Corning Pyroceram 9606 glass-ceramic (cooktops, radomes).',
      mech={'density': P(2600.0, 'INC_NM'), 'youngsModulus': P(1.2e11, 'CALL', ver=R, note='Callister glass-ceramic (Pyroceram)')},
      therm={'specificHeat': P(808.0, 'INC_NM'), 'conductivity': P(3.98, 'INC_NM'), 'meltingPoint': P(1623.0, 'INC_NM'),
             'emissivity': P(0.85, 'EMI', note='300 K; 0.57 at 1500 K')},
      laws=nm([5.25, 4.78, 3.98, 3.64, 3.28, 3.08, 2.96], [None, None, 808, 908, 1038, 1122, 1197]) +
           [table('thermal.emissivity', 'EMI', [300, 1500], [0.85, 0.57], conf='estimate', note='ends of the tabulated range')]),

    E('silicon', 'silicon (crystalline)', 'solid', 'Single-crystal silicon (a wafer).',
      ext={'CAS': '7440-21-3', 'physicallybased.info': 'Silicon'},
      mech={'density': P(2330.0, 'INC'), 'youngsModulus': P(1.29e11, 'CALL', ver=R, note='anisotropic: 130-185 GPa by direction (Engineering ToolBox)'),
            'poissonRatio': NUL('anisotropic; not read')},
      therm={'specificHeat': P(712.0, 'INC'), 'conductivity': P(148.0, 'INC'), 'meltingPoint': P(1685.0, 'INC')},
      acou={'speedOfSound': P(9620.0, 'OLY')},
      opt={'metalReflectance': mrgb([0.345, 0.369, 0.426], note='rendered as a metal in the database; a semiconductor, its F0 from n and k')},
      elec={'resistivity': P(2.3e3, 'WIKI_RES', note='intrinsic'), 'resistivityTempCoeff': P(-7.5e-2, 'WIKI_RES')},
      laws=[table(TH, 'INC', [100, 200, 300, 400, 600, 800, 1000], [884, 264, 148, 98.9, 61.9, 42.4, 31.2]),
            table(CP, 'INC', [100, 200, 300, 400, 600, 800, 1000], [259, 556, 712, 790, 867, 913, 946])]),

    E('siliconNitride', 'silicon nitride', 'solid', 'Silicon nitride ceramic.',
      ext={'CAS': '12033-89-5'},
      mech={'density': P(2400.0, 'INC_NM', note='Callister: hot pressed and sintered 3300, reaction bonded 2700'),
            'youngsModulus': P(3.04e11, 'CALL', ver=R, note='hot pressed')},
      therm={'specificHeat': P(691.0, 'INC_NM'), 'conductivity': P(16.0, 'INC_NM'), 'meltingPoint': P(2173.0, 'INC_NM')},
      laws=nm([16.0, 13.9, 11.3, 9.88, 8.76], [691, 778, 937, 1063, 1155], xs=[300, 400, 600, 800, 1000])),

    E('concrete', 'concrete (normal weight)', 'solid', 'Normal-weight concrete, stone mix, about C30.', catalogId='f3d.concrete',
      ext={'IFC4.Category': 'concrete', 'CAS': None, 'physicallybased.info': 'Concrete'},
      mech={'density': P(2300.0, 'MISC', note='stone mix; Cremer & Heckl dense concrete 2300'),
            'youngsModulus': P(3.0e10, 'EXISTING', note="ACI 318-19 for about 30 MPa (f3d.concrete); Cremer & Heckl dense concrete 26 GPa"),
            'poissonRatio': P(0.2, 'EXISTING', note='ACI 318 / EN 1992-1-1 3.1.3 uncracked'),
            'compressiveStrength': P(3.0e7, 'EXISTING', conf='estimate', note='the class the modulus assumes'),
            'staticFriction': NUL('concrete on concrete not read; wood on concrete 0.62, rubber on dry concrete 0.6-0.85 (pairs)'),
            'kineticFriction': NUL('not read')},
      therm={'specificHeat': P(880.0, 'MISC'), 'conductivity': P(1.4, 'MISC'),
             'linearExpansion': P(12e-6, 'ETB_CTE', conf='estimate', rng=[9.8e-6, 14e-6], note='concrete 13-14, concrete structure 9.8'),
             'emissivity': P(0.91, 'EMI', conf='estimate', rng=[0.88, 0.94])},
      acou={'speedOfSound': P(3700.0, 'ETB_SND'), 'rodWaveSpeed': P(3400.0, 'CH', note='dense concrete'),
            'absorption': P([0.01, 0.01, 0.02, 0.02, 0.02, 0.05], 'AKU', note='smooth unpainted concrete; rough concrete 0.02 0.03 0.03 0.03 0.04 0.07; f3d.concrete has 0.01 0.01 0.015 0.02 0.02 0.02 (concrete floor)')},
      opt={'refractiveIndex': P(1.5, 'PBI', conf='estimate', note='the database default 1.5')},
      inel={'damping': {'lossFactor': P(6e-3, 'CH', conf='estimate', rng=[4e-3, 8e-3], note='dense concrete')}},
      laws=[law(TH, 'polynomial', 'EN1992', ver=R, x='theta', xUnit='C', validRange=[20, 1200],
                form='upper limit: 2 - 0.2451 (theta/100) + 0.0107 (theta/100)^2; lower limit: 1.36 - 0.136 (theta/100) + 0.0057 (theta/100)^2',
                note='3.3.3; the national annex chooses between the two limits'),
            law(CP, 'piecewise', 'EN1992', ver=R, x='theta', xUnit='C',
                pieces=[{'range': [20, 100], 'form': '900'}, {'range': [100, 200], 'form': '900 + (theta - 100)'},
                        {'range': [200, 400], 'form': '1000 + (theta - 200) / 2'}, {'range': [400, 1200], 'form': '1100'}],
                note='3.3.2, dry siliceous and calcareous concrete; the moisture peak at 100-115 C is added separately'),
            table('mechanical.compressiveStrength', 'EN1992', [20, 100, 200, 300, 400, 500, 600, 700, 800, 900, 1000, 1100, 1200],
                  [1.0, 1.0, 0.95, 0.85, 0.75, 0.60, 0.45, 0.30, 0.15, 0.08, 0.04, 0.01, 0.0], x='theta', xunit='C', ver=R,
                  valueIs='factor on fck, siliceous aggregate (table 3.1)')]),

    E('lightweightConcrete', 'lightweight concrete', 'solid', 'Lightweight-aggregate concrete (expanded clay, shale, pumice), about 1300-1600 kg/m3.',
      ext={'IFC4.Category': 'concrete'},
      mech={'density': P(1300.0, 'CH', note='Cremer & Heckl light concrete; ASHRAE lists 960-1920 grades'),
            'youngsModulus': P(3.8e9, 'CH')},
      therm={'specificHeat': P(840.0, 'ASHRAE', note='1280-1600 kg/m3 grades'),
             'conductivity': P(0.54, 'ASHRAE', note='1280 kg/m3 grade; 1600: 0.79; 1920: 1.1; 960: 0.33')},
      acou={'rodWaveSpeed': P(1700.0, 'CH'),
            'absorption': P([0.05, 0.05, 0.05, 0.08, 0.14, 0.2], 'AKU', note='porous concrete blocks, no surface finish')},
      inel={'damping': {'lossFactor': P(1.5e-2, 'CH')}}),

    E('brick', 'brick (common, fired clay)', 'solid', 'Common fired-clay brick.', catalogId='f3d.brick',
      ext={'IFC4.Category': 'brick', 'MaterialX': 'standard_surface_brick_procedural', 'physicallybased.info': 'Brick'},
      mech={'density': P(1922.0, 'ASHRAE', note='common brick; face brick 2082, fire clay 2400; Cremer & Heckl 1900-2200; f3d.brick 1920'),
            'youngsModulus': NUL('Cremer & Heckl prints 2.5-3e10 dyn/cm2 (2.5-3 GPa) beside a wavespeed of 2500-3000 m/s, which implies 12-18 GPa: unresolved'),
            'poissonRatio': NUL('not read'),
            'staticFriction': NUL('brick on brick not read; wood on brick 0.6 (pairs)')},
      therm={'specificHeat': P(835.0, 'EXISTING', note='Incropera A.3 common brick (f3d.brick); ASHRAE fire clay 1920 kg/m3: 790'),
             'conductivity': P(0.72, 'ASHRAE', note='common brick; face brick 1.30'),
             'linearExpansion': P(5.5e-6, 'ETB_CTE', conf='estimate', rng=[4.7e-6, 9.0e-6], note='brick masonry 5, masonry brick 4.7-9.0'),
             'emissivity': P(0.93, 'EMI', note='common brick 0.93-0.96; fireclay at 1200 K 0.75')},
      acou={'rodWaveSpeed': P(2750.0, 'CH', conf='estimate', rng=[2500.0, 3000.0]),
            'speedOfSound': P(4200.0, 'ETB_SND', note='unlabelled column in the table read'),
            'absorption': P([0.03, 0.03, 0.03, 0.04, 0.05, 0.07], 'EXISTING', note='unglazed brick (Everest & Pohlmann), as f3d.brick; akustik.ua smooth brickwork with flush pointing is the same')},
      inel={'damping': {'lossFactor': P(1.5e-2, 'CH', conf='estimate', rng=[1e-2, 2e-2])}}),

    E('granite', 'granite', 'solid', 'Granite (Barre granite for the thermal data).', catalogId='f3d.granite',
      ext={'IFC4.Category': 'stone'},
      mech=dict(density=P(2630.0, 'INC_A3', ver=R, note='Barre granite, as f3d.granite'),
                **rock(5.0e10, [4e10, 7e10], 0.25, [0.2, 0.3], 1.75e8, [1e8, 2.5e8]),
                staticFriction=NUL('dry granite-on-granite sliding friction about 0.6-0.85 in rock-mechanics tests (Byerlee) but not read here')),
      therm={'specificHeat': P(775.0, 'INC_A3', ver=R), 'conductivity': P(2.79, 'INC_A3', ver=R),
             'linearExpansion': P(8.1e-6, 'ETB_CTE', rng=[7.9e-6, 8.4e-6]),
             'emissivity': P(0.96, 'ETB_EMI', note='natural surface; f3d.granite uses 0.93')},
      acou={'speedOfSound': P(5950.0, 'ETB_SND', note='unlabelled column'),
            'absorption': NUL('akustik.ua "stone floor, plain or tooled" gives 0.02 at 125 and 500 Hz and 0.05 at 2-4 kHz with blanks at 250 and 1000 Hz; smooth marble 0.01 0.01 0.01 0.01 0.02 0.02 is the nearest full row')}),
]
