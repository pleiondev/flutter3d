/// The visible half: ground as a mesh, a crowd as one batch, buildings as
/// themselves.
///
/// **The only file in this package that draws**, which is what the structure
/// rule `a genre package draws only where it says` is about — reaching a
/// renderer, rather than importing Flutter. Everything under `src/` is
/// arithmetic and stays reachable from a test with no device; this is where the
/// arithmetic meets a GPU, and the seam is one class wide on purpose.
///
/// **The crowd is one node, not one node each.** That is the whole reason a
/// strategy is the genre that exercises `InstancedMeshNode`: a thousand nodes
/// is a thousand draws, and the measurement that started this work put fifty
/// thousand instanced units at the refresh rate of the display with the
/// processor encoding the frame — not the device drawing it — as what gives way
/// first. So the batch is written every frame, in full, because that is the
/// case a game actually has: units that stand still would let the engine skip
/// an upload a moving crowd cannot skip.
library;

import 'dart:typed_data';

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_bridge/flutter3d_bridge.dart';
import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:vector_math/vector_math.dart';

import 'src/building.dart';
import 'src/fog.dart';
import 'src/simulation.dart';
import 'src/unit.dart';

/// Draws a [StrategySimulation].
final class StrategyVisuals {
  /// Builds the ground and the batch the crowd is drawn in.
  ///
  /// [capacity] is the largest crowd this will draw. A batch's size is fixed
  /// when it is made — the buffer behind it is allocated once — so a game that
  /// intends thousands says so here rather than discovering the ceiling when it
  /// reaches it.
  StrategyVisuals({
    required this.simulation,
    required GraphicsDevice device,
    int capacity = 4096,
    this.viewer,
    Material? ground,
    Material? units,
    Material? buildings,
    Material? unseen,
    Material? remembered,
    this.unitSize = const UnitSize(),
  }) : _buildingMaterial = buildings ?? _stone(),
       _device = device {
    _ground = MeshNode(
      DeviceMesh.upload(
        device,
        meshDataOf(
          const HeightfieldGeometry().build(
            simulation.ground,
            material: 'ground',
          ),
        ),
      ),
      ground ?? _turf(),
      name: 'ground',
    );

    _crowd = InstancedMeshNode(
      DeviceMesh.upload(
        device,
        CuboidShape(
          size: Vector3(unitSize.width, unitSize.height, unitSize.width),
        ).build(),
      ),
      units ?? _cloth(),
      capacity: capacity,
      name: 'crowd',
    );
    for (var i = 0; i < capacity; i++) {
      _crowd.addInstance(Matrix4.identity());
    }
    _crowd.count = 0;

    if (viewer == null) return;
    final FogOfWar fog = simulation.fog;
    _tileTop = Float32List(fog.cellCount);
    for (var cell = 0; cell < fog.cellCount; cell++) {
      _tileTop[cell] = _topOf(fog, cell);
    }
    final DeviceMesh tile = DeviceMesh.upload(
      device,
      CuboidShape(
        size: Vector3(fog.cellSize, _tileDepth, fog.cellSize),
      ).build(),
    );
    _unseen = _tileBatch(tile, unseen ?? _night(), 'unseen', fog.cellCount);
    _remembered = _tileBatch(
      tile,
      remembered ?? _dusk(),
      'remembered',
      fog.cellCount,
    );
  }

  /// What is drawn.
  final StrategySimulation simulation;

  /// Whose view this is, or null for a view belonging to nobody.
  ///
  /// **Null means a spectator, and a spectator sees everything.** A test
  /// harness, a replay watched from above, an editor looking at a map: none of
  /// them is a side, and a fog that made them guess would be a fog nobody could
  /// debug through. A game passes the side the person is playing, and then this
  /// object draws that side's *knowledge* rather than the simulation — which is
  /// the only place in this package where the two are allowed to differ.
  final int? viewer;

  /// The batch the crowd is drawn in, for a game that wants to tint or hide
  /// it and for a test that wants to read a transform back.
  InstancedMeshNode get crowd => _crowd;

  /// The tiles over ground [viewer] has never seen, or null for a spectator.
  InstancedMeshNode? get unseen => _unseen;

  /// The tiles over ground [viewer] has seen and cannot see now.
  InstancedMeshNode? get remembered => _remembered;

  /// The building nodes drawn so far, in the order they were drawn.
  ///
  /// For a game that wants to do something to one of them — light the one the
  /// cursor is over, say. Shorter than `simulation.buildings` whenever the
  /// viewer has not found them all.
  Iterable<MeshNode> get buildings => _buildings.whereType<MeshNode>();

  /// How big a unit is drawn.
  final UnitSize unitSize;

  /// How far a fog tile hangs below its own top, in metres.
  ///
  /// **A slab rather than a sheet, and the terrain is why.** Neighbouring
  /// lattice cells sit at different heights, so a fog made of flat squares is a
  /// staircase with a hole at every step — you see the lit hillside through the
  /// risers. A tile deep enough to reach past its neighbours closes them: the
  /// tops read as fog and the sides read as the wall of it.
  static const double _tileDepth = 10.0;

  final GraphicsDevice _device;
  final Material _buildingMaterial;
  late final MeshNode _ground;
  late final InstancedMeshNode _crowd;
  late final Float32List _tileTop;
  InstancedMeshNode? _unseen;
  InstancedMeshNode? _remembered;
  final List<MeshNode?> _buildings = <MeshNode?>[];
  final Matrix4 _transform = Matrix4.identity();

  Scene? _scene;

  InstancedMeshNode _tileBatch(
    DeviceMesh mesh,
    Material material,
    String name,
    int cells,
  ) {
    final batch = InstancedMeshNode(
      mesh,
      material,
      capacity: cells,
      name: name,
    );
    for (var i = 0; i < cells; i++) {
      batch.addInstance(Matrix4.identity());
    }
    batch.count = 0;
    return batch;
  }

  /// The highest ground a fog cell covers.
  ///
  /// Corners and middle rather than a proper maximum: the lattice is coarse and
  /// the ground under one cell is a few metres across, so five samples put the
  /// tile above the hill instead of through it, and the ones they miss are
  /// hidden by a tile deep enough to swallow them.
  static double _topOf(FogOfWar fog, int cell) {
    final double x = fog.centreX(cell);
    final double z = fog.centreZ(cell);
    final double half = fog.cellSize / 2.0;
    final Heightfield ground = fog.ground;
    var top = ground.heightAt(x, z);
    for (final double dx in <double>[-half, half]) {
      for (final double dz in <double>[-half, half]) {
        final double at = ground.heightAt(x + dx, z + dz);
        if (at > top) top = at;
      }
    }
    return top;
  }

  /// Puts the ground, the crowd and the fog into [scene], and keeps it for the
  /// buildings that arrive later.
  void addTo(Scene scene) {
    _scene = scene;
    scene
      ..add(_ground)
      ..add(_crowd);
    final InstancedMeshNode? unseen = _unseen;
    final InstancedMeshNode? remembered = _remembered;
    if (unseen != null) scene.add(unseen);
    if (remembered != null) scene.add(remembered);
  }

  /// Brings the picture up to date with the simulation.
  ///
  /// Called after a step, once a frame. Nothing here reads the clock or decides
  /// anything: what a unit does is settled by the time this runs, and a drawing
  /// half that made decisions would be a second simulation disagreeing with the
  /// first.
  void sync() {
    // **The fog is what decides how many instances are written**, and that is
    // the cheapest form the saving could take: a unit nobody can see is not
    // culled after being encoded, it is never encoded. The measurement that
    // started this genre put the ceiling at the processor writing instances —
    // about 0.07 microseconds each, every frame — so the crowd a side cannot
    // see is exactly the part of that bill it should not be paying.
    final int? side = viewer;
    var drawn = 0;
    for (final Unit unit in simulation.units) {
      if (drawn >= _crowd.capacity) break;
      if (side != null && !_showsUnit(side, unit)) continue;
      final Vector3 at = unit.position;
      _transform.setIdentity();
      _transform.setTranslationRaw(at.x, at.y + unitSize.height / 2.0, at.z);
      _crowd.setTransform(drawn, _transform);
      drawn++;
    }
    _crowd.count = drawn;

    // Buildings are nodes of their own rather than instances: a batch scales
    // its copies uniformly by the engine's own account, and buildings are the
    // one thing on this map with sizes of their own.
    //
    // A building appears the first time its side's ground is uncovered and then
    // stays, because that is what "explored" means — a hall seen once is
    // remembered where it stood, even after the crowd that saw it walked home.
    for (var i = _buildings.length; i < simulation.buildings.length; i++) {
      _buildings.add(null);
    }
    for (var i = 0; i < simulation.buildings.length; i++) {
      if (_buildings[i] != null) continue;
      final Building building = simulation.buildings[i];
      if (side != null &&
          building.side != side &&
          !simulation.fog.knows(side, building.centre.x, building.centre.z)) {
        continue;
      }
      final node =
          MeshNode(
            DeviceMesh.upload(
              _device,
              CuboidShape(
                size: Vector3(
                  building.width,
                  unitSize.height * 2.5,
                  building.depth,
                ),
              ).build(),
            ),
            // A copy each, not the one material shared. It costs a handful of
            // objects and it buys the only thing a picking pass is good for
            // here: a hall the cursor is over can be lit on its own. Shared,
            // the highlight would light every hall on the map at once.
            _buildingMaterial.copy(),
            name: building.name,
          )..setPosition(
            building.centre.x,
            building.centre.y + unitSize.height * 1.25,
            building.centre.z,
          );
      _buildings[i] = node;
      _scene?.add(node);
    }

    if (side != null) _syncFog(side);
  }

  /// Whether [side] is shown [unit].
  ///
  /// Its own are never hidden from it. That is not the same answer as asking
  /// the fog — a side's own units light the ground they stand on, so the fog
  /// would say yes as well — but it is the answer that stays right when
  /// somebody gives a unit a sight of nothing, and it costs a comparison.
  bool _showsUnit(int side, Unit unit) =>
      unit.side == side ||
      simulation.fog.sees(side, unit.position.x, unit.position.z);

  /// Fills the two fog batches from what [side] knows.
  void _syncFog(int side) {
    final InstancedMeshNode? unseen = _unseen;
    final InstancedMeshNode? remembered = _remembered;
    if (unseen == null || remembered == null) return;

    final FogOfWar fog = simulation.fog;
    var dark = 0;
    var dim = 0;
    for (var cell = 0; cell < fog.cellCount; cell++) {
      if (fog.isVisible(side, cell)) continue;
      final bool known = fog.isExplored(side, cell);
      _transform.setIdentity();
      _transform.setTranslationRaw(
        fog.centreX(cell),
        _tileTop[cell] + 0.3 - _tileDepth / 2.0,
        fog.centreZ(cell),
      );
      if (known) {
        remembered.setTransform(dim++, _transform);
      } else {
        unseen.setTransform(dark++, _transform);
      }
    }
    unseen.count = dark;
    remembered.count = dim;
  }
}

/// How big a unit is drawn, in metres.
///
/// The drawn size, not the simulated one: `Unit.radius` is how much room a unit
/// needs and this is how much of it a player sees, and a game is free to make
/// the second larger than the first so that a crowd reads as a crowd rather
/// than as a scatter of dots.
final class UnitSize {
  /// Builds the pair.
  const UnitSize({this.width = 0.8, this.height = 1.2});

  /// How wide the box is, along both ground axes.
  final double width;

  /// How tall it stands.
  final double height;
}

Material _turf() => Material(
  lighting: LightingModel.pbr,
  baseColor: Vector4(0.32, 0.38, 0.24, 1.0),
  roughness: 0.95,
);

Material _cloth() => Material(
  lighting: LightingModel.pbr,
  baseColor: Vector4(0.74, 0.70, 0.62, 1.0),
  roughness: 0.7,
);

Material _stone() => Material(
  lighting: LightingModel.pbr,
  baseColor: Vector4(0.55, 0.53, 0.5, 1.0),
  roughness: 0.85,
);

/// Ground nobody has been to. Unlit, because fog is not a surface the sun
/// falls on — a shaded one would report the shape of the hill it is hiding.
Material _night() => Material(
  lighting: LightingModel.unlit,
  baseColor: Vector4(0.03, 0.035, 0.05, 1.0),
);

/// Ground somebody has been to and nobody is watching. Blended, so the hillside
/// underneath stays legible: what a side remembers is the *place*, and the
/// place is the part that has not changed.
Material _dusk() => Material(
  lighting: LightingModel.unlit,
  baseColor: Vector4(0.05, 0.06, 0.09, 0.62),
  alphaMode: MaterialAlphaMode.blend,
);
