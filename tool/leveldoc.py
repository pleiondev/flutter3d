#!/usr/bin/env python3
"""How a level document is written down, for every generator that writes one.

**Extracted at the second consumer**, which is this repository's habit rather
than a new rule: `apps/flutter3d_demo_platformer/tool/levelkit.py` had this to itself until
`apps/flutter3d_demo_dungeon/tool/cryptkit.py` wanted the same shape, and a second copy of a
formatter is a second answer to "what does a brush look like on the page".

What is here is only what is genuinely common. **`write` is not**, and that is
worth saying because it looks as though it should be: each game's writer names
its own material table, its own document skeleton and its own refusals — the
platformer will not write a level with a coin buried in a wall, and a crypt has
no coins. A shared `write` would have to be told all of that, and being told all
of it is what having two of them avoids.

Nothing here reads or writes a file. `dump` returns a string.
"""

import json


def dump(value, indent=0):
    """Compact where compact reads better: one line per brush, per entity.

    A level document is read far more often in a diff than in an editor, and
    the two want opposite things — a pretty-printer puts a brush on nine lines,
    so moving one reads as nine changes, and one line per brush makes a moved
    brush one line. The 110-character limit is where a brush stops fitting on a
    reviewer's screen.

    The second condition is the one that is easy to get wrong: a dictionary is
    only inlined if none of its *values* is itself a large structure. Without it
    a brush with a long route in it collapses onto one unreadable line that
    happens to be under the limit at the top level.
    """
    pad = "  " * indent
    if isinstance(value, dict):
        inner = json.dumps(value, separators=(", ", ": "))
        if len(inner) <= 110 and not any(isinstance(v, (dict, list)) and
                                         len(json.dumps(v)) > 60
                                         for v in value.values()):
            return pad + inner
        rows = [f'{pad}  {json.dumps(k)}: '
                f'{dump(v, indent + 1).lstrip() if isinstance(v, (dict, list)) else json.dumps(v)}'
                for k, v in value.items()]
        return pad + "{\n" + ",\n".join(rows) + "\n" + pad + "}"
    if isinstance(value, list):
        if all(isinstance(v, (int, float, str)) for v in value):
            return pad + json.dumps(value, separators=(", ", ": "))
        return pad + "[\n" + ",\n".join(dump(v, indent + 1) for v in value) + \
            "\n" + pad + "]"
    return pad + json.dumps(value)


def rounded(values):
    """A vector, at millimetre precision.

    Three places rather than full float repr, because the difference between
    `2.0999999999999996` and `2.1` is invisible in the game and enormous in a
    diff — a generator re-run on a different machine should produce the same
    file or a deliberately different one, never a noisier one.
    """
    return [round(float(x), 3) for x in values]
