#!/usr/bin/env python3
"""Writes the circuit this game is played on.

The same rule the levels keep, for the same reason: **edit this, not the JSON**.
A circuit is several hundred numbers that have to agree with each other — a
width that changes over four metres of a corner, a barrier that stops halfway
along a straight, a checkpoint behind the one before it — and a person editing
those by hand is a person introducing exactly one of them and not noticing.

The shape is a closed curve with a varying radius, which is a cheap way to get a
circuit that is not a ring: the lobes become corners of different speeds, and
where the radius closes fastest is where the road narrows and tilts. Everything
downstream is measured in metres along that curve, so nothing here has to agree
with anything about segments.

Run: python3 tool/make_track.py
"""

import json
import math
from pathlib import Path

TRACKS = Path(__file__).resolve().parent.parent / "assets" / "tracks"

# How many control points the curve is authored with. Enough that the corners
# are corners rather than polygons, few enough that the file is readable.
POINTS = 32

# The shape. `base` sets how big the circuit is; the two lobes are what turn a
# ring into a lap with corners worth naming.
BASE_RADIUS = 150.0
LOBE_TWO = 34.0
LOBE_THREE = 22.0

# How much the circuit climbs and falls, top to bottom.
RELIEF = 9.0

WIDEST = 18.0
NARROWEST = 11.0

# How far the ground either side stays part of the track before the level takes
# over. Wide enough to run wide and get back on.
SHOULDER = 5.0

# The most a corner is tilted, in degrees, at the tightest radius on the lap.
MAX_BANK = 7.0

LAP_CHECKPOINTS = 4


def centre_line():
    """The control points, as (position, curvature) pairs."""
    points = []
    for i in range(POINTS):
        angle = 2 * math.pi * i / POINTS
        radius = (
            BASE_RADIUS
            + LOBE_TWO * math.cos(2 * angle)
            + LOBE_THREE * math.cos(3 * angle)
        )
        points.append(
            (
                radius * math.cos(angle),
                RELIEF * 0.5 * math.sin(angle) - RELIEF * 0.25 * math.cos(2 * angle),
                radius * math.sin(angle),
            )
        )
    return points


def curvature_at(points, i):
    """How sharply the line bends at point `i`, from its neighbours.

    Worked out here rather than read back from the engine's curve because this
    script has no engine: it is an estimate, used only to decide where the road
    narrows and tilts, and being a few percent out costs nothing.
    """
    before = points[(i - 1) % len(points)]
    here = points[i]
    after = points[(i + 1) % len(points)]

    ax, az = here[0] - before[0], here[2] - before[2]
    bx, bz = after[0] - here[0], after[2] - here[2]
    la = math.hypot(ax, az)
    lb = math.hypot(bx, bz)
    if la < 1e-6 or lb < 1e-6:
        return 0.0

    # The angle between the two chords, over the distance they cover: the
    # discrete version of radians per metre.
    cross = (ax * bz - az * bx) / (la * lb)
    dot = (ax * bx + az * bz) / (la * lb)
    turn = math.atan2(cross, dot)
    return turn / ((la + lb) / 2)


def build():
    points = centre_line()
    curves = [curvature_at(points, i) for i in range(len(points))]
    sharpest = max(abs(c) for c in curves) or 1.0

    entries = []
    for i, (x, y, z) in enumerate(points):
        tightness = abs(curves[i]) / sharpest
        entries.append(
            {
                "at": rounded([x, y, z]),
                # The road closes down through the tight stuff, which is what
                # makes a slow corner feel slow.
                "width": round(WIDEST - (WIDEST - NARROWEST) * tightness, 2),
                # Tilted into the turn. The sign matters and is easy to get
                # backwards: a positive camber raises the road's right-hand
                # edge, and a left-hand corner — which is a positive curvature
                # here — throws the car to its right, so the right edge is the
                # one that has to come up. Getting this the wrong way round
                # produces a circuit that is off-camber everywhere, which does
                # not look wrong and puts the car off the road at every corner
                # tight enough to matter.
                "bank": round(MAX_BANK * tightness * sign(curves[i]), 2),
            }
        )
    return entries


def sign(value):
    return (value > 0) - (value < 0)


def rounded(values):
    return [round(float(v), 3) for v in values]


def lap_length(points):
    """The chord length round the control points.

    An underestimate of the real curve — which is what the engine measures — by
    well under a percent at this spacing. Only used to place things round the
    lap as fractions of it, so the error cancels.
    """
    total = 0.0
    for i in range(len(points)):
        a = points[i]
        b = points[(i + 1) % len(points)]
        total += math.dist(a, b)
    return total


def ground(points):
    """The level around the circuit: something to land on off the road.

    Its top sits below the lowest point of the circuit rather than at zero. The
    road rises and falls, and a ground plane at zero would be *above* it wherever
    it dips — burying the track in the scenery, which looks like the road
    disappearing into a hillside and drives like a wall.

    How far it reaches is not a taste: it is the haze. The ground is a square and
    past its edge there is nothing, so the edge has to fall somewhere the air has
    already swallowed — see `ground_reach`.
    """
    reach = ground_reach()
    floor = min(y for _, y, _ in points) - 1.5
    thickness = 4.0
    brushes = [
        {
            "at": [0.0, round(floor - thickness / 2, 3), 0.0],
            "size": [reach * 2, thickness, reach * 2],
            "material": "grass",
            "surface": "grass",
        }
    ]

    # A ring of pillars outside the circuit, so that there is something to
    # measure speed against. Placed well clear of the road: scenery a car can
    # reach is scenery a car will hit.
    for i in range(24):
        angle = 2 * math.pi * i / 24
        radius = PILLAR_RADIUS
        brushes.append(
            {
                "at": rounded(
                    [radius * math.cos(angle), floor + 6.0,
                     radius * math.sin(angle)]
                ),
                "size": [4.0, 12.0, 4.0],
                "material": "stone",
            }
        )
    return brushes


# Flat colours rather than texture maps. `albedo` in this format is the path to
# a base-colour image; `baseColor` is the colour itself, which is what a circuit
# that has not been dressed yet wants — and a level that will not load because
# nobody has drawn the grass is a level nobody can drive.
MATERIALS = {
    "grass": {"baseColor": [0.18, 0.3, 0.14, 1.0], "roughness": 1.0},
    "stone": {"baseColor": [0.45, 0.44, 0.42, 1.0], "roughness": 0.9},
}

# --- The sky ----------------------------------------------------------------
#
# One preset decides the sun, the gradient, the haze and the exposure, and
# everything else about the light is *derived* from it here. That is the whole
# point of this section, and it is a repair: the atmosphere used to be written
# in four places that could not agree — a sky colour in `main.dart`, a fog
# density beside it, a `fogColor`/`fogDensity` in this file that nothing ever
# read, and a sun direction typed out here and again in `frame_test.dart`.
# Changing the hour meant changing four numbers, and getting one wrong meant a
# circuit lit from the east and hazed from the west.
#
# These five are the same five as `SkyPresets` in
# `packages/flutter3d_racing/lib/src/sky.dart`, and `frame_test.dart` compares
# the block written below against the Dart constant of the same name — so the
# copy cannot drift without a test saying so. The Dart side exists because a
# track file with no `"sky"` block still has to have weather.
SKY_PRESETS = {
    "dawn": {
        "name": "dawn",
        "sunElevationDeg": 4.0,
        "sunAzimuthDeg": 95.0,
        "sunColor": [1.0, 0.62, 0.38],
        "sunIntensity": 2.1,
        "zenith": [0.16, 0.24, 0.42],
        "horizon": [0.72, 0.52, 0.44],
        "belowHorizon": [0.16, 0.15, 0.17],
        "glowWide": 5.0,
        "glowStrength": 0.55,
        "fogDensity": 0.006,
        "fogBacklitExponent": 5.0,
        "fogBacklitStrength": 0.45,
        "ambientIntensity": 0.08,
        "exposure": 1.85,
        "sunDisc": 26.0,
    },
    "morning": {
        "name": "morning",
        "sunElevationDeg": 34.0,
        "sunAzimuthDeg": 112.0,
        "sunColor": [1.0, 0.95, 0.86],
        "sunIntensity": 3.1,
        "zenith": [0.26, 0.42, 0.72],
        "horizon": [0.66, 0.75, 0.85],
        "belowHorizon": [0.2, 0.21, 0.22],
        "glowWide": 6.0,
        "glowStrength": 0.3,
        "fogDensity": 0.0042,
        "fogBacklitExponent": 6.0,
        "fogBacklitStrength": 0.35,
        "ambientIntensity": 0.1,
        "exposure": 1.6,
        "sunDisc": 14.0,
    },
    "noon": {
        "name": "noon",
        "sunElevationDeg": 78.0,
        "sunAzimuthDeg": 150.0,
        "sunColor": [1.0, 0.99, 0.96],
        "sunIntensity": 3.6,
        "zenith": [0.2, 0.38, 0.76],
        "horizon": [0.62, 0.72, 0.86],
        "belowHorizon": [0.22, 0.23, 0.24],
        "glowWide": 8.0,
        "glowStrength": 0.18,
        "fogDensity": 0.003,
        "fogBacklitExponent": 8.0,
        "fogBacklitStrength": 0.22,
        "ambientIntensity": 0.12,
        "exposure": 1.45,
        "sunDisc": 9.0,
    },
    "golden": {
        "name": "golden",
        "sunElevationDeg": 11.0,
        "sunAzimuthDeg": 285.0,
        "sunColor": [1.0, 0.78, 0.52],
        "sunIntensity": 2.6,
        "zenith": [0.22, 0.34, 0.6],
        "horizon": [0.86, 0.62, 0.4],
        "belowHorizon": [0.2, 0.17, 0.15],
        "glowWide": 4.5,
        "glowStrength": 0.7,
        "fogDensity": 0.005,
        "fogBacklitExponent": 4.5,
        "fogBacklitStrength": 0.6,
        "ambientIntensity": 0.09,
        "exposure": 1.75,
        "sunDisc": 34.0,
    },
    "dusk": {
        "name": "dusk",
        "sunElevationDeg": -2.0,
        "sunAzimuthDeg": 292.0,
        "sunColor": [0.72, 0.6, 0.66],
        "sunIntensity": 1.2,
        "zenith": [0.1, 0.14, 0.3],
        "horizon": [0.44, 0.38, 0.48],
        "belowHorizon": [0.09, 0.09, 0.12],
        "glowWide": 4.0,
        "glowStrength": 0.4,
        "fogDensity": 0.0075,
        "fogBacklitExponent": 4.0,
        "fogBacklitStrength": 0.3,
        "ambientIntensity": 0.14,
        "exposure": 2.05,
        "sunDisc": 0.0,
    },
}

# Which hour this circuit is raced at. The one line to change.
PRESET = "morning"

# How much of the far edge of the ground may still show through the haze.
#
# `exp(-density * reach)` is exactly how much of it survives, so this number and
# the preset's density between them decide how big the ground has to be. A tenth
# is below what anybody notices against a horizon of the same colour.
GROUND_FADE = 0.12

# And the ground is not free at any size: `Scene.computeBounds` takes it, the
# last shadow cascade is fitted to the scene, and its texels grow with it. Clear
# air would ask for a kilometre; it does not get one, and the cost of the clamp
# is a faint seam at the horizon on the clearest presets.
GROUND_MIN = 300.0
GROUND_MAX = 700.0


def sky():
    return SKY_PRESETS[PRESET]


def direction_to_sun(preset):
    """A unit vector pointing up at the sun. Mirrors `SkyPreset.directionToSun`."""
    elevation = math.radians(preset["sunElevationDeg"])
    azimuth = math.radians(preset["sunAzimuthDeg"])
    flat = math.cos(elevation)
    return (
        flat * math.sin(azimuth),
        math.sin(elevation),
        flat * math.cos(azimuth),
    )


def sky_colour_at(preset, direction):
    """The sky in `direction`. Mirrors `SkyPreset.colourAt`."""
    length = math.dist((0.0, 0.0, 0.0), direction)
    if length <= 0.0:
        return list(preset["horizon"])
    y = max(-1.0, min(1.0, direction[1] / length))

    horizon = preset["horizon"]
    other = preset["zenith"] if y >= 0.0 else preset["belowHorizon"]
    t = abs(y)
    t = t * t * (3.0 - 2.0 * t)
    base = [horizon[i] + (other[i] - horizon[i]) * t for i in range(3)]

    to_sun = direction_to_sun(preset)
    towards = sum(direction[i] * to_sun[i] for i in range(3)) / length
    if towards <= 0.0:
        return base
    lobe = preset["glowStrength"] * towards ** preset["glowWide"]
    return [base[i] + preset["sunColor"][i] * lobe for i in range(3)]


def horizon_fog_colour(preset):
    """What distance settles to: the sky at the horizon, across the sun.

    **Deliberately not a field anybody sets.** The reason the far side of the
    circuit does not end in a visible band is that the haze and the sky are the
    same arithmetic, and the only way to keep that true is to make it impossible
    to author them apart. Mirrors `SkyPreset.horizonFogColour`.
    """
    to_sun = direction_to_sun(preset)
    across = (to_sun[2], 0.0, -to_sun[0])
    length = math.dist((0.0, 0.0, 0.0), across)
    if length < 1e-5:
        across = (1.0, 0.0, 0.0)
        length = 1.0
    unit = tuple(component / length for component in across)
    return sky_colour_at(preset, unit)


def ground_reach():
    """Half the width of the ground, in metres, sized by the haze."""
    preset = sky()
    reach = math.log(1.0 / GROUND_FADE) / preset["fogDensity"]
    return round(max(GROUND_MIN, min(GROUND_MAX, reach)), 1)


# Scenery a car can reach is scenery a car will hit, so the pillars stand well
# outside the widest part of the circuit — and inside the ground, or they would
# be posts driven into nothing.
PILLAR_RADIUS = min(BASE_RADIUS + LOBE_TWO + 55.0, ground_reach() - 30.0)


def lights():
    """The one sun, derived from the preset rather than typed out beside it."""
    preset = sky()
    to_sun = direction_to_sun(preset)
    return [
        {
            "type": "directional",
            # Where the light goes, which is away from where the sun is.
            "direction": rounded([-to_sun[0], -to_sun[1], -to_sun[2]]),
            "color": list(preset["sunColor"]),
            "intensity": preset["sunIntensity"],
            "castsShadow": True,
        }
    ]


def main():
    points = centre_line()
    length = lap_length(points)
    entries = build()

    document = {
        "version": 1,
        "name": "ring",
        "generatedBy": "tool/make_track.py",
        "track": {
            "closed": True,
            "shoulder": SHOULDER,
            "points": entries,
            "surfaces": [
                {
                    "fromS": 0.0,
                    "toS": length,
                    "centre": "asphalt",
                    "shoulder": "grass",
                }
            ],
            # Walls down the outside of the two fastest corners, where a car
            # that has run out of road has run out of it at speed.
            "barriers": [
                {
                    "fromS": round(length * 0.08, 2),
                    "toS": round(length * 0.22, 2),
                    "right": True,
                },
                {
                    "fromS": round(length * 0.58, 2),
                    "toS": round(length * 0.72, 2),
                    "right": True,
                },
            ],
            "checkpoints": [
                {"s": round(length * i / LAP_CHECKPOINTS, 2)}
                for i in range(1, LAP_CHECKPOINTS)
            ],
            "grid": {"s": -14.0, "columns": 2, "rowGap": 7.0, "columnGap": 4.0},
        },
        "sky": sky(),
        "level": {
            "version": 1,
            "name": "ring",
            "generatedBy": "tool/make_track.py",
            # Both derived from the sky above, and neither read back by the
            # application: it asks the preset, which knows which way the camera
            # is pointing and can therefore answer something a file cannot.
            # Written anyway so that anything else loading this level alone —
            # an editor, a thumbnail, a test — gets air of the right colour.
            "fogColor": rounded(horizon_fog_colour(sky())),
            "fogDensity": sky()["fogDensity"],
            "materials": MATERIALS,
            "brushes": ground(points),
            "lights": lights(),
            "entities": [],
        },
    }

    TRACKS.mkdir(parents=True, exist_ok=True)
    out = TRACKS / "ring.json"
    out.write_text(json.dumps(document, indent=1) + "\n")

    # And the level on its own, for `LevelLoader` — which reads an asset whose
    # top level *is* a level, and is the shared, tested path from brushes to
    # mesh nodes and uploaded textures. Written from the same object as the
    # section above rather than built twice, so the two cannot disagree about
    # where the ground is.
    level_out = TRACKS / "ring_level.json"
    level_out.write_text(json.dumps(document["level"], indent=1) + "\n")

    widths = [e["width"] for e in entries]
    banks = [abs(e["bank"]) for e in entries]
    print(
        f"{out.name} + {level_out.name}: {len(entries)} points, "
        f"about {length:.0f} m round, "
        f"width {min(widths):.1f}-{max(widths):.1f} m, "
        f"camber up to {max(banks):.1f} degrees, "
        f"{LAP_CHECKPOINTS - 1} checkpoints"
    )


if __name__ == "__main__":
    main()
