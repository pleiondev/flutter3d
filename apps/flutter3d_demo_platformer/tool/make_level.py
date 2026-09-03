#!/usr/bin/env python3
"""Writes `assets/levels/ascent.json` — the second level, and the big one.

    python3 tool/make_level.py

The field is a hundred and twenty metres by two hundred and sixty-four. A level
that size, hand-authored in JSON, is a level with nine coins standing in an
empty field — which is what the first two drafts of this one were, and what
playing it looked like. Filling it by hand is four hundred brushes of typing
that nobody will ever re-indent; filling it with a program is the arrangement
written down as an arrangement.

Two kinds of thing go into it, and the difference matters:

  * **route** — everything the player's way through is made of, and everything
    the tests name: both gates and their plates, the keys, the barges, the
    ferry, the lifts, the springs, the checkpoints, the maze, the vault, the
    summit stair. Written out one by one, with the coordinates that make them
    work, because a set piece a program placed is a set piece nobody checked.
  * **fill** — the huts, pillars, walkways, ledges, crates and coins in between.
    Placed in loops, and never allowed to touch the route: `KEEP_CLEAR` lists
    the ground the route needs and `_fill` refuses to put a brush on it.

Sizes are chosen against what the runner can actually do, measured rather than
assumed — see `_doubleJumpHeight` in `test/playthrough_test.dart`. As of writing
the runner walks at 6 m/s, jumps 1.8 m, double-jumps 3.13 m and clears about
7.5 m of gap.

The vocabulary — brushes, coins, movers, keys, gates, the writer — lives in
`levelkit.py`, which every one of the five generators shares.
"""

from levelkit import *  # noqa: F403
import levelkit

# Footprints the generated filling may not stand on: the walked line out of the
# spawn, the shaft, the canyon crossing, both gates, the maze, the ice, the
# summit stair, the yard, and the patch of grass one test shoves a crate across.
KEEP_CLEAR = [
    (-3.0, 3.0, -25.0, 26.0),
    (-5.0, 5.0, 29.0, 51.0),
    (-5.0, 5.0, 51.0, 72.0),
    (-4.0, 4.0, 72.0, 84.0),
    (-28.0, 28.0, 83.0, 121.0),
    (-6.0, 6.0, 121.0, 170.0),
    (-14.0, 14.0, 188.0, 233.0),
    (-52.0, -24.0, -24.0, 4.0),
    (4.0, 11.0, -9.0, -1.0),
    (25.0, 39.0, 1.0, 20.0),
    (-45.0, -31.0, 70.0, 82.0),
]

levelkit.start(KEEP_CLEAR)

# ---------------------------------------------------------------- zone one ---
# The yard: moss, a walled crate puzzle, a village, and a lot of grass that used
# to be nothing but grass.

route([0.0, -0.5, -2.5], [120.0, 1.0, 55.0], "moss")
route([0.0, -0.5, 42.5], [120.0, 1.0, 27.0], "stone")
route([0.0, -0.5, 69.5], [120.0, 1.0, 3.0], "stone")
route([0.0, -0.5, 96.0], [120.0, 1.0, 50.0], "wood")
route([0.0, -0.5, 124.5], [120.0, 1.0, 7.0], "ice", surface="ice")
route([0.0, -0.5, 156.5], [120.0, 1.0, 21.0], "ice", surface="ice")
route([0.0, -0.5, 200.0], [120.0, 1.0, 66.0], "stone")

route([-60.5, 4.0, 105.0], [1.0, 8.0, 274.0], "stone")
route([60.5, 4.0, 105.0], [1.0, 8.0, 274.0], "stone")
route([0.0, 4.0, -30.5], [122.0, 8.0, 1.0], "stone")
route([0.0, 4.0, 233.5], [122.0, 8.0, 1.0], "stone")

spawn([0.0, 0.0, -22.0])
coin([0.0, 0.8, -16.0], "coin one")
coin([-3.0, 0.8, -11.0], "coin two")
coin([3.0, 0.8, -11.0], "coin three")
crate([7.0, 0.0, -4.0], "the crate")
crate([8.8, 0.0, -4.0], "the other crate")

# The walled yard, and the vault above it. The ledge is 4.2: over a double jump
# and under a crate plus a double jump, which is the whole puzzle.
route([-50.5, 2.3, -10.0], [1.0, 4.6, 25.0], "stone")
route([-38.5, 2.3, 2.5], [25.0, 4.6, 1.0], "stone")
route([-38.5, 2.3, -22.5], [25.0, 4.6, 1.0], "stone")
route([-25.5, 2.3, -19.25], [1.0, 4.6, 6.5], "stone")
route([-25.5, 2.3, -4.75], [1.0, 4.6, 14.5], "stone")
route([-46.0, 2.1, -10.0], [8.0, 4.2, 25.0], "stone")
route([-33.0, 2.3, -14.75], [1.0, 4.6, 15.5], "wood")
route([-37.0, 2.3, -0.75], [1.0, 4.6, 6.5], "wood")

crate([-29.0, 0.0, -19.0], "the yard crate")
crate([-31.0, 0.0, -19.0], "the second yard crate")
crate([-30.0, 0.0, -21.0], "the spare yard crate")
coin([-29.0, 0.8, -13.0], "yard coin one")
coin([-35.0, 0.8, -6.0], "yard coin two")
coin([-40.0, 0.8, -12.0], "yard coin three")
for i, z in enumerate((-18.0, -14.0, -6.0, -2.0)):
    coin([-46.0, 5.0, z], f"vault coin {i + 1}")
key("the green key", [-46.0, 5.2, -10.0], "green")

# The east plateau, with its own stair up.
route([-30.0, 2.0, 18.0], [12.0, 4.0, 12.0], "stone")
route([32.0, 3.0, 8.0], [12.0, 6.0, 12.0], "stone")
route([32.0, 1.0, 16.5], [8.0, 2.0, 5.0], "stone")
# **A way up the plateau that is walked rather than jumped.** Six metres over
# twelve is twenty-seven degrees, up the western face, and it is additive: the
# spring, the gantry and the two-metre step from the north are all still there.
# A plateau reachable four ways is a plateau, and one reachable only by jumping
# is a puzzle nobody set.
#
# **The first placement of this hung in mid-air** — put against the northern
# face, its foot landed at z = 26, and the ground ends at z = 25 where the drop
# begins. Nothing complained: a ramp whose bottom is over a hole is a perfectly
# valid brush. The western field is solid for sixty metres.
slope([20.0, 3.0, 5.0], [12.0, 6.0, 6.0], "stone", "+x")
route([-8.0, 0.9, 22.0], [3.0, 0.4, 2.4], "brass")
route([8.0, 0.9, 22.0], [3.0, 0.4, 2.4], "brass")
coin([32.0, 6.8, 4.0], "plateau coin one")
coin([28.0, 6.8, 8.0], "plateau coin two")
coin([36.0, 6.8, 8.0], "plateau coin three")
spring("the high pad", [32.0, 6.2, 11.0])
coin([32.0, 11.0, 11.0], "plateau coin four")
spring("the first pad", [-30.0, 4.2, 18.0], speed=16.0)
coin([-30.0, 10.0, 18.0], "high coin")

checkpoint("the brink", 20.0, 1, respawn=18.0)
coin([0.0, 2.0, 24.0], "arc coin one")
coin([0.0, 3.0, 27.0], "arc coin two")
coin([0.0, 2.0, 30.0], "arc coin three")
hazard("the first drop", [0.0, -4.0, 27.0], [122.0, 6.0, 4.0], instant=True)
checkpoint("past the drop", 33.0, 2, respawn=34.0)

# The village: twelve huts with a coin on every roof and planks between them,
# because a roof you cannot get to is a roof with a coin nobody will ever have.
for row_i, z in enumerate((-26.0, -18.0, -10.0)):
    heights = (3.0, 5.6, 4.2, 6.4) if row_i % 2 == 0 else (5.2, 3.4, 6.0, 4.4)
    xs = (24.0, 33.0, 42.0, 51.0)
    for x, h in zip(xs, heights):
        hut(x, z, h)
    for i in range(3):
        low = min(heights[i], heights[i + 1])
        plank((xs[i] + xs[i + 1]) / 2, z, True, 9.0 - 7.0 + 2.0, low)
for x in (24.0, 33.0, 42.0, 51.0):
    crate([x, 0.0, -22.0])

# Stepping stones out to the eastern corner.
for i, x in enumerate((42.0, 48.0, 54.0)):
    for j, z in enumerate((2.0, 8.0, 14.0, 20.0)):
        pillar(x, z, 1.0 + ((i + j) % 4) * 0.8, width=3.0, top_coin=(i + j) % 2 == 0)

# The western colonnade, along the wall.
for i in range(7):
    z = -26.0 + i * 8.0
    # **The cap goes on, then the coin goes on the cap.** Asking `pillar` for a
    # top coin and then roofing the pillar put the coin inside the roof: at
    # 5.8 against a cap spanning 5.3 to 5.9. Four coins nobody could ever take,
    # and they looked exactly like four coins nobody had taken yet.
    capped = i % 2 == 0
    pillar(-57.0, z, 5.0, width=2.6, top_coin=not capped)
    if capped:
        fill([-57.0, 5.6, z], [4.0, 0.6, 4.0], "wood")
        coin([-57.0, 6.7, z])

# The training ground, west of the walked line: a grid of stumps to hop across.
for i, x in enumerate((-22.0, -17.0, -12.0, -7.0)):
    for j, z in enumerate((-26.0, -20.0, -14.0, -8.0)):
        pillar(x, z, 0.8 + ((i * 3 + j) % 5) * 0.6, width=3.2,
               top_coin=(i + j) % 2 == 0)

# The ruin: two arches, a spike pit and a pad to clear it with.
for x in (13.0, 19.0):
    fill([x, 3.0, -26.0], [1.6, 6.0, 1.6], "stone")
    fill([x, 3.0, -18.0], [1.6, 6.0, 1.6], "stone")
fill([16.0, 6.3, -26.0], [8.0, 0.6, 1.6], "stone")
fill([16.0, 6.3, -18.0], [8.0, 0.6, 1.6], "stone")
coin([16.0, 7.4, -26.0])
coin([16.0, 7.4, -18.0])
hazard("the ruin spikes", [16.0, 0.4, -22.0], [8.0, 0.8, 5.0], damage=35.0)
spring("the ruin pad", [16.0, 0.2, -13.0], speed=14.0)
coin([16.0, 5.0, -13.0])

# The yard of surfaces: where a player meets a floor that behaves, early and
# where falling off costs nothing. Three lessons, in the order a level teaches
# them — a platform you pass through, a floor that slides, a floor that carries.
#
# East of the walked line and south of the plateau's stair, so none of it is on
# the route: the whole point is that a player who never comes here can still
# finish the level.
for i, y in enumerate((1.6, 3.0, 4.4)):
    oneway(f"the gantry {i + 1}", [14.0 + i * 1.5, y, 10.0], size=(6.0, 0.3, 6.0))
    coin([14.0 + i * 1.5, y + 1.0, 10.0])
# Under the lowest one, so the only way out is down through it.
coin([14.0, 0.8, 10.0])

# A rink, and a kerb at the far end so a player who overshoots stops rather
# than skates into the plateau's stair.
fill([-14.0, 0.05, 8.0], [16.0, 0.1, 16.0], "ice", surface="ice")
fill([-14.0, 1.0, 16.5], [16.0, 2.0, 1.0], "stone")
coin([-18.0, 0.9, 12.0])
coin([-10.0, 0.9, 12.0])

# The belts run north, in the clear strip between the yard's north wall and the
# plateau. The first draft put them at x = -30, which is *inside* the walled
# yard — entities do not go through `KEEP_CLEAR`, so nothing complained and the
# belt delivered its passenger into a fence.
conveyor("the first belt", [-44.0, 0.2, 13.0], [0.0, 0.0, 5.0], size=(4.0, 0.4, 14.0))
conveyor("the second belt", [-39.0, 0.2, 13.0], [0.0, 0.0, -5.0], size=(4.0, 0.4, 14.0))
coin([-44.0, 0.9, 19.0])
coin([-39.0, 0.9, 7.0])

# A crawlspace, and the only way to the coin behind it is on your belly. The
# slot is one metre: a standing runner is 1.8 and a crouched one 0.9.
# At z = 14 rather than 21: the brass pads by the brink stand at 20.8, they are
# waist-high, and a crawl that ends in one is a crawl nobody finishes.
fill([7.0, 2.0, 14.0], [7.0, 1.9, 7.0], "stone")
coin([7.0, 0.6, 14.0])
coin([7.0, 3.9, 14.0])

# The first thing in the level that walks. On the moss, in the open, where a
# player meets one before anything else can go wrong — and a coin on the far
# side of it, so meeting one is worth something.
# A third of walking pace: a guard that moves as fast as the player is a
# guard you cannot get round, and the first one a player meets should be
# something to learn on.
enemy("the first guard", [-10.0, 0.0, -4.0], [[-10.0, 0.0, -20.0]], speed=0.32)
coin([-10.0, 0.8, -22.0])
enemy("the second guard", [30.0, 0.0, -6.0], [[44.0, 0.0, -6.0]], speed=0.42)

# The north strip: broken walls with coins behind them.
for i in range(6):
    x = -54.0 + i * 8.0
    fill([x, 1.2, 16.0], [6.0, 2.4, 1.0], "stone")
    # One of the six lands on the hut at (-30, 18): a loop that steps blindly
    # across a field will eventually step inside something standing in it.
    if abs(x - -30.0) > 0.5:
        coin([x, 0.8, 18.5])

# ---------------------------------------------------------------- zone two ---
# The shaft, the quarry, the scaffold and the canyon.

route([-3.5, 6.0, 44.0], [1.0, 12.0, 10.0], "stone")
route([3.5, 6.0, 44.0], [1.0, 12.0, 10.0], "stone")
route([0.0, 4.0, 48.5], [8.0, 8.0, 1.0], "stone")
route([-7.0, 4.0, 44.0], [6.0, 8.0, 10.0], "stone")
route([7.0, 4.0, 44.0], [6.0, 8.0, 10.0], "stone")
coin([0.0, 3.0, 44.0], "the shaft coin")
coin([0.0, 6.0, 42.0], "the second shaft coin")
coin([0.0, 9.0, 42.0], "the third shaft coin")
key("the blue key", [0.0, 9.0, 46.0], "blue")

checkpoint("the canyon rim", 53.0, 3, respawn=52.0)
hazard("the gulf", [0.0, -4.0, 62.0], [122.0, 6.0, 12.0], instant=True)
mover("platform", "the first barge", [-8.0, 1.0, 58.0], [5.0, 0.6, 5.0],
      [16.0, 0.0, 0.0], 3.5, 1.2)
mover("platform", "the second barge", [8.0, 1.0, 62.0], [5.0, 0.6, 5.0],
      [-16.0, 0.0, 0.0], 3.5, 1.2, phase=2.5)
mover("platform", "the third barge", [-8.0, 1.0, 66.0], [5.0, 0.6, 5.0],
      [16.0, 0.0, 0.0], 3.5, 1.2, phase=5.0)
coin([0.0, 3.0, 58.0], "canyon coin one")
coin([0.0, 3.0, 62.0], "canyon coin two")
coin([0.0, 3.0, 66.0], "canyon coin three")

# Two more ways across, so the canyon is a canyon rather than a doorway.
for side, x in (("west", -30.0), ("east", 30.0)):
    mover("platform", f"the {side} ferry", [x, 1.0, 59.0], [4.5, 0.6, 4.5],
          [0.0, 0.0, 8.0], 3.0, 1.2, phase=1.5)
    mover("platform", f"the {side} skiff", [x, 1.0, 67.0], [4.5, 0.6, 4.5],
          [8.0 if x < 0 else -8.0, 0.0, 0.0], 3.0, 1.0, phase=3.0)
    coin([x, 2.6, 59.0])
    coin([x, 2.6, 67.0])
    # Columns out of the depths, tall enough to stand on and no taller.
    for z in (60.0, 64.0):
        fill([x + 10.0, -2.0, z], [3.0, 6.0, 3.0], "stone")
        coin([x + 10.0, 1.8, z])

# The quarry: terraces stepping up, with crates and a pad at the top.
for i in range(6):
    x = -54.0 + i * 8.0
    h = 1.2 + i * 0.9
    fill([x, h / 2, 40.0], [7.0, h, 18.0], "stone")
    coin([x, h + 0.8, 36.0])
    coin([x, h + 0.8, 44.0])
for x in (-52.0, -44.0, -36.0):
    crate([x, 0.0, 31.0])
spring("the quarry pad", [-14.0, 6.0, 40.0], speed=16.0)
fill([-14.0, 2.9, 40.0], [5.0, 5.8, 5.0], "stone")
coin([-14.0, 12.0, 40.0])

# The scaffold: platforms at three heights with movers between them.
for i, x in enumerate((16.0, 28.0, 40.0, 52.0)):
    for j, z in enumerate((34.0, 44.0, 52.0)):
        h = 2.0 + ((i + j) % 3) * 2.0
        fill([x, h - 0.3, z], [7.0, 0.6, 7.0], "wood")
        fill([x, (h - 0.6) / 2, z], [1.0, h - 0.6, 1.0], "stone")
        coin([x, h + 0.8, z])
mover("platform", "the scaffold hoist", [22.0, 2.0, 48.0], [4.0, 0.6, 4.0],
      [0.0, 4.0, 0.0], 2.0, 1.5)
mover("platform", "the scaffold shuttle", [46.0, 3.0, 39.0], [4.0, 0.6, 4.0],
      [0.0, 0.0, 10.0], 2.5, 1.0, phase=1.0)

# -------------------------------------------------------------- zone three ---
# The forecourt, the maze, and two wings of filling either side of it.

route([-40.0, 3.5, 76.0], [8.0, 7.0, 8.0], "wood")
route([-31.0, 4.0, 80.0], [58.0, 8.0, 2.0], "wood")
route([31.0, 4.0, 80.0], [58.0, 8.0, 2.0], "wood")
checkpoint("the forecourt", 72.0, 4, respawn=73.0)
mover("lift", "the tower lift", [-34.0, 0.3, 76.0], [4.0, 0.6, 4.0],
      [0.0, 7.0, 0.0], 2.0, 4.0)
plate("the lift plate", "the tower lift", [-34.0, 1.6, 76.0])
coin([-42.0, 7.8, 74.0], "tower coin one")
coin([-38.0, 7.8, 74.0], "tower coin two")
coin([-42.0, 7.8, 78.0], "tower coin three")
coin([-38.0, 7.8, 78.0], "tower coin four")

gate("the blue gate", [0.0, 2.5, 80.0], "blue")
plate("the blue gate's plate", "the blue gate", [0.0, 1.6, 77.0],
      size=(6.0, 3.0, 3.0))

# The maze. Five metres tall, which is over a double jump and under the walls of
# a room; a maze a player can hop out of is scenery.
route([-27.5, 2.5, 102.0], [1.0, 5.0, 37.0], "stone")
route([27.5, 2.5, 102.0], [1.0, 5.0, 37.0], "stone")
for z in (83.5, 114.0, 120.5):
    route([-15.25, 2.5, z], [24.5, 5.0, 1.0], "stone")
    route([15.25, 2.5, z], [24.5, 5.0, 1.0], "stone")
for z, x in ((90.0, -3.0), (96.0, 3.0), (102.0, -3.0), (108.0, 3.0)):
    route([x, 2.5, z], [49.0, 5.0, 1.0], "stone")
# Stubs inside the rows: without them a serpentine is a corridor with a bend.
for z, x in ((87.0, 8.0), (93.0, -8.0), (99.0, 8.0), (105.0, -8.0), (111.0, 14.0)):
    route([x, 2.5, z], [1.0, 5.0, 3.6], "stone")
# Lamps down the maze, which is five hundred metres of corridor between
# walls with nothing to look at.
for i, (x, z) in enumerate((
    (-24.0, 87.0), (24.0, 87.0), (-24.0, 99.0), (24.0, 99.0),
    (-24.0, 111.0), (24.0, 111.0), (0.0, 93.0), (0.0, 105.0), (0.0, 117.0),
)):
    lamp(f"the maze lamp {i + 1}", [x, 2.2, z])

for i, (x, z) in enumerate((
    (-24.0, 87.0), (-18.0, 87.0), (12.0, 87.0), (24.0, 93.0), (18.0, 93.0),
    (-24.0, 99.0), (-18.0, 99.0), (24.0, 105.0), (18.0, 105.0),
    (-24.0, 111.0), (24.0, 111.0), (-24.0, 117.0), (24.0, 117.0),
)):
    coin([x, 0.8, z], f"maze coin {i + 1}")

gate("the green gate", [0.0, 2.5, 120.5], "green", size=(6.0, 5.0, 2.0))
plate("the green gate's plate", "the green gate", [0.0, 1.6, 118.0],
      size=(6.0, 3.0, 3.0))

# The forecourt filling: pillars, crates and a second tower with its own lift.
for i, x in enumerate((-54.0, -22.0, -12.0, 12.0, 22.0, 54.0)):
    pillar(x, 74.0, 4.0 + (i % 3), width=3.0)
    crate([x + 4.0 if x < 0 else x - 4.0, 0.0, 74.0])
fill([40.0, 3.5, 76.0], [8.0, 7.0, 8.0], "wood")
mover("lift", "the east lift", [34.0, 0.3, 76.0], [4.0, 0.6, 4.0],
      [0.0, 7.0, 0.0], 2.0, 4.0)
plate("the east plate", "the east lift", [34.0, 1.6, 76.0])
for dx in (-2.0, 2.0):
    for dz in (-2.0, 2.0):
        coin([40.0 + dx, 7.8, 76.0 + dz])

# A leaper on the forecourt: it jumps the gaps in its own route, which is what
# separates it from the guards on the moss.
enemy("the leaper", [-16.0, 0.0, 74.0], [[8.0, 0.0, 74.0]], kind="leaper",
      speed=0.45)

# A saw on an arm, which is a hazard riding a mover — the two have existed
# separately since the engine had either.
mover("platform", "the saw arm", [20.0, 3.4, 76.0], [2.0, 0.4, 2.0],
      [0.0, 0.0, 9.0], 3.5, 0.6)
hazard("the saw", [20.0, 4.4, 76.0], [1.8, 1.8, 1.8], damage=55.0)
entities[-1]["follows"] = "the saw arm"
# Above the plank at y = 4 ± 4, not inside it. A coin beside a moving saw is
# meant to be the reason to time the jump, and it was in the walkway.
coin([20.0, 8.8, 80.0])

# A ladder to the gallery, and a rope over the drop beside it.
climbable("the gallery ladder", [48.0, 4.0, 88.0], size=(1.2, 8.0, 1.2))
coin([48.0, 8.8, 88.0])
climbable("the rope", [52.0, 6.0, 104.0], size=(1.0, 10.0, 1.0),
          swing=3.5, period=2.6)
coin([56.0, 10.0, 104.0])

# The warehouse, west of the maze: twelve crates in a yard, sheds, a gantry.
for i in range(4):
    for j in range(3):
        crate([-54.0 + i * 4.0, 0.0, 90.0 + j * 5.0])
for j, z in enumerate((86.0, 98.0, 110.0)):
    fill([-36.0, 2.5, z], [8.0, 5.0, 8.0], "stone")
    coin([-36.0, 6.3, z])
fill([-45.0, 5.0, 104.0], [22.0, 0.6, 4.0], "wood")
for i in range(5):
    coin([-54.0 + i * 4.5, 6.0, 104.0])
for i in range(3):
    h = 1.4 + i * 1.4
    fill([-33.0, h / 2, 116.0 - i * 4.0], [5.0, h, 4.0], "stone")

# The east gallery: a stair to a walkway along the maze's outer wall.
for i in range(5):
    h = 1.6 + i * 1.4
    fill([32.0, h / 2, 86.0 + i * 7.0], [6.0, h, 6.0], "stone")
    coin([32.0, h + 0.8, 86.0 + i * 7.0])
fill([42.0, 8.0, 102.0], [4.0, 0.6, 36.0], "wood")
for i in range(6):
    coin([42.0, 9.2, 86.0 + i * 6.0])
for i in range(4):
    pillar(52.0, 88.0 + i * 9.0, 3.0 + i * 1.2, width=3.4)

# --------------------------------------------------------------- zone four ---
# The ice: a crevasse with five ways across and a field of spikes beyond it.

checkpoint("the cold", 124.0, 5)
hazard("the crevasse", [0.0, -4.0, 137.0], [122.0, 6.0, 18.0], instant=True)
mover("platform", "the ferry", [0.0, 1.0, 131.0], [5.0, 0.6, 5.0],
      [0.0, 0.0, 13.0], 3.0, 1.5)
mover("platform", "the west floe", [-14.0, 1.0, 134.0], [4.0, 0.6, 4.0],
      [0.0, 0.0, 8.0], 2.5, 1.0, phase=1.0)
mover("platform", "the east floe", [14.0, 1.0, 142.0], [4.0, 0.6, 4.0],
      [0.0, 0.0, -8.0], 2.5, 1.0, phase=3.0)
coin([-14.0, 2.6, 134.0], "floe coin one")
coin([-14.0, 2.6, 142.0], "floe coin two")
coin([14.0, 2.6, 134.0], "floe coin three")
coin([14.0, 2.6, 142.0], "floe coin four")
for side, x in (("far west", -34.0), ("far east", 34.0)):
    mover("platform", f"the {side} floe", [x, 1.0, 132.0], [4.5, 0.6, 4.5],
          [0.0, 0.0, 10.0], 2.5, 1.2, phase=2.0)
    coin([x, 2.6, 132.0])
    fill([x + 8.0, -2.0, 137.0], [3.4, 6.4, 3.4], "ice")
    coin([x + 8.0, 2.0, 137.0])

# A bridge of shelves across the crevasse, for a player who would rather not
# wait for the ferry. Each one holds for less than half a second.
for i, z in enumerate((129.0, 133.0, 137.0, 141.0, 145.0)):
    crumbling(f"the shelf {i + 1}", [-24.0, 0.8, z])
coin([-24.0, 1.8, 137.0])

# **The staircase to the cold pad, and its first step used to be unclimbable.**
# It was two steps, tops at 3.6 and 6.0. A double jump rises 3.13 — measured in
# `ascent_route_test.dart` rather than guessed — so the first step was half a
# metre above anything that could reach it, and the spring on top of the second
# one, with the coin above that, could only be got to by pushing a crate ten
# metres and standing on it.
#
# Three steps now, and every climb has margin: 2.0 off the ice, then 2.2, then
# 1.8.
route([0.0, 1.0, 144.5], [12.0, 2.0, 3.0], "ice")
route([0.0, 2.1, 148.0], [12.0, 4.2, 3.0], "ice")
route([0.0, 3.0, 152.0], [12.0, 6.0, 4.0], "ice")
route([-22.0, 1.5, 162.0], [12.0, 3.0, 8.0], "ice")
route([22.0, 1.5, 162.0], [12.0, 3.0, 8.0], "ice")
hazard("the spikes", [-9.0, 0.4, 150.0], [10.0, 0.8, 8.0])
hazard("more spikes", [9.0, 0.4, 158.0], [10.0, 0.8, 8.0])
hazard("the far spikes", [-30.0, 0.4, 154.0], [14.0, 0.8, 8.0], damage=35.0)
hazard("the eastern spikes", [30.0, 0.4, 154.0], [14.0, 0.8, 8.0], damage=35.0)
spring("the cold pad", [0.0, 6.2, 152.0], speed=17.0)
coin([0.0, 12.5, 156.0], "the cold coin")
coin([-22.0, 3.8, 162.0], "ice coin one")
coin([22.0, 3.8, 162.0], "ice coin two")

# The near shore, and the ridges beyond the spikes.
for i in range(7):
    x = -48.0 + i * 16.0
    if abs(x) < 8.0:
        continue
    pillar(x, 123.5, 1.4 + (i % 3) * 0.9, width=4.0, material="ice")
for x in (-46.0, -26.0, 26.0, 46.0):
    fill([x, 1.5, 150.0], [10.0, 3.0, 1.2], "ice")
    fill([x, 1.5, 158.0], [10.0, 3.0, 1.2], "ice")
    coin([x, 4.2, 150.0])
    coin([x, 4.2, 158.0])
for x in (-44.0, 44.0):
    spring(f"the floe pad {'west' if x < 0 else 'east'}", [x, 0.2, 164.0], speed=15.0)
    coin([x, 5.5, 164.0])
for x in (-16.0, 16.0):
    crate([x, 0.0, 148.0])
    crate([x, 0.0, 160.0])

# --------------------------------------------------------------- zone five ---
# The summit: a colonnade, two ziggurats, the stair, and a ring of coins on top.

checkpoint("past the ice", 170.0, 6)

# ------------------------------------------------- the gate of two skills ---
# **The summit is earned with the two verbs this level never asked for.** The
# wall jump and the dash were paid for in the engine, taught in `first_steps`,
# and then Ascent wanted neither of them for two hundred and sixty metres — so a
# player learned two moves in the tutorial and never used them again.
#
# A corridor, because the field is sixty metres wide and anything not fenced is
# something you walk around. The fences cast no shadow: see `Brush.castsShadow`.
for x in (-13.0, 13.0):
    route([x, 5.0, 181.0], [2.0, 12.0, 28.0], "stone", casts=False)

# The chimney. **Two metres**, and that number is measured rather than chosen:
# the runner's wall probe reaches fourteen centimetres, so a slot much wider is
# one it falls down the middle of. Four metres was tried in `first_steps` and
# the autopilot sat at the bottom of it.
for x in (-6.5, 6.5):
    route([x, 3.5, 180.0], [11.0, 7.0, 8.0], "stone")
route([0.0, 3.5, 184.5], [2.0, 7.0, 1.0], "stone")
coin([0.0, 2.0, 180.0], "the chimney coin one")
coin([0.0, 5.0, 180.0], "the chimney coin two")

# And the dash, from the top of the chimney. Nine metres against a double jump
# that clears seven and a half — shown first by a coin out over solid ground, so
# the move is worth trying before it is needed.
coin([0.0, 8.2, 186.0], "the dash coin")
# **Measured from the chimney's closing wall, not from the blocks.** The first
# version put the landing at z = 195 and called the gap nine metres; the wall
# that seals the top of the slot ends at 185, so the gap was seven — which a
# double jump clears, and the set piece asked for nothing.
route([0.0, 6.5, 197.5], [24.0, 1.0, 6.0], "stone")
coin([0.0, 8.5, 190.0], "the coin over the gap")

# **Nothing under the gap, and that is deliberate.** The ground runs the whole
# length of this end of the level, so a miss drops you onto it and costs the
# climb again — which is the right price for a mistake, and not the run. The
# first version built a floor and a stair out of it, and put the stair directly
# underneath the landing platform: half a metre of headroom against a body 1.8 m
# tall, so the runner arrived, climbed, and was trapped under the thing it was
# climbing towards.

checkpoint("the foot of the stair", 190.0, 7)
route([0.0, 1.2, 196.0], [26.0, 2.4, 8.0], "stone")
route([0.0, 2.5, 206.0], [22.0, 5.0, 8.0], "stone")
route([0.0, 3.8, 216.0], [18.0, 7.6, 8.0], "stone")
route([0.0, 5.1, 226.0], [14.0, 10.2, 8.0], "stone")
coin([0.0, 3.2, 196.0], "stair coin one")
spring("the last pad", [9.0, 2.6, 196.0])
coin([9.0, 8.0, 196.0], "stair coin two")
coin([0.0, 5.8, 206.0], "stair coin three")
coin([0.0, 8.4, 216.0], "stair coin four")
mover("lift", "the summit lift", [-12.0, 0.3, 214.0], [4.0, 0.6, 4.0],
      [0.0, 7.0, 0.0], 2.0, 4.0)
plate("the summit plate", "the summit lift", [-12.0, 1.6, 214.0])
for i, (x, z) in enumerate((
    (4.0, 226.0), (2.8, 228.8), (0.0, 230.0), (-2.8, 228.8),
    (-4.0, 226.0), (-2.8, 223.2), (0.0, 222.0), (2.8, 223.2),
)):
    coin([x, 11.0, z], f"ring coin {i + 1}")
exit_at("the summit", [0.0, 11.7, 226.0], "The summit.")

# The colonnade below the stair.
for i in range(6):
    z = 172.0 + i * 4.0
    for x in (-18.0, 18.0):
        pillar(x, z, 6.0, width=2.4, top_coin=i % 2 == 0)
    coin([0.0, 0.8, z])
for i in range(5):
    x = -52.0 + i * 8.0
    pillar(x, 176.0, 2.0 + i * 0.8, width=4.0)
    pillar(-x, 176.0, 2.0 + i * 0.8, width=4.0)

# A gap of nine and a half metres, beside the path rather than on it: a double
# jump clears seven and a half, and a long jump out of a slide clears this.
fill([-30.0, 1.0, 172.0], [7.0, 2.0, 7.0], "stone")
fill([-30.0, 1.0, 185.0], [7.0, 2.0, 7.0], "stone")
coin([-30.0, 3.0, 185.0])
coin([-30.0, 3.0, 188.0])

# A cap of blocks over a pocket of coins. Nothing but a pound gets through it.
#
# **Moved back down the level, out of the gate of two skills.** It stood at
# z = 176, which the chimney now occupies — so the three caps were inside solid
# rock and the test that pounds one found nothing to pound. Moved in z rather
# than in x, because the field either side of the corridor is already a forest
# of pillars and every x tried put a coin inside one.
_CAP_AT = 30.0
for i, dx in enumerate((-2.0, 0.0, 2.0)):
    breakable(f"the cap {i + 1}", [_CAP_AT + dx, 3.6, 164.0], size=(2.0, 1.2, 4.0))
fill([_CAP_AT - 4.0, 1.5, 164.0], [2.0, 3.0, 6.0], "stone")
fill([_CAP_AT + 4.0, 1.5, 164.0], [2.0, 3.0, 6.0], "stone")
fill([_CAP_AT, 1.5, 167.5], [10.0, 3.0, 1.0], "stone")
fill([_CAP_AT, 1.5, 160.5], [10.0, 3.0, 1.0], "stone")
coin([_CAP_AT, 0.8, 164.0])
coin([_CAP_AT - 2.0, 0.8, 164.0])
coin([12.0, 0.8, 176.0])

# Two ziggurats flanking the stair, and lifts up the outer walls.
ziggurat(-34.0, 208.0, 4, 2.4, 20.0)
ziggurat(34.0, 208.0, 4, 2.4, 20.0)
for x in (-50.0, 50.0):
    mover("lift", f"the {'west' if x < 0 else 'east'} hoist", [x, 0.3, 196.0],
          [4.0, 0.6, 4.0], [0.0, 8.0, 0.0], 2.0, 4.0)
    plate(f"the {'west' if x < 0 else 'east'} hoist plate",
          f"the {'west' if x < 0 else 'east'} hoist", [x, 1.6, 196.0])
    fill([x, 4.0, 204.0], [8.0, 8.0, 8.0], "stone")
    coin([x, 8.8, 204.0])
    fill([x, 8.3, 212.0], [8.0, 0.6, 8.0], "wood")
    coin([x, 9.4, 212.0])

# The back wall, so the summit has something behind it.
for i in range(9):
    x = -48.0 + i * 12.0
    if abs(x) < 20.0:
        continue
    fill([x, 2.0, 230.0], [8.0, 4.0, 4.0], "stone")
    coin([x, 5.2, 230.0])

LIGHTS = [
    {
        # Back to an angle that casts. It was pinned nearly overhead as a
        # workaround: one shadow map stretched over a hundred and twenty metres
        # of level is fourteen centimetres of world per texel, and at a low sun
        # the runner's own shadow came out as a blurred slab beside them —
        # reported, in those words, as the character being drawn twice. The
        # renderer has cascades now and the near one is four centimetres a
        # texel, so the sun can go back to throwing a shadow you can see.
        "type": "directional",
        "direction": [-0.35, -0.85, 0.4],
        "color": [1.0, 0.96, 0.88],
        "intensity": 2.6,
        "castsShadow": True,
    },
] + [
    {"at": [x, y, z], "color": c, "intensity": 26.0, "range": r}
    for x, y, z, c, r in (
        (0.0, 7.0, -12.0, [0.6, 0.75, 1.0], 46.0),
        (-38.0, 7.0, -10.0, [1.0, 0.85, 0.6], 34.0),
        (36.0, 8.0, -18.0, [1.0, 0.85, 0.6], 40.0),
        (0.0, 9.0, 44.0, [1.0, 0.8, 0.55], 40.0),
        (-30.0, 8.0, 40.0, [1.0, 0.86, 0.62], 44.0),
        (34.0, 8.0, 44.0, [1.0, 0.86, 0.62], 44.0),
        (0.0, 9.0, 62.0, [0.8, 0.85, 1.0], 44.0),
        (0.0, 7.0, 78.0, [1.0, 0.86, 0.62], 40.0),
        (0.0, 8.0, 96.0, [1.0, 0.9, 0.7], 46.0),
        (0.0, 8.0, 114.0, [1.0, 0.9, 0.7], 46.0),
        (-42.0, 8.0, 100.0, [1.0, 0.88, 0.66], 44.0),
        (42.0, 9.0, 100.0, [1.0, 0.88, 0.66], 44.0),
        (0.0, 8.0, 137.0, [0.7, 0.9, 1.0], 48.0),
        (0.0, 8.0, 155.0, [0.7, 0.9, 1.0], 42.0),
        (0.0, 8.0, 178.0, [0.95, 0.95, 1.0], 46.0),
        (0.0, 14.0, 214.0, [0.9, 1.0, 0.95], 50.0),
    )
]


levelkit.write(
    "ascent.json",
    name="Ascent",
    lights=LIGHTS,
    # **Ascent is no longer where the game stops.** It was the last level for as
    # long as there were two, and the summit's exit put up the credits; three
    # levels follow it now, and what a finished level does next is a line in the
    # document rather than a rule in the application — so the ending moves by
    # moving this.
    next_level="assets/levels/cisterns.json",
    tool="tool/make_level.py",
)
