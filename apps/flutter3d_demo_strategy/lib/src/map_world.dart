/// The shipped map's water and woods, and its world stood from them.
///
/// **The world is the package's**, `package:flutter3d_game_strategy/
/// map_world.dart`: the river laid down a course and run into the pond, the
/// halls' timber, the woods that burn, the stones a siege throws — hung on
/// the simulation's step and saved in its snapshot, so the screen, a replay
/// and a playthrough step and save the same world. What is here is what only
/// this game knows: where its river runs on its map, how much of it there
/// is, and where its trees were planted. [mapWorldOf] is the one way the game
/// and its tests stand it.
///
/// `effects.dart` draws and hears the world; nothing here draws.
library;

import 'package:flutter3d_demo_content/map_world.dart';
import 'package:flutter3d_game_strategy/flutter3d_game_strategy.dart';
import 'package:vector_math/vector_math.dart';

import 'kit.dart' show pondLevel;
import 'staging.dart' show viewerSide;
import 'woods.dart' show PlantedTree, plantTrees, woodScales;

export 'package:flutter3d_demo_content/map_world.dart';

/// The shipped map's river and pond.
///
/// **The grid is half a metre a cell, not a metre**, from the spring's valley
/// to past the pond's east shore. The water is drawn one vertex a cell, and
/// where it ends is found between a wet vertex and a dry one, so a shore is
/// as fine as the grid: at a metre a cell a river five metres wide had an
/// edge in steps as long as a fifth of its width, and from above it was a
/// thing of squares.
///
/// **Two and a half cubic metres a second, enough to run a foot deep.** How
/// deep water runs down a slope is set by how much of it there is, for the
/// width it has and the bed it runs on, and the colour of water a few
/// centimetres deep over grass is mostly the grass's: four hundred litres a
/// second over a bed two metres wide ran ten centimetres deep, and read from
/// above as a pale wet strip.
///
/// **The course is read off the map's ground**: down the valley's low line
/// from the spring, swinging a stride or two either side of it, and where the
/// valley tips into the pond's hollow straight down its bank along the grid,
/// east, into the pond — a course along the grid can fall more steeply
/// before the view takes its water for a falls. The pond lets out over a
/// sill eight metres wide at its outfall.
MapWater get mapAWater => MapWater(
  x0: 48.0,
  z0: 44.0,
  cell: 0.5,
  nx: 176,
  nz: 72,
  course: <Vector2>[
    Vector2(52.0, 62.0),
    Vector2(56.5, 61.0),
    Vector2(61.0, 59.2),
    Vector2(66.0, 58.6),
    Vector2(71.0, 57.2),
    Vector2(76.0, 57.6),
    Vector2(81.0, 59.0),
    Vector2(86.0, 60.2),
    Vector2(92.0, 60.6),
    Vector2(98.0, 61.0),
    Vector2(104.0, 61.5),
    Vector2(110.0, 62.0),
  ],
  flow: 2.5,
  drainX: 120.0,
  drainZ: 64.0,
  sill: 8.0,
  pondLevel: pondLevel,
);

/// The world over [simulation]'s map, hung on its step and its save: the
/// shipped map's water, and its woods planted as they are drawn.
///
/// Stood after the map is staged and before a save is put back, as the
/// screen does in `_place`: a restore then finds it there to fill.
MapWorld mapWorldOf(StrategySimulation simulation) {
  final List<List<PlantedTree>> planted = plantTrees(
    simulation: simulation,
    kinds: woodScales,
    waterLevel: pondLevel,
  );
  return MapWorld(
    simulation,
    water: mapAWater,
    viewer: viewerSide,
    trees: <MapTree>[
      for (var b = 0; b < planted.length; b++)
        for (var p = 0; p < planted[b].length; p++)
          MapTree(
            batch: b,
            placement: p,
            x: planted[b][p].x,
            z: planted[b][p].z,
            base: planted[b][p].y,
            size: planted[b][p].scale,
          ),
    ],
  );
}
