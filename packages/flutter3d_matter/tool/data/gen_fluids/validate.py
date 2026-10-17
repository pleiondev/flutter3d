import json
import sys

GROUPS = {
    'mechanical': {'density'},
    'fluid': {'viscosity', 'surfaceTension', 'bulkModulus'},
    'thermal': {'specificHeat', 'conductivity', 'volumetricExpansion', 'meltingPoint', 'boilingPoint',
                'latentHeatOfFusion', 'latentHeatOfVaporization', 'emissivity', 'ignitionTemperature',
                'autoignitionTemperature', 'heatOfCombustion', 'radiantFraction'},
    'acoustic': {'speedOfSound', 'impedance', 'absorption'},
    'optical': {'refractiveIndex', 'abbeNumber', 'absorption'},
    'electrical': {'resistivity'},
    'extra': None,
}
RANGES = {  # loose plausibility bounds, SI
    'density': (0.05, 25000), 'viscosity': (1e-6, 1e9), 'surfaceTension': (1e-5, 2.5),
    'specificHeat': (100, 16000), 'conductivity': (0.003, 200), 'meltingPoint': (0.5, 2500),
    'boilingPoint': (3, 4000), 'speedOfSound': (100, 6000), 'refractiveIndex': (1.0, 2.0),
    'autoignitionTemperature': (400, 1400), 'heatOfCombustion': (1e5, 1.5e8),
}

d = json.load(open(sys.argv[1]))
ids, problems = set(), []
for e in d['entries']:
    i = e.get('id')
    for k in ('id', 'name', 'phase', 'cas', 'referenceState', 'groups'):
        if k not in e:
            problems.append(f'{i}: no {k}')
    if i in ids:
        problems.append(f'{i}: duplicate')
    ids.add(i)
    if e.get('phase') not in ('liquid', 'gas'):
        problems.append(f'{i}: phase {e.get("phase")}')
    for g, ps in e.get('groups', {}).items():
        if g not in GROUPS:
            problems.append(f'{i}: unknown group {g}')
            continue
        for k, p in ps.items():
            if GROUPS[g] is not None and k not in GROUPS[g]:
                problems.append(f'{i}: unknown field {g}.{k}')
            if not isinstance(p, dict):
                problems.append(f'{i}: {g}.{k} not an object')
                continue
            v = p.get('value')
            if v is None and not p.get('law'):
                if not p.get('note'):
                    problems.append(f'{i}: {g}.{k} null without note')
                continue
            if p.get('confidence') not in ('measured', 'handbook', 'estimate'):
                problems.append(f'{i}: {g}.{k} confidence {p.get("confidence")}')
            if not p.get('source'):
                problems.append(f'{i}: {g}.{k} no source')
            if isinstance(v, (int, float)) and k in RANGES:
                lo, hi = RANGES[k]
                if not lo <= v <= hi:
                    problems.append(f'{i}: {g}.{k} = {v} outside plausibility {lo}..{hi}')
print(len(d['entries']), 'entries;', len(problems), 'problems')
for p in problems:
    print(' ', p)
