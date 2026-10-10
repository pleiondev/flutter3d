"""Helpers and the source register for solids.json (task 0.4).

Every value is P(value, sourceKey, confidence, verification, note, range).
verification: 'fetched' = the number was read from the cited source during
this research session; 'recalled' = the number is the cited handbook's as the
researcher knows it, not re-read here: a human check should open the source.
"""

SOURCES = {
    # --- read during the session (fetched) ---
    'INC': ('Incropera & DeWitt, Fundamentals of Heat and Mass Transfer, 3rd ed. (1990), '
            'table A.1 (metallic solids, 300 K and 100-1000 K), as reproduced in Cengel & '
            'Ghajar, Heat and Mass Transfer, 5th ed. (2015), appendix 1, table A-3',
            'https://highered.mheducation.com/sites/dl/free/0073398187/1016975/Appendix1.pdf'),
    'INC_NM': ('Incropera & DeWitt (1990), table A.2 (nonmetallic solids), as reproduced in '
               'Cengel & Ghajar (2015), table A-4',
               'https://highered.mheducation.com/sites/dl/free/0073398187/1016975/Appendix1.pdf'),
    'ASHRAE': ('ASHRAE Handbook of Fundamentals (1993), ch. 22 table 4, as reproduced in '
               'Cengel & Ghajar (2015), tables A-5 (building materials) and A-6 (insulation), '
               'mean temperature 24 C',
               'https://highered.mheducation.com/sites/dl/free/0073398187/1016975/Appendix1.pdf'),
    'MISC': ('Cengel & Ghajar (2015), table A-8, properties of miscellaneous materials at '
             '300 K (compiled from various sources, largely Incropera table A.3)',
             'https://highered.mheducation.com/sites/dl/free/0073398187/1016975/Appendix1.pdf'),
    'EMI': ('Cengel & Ghajar (2015), table A-18, emissivities of surfaces',
            'https://highered.mheducation.com/sites/dl/free/0073398187/1016975/Appendix1.pdf'),
    'ETB_EMI': ('Engineering ToolBox, Emissivity coefficients of common materials (about 300 K)',
                'https://www.engineeringtoolbox.com/emissivity-coefficients-d_447.html'),
    'ETB_FR': ('Engineering ToolBox, Friction and friction coefficients for some common '
               'materials (dry, clean unless noted)',
               'https://www.engineeringtoolbox.com/friction-coefficients-d_778.html'),
    'ETB_SND': ('Engineering ToolBox, Speed of sound in solids (longitudinal bulk, shear, thin '
                'rod; the classic CRC / Kinsler table)',
                'https://www.engineeringtoolbox.com/sound-speed-solids-d_713.html'),
    'ETB_E': ("Engineering ToolBox, Young's modulus, tensile and yield strength for common "
              'materials', 'https://www.engineeringtoolbox.com/young-modulus-d_417.html'),
    'OLY': ('Evident (Olympus) NDT, Material sound velocities (longitudinal), thickness-gauge '
            'appendix', 'https://ims.evidentscientific.com/en/learn/ndt-tutorials/thickness-gauge/appendices-velocities'),
    'ETB_CTE': ('Engineering ToolBox, Coefficients of linear thermal expansion (mostly 25 C)',
                'https://www.engineeringtoolbox.com/linear-expansion-coefficients-d_95.html'),
    'WIKI_RES': ('Wikipedia, Electrical resistivity and conductivity, table of resistivity and '
                 'temperature coefficient at 20 C (after Serway, Giancoli, CRC)',
                 'https://en.wikipedia.org/wiki/Electrical_resistivity_and_conductivity'),
    'CH': ('Cremer & Heckl, Structure-Borne Sound (Springer 1988), tables of static and dynamic '
           'properties and of building materials (loss factors), as reproduced in T. Irvine, '
           'Damping Properties of Materials, rev. D (2010), tables 1, 2 and 7',
           'http://vibrationdata.com/tutorials_alt/damping.pdf'),
    'WH4': ('Wood Handbook, FPL-GTR-190 (USDA Forest Products Laboratory, 2010), ch. 4 '
            '(Glass & Zelinka): eq. 4-15 conductivity, eq. 4-16..4-18 heat capacity, table 4-7, '
            'eq. 4-19/4-20 expansion, friction text',
            'https://research.fs.usda.gov/download/treesearch/37428.pdf'),
    'WH5': ('Wood Handbook, FPL-GTR-190 (2010), ch. 5 (Kretschmann): tables 5-1 (elastic '
            'ratios), 5-2 (Poisson ratios), 5-3a (US species, 12 % MC), 5-5a (imports)',
            'https://research.fs.usda.gov/download/treesearch/37427.pdf'),
    'AKU': ('akustik.ua absorption coefficient table (octave bands 125-4000 Hz), compiled from '
            'standard acoustic references',
            'https://www.acoustic.ua/st/web_absorption_data_eng.pdf'),
    'PRA': ('pyroomacoustics materials database (octave-band absorption coefficients)',
            'https://pyroomacoustics.readthedocs.io/en/stable/pyroomacoustics.materials.database.html'),
    'PBI': ('physicallybased.info material database API (linear sRGB base colour / F0 from '
            'spectral complex IOR; IOR at 589 nm), retrieved 2026-10-09',
            'https://api.physicallybased.info/materials'),
    'MTLX': ('MaterialX repository, resources/Materials/Examples/StandardSurface (file names)',
             'https://github.com/AcademySoftwareFoundation/MaterialX/tree/main/resources/Materials/Examples/StandardSurface'),
    'WIKI_PMMA': ('Wikipedia, Poly(methyl methacrylate), infobox and Properties',
                  'https://en.wikipedia.org/wiki/Poly(methyl_methacrylate)'),
    'WIKI_PTFE': ('Wikipedia, Polytetrafluoroethylene, infobox and properties table',
                  'https://en.wikipedia.org/wiki/Polytetrafluoroethylene'),
    'WIKI_PC': ('Wikipedia, Polycarbonate, properties table',
                'https://en.wikipedia.org/wiki/Polycarbonate'),
    'WIKI_PP': ('Wikipedia, Polypropylene', 'https://en.wikipedia.org/wiki/Polypropylene'),
    'EXISTING': ('the flutter3d_matter catalog as of rc.1 '
                 '(packages/flutter3d_matter/lib/src/materials/materials.dart), whose own '
                 'source string is quoted in the note', None),
    # --- recalled (handbook values known to the researcher, not re-read) ---
    'CRC_MP': ('CRC Handbook of Chemistry and Physics, 97th ed. (2016), melting, boiling '
               'points and enthalpy of fusion of the elements (J/kg = molar value / molar mass)',
               None),
    'KL': ('Kaye & Laby, Tables of Physical and Chemical Constants, 16th ed., 2.2.2 elastic '
           'moduli of polycrystalline metals', 'https://web.archive.org/web/2019/http://www.kayelaby.npl.co.uk/general_physics/2_2/2_2_2.html'),
    'ASM': ('ASM Aerospace Specification Metals datasheets (asm.matweb.com) for the named '
            'temper; typical values', 'https://asm.matweb.com/'),
    'CALL': ('Callister & Rethwisch, Materials Science and Engineering, 9th ed. (2014), '
             'appendix B (tables B.1-B.9, typical values)', None),
    'EN1993': ('EN 1993-1-2:2005 (Eurocode 3, structural fire design): 3.2.1 table 3.1 '
               'reduction factors, 3.4.1 thermal properties of carbon steel; annex C '
               'stainless steel', None),
    'EN1992': ('EN 1992-1-2:2004 (Eurocode 2, structural fire design): 3.2.2 table 3.1 '
               'strength reduction, 3.3.2 specific heat, 3.3.3 thermal conductivity', None),
    'EN1999': ('EN 1999-1-2:2007 (Eurocode 9, aluminium, structural fire design) 3.3.1', None),
    'JC83': ('Johnson & Cook, A constitutive model and data for metals subjected to large '
             'strains, high strain rates and high temperatures, Proc. 7th Int. Symp. '
             'Ballistics (1983), table 1', None),
    'LESUER': ('Lesuer, Experimental investigations of material models for Ti-6Al-4V titanium '
               'and 2024-T3 aluminum, DOT/FAA/AR-00/25 (2000), Johnson-Cook fits', None),
    'OGDEN72': ('Ogden, Large deformation isotropic elasticity: on the correlation of theory '
                "and experiment for incompressible rubberlike solids, Proc. R. Soc. A 326 (1972); "
                "three-term fit to Treloar's (1944) vulcanised natural rubber", None),
    'TRELOAR': ('Treloar, The Physics of Rubber Elasticity, 3rd ed. (1975)', None),
    'CP2010': ('Cuffey & Paterson, The Physics of Glaciers, 4th ed. (2010), section 9.2, '
               'eqs. for the conductivity and specific heat of ice', None),
    'PW99': ('Petrenko & Whitworth, Physics of Ice (Oxford 1999), ch. 2 and 11: elastic '
             'constants and strength of polycrystalline ice near 263 K', None),
    'STURM97': ('Sturm, Holmgren, Konig & Morris, The thermal conductivity of seasonal snow, '
                'J. Glaciology 43(143), 1997, eq. 4 (quadratic fit, 0.156-0.6 g/cm3)', None),
    'PAT_SNOW': ('Cuffey & Paterson (2010), table 2.1, typical densities of snow and firn', None),
    'SCHOTT': ('SCHOTT optical glass datasheets (N-BK7 517642.251, F2 620364.360)', None),
    'BORO33': ('SCHOTT BOROFLOAT 33 datasheet / Corning 7740 (Pyrex) properties', None),
    'HERAEUS': ('Heraeus / Corning 7980 fused silica datasheets; Malitson, J. Opt. Soc. Am. '
                '55 (1965) for n_D', None),
    'RII': ('refractiveindex.info (Sultanova et al. 2009 for polymers; Malitson for silica; '
            'Dodge for sapphire/fluorides); n at 589 nm', 'https://refractiveindex.info'),
    'RTR': ('Akenine-Moller et al., Real-Time Rendering, 4th ed. (2018), table 9.2 (F0 of '
            'metals, linear), after Hoffman', None),
    'ASHBY': ('Ashby, Materials Selection in Mechanical Design, 4th ed. (2011), appendix C '
              '(typical values within the ranges)', None),
    'DOW184': ('Dow SYLGARD 184 silicone elastomer technical data sheet; Johnston et al., '
               'J. Micromech. Microeng. 24 (2014) 035017 for the cure-dependent modulus', None),
    'SFPE': ('SFPE Handbook of Fire Protection Engineering, 3rd ed. (2002), Tewarson, '
             'Generation of heat and chemical compounds in fires, table 3-4.14 (net heat of '
             'complete combustion of polymers)', None),
    'CALL_POLY': ('Callister & Rethwisch, Materials Science and Engineering, 9th ed., appendix B, '
                  'tables B.2-B.4 (room-temperature ranges for polymers)', None),
    'BHUSHAN': ('Bhushan, Introduction to Tribology, 2nd ed. (2013) / Rabinowicz, Friction '
                'and Wear of Materials (1995): self-mated friction of polymers and ceramics', None),
    'SERWAY': ('Serway & Jewett, Physics for Scientists and Engineers, table 5.1 '
               '(coefficients of friction)', None),
    'BRIDGES84': ('Bridges, Hatzes & Lin, Structure, stability and evolution of Saturn\'s '
                  'rings, Nature 309 (1984): e(v) of frost-covered ice spheres at about 165 K',
                  None),
    'ACI318': ('ACI 318-19, 19.2.2: Ec = 4700 sqrt(fc\') MPa for normal-weight concrete', None),
    'INC_A3': ('Incropera & DeWitt, Fundamentals of Heat and Mass Transfer, table A.3 '
               '(common materials at 300 K: named rocks, woods, etc.)', None),
    'ROCKS': ('representative value inside the textbook ranges for intact rock (Goodman 1989 '
              'appendix 1; Jaeger, Cook & Zimmerman, Fundamentals of Rock Mechanics, 4th ed.); '
              'a rock\'s properties vary by site more than the ranges suggest', None),
    'GOODMAN': ('Goodman, Introduction to Rock Mechanics, 2nd ed. (1989), tables A1.1-A1.3 '
                '(laboratory values for named rocks)', None),
    'TOULOUKIAN': ('Touloukian et al., Thermophysical Properties of Matter (TPRC data series) '
                   'vols. 1-2, recommended values', None),
    'REILLY': ('Reilly & Burstein, The elastic and ultimate properties of compact bone '
               'tissue, J. Biomech. 8 (1975); Currey, Bones (2002)', None),
    'CFRP': ('Daniel & Ishai, Engineering Mechanics of Composite Materials, 2nd ed. (2006), '
             'table A.4 (AS4/3501-6 carbon/epoxy) and A.4 E-glass/epoxy; quasi-isotropic '
             'laminate by classical lamination theory', None),
}

CORE = {
    'mechanical': ['density', 'youngsModulus', 'poissonRatio', 'staticFriction',
                   'kineticFriction'],
    'thermal': ['specificHeat', 'conductivity', 'emissivity'],
}

UNITS = {
    'density': 'kg/m^3', 'youngsModulus': 'Pa', 'shearModulus': 'Pa',
    'poissonRatio': '1', 'yieldStrength': 'Pa', 'tensileStrength': 'Pa',
    'compressiveStrength': 'Pa', 'flexuralStrength': 'Pa',
    'hardness': 'Pa (HV x 9.807 MPa)', 'staticFriction': '1', 'kineticFriction': '1',
    'restitution': '1', 'rollingResistance': '1', 'specificHeat': 'J/(kg K)',
    'conductivity': 'W/(m K)', 'linearExpansion': '1/K', 'volumetricExpansion': '1/K',
    'meltingPoint': 'K', 'boilingPoint': 'K', 'latentHeatOfFusion': 'J/kg',
    'emissivity': '1', 'ignitionTemperature': 'K', 'heatOfCombustion': 'J/kg',
    'speedOfSound': 'm/s', 'shearWaveSpeed': 'm/s', 'rodWaveSpeed': 'm/s',
    'absorption': '1 per octave band 125,250,500,1000,2000,4000 Hz',
    'impedance': 'Pa s/m', 'refractiveIndex': '1 (n_D, 589 nm)', 'abbeNumber': '1',
    'dielectricF0': '1 (((n-1)/(n+1))^2 at normal incidence from air)',
    'metalReflectance': '1, linear RGB', 'resistivity': 'ohm m',
    'resistivityTempCoeff': '1/K', 'lossFactor': '1 (eta = 2 x damping ratio)',
    'relativePermittivity': '1', 'jankaHardness': 'N (side hardness, a force)',
    'glassTransition': 'K', 'youngsModulusAlongGrain': 'Pa', 'youngsModulusInPlane': 'Pa',
    'conductivityAcross': 'W/(m K) (across layers / perpendicular axis)',
    'emissivityBySurface': '1 per named surface state',
    'johnsonCook': 'A, B in Pa; n, C, m no unit; meltTemperature, roomTemperature K; referenceStrainRate 1/s',
    'ogden': 'mu_p in Pa, alpha_p no unit',
}


def P(value, src, conf='handbook', ver='fetched', note=None, rng=None):
    text, url = SOURCES[src]
    if src == 'EXISTING' and ver == 'fetched':
        ver = 'catalog'  # read from materials.dart, its handbook not re-read here
    out = {'value': value, 'source': text}
    if url:
        out['sourceUrl'] = url
    out['confidence'] = conf
    out['verification'] = ver
    if rng is not None:
        out['range'] = rng
    if note:
        out['note'] = note
    return out


def NUL(note):
    return {'value': None, 'note': note}


def F0(n):
    return round(((n - 1.0) / (n + 1.0)) ** 2, 4)


def law(prop, kind, src, ver='fetched', conf='handbook', **kw):
    text, url = SOURCES[src]
    out = {'property': prop, 'kind': kind}
    out.update(kw)
    out['source'] = text
    if url:
        out['sourceUrl'] = url
    out['confidence'] = conf
    out['verification'] = ver
    return out


def table(prop, src, xs, ys, x='T', xunit='K', ver='fetched', **kw):
    pts = [[a, b] for a, b in zip(xs, ys) if b is not None]
    return law(prop, 'table', src, ver=ver, x=x, xUnit=xunit, points=pts,
               validRange=[pts[0][0], pts[-1][0]], **kw)


def resist_law(rho20, alpha, src='WIKI_RES'):
    return law('electrical.resistivity', 'linear', src,
               form='rho(T) = rho20 * (1 + alpha * (T - 293.15))',
               coefficients={'rho20': rho20, 'alpha': alpha},
               validRange=[200.0, 400.0],
               note='linear only near room temperature; the alpha is the 20 C one')


def E(id, name, phase, desc, catalogId=None, ext=None, mech=None, therm=None,
      acou=None, opt=None, elec=None, inel=None, laws=None, notes=None):
    entry = {'id': id, 'catalogId': catalogId, 'name': name, 'phase': phase,
             'description': desc,
             'referenceState': {'temperature': 293.15, 'pressure': 101325.0,
                                'note': 'values at 20 C unless the value note says '
                                        'otherwise (300 K tables differ by < 1 % for '
                                        'solids except where a law is given)'},
             'externalIds': ext or {}}
    groups = {'mechanical': mech, 'thermal': therm, 'acoustic': acou,
              'optical': opt, 'electrical': elec, 'inelastic': inel}
    for g, d in groups.items():
        d = dict(d or {})
        for k in CORE.get(g, []):
            if k not in d:
                d[k] = NUL('not found in the sources read for this material')
        if d:
            entry[g] = d
    # derived dielectric F0 and volumetric expansion
    o = entry.get('optical')
    if o and isinstance(o.get('refractiveIndex'), dict) and o['refractiveIndex'].get('value') \
            and 'dielectricF0' not in o:
        n = o['refractiveIndex']['value']
        o['dielectricF0'] = {'value': F0(n), 'derivedFrom': 'optical.refractiveIndex',
                             'confidence': o['refractiveIndex']['confidence'],
                             'note': 'Fresnel at normal incidence from air, ((n-1)/(n+1))^2'}
    t = entry.get('thermal')
    if t and isinstance(t.get('linearExpansion'), dict) and t['linearExpansion'].get('value') \
            and 'volumetricExpansion' not in t:
        a = t['linearExpansion']['value']
        t['volumetricExpansion'] = {'value': round(3 * a, 10),
                                    'derivedFrom': 'thermal.linearExpansion (x3, isotropic)',
                                    'confidence': t['linearExpansion']['confidence']}
    entry['laws'] = laws or []
    entry['notes'] = notes or []
    return entry
