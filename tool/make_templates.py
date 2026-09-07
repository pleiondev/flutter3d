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
crypt's file — so the rule `apps/flutter3d_editor/lib/src/vocabulary.dart` states holds
literally: the editor's code contains no genre word, only the name of a file.

What the words are is not invented here either. They are read off the genre
packages: `EntityTypes` from the level format, `ShooterEntities` and
`SampleEntities` from the shooter, `PlatformerEntities` from the platformer, at
the sizes those classes give as their defaults. A test asserts every one of them
still exists.

`secret` is deliberately absent: it is declared in the shooter and is **not** in
`sampleRegistry()`, so a level containing one does not validate.

## Four genres, and only two of them are a room

The two that came first are played indoors, so their first level is a room and
`room()` below builds it. The other two are not, and pretending otherwise would
have given each of them a template that is wrong about the first thing anybody
sees.

**Racing gets a field and no road.** A circuit is two documents — the level
here, and beside it a measured curve with widths, banks, barriers, checkpoints
and a starting grid — and only the first is a level. So the template is the
level half: turf to land on, a fence of posts to measure speed against, and the
air of a morning. What a new project does *not* get is a circuit, because there
is nothing in this repository that edits one; see the note on `paddock`.

**Strategy gets the map the demo plays.** Its ground is eighty-one by eighty-one
samples of a hillside and its opening is an economy — two halls, two seams, a
purse each and a block of workers apiece pointing at them by name. Neither half
is something this file could invent and still call playable, and
`apps/flutter3d_demo_strategy/tool/make_map.py` has already written one that the
game is played on. So the template reads that document rather than guessing at
one; see `strategy_level`.

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


def level(
    name,
    template,
    *,
    materials,
    brushes,
    lights,
    entities,
    fog,
    density=0.0,
    before=None,
    after=None,
):
    """A document in the shape the writer produces, so it round-trips.

    The keys are in the order `Level.toJson` writes them, and everything the
    format does not know — `generatedBy`, `editor`, and strategy's `goal` — is
    written where it should stay. `writeThrough` keeps the order it read and
    appends only what was missing, so a document written in some other order
    comes back rearranged on its first save; [before] and [after] exist so that
    a genre with a section of its own can put it somewhere and have it stay
    there.
    """
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
        **(before or {}),
        'fogColor': fog,
        'fogDensity': density,
        'materials': materials,
        'brushes': brushes,
        'lights': lights,
        'entities': entities,
        **(after or {}),
    }


INDOOR_LIGHT = [
    {
        'type': 'point',
        'at': [0.0, 3.2, 0.0],
        'color': [1.0, 0.92, 0.78],
        'intensity': 9.0,
        # A range, because a point light without one lights the level through
        # its own walls.
        'range': 16.0,
    },
]


def indoors(genre, template):
    """The first level of a genre played inside a building: one room."""
    return level(
        f'{template["name"].lower()} start',
        genre,
        materials=template['materials'],
        brushes=room(),
        lights=INDOOR_LIGHT,
        entities=template['entities'],
        fog=template['fog'],
    )


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

TURF = {
    'grass': {'baseColor': [0.18, 0.30, 0.14, 1.0], 'roughness': 1.0},
    'stone': {'baseColor': [0.45, 0.44, 0.42, 1.0], 'roughness': 0.9},
}


def fence(extent, step):
    """The coordinates along one side of a square of posts, ends included."""
    return [round(-extent + i * step, 3) for i in range(int(2 * extent / step) + 1)]


def paddock(reach=200.0, extent=150.0, step=50.0, floor=-1.5):
    """Somewhere to drive, with nothing to drive on yet.

    **The half of a circuit that is a level.** A track in this repository is a
    measured curve — points, widths, banks, barriers, checkpoints, a starting
    grid — held in a second document beside this one and read by
    `TrackDocument`, and the ground here is only what a car lands on when it
    leaves the road. A new project gets the ground; the road is drawn by
    `apps/flutter3d_demo_racing/tool/make_track.py` and edited by nothing.

    The turf's top face is [floor] rather than zero for the reason `make_track`
    gives: a road rises and falls, and ground at zero is *above* it wherever it
    dips. `surface` is on the turf and not on the posts because a racing game
    asks the brush under a wheel what it is, and a post is something a car hits
    rather than something it drives on.

    The posts stand on a square rather than on a ring because this file is
    regenerated and its output diffed byte for byte: `sin` and `cos` are libm,
    one unit in the last place is one different byte, and a fence needs no
    trigonometry to be a fence. Their feet sit exactly on the turf's top face —
    a shared face has no volume, and shared volume is what the validator counts.
    """
    thickness = 4.0
    height = 12.0
    posts = [(x, z) for x in fence(extent, step) for z in (-extent, extent)]
    posts += [
        (x, z) for x in (-extent, extent) for z in fence(extent - step, step)
    ]
    return [
        {
            'at': [0.0, floor - thickness / 2, 0.0],
            'size': [reach * 2, thickness, reach * 2],
            'material': 'grass',
            'surface': 'grass',
        },
        *[
            {
                'at': [x, floor + height / 2, z],
                'size': [4.0, height, 4.0],
                'material': 'stone',
            }
            for x, z in posts
        ],
    ]


# The air the racing template is raced in, which is `SkyPresets.morning` and not
# a set of numbers chosen beside it. The preset decides the sun, the haze and
# the colour distance settles to all at once — that is what stops the far side
# of a circuit ending in a visible band — so a template that picked its own
# would be the one place in this genre where the sky and the fog can disagree.
# `templates_test.dart` reads the preset out of the package and checks these.
MORNING_SUN = [
    {
        'type': 'directional',
        # `SkyPreset.sunDirection`, rounded the way `make_track.py` rounds it.
        'direction': [-0.769, -0.559, 0.311],
        'color': [1.0, 0.95, 0.86],
        'intensity': 3.1,
        'castsShadow': True,
    },
]
MORNING_HAZE = [0.66, 0.75, 0.85]
MORNING_DENSITY = 0.0042


def racing_level(genre, template):
    """A field, a fence and a morning — and no circuit. See `paddock`."""
    return level(
        f'{template["name"].lower()} start',
        genre,
        materials=TURF,
        brushes=paddock(),
        lights=MORNING_SUN,
        # **Empty on purpose, and the empty list is the statement.** A circuit
        # places nothing: its scenery is brushes and everything that is really
        # an object belongs to the track document. `main.dart` in the racing
        # demo loads its level with an empty `EntityRegistry` for exactly this
        # reason, and a template that invented a word here would be offering
        # something no racing game reads.
        entities=[],
        fog=MORNING_HAZE,
        density=MORNING_DENSITY,
    )


# The map the strategy template starts a project on, read rather than invented.
STRATEGY_MAP = os.path.join(
    'apps', 'flutter3d_demo_strategy', 'assets', 'levels', 'map_a.json',
)


def strategy_level(genre, template):
    """The map the strategy demo plays, as the first level of a new project.

    **Not a room, and not a guess at one.** A strategy map is ground made of
    samples and an economy standing on it: halls that everything else points at
    by name, seams worth digging, a purse each and a block of workers apiece.
    Every one of those is checked by `strategyValidator`, and a starter map
    written here would be this file inventing an economy it cannot play — where
    `make_map.py` has already written one the demo is played on and the tests
    are run against.

    So the document is read and three lines of it are changed: what it is
    called, what wrote it, and which template it belongs to. The heightfield,
    the seams and the finishing line come across untouched — the line
    especially, which is `goal`, which the level format does not know and
    carries anyway.
    """
    with open(os.path.join(HERE, STRATEGY_MAP)) as file:
        played = json.load(file)
    return level(
        f'{template["name"].lower()} start',
        genre,
        materials=played['materials'],
        brushes=played['brushes'],
        lights=played['lights'],
        entities=played['entities'],
        # Open air under one sun, so the haze is the sky's colour and there is
        # no density: a map this size read through fog would be a map nobody
        # can command from above.
        fog=[0.58, 0.66, 0.74],
        before={'goal': played['goal']},
        after={'heightfield': played['heightfield']},
    )


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


# Racing places nothing. See the note in `racing_level`: a circuit's scenery is
# brushes and everything that is really an object is in the track document, so
# the vocabulary a racing project starts with is empty — which is a sentence
# about the genre and not a gap. The palette still offers this template's
# materials and a light, because those are what a level is made of here.
RACING_TYPES = {}

# What a strategy map has on it, at the sizes the strategy package draws them.
#
# A hall is `Building.width` by `Building.depth` and stands as high as
# `StrategyBridge` builds it, which is `UnitSize.height * 2.5`; a worker is one
# unit, `Unit.radius` across and `UnitSize.height` tall. A seam and a purse have
# no size of their own — a `ResourceNode` is a place and an amount, a stockpile
# and a producer are bookkeeping pinned to a hall — so what is written for those
# is the box a click has to hit, chosen so that they can be told apart from the
# hall they sit on top of.
#
# `defaults` carries only what a document can be right about without knowing the
# rest of the map. Every name a `worker` and a `producer` point at — `digs`,
# `home`, `target` — is deliberately absent: a default naming some other
# entity would be a default that is wrong the moment it is placed on a map that
# has no such hall, and `strategyValidator` says so in words.
STRATEGY_TYPES = {
    'camp': {
        'size': [12.0, 3.0, 10.0],
        'defaults': {'side': 0, 'width': 12.0, 'depth': 10.0},
    },
    'worker': {
        'size': [0.8, 1.2, 0.8],
        'defaults': {'side': 0, 'count': 10, 'across': 5, 'spacing': 1.1},
    },
    'resource_node': {
        'size': [4.0, 1.0, 4.0],
        'defaults': {'amount': 1600.0},
    },
    'stockpile': {
        'size': [1.2, 1.2, 1.2],
        'defaults': {'side': 0, 'amount': 0.0},
    },
    'producer': {
        'size': [1.2, 1.2, 1.2],
        # `Producer`'s own defaults, which `openMatch` falls back to as well.
        'defaults': {'cost': 25.0, 'seconds': 4.0},
    },
}


TEMPLATES = {
    'shooter': {
        'name': 'Shooter',
        'about': 'Rooms, monsters, keys and a way down.',
        'types': SHOOTER_TYPES,
        'level': indoors,
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
        'level': indoors,
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
    'racing': {
        'name': 'Racing',
        'about': 'Turf to land on, a fence to measure speed against.',
        'types': RACING_TYPES,
        'level': racing_level,
    },
    'strategy': {
        'name': 'Strategy',
        'about': 'A hillside, two halls, two seams and a crowd apiece.',
        'types': STRATEGY_TYPES,
        'level': strategy_level,
    },
}


# The application a new project starts as, copied into the editor's bundle so
# it can be written into a project.
#
# **A real application in this repository, not a string in a scaffolder.** A
# `main.dart` that only ever exists as text is one that stops compiling six
# months later and nobody finds out until somebody creates a project;
# `apps/flutter3d_template_app` is analysed by CI like everything else, and this copies
# it. One source, one regeneration, one diff.
APP = {
    'app.main.dart.txt': ('apps/flutter3d_template_app/lib/main.dart', 'lib/main.dart'),
    'app.backend.dart.txt': (
        'apps/flutter3d_template_app/lib/src/backend.dart',
        'lib/src/backend.dart',
    ),
    # The test a new project comes with. Same argument as `main.dart` above,
    # and it used to be a string inside the scaffolder — which is the one
    # place in this repository where nothing compiles what it holds.
    'app.test.dart.txt': (
        'apps/flutter3d_template_app/test/widget_test.dart',
        'test/widget_test.dart',
    ),
}


def copy_app(where):
    """Puts the seed application beside a template, as text."""
    for name, (source, _) in APP.items():
        with open(os.path.join(HERE, source)) as file:
            text = file.read()
        os.makedirs(where, exist_ok=True)
        with open(os.path.join(where, name), 'w') as out:
            out.write(text)


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
        os.path.join(HERE, 'apps', 'flutter3d_editor', 'assets', 'templates', 'index.json'),
    )

    for genre, template in TEMPLATES.items():
        where = os.path.join(HERE, 'apps', 'flutter3d_editor', 'assets', 'templates', genre)

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
            template['level'](genre, template),
            os.path.join(where, 'level.first.json'),
        )

        # The manifest: what to copy, and where it lands in a new project. A
        # file missing from `pubspec.yaml`'s `assets:` throws at scaffold time
        # in front of somebody; a test walks this list instead.
        copy_app(where)
        files = {
            'editor.json': 'assets/editor.json',
            'level.first.json': 'assets/levels/first.json',
            **{name: destination for name, (_, destination) in APP.items()},
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
