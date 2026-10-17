"""Assemble matter_data/fluids.json from the part files and print coverage."""
import collections
import json
import os

ROOT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), 'sources')
PARTS = ['part_nist.json', 'part_solvents.json', 'part_fuels_oils.json', 'part_metals_melts.json', 'part_bio_misc.json']
CORE = [('mechanical', 'density'), ('fluid', 'viscosity'), ('fluid', 'surfaceTension'), ('fluid', 'bulkModulus'),
        ('thermal', 'specificHeat'), ('thermal', 'conductivity'), ('thermal', 'volumetricExpansion'),
        ('thermal', 'meltingPoint'), ('thermal', 'boilingPoint'), ('thermal', 'latentHeatOfFusion'),
        ('thermal', 'latentHeatOfVaporization'), ('thermal', 'autoignitionTemperature'), ('thermal', 'heatOfCombustion'),
        ('thermal', 'emissivity'), ('thermal', 'radiantFraction'),
        ('acoustic', 'speedOfSound'), ('optical', 'refractiveIndex'), ('electrical', 'resistivity'),
        ('extra', 'vaporPressure'), ('extra', 'flashPoint')]


CODATA = ('CODATA Key Values for Thermodynamics (Cox, Wagman and Medvedev, 1989): '
          'ΔfH°(H2O, g) = -241.826 kJ/mol, ΔfH°(CO2, g) = -393.51 kJ/mol, ΔfH°(CO, g) = -110.53 kJ/mol, '
          'ΔfH°(NH3, g) = -45.94 kJ/mol')


def lhv(value, how):
    return {'value': value, 'unit': 'J/kg', 'confidence': 'handbook', 'source': CODATA,
            'note': f'net (lower) heat of combustion, product water as vapour, at 298.15 K; derived here: {how}. '
                    'A fire\'s effective heat is lower by its combustion efficiency'}


def curate(enrich, nist_by_id):
    """Corrections to the PubChem/NIST enrichment found on review."""
    for fid, x in enrich.items():
        g = x.get('groups', {})
        phase = nist_by_id.get(fid, {}).get('phase')
        ri = g.get('optical', {}).get('refractiveIndex')
        if ri and phase == 'gas' and not (1.0001 <= ri['value'] <= 1.002):
            # liquid-phase or garbled values listed for gases (O2 1.2243 liq, CO2 1.663,
            # N2 '1.003012' is an HSDB typo for 1.000300, ethane 1.0377)
            del g['optical']['refractiveIndex']
        if phase == 'gas' and 'flashPoint' in g.get('extra', {}):
            del g['extra']['flashPoint']  # a flash point means nothing for a gas at 20 °C
        if fid in ('liquidMethane', 'liquidHydrogen') and 'flashPoint' in g.get('extra', {}):
            del g['extra']['flashPoint']
        hc = g.get('thermal', {}).get('heatOfCombustion')
        if hc and fid.startswith('r'):
            del g['thermal']['heatOfCombustion']  # halogenated: products are HF/HCl, the H2O correction is wrong
    ai = enrich.get('r141b', {}).get('groups', {}).get('thermal', {}).get('autoignitionTemperature')
    if ai:
        ai['value'] = 803.15
        ai['note'] = 'ICSC gives a range, 530-550 °C; the lower end is given here'
    ai = enrich.get('r14', {}).get('groups', {}).get('thermal', {}).get('autoignitionTemperature')
    if ai:
        enrich['r14']['groups']['thermal']['autoignitionTemperature'] = {
            'value': None, 'confidence': None, 'source': None,
            'note': 'ICSC lists only ">1100 °C"; CF4 is not flammable in air'}
    fn = enrich.get('fluorine', {}).get('groups', {}).get('optical', {}).get('refractiveIndex')
    if fn:
        fn['note'] = 'HSDB gives "1.0002" with no conditions: gas at about 0 °C, 1 atm, to four places only'
    add = {
        'hydrogen': lhv(1.1996e8, '241.826 kJ/mol over M = 2.01588 g/mol'),
        'liquidHydrogen': lhv(1.1951e8, '241.826 kJ/mol over 2.01588 g/mol, less the NIST heat of vaporization of para-hydrogen at 20.27 K, 0.446 MJ/kg'),
        'carbonMonoxide': lhv(1.0103e7, '(393.51 - 110.53) kJ/mol over M = 28.010 g/mol; no water is formed, so gross = net'),
        'ammonia': lhv(1.8601e7, '(1.5 × 241.826 - 45.94) kJ/mol over M = 17.031 g/mol, to N2 and H2O(g)'),
    }
    for fid, p in add.items():
        enrich.setdefault(fid, {'groups': {}})['groups'].setdefault('thermal', {}).setdefault('heatOfCombustion', p)
    m = enrich.get('methane', {}).get('groups', {}).get('thermal', {}).get('heatOfCombustion')
    lv = nist_by_id.get('liquidMethane', {}).get('groups', {}).get('thermal', {}).get('latentHeatOfVaporization', {}).get('value')
    if m and lv:
        p = dict(m)
        p['value'] = float(f'{m["value"] - lv:.4g}')
        p['note'] = m['note'] + f'; for the liquid, the gas value less the NIST heat of vaporization at the boiling point ({lv:.4g} J/kg), derived here'
        enrich.setdefault('liquidMethane', {'groups': {}})['groups'].setdefault('thermal', {})['heatOfCombustion'] = p


# hydrogen atoms per molecule, for gross -> net conversion of entries whose source gives gross
H_ATOMS = {'ethanol': 6, 'glycerol': 8, 'isopropanol': 8, 'butanol': 10, 'acetone': 6, 'ethyleneGlycol': 6,
           'propyleneGlycol': 8, 'diethylEther': 10, 'aceticAcid': 4, 'pXylene': 10, 'formicAcid': 2}


def to_net(e):
    p = e['groups'].get('thermal', {}).get('heatOfCombustion')
    if not p or p.get('value') is None or p.get('basis') == 'net':
        return
    n = H_ATOMS.get(e['id'])
    m = e.get('molarMass')
    if n is None or not m:
        if e['id'] == 'dimethylSulfoxide':
            p['note'] = (p.get('note') or '') + '; basis (gross or net) not stated by the source: the net value would be about 1.7 MJ/kg lower'
        return
    gross = p['value']
    net = gross - (n / 2.0) * 44.0e3 / m
    p['value'] = float(f'{net:.4g}')
    p['basis'] = 'net'
    p['note'] = (f'net (lower) heat, derived here from the gross {gross:.4g} J/kg less the vaporization of the '
                 f'product water, {n}/2 mol × 44.0 kJ/mol over M = {m * 1000:.4f} g/mol. Source note: ' + (p.get('note') or ''))


import math  # noqa: E402

# closed forms the metals slice gave as kind "expression", transcribed from their "form"
EXPR = {
    ('sodium', 'mechanical', 'density'): lambda T: 219 + 275.32 * (1 - T / 2503.7) + 511.58 * (1 - T / 2503.7) ** 0.5,
    ('sodium', 'fluid', 'viscosity'): lambda T: math.exp(-6.4406 - 0.3958 * math.log(T) + 556.835 / T),
    ('sodium', 'fluid', 'surfaceTension'): lambda T: 0.2405 * (1 - T / 2503.7) ** 1.126,
    ('lead', 'thermal', 'specificHeat'): lambda T: 176.2 - 4.923e-2 * T + 1.544e-5 * T ** 2 - 1.524e6 / T ** 2,
    ('lead', 'extra', 'vaporPressure'): lambda T: 5.76e9 * math.exp(-22131 / T),
    ('leadBismuthEutectic', 'thermal', 'specificHeat'): lambda T: 164.8 - 3.94e-2 * T + 1.25e-5 * T ** 2 - 4.56e5 / T ** 2,
    ('leadBismuthEutectic', 'extra', 'vaporPressure'): lambda T: 1.22e10 * math.exp(-22552 / T),
    ('tin', 'thermal', 'specificHeat'): lambda T: 182.7 + 5.177e-2 * T + 1.086e7 / T ** 2,
    ('aluminumMelt', 'thermal', 'conductivity'): lambda T: 90.726 + 36.0231e-3 * (T - 933.47) - 13.2857e-6 * (T - 933.47) ** 2,
    ('aluminumMelt', 'electrical', 'resistivity'): lambda T: (24.834 + 15.834e-3 * (T - 933.47) - 2.1217e-6 * (T - 933.47) ** 2) * 1e-8,
    ('flibe', 'fluid', 'viscosity'): lambda T: 5.762e-5 * math.exp(4670.28 / T - 283383 / T ** 2),
}


def tabulate_expressions(e):
    tref = e['referenceState']['temperature']
    for g, props in e['groups'].items():
        for k, p in props.items():
            law = p.get('law') if isinstance(p, dict) else None
            if not law or law.get('kind') != 'expression':
                continue
            f = EXPR.get((e['id'], g, k))
            if f is None:
                law['note'] = (law.get('note') or '') + '; closed form not one of PropertyLaw\'s kinds and not tabulated here: convert at 3A'
                print('  untabulated expression', e['id'], g, k)
                continue
            lo, hi = law['validRange']
            hi = min(hi, lo + 1200.0)
            ts = [lo + (hi - lo) * i / 12 for i in range(13)]
            if p.get('value') is not None:
                check = f(tref) / p['value'] - 1
                if abs(check) > 0.01:
                    print('  MISMATCH', e['id'], g, k, f(tref), p['value'])
                    continue
            law['originalForm'] = law.pop('form')
            law['kind'] = 'table'
            law['variable'] = 'T'
            law['unit'] = 'K'
            law['points'] = [[round(t, 2), float(f'{f(t):.5g}')] for t in ts]
            law['fit'] = (f'tabulated here from the closed form at 13 points over {lo:g}-{hi:g} K; the form reproduces '
                          f'the entry value at {tref:g} K')


def main():
    entries, seen, origin = [], {}, {}
    enrich = {}
    ep = os.path.join(ROOT, 'enrich_nist.json')
    if os.path.exists(ep):
        enrich = json.load(open(ep))
        nist = {e['id']: e for e in json.load(open(os.path.join(ROOT, 'part_nist.json')))['entries']}
        curate(enrich, nist)
    for part in PARTS:
        p = os.path.join(ROOT, part)
        if not os.path.exists(p):
            print('missing part', part)
            continue
        for e in json.load(open(p))['entries']:
            if e['id'] in seen:
                print('DUPLICATE', e['id'], 'in', part, 'and', origin[e['id']], '- keeping the first')
                continue
            for g, props in enrich.get(e['id'], {}).get('groups', {}).items():
                for k, v in props.items():
                    cur = e['groups'].setdefault(g, {}).get(k)
                    if cur is None or cur.get('value') is None:
                        e['groups'][g][k] = v
            if part == 'part_solvents.json':
                to_net(e)
            tabulate_expressions(e)
            seen[e['id']] = e
            origin[e['id']] = part
            entries.append(e)

    cov = collections.Counter()
    laws = collections.Counter()
    conf = collections.Counter()
    for e in entries:
        for g, props in e['groups'].items():
            for k, p in props.items():
                if not isinstance(p, dict):
                    continue
                if p.get('value') is not None or p.get('law'):
                    cov[(g, k)] += 1
                    conf[p.get('confidence')] += 1
                if p.get('law'):
                    laws[(g, k, p['law'].get('kind'))] += 1
    meta = {
        'task': 'flutter3d rc.1 plan, step 0.4: verified physical data for ~100 fluids for flutter3d_matter (step 3.1, 3A)',
        'generated': '2026-10-09',
        'schema': 'see SCHEMA.txt beside this file; groups and field names match packages/flutter3d_matter property_groups.dart, all SI',
        'defaultReferenceState': {'temperature': 293.15, 'pressure': 101325.0},
        'confidence': {
            'measured': 'a primary measurement paper',
            'handbook': 'a compiled handbook or a reference equation of state / correlation (NIST WebBook SRD 69, CRC, TEOS-10, IAEA...), or a quantity derived from such values by exact thermodynamics (rho*c^2, -(1/rho)drho/dT) as the note says',
            'estimate': 'a typical value, a midpoint of a spread, or a rule of thumb; every one is marked'},
        'caveat': 'reference values for simulation, not for design or safety calculations',
        'counts': {'entries': len(entries), 'byPart': dict(collections.Counter(origin.values())),
                   'byConfidence': dict(conf)},
        'coverage': {f'{g}.{k}': cov[(g, k)] for g, k in CORE},
        'lawsByProperty': {f'{g}.{k}:{kind}': n for (g, k, kind), n in sorted(laws.items())},
    }
    json.dump({'meta': meta, 'entries': entries}, open(os.path.join(ROOT, 'fluids.json'), 'w'), indent=1, ensure_ascii=False)
    print(json.dumps(meta['counts'], indent=1))
    for g, k in CORE:
        print(f'{g}.{k}: {cov[(g, k)]}/{len(entries)}')
    print('laws:', sum(laws.values()))


if __name__ == '__main__':
    main()
