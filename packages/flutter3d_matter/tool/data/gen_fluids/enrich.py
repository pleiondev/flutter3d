"""Gather refractive index, autoignition, flash point (PubChem, citing HSDB / CRC /
ICSC) and heat of combustion (NIST WebBook thermochemistry) for the NIST fluids.

Writes matter_data/enrich_nist.json: {id: {group: {key: P}}} plus raw strings, for
review before merging.
"""
import html
import json
import os
import re
import statistics
import subprocess
import sys
import time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RAW = os.path.join(ROOT, 'nist_raw')
OUT = os.path.join(ROOT, 'sources', 'enrich_nist.json')
sys.path.insert(0, os.path.join(ROOT, 'gen_fluids'))
from nist_fluids import FLUIDS  # noqa: E402

PREFERRED = ('ILO-WHO International Chemical Safety Cards (ICSCs)', 'Hazardous Substances Data Bank (HSDB)',
             'CAMEO Chemicals')


def fetch(url, name):
    path = os.path.join(RAW, name)
    if os.path.exists(path) and os.path.getsize(path) > 50:
        return open(path, encoding='utf-8', errors='replace').read()
    for _ in range(3):
        r = subprocess.run(['curl', '-s', '-m', '60', url], capture_output=True)
        t = r.stdout.decode('utf-8', 'replace')
        if t and not t.lower().startswith('error code') and 'PUGREST.ServerBusy' not in t:
            open(path, 'w', encoding='utf-8').write(t)
            time.sleep(0.35)
            return t
        time.sleep(2)
    return ''


def cid_for(cas):
    t = fetch(f'https://pubchem.ncbi.nlm.nih.gov/rest/pug/compound/name/{cas}/cids/TXT', f'cid_{cas}.txt').split()
    return t[0] if t and t[0].isdigit() else None


def pubchem(cid, heading):
    t = fetch(f'https://pubchem.ncbi.nlm.nih.gov/rest/pug_view/data/compound/{cid}/JSON?heading={heading.replace(" ", "+")}',
              f'pc_{cid}_{heading.replace(" ", "_")}.json')
    try:
        d = json.loads(t)
    except ValueError:
        return []
    refs = {r.get('ReferenceNumber'): r.get('SourceName') for r in d.get('Record', {}).get('Reference', [])}
    out = []

    def walk(x):
        if isinstance(x, dict):
            for i in x.get('Information', []) or []:
                v = i.get('Value', {})
                if 'StringWithMarkup' in v:
                    s = ' '.join(m.get('String', '') for m in v['StringWithMarkup'])
                elif 'Number' in v:
                    s = ' '.join(str(n) for n in v['Number']) + ' ' + (v.get('Unit') or '')
                else:
                    continue
                out.append({'source': refs.get(i.get('ReferenceNumber')), 'cite': '; '.join(i.get('Reference', []) or []), 'text': s})
            for y in x.values():
                if isinstance(y, (dict, list)):
                    walk(y)
        elif isinstance(x, list):
            for y in x:
                walk(y)
    walk(d)
    return out


def temps_c(text):
    """All temperatures in a PubChem string, in °C (°F converted)."""
    vals = []
    for m in re.finditer(r'(-?\d+(?:\.\d+)?)\s*°\s*([CF])', text):
        v = float(m.group(1))
        vals.append(v if m.group(2) == 'C' else (v - 32) * 5 / 9)
    return vals


def pick_temperature(items, want_closed_cup=False):
    cands = []
    for it in items:
        ts = temps_c(it['text'])
        if not ts:
            continue
        if want_closed_cup and re.search(r'open cup|\bOC\b', it['text'], re.I) and not re.search(r'closed cup|\bCC\b', it['text'], re.I):
            continue
        cands.append((it, ts[0]))
    if not cands:
        return None
    for pref in PREFERRED:
        for it, t in cands:
            if it['source'] == pref:
                return it, t, cands
    return cands[0][0], cands[0][1], cands


def pick_refractive(items):
    for it in items:
        # "1.5011 at 20 °C/D" or "Index of refraction: 1.3288 at 20 °C/D"
        m = re.search(r'\b(1\.\d{3,6})\b', it['text'])
        if m and re.search(r'20\s*°\s*C|/D|\bD\b|589', it['text']):
            return it, float(m.group(1))
    for it in items:
        m = re.search(r'\b(1\.\d{3,6})\b', it['text'])
        if m:
            return it, float(m.group(1))
    return None


def nist_combustion(nid, phase):
    mask = 2 if phase == 'liquid' else 1
    url = f'https://webbook.nist.gov/cgi/cbook.cgi?ID={nid}&Mask={mask}&Units=SI'
    t = fetch(url, f'{nid}_m{mask}.html')
    t = re.sub(r'<script.*?</script>', '', t, flags=re.S)
    s = re.sub(r'<[^>]+>', ' ', t)
    s = html.unescape(s).replace('\xa0', ' ')
    s = re.sub(r'[ \t]+', ' ', s)
    m = re.search(r'\n ?Δ c H° (liquid|gas) (-?[\d.]+)(?: ± ([\d.]+))? kJ/mol (\S+) (.*?)\n', s)
    f = re.search(r'Formula\s*:\s*([^\n]+)', s)
    if not m:
        return None, url, (f.group(1) if f else None)
    return {'phase': m.group(1), 'value': float(m.group(2).rstrip('.')), 'pm': m.group(3), 'ref': m.group(5).strip()}, url, (f.group(1) if f else None)


def h_count(formula):
    if not formula:
        return None
    m = re.search(r'\bH (\d+)\b', formula) or re.search(r'H(\d+)', formula.replace(' ', ''))
    if m:
        return int(m.group(1))
    return 1 if re.search(r'\bH\b', formula) else 0


def main():
    parts = json.load(open(os.path.join(ROOT, 'sources', 'part_nist.json')))['entries']
    byid = {e['id']: e for e in parts}
    res = {}
    for fid, name, nid, cas, _, kind in FLUIDS:
        e = byid.get(fid)
        if not e:
            continue
        out = {}
        cid = cid_for(cas)
        raw = {'pubchemCid': cid}
        if cid:
            curl = f'https://pubchem.ncbi.nlm.nih.gov/compound/{cid}'
            ai = pick_temperature(pubchem(cid, 'Autoignition Temperature'))
            if ai:
                it, t, cands = ai
                spread = sorted({round(c[1]) for c in cands})
                out.setdefault('thermal', {})['autoignitionTemperature'] = {
                    'value': round(t + 273.15, 1), 'unit': 'K', 'confidence': 'handbook',
                    'source': f'{it["source"]} via PubChem CID {cid} ({curl}), "{it["text"]}"' + (f' [{it["cite"]}]' if it['cite'] else ''),
                    'note': f'values listed by PubChem sources, °C: {spread}; autoignition depends on the test method (ASTM E659 vs older)' if len(spread) > 1 else None}
            fp = pick_temperature(pubchem(cid, 'Flash Point'), want_closed_cup=True)
            if fp:
                it, t, cands = fp
                spread = sorted({round(c[1]) for c in cands})
                out.setdefault('extra', {})['flashPoint'] = {
                    'value': round(t + 273.15, 1), 'unit': 'K', 'confidence': 'handbook',
                    'source': f'{it["source"]} via PubChem CID {cid} ({curl}), "{it["text"]}"' + (f' [{it["cite"]}]' if it['cite'] else ''),
                    'note': f'values listed, °C: {spread}' if len(spread) > 1 else None}
            ri = pick_refractive(pubchem(cid, 'Refractive Index'))
            if ri:
                it, n = ri
                out.setdefault('optical', {})['refractiveIndex'] = {
                    'value': n, 'unit': '1', 'confidence': 'handbook',
                    'source': f'{it["source"]} via PubChem CID {cid} ({curl}), "{it["text"]}"' + (f' [{it["cite"]}]' if it['cite'] else ''),
                    'note': 'check the conditions in the quoted string (temperature, wavelength, phase)'}
        hc, hurl, formula = nist_combustion(nid, e['phase'] if kind == 'ambient' else 'liquid')
        raw['formula'] = formula
        mw = e.get('molarMass')
        halogen = formula and any(tok in ('F', 'Cl', 'Br') for tok in formula.split())
        if hc and mw and hc['value'] < 0 and not halogen:
            nh = h_count(formula)
            gross = -hc['value'] * 1000 / mw  # J/kg  (kJ/mol / (kg/mol) *1000)
            if nh is not None:
                net = (-hc['value'] - 44.0 * nh / 2.0) * 1000 / mw
                if hc['phase'] == 'liquid':
                    pass
                out.setdefault('thermal', {})['heatOfCombustion'] = {
                    'value': float(f'{net:.4g}'), 'unit': 'J/kg', 'confidence': 'handbook',
                    'source': f'NIST WebBook condensed/gas-phase thermochemistry, Δc H° {hc["phase"]} = {hc["value"]} kJ/mol ({hc["ref"]}) ({hurl})',
                    'note': (f'net (lower) heat: the standard gross heat {gross:.4g} J/kg minus the vaporization of the product water, '
                             f'{nh}/2 mol × 44.0 kJ/mol (H2O at 298.15 K); derived here. A fire\'s effective heat is lower by its combustion efficiency')}
        if out:
            res[fid] = {'groups': out, 'raw': raw}
        print(fid, {g: list(v) for g, v in out.items()})
    json.dump(res, open(OUT, 'w'), indent=1, ensure_ascii=False)


if __name__ == '__main__':
    main()
