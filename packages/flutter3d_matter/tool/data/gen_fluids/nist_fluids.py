"""Fetch NIST WebBook fluid data for the catalog's pure fluids.

Writes matter_data/part_nist.json every few entries. Raw responses are cached
in nist_raw/ so a rerun does not hit the server again.
"""
import html
import json
import math
import os
import re
import subprocess
import sys
import time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RAW = os.path.join(ROOT, 'nist_raw')
OUT = os.path.join(ROOT, 'sources', 'part_nist.json')
FLUID = ('https://webbook.nist.gov/cgi/fluid.cgi?Action=Data&Wide=on&Digits=6&RefState=DEF'
         '&TUnit=K&PUnit=MPa&DUnit=kg%2Fm3&HUnit=kJ%2Fkg&WUnit=m%2Fs&VisUnit=Pa*s&STUnit=N%2Fm')
P0 = 0.101325  # MPa
T0 = 293.15

# (id, name, NIST id, CAS, catalogId, kind)
# kind: 'ambient' = state at 20 °C, 1 atm; 'satliq' = saturated liquid at the normal
# boiling point; 'satvap' = saturated vapour at the normal boiling point.
FLUIDS = [
    ('water', 'water', 'C7732185', '7732-18-5', 'f3d.water', 'ambient'),
    ('heavyWater', 'heavy water (D2O)', 'C7789200', '7789-20-0', None, 'ambient'),
    ('methanol', 'methanol', 'C67561', '67-56-1', None, 'ambient'),
    ('pentane', 'n-pentane', 'C109660', '109-66-0', None, 'ambient'),
    ('isopentane', 'isopentane (2-methylbutane)', 'C78784', '78-78-4', None, 'ambient'),
    ('hexane', 'n-hexane', 'C110543', '110-54-3', None, 'ambient'),
    ('cyclohexane', 'cyclohexane', 'C110827', '110-82-7', None, 'ambient'),
    ('heptane', 'n-heptane', 'C142825', '142-82-5', None, 'ambient'),
    ('octane', 'n-octane', 'C111659', '111-65-9', None, 'ambient'),
    ('nonane', 'n-nonane', 'C111842', '111-84-2', None, 'ambient'),
    ('decane', 'n-decane', 'C124185', '124-18-5', None, 'ambient'),
    ('dodecane', 'n-dodecane', 'C112403', '112-40-3', None, 'ambient'),
    ('benzene', 'benzene', 'C71432', '71-43-2', None, 'ambient'),
    ('toluene', 'toluene', 'C108883', '108-88-3', None, 'ambient'),
    ('r11', 'trichlorofluoromethane (R-11)', 'C75694', '75-69-4', None, 'ambient'),
    ('r113', '1,1,2-trichloro-1,2,2-trifluoroethane (R-113)', 'C76131', '76-13-1', None, 'ambient'),
    ('r123', '2,2-dichloro-1,1,1-trifluoroethane (R-123)', 'C306832', '306-83-2', None, 'ambient'),
    ('r141b', '1,1-dichloro-1-fluoroethane (R-141b)', 'C1717006', '1717-00-6', None, 'ambient'),
    ('nitrogen', 'nitrogen', 'C7727379', '7727-37-9', None, 'ambient'),
    ('oxygen', 'oxygen', 'C7782447', '7782-44-7', None, 'ambient'),
    ('hydrogen', 'hydrogen (normal)', 'C1333740', '1333-74-0', None, 'ambient'),
    ('helium', 'helium-4', 'C7440597', '7440-59-7', None, 'ambient'),
    ('neon', 'neon', 'C7440019', '7440-01-9', None, 'ambient'),
    ('argon', 'argon', 'C7440371', '7440-37-1', None, 'ambient'),
    ('krypton', 'krypton', 'C7439909', '7439-90-9', None, 'ambient'),
    ('xenon', 'xenon', 'C7440633', '7440-63-3', None, 'ambient'),
    ('fluorine', 'fluorine', 'C7782414', '7782-41-4', None, 'ambient'),
    ('carbonMonoxide', 'carbon monoxide', 'C630080', '630-08-0', None, 'ambient'),
    ('carbonDioxide', 'carbon dioxide', 'C124389', '124-38-9', None, 'ambient'),
    ('nitrousOxide', 'nitrous oxide', 'C10024972', '10024-97-2', None, 'ambient'),
    ('methane', 'methane', 'C74828', '74-82-8', None, 'ambient'),
    ('ethane', 'ethane', 'C74840', '74-84-0', None, 'ambient'),
    ('ethylene', 'ethylene (ethene)', 'C74851', '74-85-1', None, 'ambient'),
    ('propane', 'propane', 'C74986', '74-98-6', None, 'ambient'),
    ('propylene', 'propylene (propene)', 'C115071', '115-07-1', None, 'ambient'),
    ('butane', 'n-butane', 'C106978', '106-97-8', None, 'ambient'),
    ('isobutane', 'isobutane', 'C75285', '75-28-5', None, 'ambient'),
    ('ammonia', 'ammonia', 'C7664417', '7664-41-7', None, 'ambient'),
    ('sulfurDioxide', 'sulfur dioxide', 'C7446095', '7446-09-5', None, 'ambient'),
    ('hydrogenSulfide', 'hydrogen sulfide', 'C7783064', '7783-06-4', None, 'ambient'),
    ('sulfurHexafluoride', 'sulfur hexafluoride', 'C2551624', '2551-62-4', None, 'ambient'),
    ('r12', 'dichlorodifluoromethane (R-12)', 'C75718', '75-71-8', None, 'ambient'),
    ('r14', 'tetrafluoromethane (R-14)', 'C75730', '75-73-0', None, 'ambient'),
    ('r22', 'chlorodifluoromethane (R-22)', 'C75456', '75-45-6', None, 'ambient'),
    ('r23', 'trifluoromethane (R-23)', 'C75467', '75-46-7', None, 'ambient'),
    ('r32', 'difluoromethane (R-32)', 'C75105', '75-10-5', None, 'ambient'),
    ('r125', 'pentafluoroethane (R-125)', 'C354336', '354-33-6', None, 'ambient'),
    ('r134a', '1,1,1,2-tetrafluoroethane (R-134a)', 'C811972', '811-97-2', None, 'ambient'),
    ('r143a', '1,1,1-trifluoroethane (R-143a)', 'C420462', '420-46-2', None, 'ambient'),
    ('r152a', '1,1-difluoroethane (R-152a)', 'C75376', '75-37-6', None, 'ambient'),
    ('r227ea', '1,1,1,2,3,3,3-heptafluoropropane (R-227ea)', 'C431890', '431-89-0', None, 'ambient'),
    ('r245fa', '1,1,1,3,3-pentafluoropropane (R-245fa)', 'C460731', '460-73-1', None, 'ambient'),
    ('steam', 'steam (saturated, 1 atm)', 'C7732185', '7732-18-5', None, 'satvap'),
    ('liquidNitrogen', 'liquid nitrogen', 'C7727379', '7727-37-9', None, 'satliq'),
    ('liquidOxygen', 'liquid oxygen', 'C7782447', '7782-44-7', None, 'satliq'),
    ('liquidArgon', 'liquid argon', 'C7440371', '7440-37-1', None, 'satliq'),
    ('liquidHydrogen', 'liquid hydrogen (para)', 'B5000001', '1333-74-0', None, 'satliq'),
    ('liquidHelium', 'liquid helium-4', 'C7440597', '7440-59-7', None, 'satliq'),
    ('liquidMethane', 'liquid methane (LNG proxy)', 'C74828', '74-82-8', None, 'satliq'),
]


def fetch(url, name):
    path = os.path.join(RAW, name)
    if os.path.exists(path) and os.path.getsize(path) > 200:
        return open(path, encoding='utf-8', errors='replace').read()
    for attempt in range(3):
        r = subprocess.run(['curl', '-s', '-m', '60', url], capture_output=True)
        text = r.stdout.decode('utf-8', 'replace')
        if text and not text.lower().startswith('error code'):
            open(path, 'w', encoding='utf-8').write(text)
            time.sleep(0.4)
            return text
        time.sleep(2)
    return ''


def table(text):
    lines = [l for l in text.splitlines() if l.strip()]
    if not lines or not lines[0].startswith('Temperature'):
        return None
    head = lines[0].split('\t')
    rows = []
    for l in lines[1:]:
        cells = l.split('\t')
        row = {}
        for h, c in zip(head, cells):
            try:
                row[h] = float(c)
            except ValueError:
                row[h] = c
        rows.append(row)
    return rows


def isobar(nid, tlow, thigh, tinc, tag):
    url = f'{FLUID}&ID={nid}&Type=IsoBar&P={P0}&TLow={tlow}&THigh={thigh}&TInc={tinc}'
    return table(fetch(url, f'{nid}_isobar_{tag}.tsv')), url


def satcurve(nid):
    # NB: the CGI's Type=SatP steps in temperature and Type=SatT in pressure.
    # With no range it gives the whole curve from the triple point, T-spaced.
    url = f'{FLUID}&ID={nid}&Type=SatP'
    rows = table(fetch(url, f'{nid}_satT.tsv'))
    return rows, url


def sat_at_p(nid, p):
    url = f'{FLUID}&ID={nid}&Type=SatT&PLow={p}&PHigh={p * 2}&PInc={p}'
    rows = table(fetch(url, f'{nid}_satAtP.tsv'))
    return (rows[0] if rows and abs(rows[0]['Pressure (MPa)'] - p) < 1e-9 else None), url


def sat_at_t(nid, t):
    url = f'{FLUID}&ID={nid}&Type=SatP&TLow={t}&THigh={t + 1}&TInc=1'
    rows = table(fetch(url, f'{nid}_satAtT.tsv'))
    return (rows[0] if rows and abs(rows[0]['Temperature (K)'] - t) < 1e-6 else None), url


def interp(rows, xkey, x, ykey, xf=lambda v: v, yf=lambda v: v, yinv=lambda v: v):
    """Quadratic Lagrange interpolation of ykey at xkey = x over sorted rows."""
    pts = sorted(((xf(r[xkey]), yf(r[ykey])) for r in rows
                  if isinstance(r.get(xkey), float) and isinstance(r.get(ykey), float)),
                 key=lambda p: p[0])
    X = xf(x)
    if len(pts) < 3 or not (pts[0][0] <= X <= pts[-1][0]):
        return None
    i = min(range(len(pts)), key=lambda k: abs(pts[k][0] - X))
    i = max(1, min(len(pts) - 2, i))
    (x0, y0), (x1, y1), (x2, y2) = pts[i - 1], pts[i], pts[i + 1]
    y = (y0 * (X - x1) * (X - x2) / ((x0 - x1) * (x0 - x2))
         + y1 * (X - x0) * (X - x2) / ((x1 - x0) * (x1 - x2))
         + y2 * (X - x0) * (X - x1) / ((x2 - x0) * (x2 - x1)))
    return yinv(y)


def phase_page(nid):
    url = f'https://webbook.nist.gov/cgi/cbook.cgi?ID={nid}&Mask=4&Units=SI'
    t = fetch(url, f'{nid}_m4.html')
    t = re.sub(r'<script.*?</script>', '', t, flags=re.S)
    s = re.sub(r'<[^>]+>', ' ', t)
    s = html.unescape(s).replace('\xa0', ' ')
    s = re.sub(r'[ \t]+', ' ', s)
    s = re.sub(r'\n\s*\n+', '\n', s)
    return s, url


def num(tok):
    try:
        return float(tok.rstrip('.'))
    except ValueError:
        return None


def parse_phase(s):
    out = {}
    m = re.search(r'Molecular weight\s*:\s*([\d.]+)', s)
    out['mw'] = float(m.group(1)) if m else None

    def quantity(label):
        m = re.search(r'\n ' + label + r' ([\d.]+)(?: ± ([\d.]+))? (K|bar|kJ/mol) (\S+) (.*?)\n', s)
        if not m:
            return None
        return {'value': float(m.group(1)), 'pm': m.group(2), 'unit': m.group(3),
                'method': m.group(4), 'ref': m.group(5).strip()}

    out['tboil'] = quantity('T boil')
    out['tfus'] = quantity('T fus')
    out['ttriple'] = quantity('T triple')
    out['tc'] = quantity('T c')
    out['pc'] = quantity('P c')
    # enthalpy of fusion table
    fus = []
    i = s.find('\n Enthalpy of fusion \n Δ fus H (kJ/mol)')
    if i >= 0:
        block = s[i:].split('\n')[7:]
        for line in block:
            toks = line.split()
            if len(toks) < 2 or num(toks[0]) is None:
                break
            fus.append((num(toks[0]), num(toks[1]), ' '.join(toks[2:])))
    out['fus'] = fus
    # Antoine rows
    ant = []
    i = s.find('Antoine Equation Parameters')
    if i >= 0:
        block = s[i:].split('\n')
        start = next((k for k, l in enumerate(block) if l.strip() == 'Comment'), None)
        if start is not None:
            for line in block[start + 1:]:
                m = re.match(r'\s*([\d.]+) to ([\d.]+) (-?[\d.]+) (-?[\d.]+) (-?[\d.]+) (.*)', line)
                if not m:
                    break
                ant.append({'tmin': float(m.group(1).rstrip('.')), 'tmax': float(m.group(2).rstrip('.')),
                            'A': float(m.group(3)), 'B': float(m.group(4)), 'C': float(m.group(5)),
                            'ref': m.group(6).strip()})
    out['antoine'] = ant
    return out


def lsq(xs, ys, deg):
    """Least squares polynomial; returns coefficients c0..cdeg."""
    n = deg + 1
    # normal equations on centred x for conditioning
    xm = sum(xs) / len(xs)
    M = [[sum((x - xm) ** (i + j) for x in xs) for j in range(n)] for i in range(n)]
    v = [sum(y * (x - xm) ** i for x, y in zip(xs, ys)) for i in range(n)]
    # solve
    for c in range(n):
        p = max(range(c, n), key=lambda r: abs(M[r][c]))
        M[c], M[p] = M[p], M[c]
        v[c], v[p] = v[p], v[c]
        for r in range(n):
            if r != c:
                f = M[r][c] / M[c][c]
                M[r] = [a - f * b for a, b in zip(M[r], M[c])]
                v[r] -= f * v[c]
    cc = [v[i] / M[i][i] for i in range(n)]
    # expand back to powers of x
    coef = [0.0] * n
    for i, a in enumerate(cc):
        for k in range(i + 1):
            coef[k] += a * math.comb(i, k) * (-xm) ** (i - k)
    return coef


def sig(x, d=6):
    if x is None:
        return None
    return float(f'{x:.{d}g}')


def prop(value, unit, source, confidence='handbook', **kw):
    p = {'value': value, 'unit': unit, 'confidence': confidence if value is not None else None,
         'source': source if value is not None else None}
    p.update({k: v for k, v in kw.items() if v is not None})
    return p


def missing(note):
    return {'value': None, 'confidence': None, 'source': None, 'note': note}


def eos_name(nid):
    return f'NIST Chemistry WebBook, SRD 69, "Thermophysical Properties of Fluid Systems" (Lemmon, McLinden, Friend; reference EOS and transport correlations as REFPROP), fluid ID {nid}'


def build(spec):
    fid, name, nid, cas, catalog, kind = spec
    log = []
    page, purl = phase_page(nid)
    ph = parse_phase(page)
    sat, caturl = satcurve(nid)
    mw = ph['mw']
    src = eos_name(nid)

    # normal boiling point: the saturation state at exactly 0.101325 MPa
    bp, burl = sat_at_p(nid, P0)
    tb = bp['Temperature (K)'] if bp else None
    tfus = ph['tfus']['value'] if ph['tfus'] else None
    ttr = ph['ttriple']['value'] if ph['ttriple'] else None

    if kind == 'ambient':
        T = T0
        ref, rurl = isobar(nid, 292.15, 294.15, 1, 'ref')
        if not ref or len(ref) != 3:
            raise RuntimeError(f'{fid}: no reference isobar')
        r0 = ref[1]
        state = r0['Phase']
        phase = 'liquid' if state == 'liquid' else 'gas'
        rho = r0['Density (kg/m3)']
        cp = r0['Cp (J/g*K)'] * 1000
        c = r0['Sound Spd. (m/s)']
        mu = r0['Viscosity (Pa*s)'] if isinstance(r0['Viscosity (Pa*s)'], float) else None
        k = r0['Therm. Cond. (W/m*K)'] if isinstance(r0['Therm. Cond. (W/m*K)'], float) else None
        beta = -(ref[2]['Density (kg/m3)'] - ref[0]['Density (kg/m3)']) / (2.0 * rho)
        sigma = None
        surl = None
        if phase == 'liquid':
            st0, surl = sat_at_t(nid, T0)
            if st0 and isinstance(st0.get('Surf. Tension (l, N/m)'), float):
                sigma = st0['Surf. Tension (l, N/m)']
        ref_state = {'temperature': T0, 'pressure': 101325.0, 'note': None}
        cond_src = f'{src}; isobar 0.101325 MPa at 293.15 K ({rurl})'
    else:
        if tb is None:
            raise RuntimeError(f'{fid}: no boiling point')
        T = tb
        side = 'l' if kind == 'satliq' else 'v'
        phase = 'liquid' if side == 'l' else 'gas'

        def at(col):
            v = bp.get(f'{col} ({side}, {UNITS[col]})')
            return v if isinstance(v, float) else None
        surl = burl
        rho = at('Density')
        cp = at('Cp') * 1000
        c = at('Sound Spd.')
        mu = at('Viscosity')
        k = at('Therm. Cond.')
        # expansion along the saturation line is not isobaric; use the isobar just
        # off saturation on the stable side instead
        beta = None
        if side == 'l':
            iso, _ = isobar(nid, round(tb - 2.0, 3), round(tb - 0.2, 3), 0.9, 'beta')
            if iso and len(iso) >= 3 and all(r['Phase'] == 'liquid' for r in iso):
                d = iso[-1]['Density (kg/m3)'] - iso[0]['Density (kg/m3)']
                dT = iso[-1]['Temperature (K)'] - iso[0]['Temperature (K)']
                beta = -d / dT / iso[1]['Density (kg/m3)']
        else:
            iso, _ = isobar(nid, round(tb + 0.2, 3), round(tb + 2.0, 3), 0.9, 'beta')
            if iso and len(iso) >= 3 and all(r['Phase'] == 'vapor' for r in iso):
                d = iso[-1]['Density (kg/m3)'] - iso[0]['Density (kg/m3)']
                dT = iso[-1]['Temperature (K)'] - iso[0]['Temperature (K)']
                beta = -d / dT / iso[1]['Density (kg/m3)']
        sigma = at('Surf. Tension') if side == 'l' else None
        ref_state = {'temperature': sig(tb, 6), 'pressure': 101325.0,
                     'note': ('saturated liquid at the normal boiling point' if side == 'l'
                              else 'saturated vapour at the normal boiling point')}
        cond_src = f'{src}; saturation state at 0.101325 MPa ({burl})'

    groups = {}
    groups['mechanical'] = {'density': prop(sig(rho), 'kg/m3', cond_src)}

    fluid = {}
    fluid['viscosity'] = prop(sig(mu), 'Pa*s', cond_src) if mu else missing('no transport correlation in NIST WebBook for this fluid')
    if phase == 'liquid':
        fluid['surfaceTension'] = (prop(sig(sigma), 'N/m', f'{src}; surface-tension correlation, saturated liquid ({surl})',
                                        note='against its own saturated vapour, which differs from the value against air by well under 1 % for these fluids')
                                   if sigma else missing('no surface-tension correlation in NIST WebBook for this fluid'))
    fluid['bulkModulus'] = prop(sig(rho * c * c, 4), 'Pa', cond_src,
                                note='adiabatic (isentropic) bulk modulus K_s = rho*c^2, derived here from the NIST density and speed of sound' + (
                                    '; for a gas this equals gamma*p' if phase == 'gas' else ''))
    groups['fluid'] = fluid

    th = {}
    th['specificHeat'] = prop(sig(cp, 5), 'J/(kg*K)', cond_src, note='isobaric, cp')
    th['conductivity'] = prop(sig(k, 4), 'W/(m*K)', cond_src) if k else missing('no thermal-conductivity correlation in NIST WebBook for this fluid')
    if beta is not None:
        th['volumetricExpansion'] = prop(sig(beta, 4), '1/K', cond_src,
                                         note='derived here: -(1/rho) d(rho)/dT by a central difference over ±1 K of the NIST isobar' if kind == 'ambient'
                                         else 'derived here: -(1/rho) d(rho)/dT over 1.8 K of the NIST 1-atm isobar on the stable side of saturation')
    if tfus:
        th['meltingPoint'] = prop(tfus, 'K', f'NIST WebBook phase-change data, T fus ({ph["tfus"]["ref"]}) ({purl})',
                                  note=f'± {ph["tfus"]["pm"]} K' if ph['tfus']['pm'] else None)
    elif ttr:
        th['meltingPoint'] = prop(ttr, 'K', f'NIST WebBook phase-change data, T triple ({ph["ttriple"]["ref"]}) ({purl})',
                                  note='triple point, given as the melting point (no T fus listed)')
    else:
        th['meltingPoint'] = missing('no T fus in NIST WebBook')
    if fid in ('carbonDioxide',):
        th['meltingPoint']['note'] = (th['meltingPoint'].get('note') or '') + '; at 1 atm CO2 sublimes at 194.7 K, there is no liquid below 0.518 MPa'
    if tb is not None:
        th['boilingPoint'] = prop(sig(tb, 6), 'K', f'{src}; saturation state at 0.101325 MPa ({burl})',
                                  note=(f'NIST phase-change compilation: T boil {ph["tboil"]["value"]} K' if ph['tboil'] else None))
        lh = bp['Enthalpy (v, kJ/kg)']
        ll = bp['Enthalpy (l, kJ/kg)']
        th['latentHeatOfVaporization'] = prop(sig((lh - ll) * 1000, 5), 'J/kg', f'{src}; h_vap - h_liq at the normal boiling point ({burl})')
    elif fid == 'carbonDioxide':
        th['boilingPoint'] = missing('no liquid at 1 atm: CO2 sublimes at 194.7 K (see extra.sublimationPoint)')
    if ph['fus'] and mw:
        vals = sorted(v for v, _, _ in ph['fus'] if v)
        med = vals[len(vals) // 2]
        first = next(f for f in ph['fus'] if f[0] == med)
        th['latentHeatOfFusion'] = prop(sig(med / mw * 1e6, 4), 'J/kg',
                                        f'NIST WebBook phase-change data, enthalpy of fusion {med} kJ/mol at {first[1]} K ({first[2]}) over M = {mw} g/mol ({purl})',
                                        note=f'median of {len(vals)} listed values ({vals[0]}–{vals[-1]} kJ/mol)')
    else:
        th['latentHeatOfFusion'] = missing('no enthalpy of fusion in NIST WebBook phase-change data')
    groups['thermal'] = th

    groups['acoustic'] = {'speedOfSound': prop(sig(c, 5), 'm/s', cond_src)}

    extra = {}
    if ph['tc']:
        extra['criticalTemperature'] = prop(ph['tc']['value'], 'K', f'NIST WebBook phase-change data, T c ({ph["tc"]["ref"]}) ({purl})')
    if ph['pc']:
        extra['criticalPressure'] = prop(sig(ph['pc']['value'] * 1e5, 5), 'Pa', f'NIST WebBook phase-change data, P c ({ph["pc"]["ref"]}) ({purl})')
    # Antoine: choose the NIST row that best reproduces the EOS saturation curve
    if ph['antoine'] and sat:
        best = None
        for a in ph['antoine']:
            errs = []
            for r in sat:
                t = r['Temperature (K)']
                if a['tmin'] <= t <= a['tmax']:
                    pa = 10 ** (a['A'] - a['B'] / (t + a['C'])) / 10.0  # bar -> MPa
                    errs.append(abs(pa / r['Pressure (MPa)'] - 1))
            if len(errs) < 3:
                continue
            covers = (a['tmin'] <= T0 <= a['tmax']) + (tb is not None and a['tmin'] <= tb <= a['tmax'])
            score = (-covers, max(errs))
            if best is None or score < best[0]:
                best = (score, a, max(errs), len(errs))
        if best:
            _, a, err, n = best
            extra['vaporPressure'] = {
                'value': sig(10 ** (a['A'] - a['B'] / (T0 + a['C'])) * 1e5, 5) if a['tmin'] <= T0 <= a['tmax'] else None,
                'unit': 'Pa', 'confidence': 'handbook',
                'source': f'NIST WebBook phase-change data, Antoine parameters ({a["ref"]}) ({purl})',
                'note': ('value at 293.15 K from the law' if a['tmin'] <= T0 <= a['tmax'] else '293.15 K outside the law\'s range; value left null'),
                'law': {'kind': 'antoine', 'form': 'log10(P/bar) = A - B/(T + C), T in K',
                        'A': a['A'], 'B': a['B'], 'C': a['C'], 'validRange': [a['tmin'], a['tmax']],
                        'source': f'NIST WebBook ({a["ref"]})',
                        'fit': f'checked here against the NIST reference EOS saturation curve: max deviation {err * 100:.2f} % over {n} points in range'}}
    if fid == 'carbonDioxide':
        extra['sublimationPoint'] = prop(194.7, 'K', f'NIST WebBook phase-change data (T sub) ({purl})', note='verify: from the NIST compilation page')
    groups['extra'] = extra

    # temperature laws from a 1-atm isobar
    laws_src = f'{src}; 1-atm isobar'
    if kind == 'ambient' and phase == 'liquid':
        lo = math.ceil((tfus or ttr or 200.0) + 1.0)
        hi = math.floor(tb - 1.0) if tb else 373
        step = max(1, round((hi - lo) / 20))
        rows, lurl = isobar(nid, lo, hi, step, 'law')
        rows = [r for r in (rows or []) if r.get('Phase') == 'liquid']
        if len(rows) >= 5:
            Ts = [r['Temperature (K)'] for r in rows]
            rhos = [r['Density (kg/m3)'] for r in rows]
            c2 = lsq(Ts, rhos, 2)
            dev = max(abs(sum(cf * t ** i for i, cf in enumerate(c2)) / y - 1) for t, y in zip(Ts, rhos))
            groups['mechanical']['density']['law'] = {
                'kind': 'polynomial', 'variable': 'T', 'form': 'rho = c0 + c1*T + c2*T^2 (kg/m3, T in K)',
                'coefficients': [sig(x, 8) for x in c2], 'validRange': [Ts[0], Ts[-1]],
                'source': f'{laws_src} ({lurl})',
                'fit': f'least-squares fit here to {len(Ts)} NIST points at 1 atm; max deviation {dev * 100:.3f} %'}
            mus = [r['Viscosity (Pa*s)'] for r in rows if isinstance(r.get('Viscosity (Pa*s)'), float)]
            if len(mus) == len(Ts):
                ab = lsq([1.0 / t for t in Ts], [math.log(m) for m in mus], 1)
                devm = max(abs(math.exp(ab[0] + ab[1] / t) / m - 1) for t, m in zip(Ts, mus))
                groups['fluid']['viscosity']['law'] = {
                    'kind': 'andrade', 'form': 'ln(mu/Pa*s) = A + B/T, T in K',
                    'A': sig(ab[0], 7), 'B': sig(ab[1], 7), 'validRange': [Ts[0], Ts[-1]],
                    'source': f'{laws_src} ({lurl})',
                    'fit': f'least-squares fit here to {len(Ts)} NIST points at 1 atm; max deviation {devm * 100:.1f} %'}
                if devm > 0.03:
                    pts = [[t, sig(m, 5)] for t, m in zip(Ts, mus)]
                    groups['fluid']['viscosity']['law']['tablePoints'] = pts
                    groups['fluid']['viscosity']['law']['note'] = 'Andrade deviates more than 3 %; the NIST points are given as a table too'
            for key, col, scale, unit in (('specificHeat', 'Cp (J/g*K)', 1000, 'J/(kg*K)'),
                                          ('conductivity', 'Therm. Cond. (W/m*K)', 1, 'W/(m*K)')):
                if key in groups['thermal'] and groups['thermal'][key].get('value') is not None:
                    groups['thermal'][key]['law'] = {
                        'kind': 'table', 'variable': 'T', 'unit': 'K',
                        'points': [[r['Temperature (K)'], sig(r[col] * scale, 5)] for r in rows[::2]],
                        'source': f'{laws_src} ({lurl})'}
            groups['acoustic']['speedOfSound']['law'] = {
                'kind': 'table', 'variable': 'T', 'unit': 'K',
                'points': [[r['Temperature (K)'], sig(r['Sound Spd. (m/s)'], 5)] for r in rows[::2]],
                'source': f'{laws_src} ({lurl})'}
    elif kind == 'ambient' and phase == 'gas':
        lo = max(200, math.ceil((tb or 150.0) + 5))
        if fid == 'carbonDioxide':
            lo = 200
        rows = None
        for hi in (600, 500, 450, 400, 350):
            rows, lurl = isobar(nid, lo, hi, 25 if hi - lo >= 150 else 10, f'law{hi}')
            if rows:
                break
        rows = [r for r in (rows or []) if r.get('Phase') in ('vapor', 'supercritical')]
        if len(rows) >= 4:
            groups['mechanical']['density']['law'] = {
                'kind': 'table', 'variable': 'T', 'unit': 'K',
                'points': [[r['Temperature (K)'], sig(r['Density (kg/m3)'], 5)] for r in rows],
                'source': f'{laws_src} ({lurl})',
                'note': f'at 1 atm; close to the ideal gas rho = p*M/(R*T), M = {mw} g/mol, with the real-gas departure included'}
            if all(isinstance(r.get('Viscosity (Pa*s)'), float) for r in rows):
                groups['fluid']['viscosity']['law'] = {
                    'kind': 'table', 'variable': 'T', 'unit': 'K',
                    'points': [[r['Temperature (K)'], sig(r['Viscosity (Pa*s)'], 5)] for r in rows],
                    'source': f'{laws_src} ({lurl})'}
            if groups['thermal']['conductivity'].get('value') is not None and all(isinstance(r.get('Therm. Cond. (W/m*K)'), float) for r in rows):
                groups['thermal']['conductivity']['law'] = {
                    'kind': 'table', 'variable': 'T', 'unit': 'K',
                    'points': [[r['Temperature (K)'], sig(r['Therm. Cond. (W/m*K)'], 4)] for r in rows],
                    'source': f'{laws_src} ({lurl})'}
            groups['thermal']['specificHeat']['law'] = {
                'kind': 'table', 'variable': 'T', 'unit': 'K',
                'points': [[r['Temperature (K)'], sig(r['Cp (J/g*K)'] * 1000, 5)] for r in rows],
                'source': f'{laws_src} ({lurl})'}
            groups['acoustic']['speedOfSound']['law'] = {
                'kind': 'table', 'variable': 'T', 'unit': 'K',
                'points': [[r['Temperature (K)'], sig(r['Sound Spd. (m/s)'], 5)] for r in rows],
                'source': f'{laws_src} ({lurl})'}
    elif kind == 'satliq':
        lo_t = (ttr or tfus or 0) + 0.5
        rows = [r for r in sat if lo_t <= r['Temperature (K)'] <= tb + 0.01]
        if len(rows) > 12:
            rows = rows[::max(1, len(rows) // 12)]
        if len(rows) >= 4:
            def st(col, scale=1.0, d=5):
                return [[r['Temperature (K)'], sig(r[col] * scale, d)] for r in rows if isinstance(r.get(col), float)]
            groups['mechanical']['density']['law'] = {'kind': 'table', 'variable': 'T', 'unit': 'K', 'points': st('Density (l, kg/m3)'),
                                                      'source': f'{src}; saturated liquid ({caturl})', 'note': 'along the saturation line, not an isobar'}
            if mu:
                groups['fluid']['viscosity']['law'] = {'kind': 'table', 'variable': 'T', 'unit': 'K', 'points': st('Viscosity (l, Pa*s)'),
                                                       'source': f'{src}; saturated liquid ({caturl})', 'note': 'along the saturation line'}
            if sigma:
                groups['fluid']['surfaceTension']['law'] = {'kind': 'table', 'variable': 'T', 'unit': 'K', 'points': st('Surf. Tension (l, N/m)'),
                                                            'source': f'{src}; ({caturl})'}
    if kind == 'ambient' and phase == 'liquid' and sigma and sat:
        rows = [r for r in sat if (tfus or ttr or 0) + 1 <= r['Temperature (K)'] <= (tb or 400)]
        if len(rows) >= 4:
            rows = rows[::max(1, len(rows) // 10)]
            groups['fluid']['surfaceTension']['law'] = {
                'kind': 'table', 'variable': 'T', 'unit': 'K',
                'points': [[r['Temperature (K)'], sig(r['Surf. Tension (l, N/m)'], 5)] for r in rows if isinstance(r.get('Surf. Tension (l, N/m)'), float)],
                'source': f'{src}; saturation ({caturl})'}

    for (g, key), p in OVERRIDES.get(nid, {}).items():
        if groups.get(g, {}).get(key, {}).get('value') is None:
            groups.setdefault(g, {})[key] = p

    entry = {
        'id': fid, 'catalogId': catalog, 'name': name, 'phase': phase, 'cas': cas,
        'molarMass': sig(mw / 1000.0, 7) if mw else None,
        'referenceState': ref_state,
        'groups': groups,
        'dataOrigin': 'NIST WebBook (fetched 2026-10-09 by the research script)',
    }
    if kind == 'ambient' and phase == 'gas' and tb is None and fid != 'carbonDioxide':
        log.append(f'{fid}: no boiling point found')
    return entry, log


OVERRIDES = {
    'C7732185': {
        ('thermal', 'meltingPoint'): {
            'value': 273.15, 'unit': 'K', 'confidence': 'handbook',
            'source': 'CRC Handbook of Chemistry and Physics, 97th ed. (2016), as in the catalog f3d.water; IAPWS R14-08 melting curve gives 273.152 K at 101.325 kPa',
            'note': 'NIST WebBook phase-change page lists no T fus for water'},
        ('thermal', 'latentHeatOfFusion'): {
            'value': 3.34e5, 'unit': 'J/kg', 'confidence': 'handbook',
            'source': 'CRC Handbook of Chemistry and Physics, 97th ed. (2016), as in the catalog f3d.water (6.01 kJ/mol over 18.015 g/mol)',
            'note': 'NIST WebBook phase-change page lists no enthalpy of fusion for water'},
    },
}

UNITS = {'Density': 'kg/m3', 'Cp': 'J/g*K', 'Sound Spd.': 'm/s', 'Viscosity': 'Pa*s',
         'Therm. Cond.': 'W/m*K', 'Surf. Tension': 'N/m'}


def main():
    entries = []
    only = set(sys.argv[1:])
    for n, spec in enumerate(FLUIDS):
        if only and spec[0] not in only:
            continue
        try:
            e, log = build(spec)
            entries.append(e)
            for l in log:
                print('WARN', l)
            print('ok', spec[0], e['phase'], e['groups']['mechanical']['density']['value'])
        except Exception as ex:  # noqa
            print('FAIL', spec[0], repr(ex))
        if len(entries) % 8 == 0:
            json.dump({'entries': entries}, open(OUT, 'w'), indent=1, ensure_ascii=False)
    json.dump({'entries': entries}, open(OUT, 'w'), indent=1, ensure_ascii=False)
    print('written', len(entries))


if __name__ == '__main__':
    main()
