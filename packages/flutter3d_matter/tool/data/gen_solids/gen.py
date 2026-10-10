import importlib.util
import json
import pathlib
import sys

HERE = pathlib.Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import core  # noqa: E402

OUT = HERE.parent / 'sources' / 'solids.json'


def load_batches():
    entries, pairs = [], []
    for f in sorted(HERE.glob('b[0-9][0-9]*.py')):
        spec = importlib.util.spec_from_file_location(f.stem, f)
        mod = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(mod)
        entries += getattr(mod, 'ENTRIES', [])
        pairs += getattr(mod, 'PAIRS', [])
    return entries, pairs


def walk_values(node):
    if isinstance(node, dict):
        if 'value' in node and 'confidence' in node or 'value' in node and node.get('value') is None:
            yield node
        else:
            for v in node.values():
                yield from walk_values(v)
    elif isinstance(node, list):
        for v in node:
            yield from walk_values(v)


def stats(entries):
    s = {'entries': len(entries), 'values': 0, 'nulls': 0, 'estimates': 0,
         'fetched': 0, 'recalled': 0, 'laws': 0}
    for e in entries:
        for g in ('mechanical', 'thermal', 'acoustic', 'optical', 'electrical', 'inelastic'):
            for v in walk_values(e.get(g, {})):
                if v.get('value') is None:
                    s['nulls'] += 1
                    continue
                s['values'] += 1
                if v.get('confidence') == 'estimate':
                    s['estimates'] += 1
                ver = v.get('verification', 'derived')
                s[ver] = s.get(ver, 0) + 1
        s['laws'] += len(e.get('laws', []))
    return s


CATALOG_KEYS = {
    'mechanical': {'density', 'youngsModulus', 'poissonRatio', 'yieldStrength', 'tensileStrength',
                   'hardness', 'staticFriction', 'kineticFriction', 'restitution', 'rollingResistance'},
    'thermal': {'specificHeat', 'conductivity', 'volumetricExpansion', 'meltingPoint', 'boilingPoint',
                'latentHeatOfFusion', 'latentHeatOfVaporization', 'emissivity', 'ignitionTemperature',
                'autoignitionTemperature', 'heatOfCombustion', 'radiantFraction'},
    'acoustic': {'absorption', 'speedOfSound', 'impedance'},
    'optical': {'refractiveIndex', 'abbeNumber', 'absorption', 'metalReflectance', 'roughnessMin',
                'roughnessMax', 'dielectricF0'},
    'electrical': {'resistivity'},
}
CAS_RE = __import__('re').compile(r'^\d{2,7}-\d{2}-\d$')


def with_unit(key, p):
    if isinstance(p, dict) and 'value' in p:
        q = dict(p)
        if key in core.UNITS:
            q = {'value': q.pop('value'), 'unit': core.UNITS[key], **q}
        if q.get('value') is None:
            q.setdefault('confidence', None)
            q.setdefault('source', None)
        return q
    if isinstance(p, dict):
        return {k: with_unit(k, v) for k, v in p.items()}
    return p


def shape(e):
    """Lay an entry out as matter_data/SCHEMA.txt has it: cas, groups{...}, extra, laws on the value."""
    ext = e['externalIds']
    cas = ext.get('CAS')
    out = {'id': e['id'], 'catalogId': e['catalogId'], 'name': e['name'], 'phase': e['phase'],
           'description': e['description'],
           'cas': cas if cas and CAS_RE.match(cas) else None}
    if cas and not CAS_RE.match(cas):
        out['casNote'] = cas
    out['externalIds'] = ext
    out['referenceState'] = e['referenceState']
    groups, extra = {}, {}
    for g in ('mechanical', 'thermal', 'acoustic', 'optical', 'electrical'):
        for k, v in e.get(g, {}).items():
            if k in CATALOG_KEYS[g]:
                groups.setdefault(g, {})[k] = with_unit(k, v)
            else:
                extra[f'{g}.{k}'] = with_unit(k, v)
    if 'inelastic' in e:
        groups['inelastic'] = with_unit('inelastic', e['inelastic'])
    leftover = []
    for lw in e.get('laws', []):
        g, _, k = lw['property'].partition('.')
        target = groups.get(g, {}).get(k) if k in CATALOG_KEYS.get(g, ()) else extra.get(lw['property'])
        if isinstance(target, dict):
            target.setdefault('laws', []).append(lw)
        else:
            leftover.append(lw)
    if extra:
        groups['extra'] = extra
    out['groups'] = groups
    if leftover:
        out['laws'] = leftover
    out['notes'] = e['notes']
    return out


def main():
    entries, pairs = load_batches()
    ids = [e['id'] for e in entries]
    dup = {i for i in ids if ids.count(i) > 1}
    if dup:
        raise SystemExit(f'duplicate ids: {dup}')
    meta = {
        'title': 'flutter3d_matter solids: verified reference data (task 0.4)',
        'generated': '2026-10-09',
        'disclaimer': 'reference values for simulation, not for design or safety calculations',
        'layout': 'matter_data/SCHEMA.txt (the fluids layout): cas, groups{mechanical, thermal, '
                  'acoustic, optical, electrical, inelastic, extra}; extra holds keys the catalog '
                  'type lacks, named group.key; a temperature law sits on its value as "laws"; '
                  'laws whose property has no value stay on the entry',
        'lawTemperature': 'laws give x and xUnit; the Eurocode laws keep theta in C (theta = T - '
                          '273.15) as the standards write them, all others are in K',
        'schema': {
            'value': 'every property is {value, unit, source, sourceUrl?, confidence, verification, '
                     'range?, note?, laws?}; value in SI; null = not found',
            'confidence': 'measured = a primary measurement on a named specimen; handbook = '
                          'a compiled table or standard; estimate = derived, representative of '
                          'a range, or assumed (always says how in the note)',
            'verification': 'fetched = the number was read from the cited source during this '
                            'research; recalled = the cited handbook value as known to the '
                            'researcher, not re-read here: open the source before 1.0; catalog = '
                            'kept from the current materials.dart, whose source string the note '
                            'quotes (not re-read here either)',
            'laws': 'temperature laws: kind table (points [T K, value]), polynomial / linear / '
                    'exponential (form, coefficients), validRange in K',
            'catalogId': 'the existing f3d.* id when the material is already in the catalog',
            'groups': 'mechanical, thermal, acoustic, optical, electrical as in '
                      'property_groups.dart; extra keys (shearModulus, compressiveStrength, '
                      'linearExpansion, shearWaveSpeed, rodWaveSpeed, resistivityTempCoeff, '
                      'dielectricF0) are new and named so; inelastic = damping, plastic, '
                      'hyperelastic (proposed group of 3A)',
            'friction': 'the material against itself, dry, unless the note says otherwise; '
                        'measured pairs are in pairs[]',
        },
        'units': core.UNITS,
        'stats': stats(entries),
        'sources': {k: {'text': t, 'url': u} for k, (t, u) in core.SOURCES.items()},
    }
    doc = {'meta': meta, 'entries': [shape(e) for e in entries],
           'pairs': [with_unit('pair', p) for p in pairs]}
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(json.dumps(doc, indent=1, ensure_ascii=False) + '\n')
    print(json.dumps(meta['stats']), len(pairs), 'pairs')


if __name__ == '__main__':
    main()
