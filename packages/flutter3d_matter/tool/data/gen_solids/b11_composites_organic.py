from core import P, NUL, E, law, table
from b01_pure_metals import TH, CP

R = 'recalled'
EST = dict(conf='estimate', ver=R)

ENTRIES = [
    E('carbonFiberComposite', 'carbon-fibre/epoxy composite (CFRP)', 'solid', 'Unidirectional carbon-fibre/epoxy, fibre volume about 0.6.',
      ext={'IFC4.Category': 'plastic'},
      mech={'density': P(1600.0, 'CALL', ver=R, note='Vf 0.65; Incropera graphite-fibre epoxy at Vf 0.25: 1400'),
            'youngsModulus': P(1.0e10, 'CALL', ver=R, note='transverse; along the fibres 142 GPa (Callister); quasi-isotropic laminates about 50 GPa'),
            'youngsModulusAlongFibre': P(1.42e11, 'CALL', ver=R),
            'poissonRatio': NUL('laminate dependent; not read')},
      therm={'specificHeat': P(935.0, 'INC_NM', note='graphite-fibre epoxy, Vf 0.25'),
             'conductivity': P(0.87, 'INC_NM', note='across the fibres, Vf 0.25; along them 11.1'),
             'conductivityAlongFibre': P(11.1, 'INC_NM')},
      acou={'speedOfSound': P(3070.0, 'OLY', note='"composite, graphite/epoxy", thickness direction')},
      laws=[table(TH, 'INC_NM', [100, 200, 300, 400], [0.46, 0.68, 0.87, 1.1], note='across the fibres'),
            table('thermal.conductivityAlongFibre', 'INC_NM', [100, 200, 300, 400], [5.7, 8.7, 11.1, 13.0]),
            table(CP, 'INC_NM', [100, 200, 300, 400], [337, 642, 935, 1216])]),

    E('fiberglassComposite', 'glass-fibre/epoxy composite (GFRP)', 'solid', 'Unidirectional E-glass/epoxy, fibre volume about 0.6.',
      ext={'IFC4.Category': 'plastic'},
      mech={'density': P(2100.0, 'CALL', ver=R),
            'youngsModulus': P(1.2e10, 'CALL', ver=R, note='transverse; along the fibres 45 GPa'),
            'youngsModulusAlongFibre': P(4.5e10, 'CALL', ver=R)},
      acou={'speedOfSound': P(2740.0, 'OLY', note='"fiberglass"')}),

    E('bone', 'bone (cortical)', 'solid', 'Compact (cortical) bone, wet, human femur for the moduli.',
      ext={'physicallybased.info': 'Bone'},
      mech={'density': P(1900.0, 'PBI', note='physicallybased.info bone; cortical bone 1800-2000'),
            'youngsModulus': P(1.8e10, 'ETB_E', note='compact bone; Reilly & Burstein femur 17.4 GPa along, 9.6 GPa across'),
            'compressiveStrength': P(1.7e8, 'ETB_E', note='compact bone'),
            'tensileStrength': P(1.35e8, 'REILLY', ver=R, note='longitudinal')},
      opt={'refractiveIndex': P(1.5, 'PBI', conf='estimate', note='database default')},
      elec={'resistivity': P(166.0, 'WIKI_RES')}),

    E('leather', 'leather (sole)', 'solid', 'Vegetable-tanned sole leather.',
      mech={'density': P(998.0, 'MISC'), 'staticFriction': NUL('leather on leather not read; leather on wood 0.3-0.4 (pairs)')},
      therm={'conductivity': P(0.159, 'MISC'), 'specificHeat': NUL('not read')},
      acou={'absorption': P([0.40, 0.50, 0.58, 0.61, 0.58, 0.50], 'AKU', conf='estimate', note='"seats, leather covers, per m2": an upholstered seat, not a sheet')}),

    E('paper', 'paper', 'solid', 'Paper, as a sheet or stack.', catalogId='f3d.paper',
      ext={'CAS': '9004-34-6 (cellulose)', 'physicallybased.info': 'Office Paper'},
      mech={'density': P(930.0, 'MISC'),
            'youngsModulus': P(2.0e9, 'EXISTING', conf='estimate', note='low end of 2-8 GPa in-plane (Mark & Borch), f3d.paper'),
            'poissonRatio': P(0.3, 'EXISTING', conf='estimate')},
      therm={'specificHeat': P(1340.0, 'MISC'), 'conductivity': P(0.180, 'MISC', note='a solid sheet; f3d.paper uses 0.05 for a stack with air'),
             'emissivity': P(0.90, 'EMI', note='white paper; Engineering ToolBox 0.93, offset paper 0.55'),
             'ignitionTemperature': P(506.15, 'EXISTING', conf='estimate', note='451 F (f3d.paper)')}),

    E('cardboard', 'cardboard (corrugated)', 'solid', 'Corrugated board, dry.', catalogId='f3d.cardboard',
      mech={'youngsModulus': P(2.0e9, 'EXISTING', conf='estimate', note='a sheet\'s in-plane modulus, as f3d.paper'),
            'density': NUL('not read; board density depends on flute; f3d.cardboard has none')},
      therm={'specificHeat': P(1800.0, 'EXISTING', note='Semmes et al. 2014, virgin layers (f3d.cardboard)'),
             'conductivity': P(0.10, 'EXISTING', note='Semmes et al. 2014 (f3d.cardboard)'),
             'emissivity': P(0.70, 'EXISTING', note='Semmes et al. 2014 (f3d.cardboard)'),
             'heatOfCombustion': P(14.03e6, 'EXISTING', conf='measured', note='UL FSRI (f3d.cardboard)')}),

    E('cotton', 'cotton (batting)', 'solid', 'Cotton fibre batting.', catalogId='f3d.cotton',
      ext={'CAS': '9004-34-6 (cellulose)'},
      mech={'density': P(80.0, 'MISC')},
      therm={'specificHeat': P(1300.0, 'MISC'), 'conductivity': P(0.06, 'MISC'),
             'emissivity': P(0.77, 'ETB_EMI', note='cotton cloth; Cengel A-18 cloth 0.75-0.90')},
      acou={'absorption': P([0.07, 0.31, 0.49, 0.81, 0.66, 0.54], 'PRA', conf='estimate', note='cotton carpet, a construction')}),

    E('wool', 'wool (sheep, batting)', 'solid', 'Sheep\'s wool batting.',
      mech={'density': P(145.0, 'MISC')}, therm={'conductivity': P(0.05, 'MISC')}),

    E('linoleum', 'linoleum', 'solid', 'Linoleum floor covering.',
      mech={'density': P(1180.0, 'MISC', note='a 535 kg/m3 row (0.081 W/mK) is also tabulated')},
      therm={'conductivity': P(0.186, 'MISC'), 'specificHeat': P(1260.0, 'ASHRAE', note='tile: asphalt, linoleum, vinyl')},
      acou={'absorption': P([0.02, 0.02, 0.03, 0.04, 0.04, 0.05], 'AKU', note='linoleum or vinyl stuck to concrete')}),

    E('bakelite', 'Bakelite (phenolic)', 'solid', 'Phenol-formaldehyde moulding.',
      mech={'density': P(1300.0, 'MISC')},
      therm={'specificHeat': P(1465.0, 'MISC'), 'conductivity': P(1.4, 'MISC', note='as tabulated; filled phenolics are usually quoted 0.2-0.5: check')}),

    E('mica', 'mica', 'solid', 'Mica sheet.', mech={'density': P(2900.0, 'MISC'), 'staticFriction': P(1.0, 'ETB_FR', note='freshly cleaved, on itself')},
      therm={'conductivity': P(0.523, 'MISC')}),

    E('coal', 'coal (anthracite)', 'solid', 'Anthracite coal.',
      mech={'density': P(1350.0, 'MISC')}, therm={'specificHeat': P(1260.0, 'MISC'), 'conductivity': P(0.26, 'MISC')}),

    E('charcoal', 'charcoal', 'solid', 'Eucalyptus charcoal, as f3d.charcoal.', catalogId='f3d.charcoal',
      mech={'density': NUL('not read'), 'staticFriction': NUL('not read')},
      therm={'specificHeat': P(1017.0, 'EXISTING', note='Santos et al., CERNE 26 (2020) (f3d.charcoal)'),
             'conductivity': P(0.030, 'EXISTING', note='as f3d.charcoal'), 'emissivity': P(0.77, 'EXISTING', note='Vanaparti 2016 (f3d.charcoal)')},
      notes=['the fire numbers stay as f3d.charcoal has them']),

    E('paraffin', 'paraffin wax', 'solid', 'Paraffin wax, as f3d.paraffin.', catalogId='f3d.paraffin',
      ext={'CAS': '8002-74-2'},
      mech={'density': P(900.0, 'EXISTING', note='Incropera A.3 (f3d.paraffin)')},
      therm={'specificHeat': P(2604.0, 'EXISTING', note='Hamins et al. 2005 (f3d.paraffin)'), 'conductivity': P(0.23, 'EXISTING'),
             'meltingPoint': NUL('paraffin waxes melt over about 320-340 K by grade; not read')}),

    E('thatch', 'thatch (straw)', 'solid', 'Dry wheat and rye straw, as f3d.thatch.', catalogId='f3d.thatch',
      mech={'density': NUL('a bed\'s bulk density depends on packing; f3d.thatch takes 15 kg/m3 for its conductivity')},
      therm={'specificHeat': P(1938.0, 'EXISTING', note='Rossa et al. 2026 (f3d.thatch)'), 'conductivity': P(0.0485, 'EXISTING'),
             'emissivity': P(0.846, 'EXISTING', note='UL FSRI (f3d.thatch)')}),

    E('sawdust', 'sawdust / wood shavings (loose)', 'granular', 'Loose sawdust or shavings.',
      mech={'density': P(184.0, 'ASHRAE', conf='estimate', rng=[128.0, 240.0])},
      therm={'specificHeat': P(1380.0, 'ASHRAE'), 'conductivity': P(0.065, 'ASHRAE')}),

    E('mineralWool', 'mineral wool (glass/rock fibre)', 'solid', 'Glass or rock wool batt, 16-48 kg/m3.',
      mech={'density': P(24.0, 'ASHRAE', conf='estimate', rng=[4.8, 32.0])},
      therm={'specificHeat': P(840.0, 'ASHRAE', conf='estimate', rng=[710.0, 960.0]),
             'conductivity': P(0.036, 'ASHRAE', note='glass fibre board, organic bonded, 64-144 kg/m3')},
      acou={'absorption': P([0.17, 0.45, 0.80, 0.89, 0.97, 0.94], 'AKU', note='glass wool 50 mm, 16 kg/m3, on solid backing')}),
]
