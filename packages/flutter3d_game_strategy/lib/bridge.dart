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
///
/// **One batch per look, not one batch.** A game that dresses its workers,
/// soldiers and tanks as three different models, in each side's colours, has
/// six meshes to draw, and an instanced batch is one mesh and one material.
/// So the crowd is split by [UnitLook] into a handful of batches — still a
/// handful of draws for a thousand units, which is the property the paragraph
/// above is about — and a kind nobody dressed falls back to the plain batch
/// [StrategyVisuals.crowd] has always been.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_foundation/flutter3d_foundation.dart';
import 'package:flutter3d_level_scene/flutter3d_level_scene.dart'
    show meshDataOf;
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:vector_math/vector_math.dart';

import 'src/building.dart';
import 'src/economy.dart';
import 'src/fog.dart';
import 'src/simulation.dart';
import 'src/unit.dart';

/// A mesh and the material it is drawn in: one way a unit, a deposit or a
/// prop looks.
///
/// The mesh is expected grounded — its local origin where it touches the
/// ground, not its middle — and facing +Z, the direction a unit turns towards
/// when it walks.
final class MeshLook {
  /// Pairs [mesh] with [material].
  const MeshLook(this.mesh, this.material);

  /// What is drawn.
  final DeviceMesh mesh;

  /// What it is drawn in.
  final RenderMaterial material;
}

/// How one kind of unit looks, side by side.
///
/// **Matched by [UnitType.name], and that is a reading, not a rule.** The
/// simulation carries a kind as its own row of numbers precisely so that no
/// pass has to interpret a name; drawing is the one place that wants to,
/// because a worker and a tank are told apart on screen by shape. A kind with
/// no look is still drawn — in [StrategyVisuals.crowd], as a box — so a game
/// that adds a fourth kind sees it on the map before it has a model.
final class UnitLook {
  /// Dresses units of [kind]; [sides] is indexed by `StrategyUnit.side`, wrapping
  /// round when there are more sides than looks.
  const UnitLook({required this.kind, required this.sides})
    : assert(sides.length > 0, 'a kind dressed in nothing');

  /// The [UnitType.name] this dresses.
  final String kind;

  /// One look per side: the team colour is the difference between them.
  final List<MeshLook> sides;
}

/// Copies of one look the map wears where the simulation has nothing: trees,
/// say, or boulders.
///
/// **Under the fog like everything else.** A tree is not a secret, but one
/// standing out of a black square tells a side the shape of ground it has not
/// been to; so a copy appears the first time its spot is explored and stays,
/// the same rule a building follows.
final class PropBatch {
  /// [placements] are full transforms, uniform scale only — a batch scales its
  /// copies uniformly.
  const PropBatch({
    required this.look,
    required this.placements,
    this.name = 'props',
  });

  /// What every copy looks like.
  final MeshLook look;

  /// Where each copy stands, turned and scaled.
  final List<Matrix4> placements;

  /// The batch's node name.
  final String name;
}

/// Draws a [StrategySimulation].
final class StrategyVisuals {
  /// Builds the ground and the batch the crowd is drawn in.
  ///
  /// [capacity] is the largest crowd this will draw. A batch's size is fixed
  /// when it is made — the buffer behind it is allocated once — so a game that
  /// intends thousands says so here rather than discovering the ceiling when it
  /// reaches it.
  ///
  /// [unitMesh] replaces the boxy default with a real model, already scaled
  /// and grounded — its own local origin is where a unit's feet stand, not
  /// its centre, since `sync()` places it with no added lift once one is
  /// set. [buildingMesh] and [buildingMeshSize] do the same for a hall, but
  /// as a shared mesh rather than a shape rebuilt at each footprint: a
  /// building's width and depth come from the level document, and one
  /// upload stretched per instance with [SceneNode.setScale] costs nothing
  /// extra past the second building, where a fresh [CuboidShape] would cost
  /// one upload apiece.
  ///
  /// [looks] dress units by kind, one batch per kind and side; see [UnitLook].
  /// [buildingSides] gives each side's buildings their own material — a
  /// castle in its owner's colours — in place of [buildings]; and
  /// [buildingStandsTall] lets a shared building mesh keep its proportions,
  /// rising by as much as its footprint stretches rather than being pressed
  /// to the fixed height a box is given.
  ///
  /// [resource] is drawn at every deposit, [props] are the map's furniture,
  /// and [waterLevel] floods everything below it with a sheet of [water].
  /// [groundMetersPerTexture] is how far the ground goes before its texture
  /// repeats — the width of the map, for a texture painted to fit it.
  StrategyVisuals({
    required this.simulation,
    required GraphicsDevice device,
    int capacity = 4096,
    this.viewer,
    RenderMaterial? ground,
    RenderMaterial? units,
    RenderMaterial? buildings,
    RenderMaterial? unseen,
    RenderMaterial? remembered,
    this.unitSize = const UnitSize(),
    DeviceMesh? unitMesh,
    DeviceMesh? buildingMesh,
    Vector3? buildingMeshSize,
    List<UnitLook> looks = const <UnitLook>[],
    List<RenderMaterial>? buildingSides,
    bool buildingStandsTall = false,
    MeshLook? resource,
    List<PropBatch> props = const <PropBatch>[],
    double? waterLevel,
    RenderMaterial? water,
    double groundMetersPerTexture = 8.0,
  }) : assert(
         (buildingMesh == null) == (buildingMeshSize == null),
         'a shared building mesh needs its own natural size to scale from, '
         'and a size with nothing to scale is dead weight',
       ),
       assert(
         buildingSides == null || buildingSides.isNotEmpty,
         'a building in nobody\'s colours',
       ),
       _buildingMaterial = buildings ?? _stone(),
       _buildingSides = buildingSides,
       _buildingMesh = buildingMesh,
       _buildingMeshSize = buildingMeshSize,
       // Not `this._…`: a private named parameter puts the private name in
       // the API and needs the newest language version to call.
       // ignore: prefer_initializing_formals
       _buildingStandsTall = buildingStandsTall,
       // ignore: prefer_initializing_formals
       _resource = resource,
       waterLevel = waterLevel,
       // A real model stands on its own feet at its local origin, once
       // grounded the way the strategy demo grounds its workers; the
       // default `CuboidShape` is centred instead, so only it needs lifting
       // by half its height to stand on the ground `at.y` names.
       _unitGroundLift = unitMesh == null ? unitSize.height / 2.0 : 0.0,
       _device = device {
    _ground = MeshNode(
      DeviceMesh.upload(
        device,
        meshDataOf(
          const HeightfieldGeometry().build(
            simulation.ground,
            material: 'ground',
            metersPerTexture: groundMetersPerTexture,
          ),
        ),
      ),
      ground ?? _turf(),
      name: 'ground',
    );

    _crowd = InstancedMeshNode(
      unitMesh ??
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
    _adopt(_crowd);
    for (final UnitLook look in looks) {
      _byKind[look.kind] = <int>[
        for (final MeshLook side in look.sides)
          _adopt(
            InstancedMeshNode(
              side.mesh,
              side.material,
              capacity: capacity,
              name: look.kind,
            ),
          ),
      ];
    }
    _filled = Int32List(_batches.length);

    for (final PropBatch batch in props) {
      _props.add(
        _reserve(
          InstancedMeshNode(
            batch.look.mesh,
            batch.look.material,
            capacity: math.max(1, batch.placements.length),
            name: batch.name,
          ),
        ),
      );
      _placements.add(batch.placements);
      _placed.add(List<bool>.filled(batch.placements.length, false));
      _slots.add(
        Int32List(batch.placements.length)
          ..fillRange(0, batch.placements.length, -1),
      );
    }

    final Heightfield field = simulation.ground;
    if (waterLevel != null) {
      if (_wetBounds(field, waterLevel) case (
        final double x0,
        final double z0,
        final double x1,
        final double z1,
      )) {
        _water = MeshNode(
          DeviceMesh.upload(
            device,
            PlaneShape(width: x1 - x0, depth: z1 - z0).build(),
          ),
          water ?? _pond(),
          name: 'water',
        )..setPosition((x0 + x1) / 2.0, waterLevel, (z0 + z1) / 2.0);
      }
    }

    if (viewer == null) return;
    final FogOfWar fog = simulation.fog;
    _tileTop = Float32List(fog.cellCount);
    for (var cell = 0; cell < fog.cellCount; cell++) {
      // Over a pond the fog has to cover the water rather than the bed under
      // it, or the sheet shows through a square of dark as a square of blue.
      final double top = _topOf(fog, cell);
      _tileTop[cell] = waterLevel != null && waterLevel > top
          ? waterLevel
          : top;
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
  ///
  /// Every unit, unless [UnitLook]s were given; then only the kinds none of
  /// them dresses.
  InstancedMeshNode get crowd => _crowd;

  /// The sheet of water, or null for a map with no [waterLevel] or with no
  /// ground below it.
  MeshNode? get water => _water;

  /// How high the water stands, or null for a dry map.
  /// In metres of world height.
  final double? waterLevel;

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

  /// The node drawn for `simulation.buildings[index]`, or null while the
  /// viewer has not found it.
  ///
  /// [buildings] answers in the order the halls were found, which is not
  /// the simulation's; a game that dresses one particular hall — the strategy
  /// demo chars the one that burns — asks by the simulation's index here.
  MeshNode? buildingAt(int index) =>
      index < _buildings.length ? _buildings[index] : null;

  /// How many batches of props there are: one per [PropBatch] given.
  int get propBatchCount => _props.length;

  /// Where each prop of batch [batch] was planted, in the order given.
  ///
  /// For a game that puts something of its own where the props stand — the
  /// strategy demo's fires give each tree a body that can burn.
  List<Matrix4> propPlacementsOf(int batch) =>
      List<Matrix4>.unmodifiable(_placements[batch]);

  /// Draws prop [placement] of batch [batch] tinted [color] and, when
  /// [transform] is given, placed by it rather than where it was planted;
  /// false, and nothing done, while the viewer has not found it yet.
  ///
  /// **A tint on the copy the batch already holds**, as a hurt unit's is: a
  /// tree charred by the strategy demo's fires stays one instance of its
  /// batch, so a burnt wood costs no draw more than a green one.
  bool dressProp(
    int batch,
    int placement, {
    required Vector4 color,
    Matrix4? transform,
  }) {
    final int slot = _slots[batch][placement];
    if (slot < 0) return false;
    final InstancedMeshNode node = _props[batch];
    node.setColor(slot, color.toLinearColor());
    if (transform != null) node.setTransform(slot, transform);
    return true;
  }

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
  final RenderMaterial _buildingMaterial;

  /// One material per side for its buildings, or null to give every building
  /// [_buildingMaterial].
  final List<RenderMaterial>? _buildingSides;

  /// Whether a shared building mesh rises with its footprint; see the
  /// constructor.
  final bool _buildingStandsTall;

  /// What a deposit looks like, or null to leave deposits undrawn.
  final MeshLook? _resource;

  /// The node drawn at each deposit, by its index in `simulation.resources`;
  /// null until the viewer has found it.
  final List<MeshNode?> _deposits = <MeshNode?>[];

  /// [crowd] and every dressed batch after it.
  final List<InstancedMeshNode> _batches = <InstancedMeshNode>[];

  /// Which entries of [_batches] dress a kind, by side.
  final Map<String, List<int>> _byKind = <String, List<int>>{};

  /// How many instances each batch has been written this sync.
  late final Int32List _filled;

  final List<InstancedMeshNode> _props = <InstancedMeshNode>[];
  final List<List<Matrix4>> _placements = <List<Matrix4>>[];

  /// Which placements of each prop batch have been written already. Only
  /// ever turns true, because exploring only ever grows.
  final List<List<bool>> _placed = <List<bool>>[];

  /// Which instance of its batch each placement was written to, or -1 while
  /// it has not been: what [dressProp] finds a prop by.
  final List<Int32List> _slots = <Int32List>[];

  MeshNode? _water;

  /// Which way each unit faces and where it stood at the last sync.
  ///
  /// **Kept here, because the simulation has no idea.** A unit is a point
  /// with a velocity it does not store, and a facing would be a field the
  /// step had to carry, save and replay for the sake of a picture. So the
  /// drawing half reads it off the walk instead: where a unit is now against
  /// where it was a frame ago. An [Expando] rather than a map, so a unit that
  /// dies takes its entry with it.
  final Expando<Float64List> _facing = Expando<Float64List>('facing');

  /// A shared upload every building instance scales to its own footprint,
  /// or null to build a fresh [CuboidShape] per building instead.
  final DeviceMesh? _buildingMesh;

  /// [_buildingMesh]'s own width, height and depth, so a building can be
  /// scaled to its footprint by ratio rather than by a number read off the
  /// file by hand.
  final Vector3? _buildingMeshSize;

  /// Added to a unit's Y position; zero once a real, already-grounded
  /// [unitMesh] replaces the centred default box. See the constructor.
  final double _unitGroundLift;

  late final MeshNode _ground;
  late final InstancedMeshNode _crowd;
  late final Float32List _tileTop;
  InstancedMeshNode? _unseen;
  InstancedMeshNode? _remembered;
  final List<MeshNode?> _buildings = <MeshNode?>[];
  final Matrix4 _transform = Matrix4.identity();
  final Vector4 _tint = Vector4(1.0, 1.0, 1.0, 1.0);

  Scene? _scene;

  /// Fills [batch] to its capacity with placeholders and draws none of them,
  /// so every later write is to an index that already exists.
  static InstancedMeshNode _reserve(InstancedMeshNode batch) {
    for (var i = 0; i < batch.capacity; i++) {
      batch.addInstance(Matrix4.identity());
    }
    batch.count = 0;
    return batch;
  }

  /// Takes [batch] on as a unit batch and answers its index in [_batches].
  int _adopt(InstancedMeshNode batch) {
    _batches.add(_reserve(batch));
    return _batches.length - 1;
  }

  InstancedMeshNode _tileBatch(
    DeviceMesh mesh,
    RenderMaterial material,
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
    final double x = fog.centerX(cell);
    final double z = fog.centerZ(cell);
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
    scene.add(_ground);
    for (final InstancedMeshNode batch in _batches) {
      scene.add(batch);
    }
    for (final InstancedMeshNode batch in _props) {
      scene.add(batch);
    }
    final MeshNode? water = _water;
    if (water != null) scene.add(water);
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
    _filled.fillRange(0, _filled.length, 0);
    for (final StrategyUnit unit in simulation.units) {
      if (side != null && !_showsUnit(side, unit)) continue;
      final List<int>? dressed = _byKind[unit.type.name];
      final int which = dressed == null
          ? 0
          : dressed[unit.side % dressed.length];
      final InstancedMeshNode batch = _batches[which];
      final int drawn = _filled[which];
      if (drawn >= batch.capacity) continue;
      final Vector3 at = unit.position;
      final double lift = which == 0 ? _unitGroundLift : 0.0;
      _transform
        ..setRotationY(_headingOf(unit))
        ..setTranslationRaw(at.x, at.y + lift, at.z);
      batch
        ..setTransform(drawn, _transform)
        ..setColor(drawn, _woundOf(unit).toLinearColor());
      _filled[which] = drawn + 1;
    }
    for (var i = 0; i < _batches.length; i++) {
      _batches[i].count = _filled[i];
    }

    _syncProps(side);
    _syncDeposits(side);

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
          !simulation.fog.knows(side, building.center.x, building.center.z)) {
        continue;
      }
      // A copy each, not the one material shared. It costs a handful of
      // objects and it buys the only thing a picking pass is good for here:
      // a hall the cursor is over can be lit on its own. Shared, the
      // highlight would light every hall on the map at once.
      final List<RenderMaterial>? sides = _buildingSides;
      final RenderMaterial material =
          (sides == null
                  ? _buildingMaterial
                  : sides[building.side % sides.length])
              .copy();
      final double height = unitSize.height * 2.5;
      final MeshNode node;
      final DeviceMesh? sharedMesh = _buildingMesh;
      if (sharedMesh != null) {
        final Vector3 natural = _buildingMeshSize!;
        final double across = building.width / natural.x;
        final double along = building.depth / natural.z;
        // A real model already stands on its own feet at Y = 0 — no lift to
        // add, only the stretch from its authored size to this building's.
        // Upright, it rises by the mean of the two ground stretches, so a
        // castle laid out a little narrower than its footprint is not also
        // squashed to the height of a shed.
        node = MeshNode(sharedMesh, material, name: building.name)
          ..setScale(
            across,
            _buildingStandsTall ? (across + along) / 2.0 : height / natural.y,
            along,
          )
          ..setPosition(
            building.center.x,
            building.center.y,
            building.center.z,
          );
      } else {
        node =
            MeshNode(
              DeviceMesh.upload(
                _device,
                CuboidShape(
                  size: Vector3(building.width, height, building.depth),
                ).build(),
              ),
              material,
              name: building.name,
            )..setPosition(
              building.center.x,
              building.center.y + unitSize.height * 1.25,
              building.center.z,
            );
      }
      _buildings[i] = node;
      _scene?.add(node);
    }

    if (side != null) _syncFog(side);
  }

  /// Which way [unit] faces, in radians about +Y, from +Z.
  ///
  /// Turned towards the way it moved since the last call, part of the way
  /// each time, so a unit shoved sideways by a neighbour for a frame does not
  /// spin round to face the shove. A unit that has not moved keeps the
  /// heading it had — a worker at a seam faces the seam it walked to.
  double _headingOf(StrategyUnit unit) {
    final Vector3 at = unit.position;
    final Float64List? known = _facing[unit];
    if (known == null) {
      _facing[unit] = Float64List.fromList(<double>[at.x, at.z, 0.0]);
      return 0.0;
    }
    final double dx = at.x - known[0];
    final double dz = at.z - known[1];
    known[0] = at.x;
    known[1] = at.z;
    // A few centimetres a frame is a walk; less is a shove settling.
    if (dx * dx + dz * dz > 0.0004) {
      final double wanted = Portable.atan2(dx, dz);
      var turn = wanted - known[2];
      if (turn > math.pi) turn -= 2.0 * math.pi;
      if (turn < -math.pi) turn += 2.0 * math.pi;
      known[2] += turn * 0.3;
    }
    return known[2];
  }

  /// Writes the props [side] has found since the last call.
  ///
  /// Only ever appends, because a placement once explored stays explored;
  /// so a frame in which nobody walked anywhere new writes nothing.
  void _syncProps(int? side) {
    for (var b = 0; b < _props.length; b++) {
      final InstancedMeshNode batch = _props[b];
      final List<Matrix4> placements = _placements[b];
      final List<bool> placed = _placed[b];
      var count = batch.count;
      for (var i = 0; i < placements.length; i++) {
        if (placed[i]) continue;
        final Float32List at = placements[i].storage;
        if (side != null && !simulation.fog.knows(side, at[12], at[14])) {
          continue;
        }
        placed[i] = true;
        _slots[b][i] = count;
        batch.setTransform(count++, placements[i]);
      }
      batch.count = count;
    }
  }

  /// Puts a [_resource] at every deposit [side] knows of, and takes away
  /// the ones dug out.
  void _syncDeposits(int? side) {
    final MeshLook? look = _resource;
    if (look == null) return;
    final List<ResourceNode> resources = simulation.resources;
    for (var i = _deposits.length; i < resources.length; i++) {
      _deposits.add(null);
    }
    for (var i = 0; i < resources.length; i++) {
      final ResourceNode deposit = resources[i];
      final MeshNode? drawn = _deposits[i];
      if (drawn != null) {
        // Hidden rather than removed, and only once the viewer is looking:
        // a seam dug out behind the fog is remembered as it was last seen.
        if (deposit.isEmpty &&
            (side == null ||
                simulation.fog.sees(side, deposit.at.x, deposit.at.z))) {
          drawn.isVisible = false;
        }
        continue;
      }
      if (side != null &&
          !simulation.fog.knows(side, deposit.at.x, deposit.at.z)) {
        continue;
      }
      final node = MeshNode(look.mesh, look.material, name: 'seam')
        ..setPosition(deposit.at.x, deposit.at.y, deposit.at.z);
      _deposits[i] = node;
      _scene?.add(node);
    }
  }

  /// How hurt [unit] looks: white at full health, darkening towards red as it
  /// is worn down.
  ///
  /// **A tint on an instance that is already there, which is why there is no
  /// new anything here.** The batch has carried four floats of colour per copy
  /// since it was written, multiplied into the vertex colour, and every unit
  /// has been writing white into them without meaning to. So showing damage
  /// costs one write per unit per frame in a buffer that is uploaded whole
  /// anyway — no second batch, no material per unit, no blending mode this
  /// package was not already using, and no picture that was correct before
  /// changes, because a crowd nobody has hit is still white.
  ///
  /// The dead are not drawn at all and need no rule for it: `_bury` takes them
  /// out of the crowd inside the step that kills them, so by the time anything
  /// here looks there is nobody to leave out.
  /// Written into [_tint] rather than returned fresh, which is the same reason
  /// [_transform] is a field: this is called once per unit per frame, and a
  /// crowd that allocated a colour apiece would spend the saving on the
  /// collector. [InstancedMeshNode.setColor] copies the components straight
  /// into the buffer, so nothing holds on to the object afterwards.
  Vector4 _woundOf(StrategyUnit unit) {
    final double left = unit.health / unit.type.health;
    if (left >= 1.0) return _tint..setValues(1.0, 1.0, 1.0, 1.0);
    // The green and blue give way and the red is held back only a little, so a
    // failing unit reads as reddening rather than as merely dimming — a dim one
    // would be indistinguishable from one standing in shadow.
    final double hurt = left < 0.0 ? 0.0 : left;
    return _tint..setValues(
      0.45 + 0.55 * hurt,
      0.12 + 0.88 * hurt,
      0.1 + 0.9 * hurt,
      1.0,
    );
  }

  /// Whether [side] is shown [unit].
  ///
  /// Its own are never hidden from it. That is not the same answer as asking
  /// the fog — a side's own units light the ground they stand on, so the fog
  /// would say yes as well — but it is the answer that stays right when
  /// somebody gives a unit a sight of nothing, and it costs a comparison.
  bool _showsUnit(int side, StrategyUnit unit) =>
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
        fog.centerX(cell),
        _tileTop[cell] + 0.3 - _tileDepth / 2.0,
        fog.centerZ(cell),
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
/// The drawn size, not the simulated one: `StrategyUnit.radius` is how much room a unit
/// needs and this is how much of it a player sees, and a game is free to make
/// the second larger than the first so that a crowd reads as a crowd rather
/// than as a scatter of dots.
final class UnitSize {
  /// Builds the pair.
  const UnitSize({this.width = 0.8, this.height = 1.2});

  /// How wide the box is, along both ground axes.
  /// In metres.
  final double width;

  /// How tall it stands.
  /// In metres.
  final double height;
}

RenderMaterial _turf() => RenderMaterial(
  lighting: LightingModel.pbr,
  baseColor: LinearColor.fromSrgb(0.32, 0.38, 0.24, 1.0),
  roughness: 0.95,
);

RenderMaterial _cloth() => RenderMaterial(
  lighting: LightingModel.pbr,
  baseColor: LinearColor.fromSrgb(0.74, 0.70, 0.62, 1.0),
  roughness: 0.7,
);

RenderMaterial _stone() => RenderMaterial(
  lighting: LightingModel.pbr,
  baseColor: LinearColor.fromSrgb(0.55, 0.53, 0.5, 1.0),
  roughness: 0.85,
);

/// The box round every sample of [field] lower than [level], one cell wider
/// on each side and kept inside the map, as `(x0, z0, x1, z1)` in world
/// metres; null if nothing is that low.
///
/// **The sheet covers the ponds, not the map.** Laid over the whole map it
/// is hidden under every hill, but not past the map's rim: the ground is a
/// surface with no sides, and from the map camera a strip of water showed
/// beneath the near edge wherever it stands above the water line.
(double, double, double, double)? _wetBounds(Heightfield field, double level) {
  var c0 = field.columns;
  var r0 = field.rows;
  var c1 = -1;
  var r1 = -1;
  for (var row = 0; row < field.rows; row++) {
    for (var column = 0; column < field.columns; column++) {
      if (field.sample(column, row) >= level) continue;
      c0 = math.min(c0, column);
      c1 = math.max(c1, column);
      r0 = math.min(r0, row);
      r1 = math.max(r1, row);
    }
  }
  if (c1 < 0) return null;
  double x(int column) =>
      field.origin.x + column.clamp(0, field.columns - 1) * field.cellSize;
  double z(int row) =>
      field.origin.z + row.clamp(0, field.rows - 1) * field.cellSize;
  return (x(c0 - 1), z(r0 - 1), x(c1 + 1), z(r1 + 1));
}

/// Still water: blended so the bed shows through near the shore, and smooth
/// so the sun catches it.
RenderMaterial _pond() => RenderMaterial(
  lighting: LightingModel.pbr,
  baseColor: LinearColor.fromSrgb(0.16, 0.34, 0.42, 0.72),
  roughness: 0.08,
  alphaMode: MaterialAlphaMode.blend,
);

/// Ground nobody has been to. Unlit, because fog is not a surface the sun
/// falls on — a shaded one would report the shape of the hill it is hiding.
RenderMaterial _night() => RenderMaterial(
  lighting: LightingModel.unlit,
  baseColor: LinearColor.fromSrgb(0.03, 0.035, 0.05, 1.0),
);

/// Ground somebody has been to and nobody is watching. Blended, so the hillside
/// underneath stays legible: what a side remembers is the *place*, and the
/// place is the part that has not changed.
RenderMaterial _dusk() => RenderMaterial(
  lighting: LightingModel.unlit,
  baseColor: LinearColor.fromSrgb(0.05, 0.06, 0.09, 0.62),
  alphaMode: MaterialAlphaMode.blend,
);
