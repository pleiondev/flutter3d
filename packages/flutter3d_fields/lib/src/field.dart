/// What a field is: a 3D grid of one quantity, where it stands in the world,
/// where its values are held, and who writes and reads it.
library;

import 'package:flutter3d_foundation/flutter3d_foundation.dart';

/// Where a field's values are held.
///
/// **An open set** (S0): a class with constants, never an enum, so a
/// residence a later minor adds (a sparse grid, a field streamed in bricks)
/// breaks no `switch` written against these three. [name] is what a report
/// and a file write; [byName] reads it.
final class FieldResidence {
  const FieldResidence._(this.name, {required this.onDevice});

  /// In host memory, as a `Float32List` (`HostField`): what a simulation
  /// subsystem steps and audio reads, and what every machine has.
  static const FieldResidence host = FieldResidence._('host', onDevice: false);

  /// In a storage buffer on a device that runs compute, the cells in the
  /// order a `HostField` keeps them: what a compute step writes and reads.
  /// Which device is the frame's to decide, by the compute placement of the
  /// step that writes it (the device that draws, a sidecar, the CPU).
  static const FieldResidence buffer = FieldResidence._(
    'buffer',
    onDevice: true,
  );

  /// In a 3D texture on the device that draws, one texel a cell, sampled
  /// and filtered by a stage: what a volume is drawn from. Needs the
  /// device's 3D textures (`DeviceFeature.texture3D`); where it has none,
  /// the frame refuses the field with a `FieldResidenceException` naming
  /// the feature, before anything is allocated.
  static const FieldResidence texture3D = FieldResidence._(
    'texture3D',
    onDevice: true,
  );

  /// Every residence this version names. A later version appends.
  static const List<FieldResidence> values = <FieldResidence>[
    host,
    buffer,
    texture3D,
  ];

  /// The residence called [name], or null for one this version does not
  /// know.
  static FieldResidence? byName(String name) {
    for (final residence in values) {
      if (residence.name == name) return residence;
    }
    return null;
  }

  /// The stable name, and the wire name.
  final String name;

  /// Whether the values live on a graphics device rather than in host
  /// memory: what only the frame can make, and the simulation cannot step.
  final bool onDevice;

  @override
  String toString() => 'FieldResidence.$name';
}

/// Which part of the engine a step that touches a field belongs to.
///
/// **An open set**, as [FieldResidence] is.
final class FieldSide {
  const FieldSide._(this.name);

  /// A subsystem of the simulation, inside the fixed step, by its id.
  static const FieldSide simulation = FieldSide._('simulation');

  /// A node of the frame graph, by its name in the frame.
  static const FieldSide frame = FieldSide._('frame');

  /// Something that makes sound from the field, by its name.
  static const FieldSide audio = FieldSide._('audio');

  /// Every side this version names. A later version appends.
  static const List<FieldSide> values = <FieldSide>[simulation, frame, audio];

  /// The side called [name], or null for one this version does not know.
  static FieldSide? byName(String name) {
    for (final side in values) {
      if (side.name == name) return side;
    }
    return null;
  }

  /// The stable name, and the wire name.
  final String name;

  @override
  String toString() => 'FieldSide.$name';
}

/// One step that writes or reads a field: which side of the engine it is
/// on and its name there.
final class FieldAccess {
  /// The step called [step] on [side].
  const FieldAccess(this.side, this.step);

  /// The simulation subsystem whose id is [id].
  const FieldAccess.simulation(String id) : this(FieldSide.simulation, id);

  /// The frame-graph node called [node].
  const FieldAccess.frame(String node) : this(FieldSide.frame, node);

  /// The sound source called [name].
  const FieldAccess.audio(String name) : this(FieldSide.audio, name);

  /// Which side of the engine it is on.
  final FieldSide side;

  /// Its name there: a subsystem's id, a node's name, a source's name.
  final String step;

  /// `{"side": …, "step": …}`.
  Map<String, Object?> toJson() => <String, Object?>{
    'side': side.name,
    'step': step,
  };

  @override
  bool operator ==(Object other) =>
      other is FieldAccess && other.side == side && other.step == step;

  @override
  int get hashCode => Object.hash(side, step);

  @override
  String toString() => '${side.name} $step';
}

/// How many cells a field has along each axis, and how many values each
/// cell holds.
final class FieldGrid {
  /// [width] cells along x, [height] along y and [depth] along z, each
  /// holding [components] values: one for a temperature, three for a wind.
  const FieldGrid(this.width, this.height, this.depth, {this.components = 1});

  final int width;
  final int height;
  final int depth;

  /// Values a cell holds, one after another.
  final int components;

  /// Cells in the grid.
  int get cellCount => width * height * depth;

  /// Values in the grid: [cellCount] times [components].
  int get valueCount => cellCount * components;

  /// What is wrong with this grid, or null when nothing is.
  String? get problem => switch (this) {
    _ when width < 1 || height < 1 || depth < 1 =>
      'a grid has at least one cell along each axis, not '
          '${width}x${height}x$depth',
    _ when components < 1 => 'a cell holds at least one value, not $components',
    _ => null,
  };

  @override
  bool operator ==(Object other) =>
      other is FieldGrid &&
      other.width == width &&
      other.height == height &&
      other.depth == depth &&
      other.components == components;

  @override
  int get hashCode => Object.hash(width, height, depth, components);

  @override
  String toString() =>
      '${width}x${height}x$depth${components == 1 ? '' : 'x$components'}';
}

/// A point in a field's grid, in cells: `(0, 0, 0)` is the middle of the
/// first cell, `(1.5, 0, 0)` halfway between the second and the third.
final class FieldCoordinate {
  const FieldCoordinate(this.x, this.y, this.z);

  /// Along the grid's x axis, in cells.
  final double x;

  /// Along the grid's y axis, in cells.
  final double y;

  /// Along the grid's z axis, in cells.
  final double z;

  @override
  bool operator ==(Object other) =>
      other is FieldCoordinate && other.x == x && other.y == y && other.z == z;

  @override
  int get hashCode => Object.hash(x, y, z);

  @override
  String toString() => 'FieldCoordinate($x, $y, $z)';
}

/// Where a field's grid stands in the world: the middle of its first cell
/// and the size of a cell, axis-aligned with the world.
///
/// **In world positions, double precision**, so a field kilometres from
/// the origin keeps its cells where they are when the floating origin
/// moves: a transform names the world, not the float32 frame the bodies are
/// held in. A rotated grid is an addition a later minor makes here, with a
/// default that is this one.
final class FieldTransform {
  /// A grid whose first cell's middle is at [origin], cells [cellSize]
  /// metres along each axis.
  const FieldTransform({
    this.origin = WorldPosition.origin,
    this.cellSize = 1.0,
  });

  /// The middle of cell `(0, 0, 0)`.
  final WorldPosition origin;

  /// The size of a cell along each axis, in metres.
  final double cellSize;

  /// Where the middle of [coordinate] is in the world.
  WorldPosition worldOf(FieldCoordinate coordinate) => WorldPosition(
    origin.x + coordinate.x * cellSize,
    origin.y + coordinate.y * cellSize,
    origin.z + coordinate.z * cellSize,
  );

  /// Where [position] is in the grid, in cells.
  FieldCoordinate gridOf(WorldPosition position) => FieldCoordinate(
    (position.x - origin.x) / cellSize,
    (position.y - origin.y) / cellSize,
    (position.z - origin.z) / cellSize,
  );

  /// `{"origin": [x, y, z], "cellSize": …}`.
  Map<String, Object?> toJson() => <String, Object?>{
    'origin': <double>[origin.x, origin.y, origin.z],
    'cellSize': cellSize,
  };

  @override
  bool operator ==(Object other) =>
      other is FieldTransform &&
      other.origin == origin &&
      other.cellSize == cellSize;

  @override
  int get hashCode => Object.hash(origin, cellSize);

  @override
  String toString() => 'FieldTransform($origin, ${cellSize}m)';
}

/// One field: a 3D grid of a quantity shared by the simulation, the frame
/// and audio, and everything a reader needs to know about it before it
/// reads a value.
///
/// * **What it holds**: [quantity], a namespaced id as a body's material
///   state names one (`f3d.temperature`, `<pluginId>.charring`), in
///   [unit], which every value of the field is in.
/// * **Where**: [grid] and [transform].
/// * **Where its values live**: [residence]. A host field is stepped by the
///   simulation; a field on a device is made by the frame.
/// * **Who writes it and who reads it**: one [writer], and the [readers],
///   each a step by side and name. A field has one writer, so there is one
///   answer to "who made this value", and the frame orders its readers
///   after it.
///
/// Its [id] is `<namespace>.<name>`, a plugin's under its own id, as every
/// name a plugin brings is; a field in the frame graph is the resource of
/// that name.
final class FieldDeclaration {
  const FieldDeclaration({
    required this.id,
    required this.quantity,
    required this.unit,
    required this.grid,
    this.transform = const FieldTransform(),
    this.residence = FieldResidence.host,
    required this.writer,
    this.readers = const <FieldAccess>[],
  });

  /// `<namespace>.<name>`.
  final String id;

  /// The quantity every cell holds, by its namespaced id.
  final String quantity;

  /// The unit every value is in.
  final Unit unit;

  /// How many cells, and how many values a cell holds.
  final FieldGrid grid;

  /// Where the grid stands in the world.
  final FieldTransform transform;

  /// Where the values are held.
  final FieldResidence residence;

  /// The one step that writes it.
  final FieldAccess writer;

  /// The steps that read it.
  final List<FieldAccess> readers;

  /// Whether [access] is the writer or one of the readers.
  bool touchedBy(FieldAccess access) =>
      writer == access || readers.contains(access);

  /// What is wrong with this declaration, or null when nothing is: an id
  /// or a quantity that is not namespaced, a grid without cells, a field
  /// on a device that a simulation subsystem writes (the simulation steps
  /// host memory), a reader that is also the writer.
  String? get problem => switch (this) {
    _ when !namespacedId.hasMatch(id) =>
      'a field\'s id is "<namespace>.<name>", as "f3d.heat" is, not "$id"',
    _ when !namespacedId.hasMatch(quantity) =>
      'field "$id" holds "$quantity", which is not a quantity\'s '
          '"<namespace>.<name>"',
    _ when grid.problem != null => 'field "$id": ${grid.problem}',
    _ when !(transform.cellSize > 0) =>
      'field "$id" has cells ${transform.cellSize} m across; a cell has a '
          'size',
    _ when residence.onDevice && writer.side == FieldSide.simulation =>
      'field "$id" is held in ${residence.name} and written by the '
          'simulation subsystem "${writer.step}"; a subsystem steps host '
          'memory, and a field on a device is the frame\'s to write',
    _ when readers.contains(writer) =>
      'field "$id" names ${writer.side.name} "${writer.step}" as its writer '
          'and as a reader',
    _ => null,
  };

  /// The shape every field id and quantity id has: `<namespace>.<name>`.
  static final RegExp namespacedId = RegExp(
    r'^[a-z][a-z0-9_.\-]*\.[a-zA-Z][A-Za-z0-9_]*$',
  );

  /// Everything about it, as a report or an inspector writes it.
  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'quantity': quantity,
    'unit': unit.symbol,
    'grid': <int>[grid.width, grid.height, grid.depth],
    if (grid.components != 1) 'components': grid.components,
    'transform': transform.toJson(),
    'residence': residence.name,
    'writer': writer.toJson(),
    if (readers.isNotEmpty)
      'readers': <Object?>[for (final reader in readers) reader.toJson()],
  };

  @override
  String toString() => 'FieldDeclaration($id: $quantity in $unit, $grid)';
}
