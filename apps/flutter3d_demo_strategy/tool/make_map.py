#!/usr/bin/env python3
"""Writes the map this game is played on.

The same rule the other levels keep, for the same reason: **edit this, not the
JSON**. A map is a hillside, two camps, the seams they dig and the line that
ends the match, and those numbers have to agree with each other — a camp placed
off the edge of the field, a seam nobody can reach, a finishing line no seam
holds enough ore to pay for. A person editing eighty-one squared heights by hand
is a person introducing one of those and not noticing.

**Why the map became a document at all.** The hillside used to be a sum of sines
in `lib/src/staging.dart` and the camps were coordinates beside it, which meant
there was nothing for an editor to open, nothing for a snapshot to name, and
nothing a playthrough could point at when it claimed to have won on *this* map.
A `Level` already carries all of it — a heightfield for the ground and entities
for everything standing on it — so the map is one of those rather than a format
this genre invented for itself.

Run: python3 tool/make_map.py
"""

import base64
import math
import struct
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[3] / "tool"))
from leveldoc import dump, rounded  # noqa: E402

LEVELS = Path(__file__).resolve().parent.parent / "assets" / "levels"

# How many samples across the field, and how far apart they stand. Eighty-one
# samples two metres apart is a hundred and sixty metres of hillside, which is
# about as far as this camera can see and about as much ground as a crowd of a
# hundred can fill.
SAMPLES = 81
CELL = 2.0

#: How many camps this map is played by. Side nought is the one the mouse
#: commands and every other side gets a policy, which is a fact about the
#: application rather than about the document — what is written here is only
#: where the camps stand.
SIDES = 2

#: What each camp opens with, and how the block of them is arranged. Ten across
#: at eleven-tenths of a metre leaves nobody starting inside anybody: a worker
#: takes eight-tenths of a metre and the crowd would otherwise spend its first
#: second shoving itself apart.
WORKERS = 60
ACROSS = 10
SPACING = 1.1

#: What a seam holds, and how much a side must bring home to win. The two are
#: related and the relation is the match: sixteen hundred in each seam against a
#: line at twelve hundred means a side that digs its own seam out still has to
#: have done it faster than the other, and neither can win by sitting still.
SEAM = 1600.0
GOAL = 1200.0


def heights():
    """The ground: two ridges and a valley between them, quantised.

    **Quantised to the centimetre, and that is what makes this file the same
    file on every machine.** The `levels` step of `tool/ci.sh` regenerates every
    document and diffs it, and `math.sin` is the platform's libm — two machines
    agreeing to the last bit is a courtesy, not a promise. `make_track.py`
    rounds its lap length for exactly this reason and `tool/make_models.py`
    quantises its coordinates for it; a centimetre is four hundred times finer
    than the two-metre spacing of the samples themselves and a hundredth of what
    the shallowest ridge here rises, so nothing in the picture can tell.

    The amplitudes are chosen by looking at it: ten metres over a hundred and
    sixty reads as one tilted plane under a camera fifty degrees off the horizon,
    because nothing is nearer than anything else by enough to see. These ridges
    are steep enough to hide a crowd behind and gentle enough to walk over — the
    navigation bake refuses forty degrees and the steepest here is about
    twenty-five.
    """
    field = []
    for row in range(SAMPLES):
        for column in range(SAMPLES):
            x = column / (SAMPLES - 1)
            z = row / (SAMPLES - 1)
            field.append(round(
                math.sin(x * math.pi * 2.0) * 9.0
                + math.sin(z * math.pi * 3.0 + 1.0) * 6.0
                + math.sin((x + z) * math.pi * 5.0) * 1.5
                + 14.0, 2))
    return field


def height_at(field, x, z):
    """The ground under a world position that sits on a sample.

    Everything this map places stands on an even coordinate, which at a
    two-metre spacing is a sample exactly — so this looks one up rather than
    interpolating, and refuses anything else rather than quietly returning the
    corner of the cell. A camp written half a metre off its sample would load
    at a height the game then corrects, and the document would disagree with
    the picture for ever after.
    """
    column, across = divmod(x, CELL)
    row, down = divmod(z, CELL)
    if across or down:
        raise SystemExit(
            f"({x}, {z}) is not on a sample, and this map places nothing "
            f"between them")
    return field[int(row) * SAMPLES + int(column)]


def packed(field):
    """The heights as the document carries them: base64 of little-endian f32.

    `Heightfield.fromJson` takes the bytes as a `Float32List` view, which is
    host order — every target this repository builds for is little-endian, and
    the day one is not, this line is where it is answered rather than wherever
    the ground came out inside a mountain.
    """
    return base64.b64encode(
        b"".join(struct.pack("<f", h) for h in field)).decode("ascii")


def camps(field):
    """Where each side opens, and what stands there.

    Spread along the hillside's diagonal, from its near corner to its far one.
    Not mirrored: the ground is a sum of sines and the camps stand on different
    parts of it, which is fair enough for a demo and would not be for a test —
    the tests that care use flat ground and a translation.
    """
    for side in range(SIDES):
        along = 0.0 if SIDES == 1 else side / (SIDES - 1)
        home = (36.0 + along * 88.0, 36.0 + along * 88.0)
        # The seam sits thirty-six metres from the hall towards the middle of
        # the map, so that no camp is asked to dig off the edge of the ground.
        depth = (SAMPLES - 1) * CELL
        seam = (home[0], home[1] + (36.0 if home[1] < depth / 2.0 else -36.0))
        yield side, home, seam


def entities(field):
    """Everything standing on the ground, in the order a side is assembled.

    One entity per thing the simulation is told about, and the names are how
    they find each other: a producer names the hall it builds from, a block of
    workers names both the seam it digs and the hall it carries to. That is the
    format's own way of pointing — `LevelValidator` refuses a name that resolves
    to nothing — rather than a side number the reader would have to match up.
    """
    out = []
    for side, home, seam in camps(field):
        # The near side's hall is `hall` and the others are `their hall`, which
        # is the wording the game already shows when the cursor is over one.
        hall = "hall" if side == 0 else "their hall"
        deposit = "seam" if side == 0 else "their seam"
        block = (home[0] - 12.0, home[1] + 8.0)

        out.append({
            "type": "camp", "at": rounded(
                [home[0], height_at(field, *home), home[1]]),
            "name": hall, "side": side, "width": 12.0, "depth": 10.0,
        })
        out.append({
            "type": "resource_node", "at": rounded(
                [seam[0], height_at(field, *seam), seam[1]]),
            "name": deposit, "amount": SEAM,
        })
        # What turns a stockpile back into workers. Written with its price and
        # its pace rather than leaning on the simulation's defaults, because
        # the economy is the whole of this match and the document is where a
        # person tuning it would look first.
        out.append({
            "type": "producer", "at": rounded(
                [home[0], height_at(field, *home), home[1]]),
            "target": hall, "cost": 25.0, "seconds": 4.0,
        })
        # The purse each side spends from, which opens empty: every unit after
        # the first sixty is paid for out of what this side has dug.
        out.append({
            "type": "stockpile", "at": rounded(
                [home[0], height_at(field, *home), home[1]]),
            "side": side, "amount": 0.0,
        })
        # A block beside the hall. One entity for the block rather than sixty
        # for the workers: what varies is how many stand there, and a document
        # with a hundred and twenty near-identical entries in it is a document
        # whose diff nobody reads.
        out.append({
            "type": "worker", "at": rounded(
                [block[0], height_at(field, *block), block[1]]),
            "side": side, "count": WORKERS, "across": ACROSS,
            "spacing": SPACING, "digs": deposit, "home": hall,
        })
    return out


def bedrock(field):
    """The block the hillside is cut from.

    **The field is the surface; this is what the format calls geometry.** A
    level with no brushes has nothing to stand on, which is true of every level
    written before ground was a grid of samples and is why the validator says
    so. Rather than teach the validator about terrain, the map writes the rock
    the terrain sits on: its top is the lowest sample of the field, so a body
    that fell through the surface would meet it instead of falling for ever.
    """
    reach = (SAMPLES - 1) * CELL
    floor = min(field)
    return {
        "at": [reach / 2.0, round(floor - 2.0, 2), reach / 2.0],
        "size": [reach, 4.0, reach],
        "material": "rock",
    }


def main():
    field = heights()
    document = {
        "version": 1,
        "name": "Map A",
        "generatedBy": "tool/make_map.py",
        # Where the match ends. Not an entity, because it is not anywhere: it
        # is how much a side has to have brought home, and the format carries a
        # section it does not know rather than losing it — see `writeThrough`.
        "goal": {"delivered": GOAL},
        "materials": {
            "rock": {"baseColor": [0.31, 0.29, 0.26, 1.0], "roughness": 0.95},
        },
        "brushes": [bedrock(field)],
        # The sun the game already draws, written down so that anything else
        # opening this document — an editor, a thumbnail — lights it the same
        # way rather than inventing its own noon.
        "lights": [{
            "type": "directional",
            "direction": rounded([0.35, -1.0, 0.5]),
            "color": [1.0, 0.96, 0.88],
            "intensity": 3.2,
            "name": "sun",
        }],
        "entities": entities(field),
        # Last, because it is thirty-five thousand characters of base64 and
        # everything above it is what a person came here to read.
        "heightfield": {
            "columns": SAMPLES,
            "rows": SAMPLES,
            "cellSize": CELL,
            "heights": packed(field),
        },
    }

    LEVELS.mkdir(parents=True, exist_ok=True)
    out = LEVELS / "map_a.json"
    out.write_text(dump(document, 0) + "\n")
    print(f"{out.name}: {SAMPLES}x{SAMPLES} samples "
          f"{min(field):.2f}-{max(field):.2f} m, "
          f"{len(document['entities'])} entities, "
          f"{SIDES} sides of {WORKERS} workers, "
          f"{SEAM:.0f} in each seam against a line at {GOAL:.0f}")


if __name__ == "__main__":
    main()
