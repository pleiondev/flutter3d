#!/usr/bin/env python3
"""Writes what a template gives a new game: a vocabulary and a first level.

    python3 tool/make_templates.py

**A new game has told the editor nothing, and cannot.** The palette is built
from the document, and a game says what its own words look like in
`assets/editor.json` — both of which need a game that already exists. A template
is that file and that level, written before there is anybody to write them.

## The editor still has no vocabulary

Nothing here is compiled into the editor. A template is copied into the new
project and read back from *there*, by the same `Looks.parse` that reads the
crypt's file — so the rule `apps/editor/lib/src/vocabulary.dart` states holds
literally: the editor's code contains no genre word, only the name of a file.

What the words are is not invented here either. They are read off the genre
packages: `EntityTypes` from the level format, `ShooterEntities` and
`SampleEntities` from the shooter, `PlatformerEntities` from the platformer, at
the sizes those classes give as their defaults. A test asserts every one of them
still exists.

`secret` is deliberately absent: it is declared in the shooter and is **not** in
`sampleRegistry()`, so a level containing one does not validate.

## The first level is the part that is easy to get wrong

`LevelValidator` is stricter than it looks, and `LevelLoader.build` throws on an
error rather than reporting it, so a bad starter level is a game that will not
start. What it demands, and what this file is shaped by:

  * geometry at all — no brushes is an **error**, not a warning;
  * exactly one `player_spawn` and at least one `exit`, in both genres;
  * brushes that meet at faces rather than interpenetrating: more than 0.05 m³
    of shared volume is a warning per pair, and a room built as six overlapping
    slabs greets its author with a dozen of them;
  * a light with an intensity, and a point light with a range — an unbounded
    one lights the whole level;
  * anything a player has to reach standing clear of the stone.

So the room is one storey, walls butted to the floor and to each other, lit by
one lamp — and the test that matters asserts **zero errors and zero warnings**.
"""

import json
import os

from make_models import MODELS

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def room(size=16.0, height=4.0):
    """Four walls, a floor and a ceiling that share faces and nothing else.

    The long walls run the full width and the end walls fill what is left, so
    the corners meet rather than overlap. That is the whole trick, and it is the
    difference between a template that opens clean and one that opens with
    twelve warnings about z-fighting.
    """
    half = size / 2
    return [
        {'at': [0.0, -0.5, 0.0], 'size': [size, 1.0, size], 'material': 'floor'},
        {'at': [0.0, height + 0.5, 0.0], 'size': [size, 1.0, size],
         'material': 'ceiling'},
        {'at': [0.0, height / 2, -(half + 0.5)],
         'size': [size, height, 1.0], 'material': 'wall'},
        {'at': [0.0, height / 2, half + 0.5],
         'size': [size, height, 1.0], 'material': 'wall'},
        {'at': [-(half + 0.5), height / 2, 0.0],
         'size': [1.0, height, size + 2.0], 'material': 'wall'},
        {'at': [half + 0.5, height / 2, 0.0],
         'size': [1.0, height, size + 2.0], 'material': 'wall'},
    ]


def level(name, materials, entities, fog, template):
    """A document in the shape the writer produces, so it round-trips."""
    return {
        # `version`, `name` and `fogColor` are written unconditionally by
        # `Level.toJson`; a document that omits one comes back with it appended,
        # and `level_roundtrip_test.dart` says so.
        'version': 1,
        'name': name,
        'generatedBy': 'tool/make_templates.py',
        # Which template this came from, kept so the palette can be rebuilt even
        # if `assets/editor.json` is lost. `Level.toJson` writes unknown keys
        # back untouched, which is what makes this safe to carry.
        'editor': {'template': template},
        'fogColor': fog,
        'fogDensity': 0.0,
        'materials': materials,
        'brushes': room(),
        'lights': [
            {
                'type': 'point',
                'at': [0.0, 3.2, 0.0],
                'color': [1.0, 0.92, 0.78],
                'intensity': 9.0,
                # A range, because a point light without one lights the level
                # through its own walls.
                'range': 16.0,
            },
        ],
        'entities': entities,
    }


STONE = {
    'floor': {'baseColor': [0.42, 0.40, 0.38, 1.0], 'roughness': 0.9},
    'wall': {'baseColor': [0.50, 0.47, 0.44, 1.0], 'roughness': 0.85},
    'ceiling': {'baseColor': [0.28, 0.27, 0.26, 1.0], 'roughness': 0.95},
}

PAINT = {
    'floor': {'baseColor': [0.35, 0.45, 0.32, 1.0], 'roughness': 0.9},
    'wall': {'baseColor': [0.52, 0.44, 0.36, 1.0], 'roughness': 0.85},
    'ceiling': {'baseColor': [0.30, 0.34, 0.42, 1.0], 'roughness': 0.9},
}


# What each genre can put in a level, at the sizes its own package gives.
#
# `size` here is the box a click has to hit and what is drawn until a model has
# been read — never something written into the document. `defaults` *is* written
# into the document, and only where the game needs it: a door with no `travel`
# is a door that does not open, and a collectible with no `what` is a coin that
# gives nothing.

SHOOTER_TYPES = {
    'player_spawn': {'size': [0.7, 1.8, 0.7]},
    'monster': {'size': [0.7, 1.7, 0.7], 'defaults': {'kind': 'runner'}},
    'pickup': {'size': [0.45, 0.45, 0.45],
               'defaults': {'gives': 'health', 'amount': 25}},
    'key': {'size': [0.4, 0.4, 0.4], 'defaults': {'color': 'iron'}},
    'note': {'size': [0.4, 0.5, 0.06],
             'defaults': {'text': 'Somebody wrote something here.'}},
    'torch': {'size': [0.3, 0.55, 0.4]},
    'lamp': {'size': [0.34, 0.34, 0.34], 'defaults': {'color': 'warm'}},
    'window': {'size': [1.4, 2.2, 0.12],
               'defaults': {'size': [1.4, 2.2, 0.12]}},
    'door': {'size': [4.0, 4.0, 1.0],
             'defaults': {'size': [4.0, 4.0, 1.0], 'travel': [0.0, 3.8, 0.0],
                          'speed': 2.2, 'wait': 4.0}},
    'lift': {'size': [3.0, 0.5, 3.0],
             'defaults': {'size': [3.0, 0.5, 3.0], 'travel': [0.0, 4.0, 0.0],
                          'speed': 1.5, 'wait': 2.0}},
    'platform': {'size': [3.0, 0.4, 3.0],
                 'defaults': {'size': [3.0, 0.4, 3.0],
                              'travel': [4.0, 0.0, 0.0], 'speed': 1.5}},
    'button': {'size': [0.6, 0.6, 0.15],
               'defaults': {'size': [0.6, 0.6, 0.15]}},
    'trigger': {'size': [4.0, 3.0, 2.0],
                'defaults': {'size': [4.0, 3.0, 2.0], 'once': False}},
    'exit': {'size': [1.5, 2.5, 1.5]},
}

PLATFORMER_TYPES = {
    'player_spawn': {'size': [0.7, 1.8, 0.7]},
    'collectible': {'size': [0.5, 0.5, 0.5], 'defaults': {'what': 'coin'}},
    'key': {'size': [0.5, 0.5, 0.5], 'defaults': {'color': 'green'}},
    'enemy': {'size': [0.7, 0.7, 0.7],
              'defaults': {'size': [0.7, 0.7, 0.7], 'kind': 'patrol'}},
    'lamp': {'size': [0.4, 1.6, 0.4], 'defaults': {'size': [0.4, 1.6, 0.4]}},
    'checkpoint': {'size': [0.35, 2.2, 0.35],
                   'defaults': {'size': [3.0, 3.0, 3.0]}},
    'crate': {'size': [1.2, 1.2, 1.2],
              'defaults': {'size': [1.2, 1.2, 1.2], 'mass': 40.0}},
    'breakable': {'size': [2.0, 1.2, 2.0],
                  'defaults': {'size': [2.0, 1.2, 2.0]}},
    'climbable': {'size': [1.0, 6.0, 1.0],
                  'defaults': {'size': [1.0, 6.0, 1.0]}},
    'conveyor': {'size': [4.0, 0.4, 8.0],
                 'defaults': {'size': [4.0, 0.4, 8.0], 'flow': 3.0}},
    'crumbling': {'size': [3.0, 0.4, 3.0],
                  'defaults': {'size': [3.0, 0.4, 3.0]}},
    'hazard': {'size': [4.0, 0.8, 4.0],
               'defaults': {'size': [4.0, 0.8, 4.0]}},
    'oneway': {'size': [4.0, 0.3, 4.0],
               'defaults': {'size': [4.0, 0.3, 4.0]}},
    'spring': {'size': [1.6, 0.4, 1.6],
               'defaults': {'size': [1.6, 0.4, 1.6]}},
    'door': {'size': [4.0, 5.0, 2.0],
             'defaults': {'size': [4.0, 5.0, 2.0], 'travel': [0.0, 5.0, 0.0],
                          'speed': 2.0, 'wait': 3.0}},
    'lift': {'size': [4.0, 0.6, 4.0],
             'defaults': {'size': [4.0, 0.6, 4.0], 'travel': [0.0, 6.0, 0.0],
                          'speed': 2.0, 'wait': 1.5}},
    'platform': {'size': [4.0, 0.6, 4.0],
                 'defaults': {'size': [4.0, 0.6, 4.0],
                              'travel': [6.0, 0.0, 0.0], 'speed': 2.0}},
    'button': {'size': [0.6, 0.6, 0.15],
               'defaults': {'size': [0.6, 0.6, 0.15]}},
    'trigger': {'size': [4.0, 2.0, 4.0],
                'defaults': {'size': [4.0, 2.0, 4.0], 'once': False}},
    'exit': {'size': [5.0, 3.0, 5.0], 'defaults': {'size': [5.0, 3.0, 5.0]}},
}


TEMPLATES = {
    'shooter': {
        'name': 'Shooter',
        'about': 'Rooms, monsters, keys and a way down.',
        'types': SHOOTER_TYPES,
        'materials': STONE,
        'fog': [0.05, 0.04, 0.06],
        'entities': [
            {'type': 'player_spawn', 'at': [0.0, 0.0, 5.0], 'yaw': 0.0},
            {'type': 'torch', 'at': [-7.7, 2.6, 0.0], 'yaw': 1.5708},
            {'type': 'pickup', 'at': [3.0, 0.6, 1.0], 'gives': 'health',
             'amount': 25},
            {'type': 'exit', 'at': [0.0, 1.25, -6.5], 'yaw': 0.0},
        ],
    },
    'platformer': {
        'name': 'Platformer',
        'about': 'A room to jump around, coins to take and a way out.',
        'types': PLATFORMER_TYPES,
        'materials': PAINT,
        'fog': [0.06, 0.07, 0.10],
        'entities': [
            {'type': 'player_spawn', 'at': [0.0, 0.0, 5.0], 'yaw': 0.0},
            {'type': 'lamp', 'at': [-6.0, 0.8, -6.0], 'yaw': 0.0,
             'size': [0.4, 1.6, 0.4]},
            {'type': 'collectible', 'at': [2.0, 0.8, 0.0], 'what': 'coin'},
            {'type': 'collectible', 'at': [3.5, 0.8, 0.0], 'what': 'coin'},
            {'type': 'exit', 'at': [0.0, 1.5, -6.0], 'yaw': 0.0,
             'size': [5.0, 3.0, 5.0]},
        ],
    },
}


def dump(document, path):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, 'w') as file:
        # Two spaces and a trailing newline, which is what `Editing.write`
        # produces — otherwise the first save in a new project rewrites the
        # whole file and the diff hides the one thing that changed.
        json.dump(document, file, indent=2)
        file.write('\n')


def main():
    # The list the editor reads first. A bundle cannot be listed, so what
    # templates exist has to be written down like everything else.
    dump(
        {'templates': sorted(TEMPLATES)},
        os.path.join(HERE, 'apps', 'editor', 'assets', 'templates', 'index.json'),
    )

    for genre, template in TEMPLATES.items():
        where = os.path.join(HERE, 'apps', 'editor', 'assets', 'templates', genre)

        # The vocabulary, with every model path written the way it will be read:
        # from inside the project this gets copied into.
        types = {}
        for name, look in template['types'].items():
            entry = dict(look)
            if name in MODELS.get(genre, {}):
                entry['model'] = f'assets/models/{name}.glb'
            types[name] = entry
        dump(types, os.path.join(where, 'editor.json'))

        dump(
            level(
                f'{template["name"].lower()} start',
                template['materials'],
                template['entities'],
                template['fog'],
                genre,
            ),
            os.path.join(where, 'level.first.json'),
        )

        # The manifest: what to copy, and where it lands in a new project. A
        # file missing from `pubspec.yaml`'s `assets:` throws at scaffold time
        # in front of somebody; a test walks this list instead.
        files = {
            'editor.json': 'assets/editor.json',
            'level.first.json': 'assets/levels/first.json',
        }
        for name in sorted(MODELS.get(genre, {})):
            files[f'model.{name}.glb'] = f'assets/models/{name}.glb'
        dump(
            {
                'name': template['name'],
                'about': template['about'],
                'files': files,
            },
            os.path.join(where, 'index.json'),
        )
        print(f'{genre}: {len(types)} types, {len(files)} files')


if __name__ == '__main__':
    main()
