import json
import sys

d = json.load(open(sys.argv[1]))
only = set(sys.argv[2:])
for e in d['entries']:
    if only and e['id'] not in only:
        continue
    print('#', e['id'], e['phase'], e.get('cas'), e['referenceState'])
    for g, ps in e['groups'].items():
        for k, p in ps.items():
            law = p.get('law')
            ls = ''
            if law:
                ls = law['kind'] + ' ' + str({x: law[x] for x in law if x in ('A', 'B', 'C', 'coefficients', 'validRange', 'fit')})[:220]
            print('  ', g, k, p.get('value'), p.get('unit'), p.get('confidence'), '|', (p.get('note') or '')[:70], '|', ls)
