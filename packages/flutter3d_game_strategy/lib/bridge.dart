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

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_bridge/flutter3d_bridge.dart';
import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:vector_math/vector_math.dart';

import 'src/building.dart';
import 'src/simulation.dart';

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
    Material? ground,
    Material? units,
    Material? buildings,
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
  }

  /// What is drawn.
  final StrategySimulation simulation;

  /// The batch the crowd is drawn in, for a game that wants to tint or hide
  /// it and for a test that wants to read a transform back.
  InstancedMeshNode get crowd => _crowd;

  /// How big a unit is drawn.
  final UnitSize unitSize;

  final GraphicsDevice _device;
  final Material _buildingMaterial;
  late final MeshNode _ground;
  late final InstancedMeshNode _crowd;
  final List<MeshNode> _buildings = <MeshNode>[];
  final Matrix4 _transform = Matrix4.identity();

  Scene? _scene;

  /// Puts the ground and the crowd into [scene], and keeps it for the
  /// buildings that arrive later.
  void addTo(Scene scene) {
    _scene = scene;
    scene
      ..add(_ground)
      ..add(_crowd);
  }

  /// Brings the picture up to date with the simulation.
  ///
  /// Called after a step, once a frame. Nothing here reads the clock or decides
  /// anything: what a unit does is settled by the time this runs, and a drawing
  /// half that made decisions would be a second simulation disagreeing with the
  /// first.
  void sync() {
    final int drawn = simulation.units.length <= _crowd.capacity
        ? simulation.units.length
        : _crowd.capacity;

    for (var i = 0; i < drawn; i++) {
      final Vector3 at = simulation.units[i].position;
      _transform.setIdentity();
      _transform.setTranslationRaw(at.x, at.y + unitSize.height / 2.0, at.z);
      _crowd.setTransform(i, _transform);
    }
    _crowd.count = drawn;

    // Buildings are nodes of their own rather than instances: a batch scales
    // its copies uniformly by the engine's own account, and buildings are the
    // one thing on this map with sizes of their own.
    for (var i = _buildings.length; i < simulation.buildings.length; i++) {
      final Building building = simulation.buildings[i];
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
            _buildingMaterial,
            name: building.name,
          )..setPosition(
            building.centre.x,
            building.centre.y + unitSize.height * 1.25,
            building.centre.z,
          );
      _buildings.add(node);
      _scene?.add(node);
    }
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
