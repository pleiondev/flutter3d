/// The commands that act on whole objects.
///
/// **Every one of them names the objects it acts on rather than reading the
/// selection**, except the three that are explicitly "do this to what is
/// selected". The reason is replay: a journal entry that said "move the
/// selection" would move whatever happens to be selected when it is read back,
/// which is not what it did the first time. The three that do read the
/// selection carry it in the step, which is what makes a redo do the same thing
/// as the do.
///
/// A `part` of `command.dart` rather than an import of it, because
/// [ModelCommand] is sealed: the exhaustive `switch` a journal writer and an
/// agent's tool table both rely on is only exhaustive if the compiler can see
/// every case, and it can only see them inside one library.
part of 'command.dart';

/// Adds one of the primitives the mesh package builds.
///
/// **The shape is named rather than handed over, and that is what lets it be
/// written down.** A `ParametricShape` is a class with a constructor; a journal
/// entry and an agent's tool call are both maps of numbers. Naming the kind and
/// the handful of numbers it takes is the only form that survives both, and it
/// is the same form the `Add` menu offers.
final class AddPrimitive extends ModelCommand {
  const AddPrimitive({
    required this.kind,
    this.size = 1.0,
    this.segments = 32,
    this.at,
  });

  /// One of [primitiveKinds].
  final String kind;

  /// How big, in the units the model is in. One number rather than three
  /// because that is what the menu offers; a box of unequal sides is a box that
  /// has been scaled, which is a transform and is a different command.
  final double size;

  /// How round the round ones are. Ignored by the box and the plane.
  final int segments;

  /// Where it goes, or the origin.
  final Vector3? at;

  @override
  String get name => 'addPrimitive';

  @override
  String get says => 'add a $kind';

  @override
  Map<String, Object?> get arguments => <String, Object?>{
    'kind': kind,
    'size': size,
    'segments': segments,
    if (at case final Vector3 where) 'at': <double>[where.x, where.y, where.z],
  };

  /// What [kind] may be.
  static const List<String> primitiveKinds = <String>[
    'box',
    'plane',
    'sphere',
    'cylinder',
    'torus',
  ];

  /// The shape this describes, or null when the kind is not one of ours.
  ParametricShape? get shape => switch (kind) {
    'box' => ParametricCuboid(size: Vector3.all(size)),
    'plane' => ParametricPlane(width: size, depth: size),
    'sphere' => ParametricSphere(radius: size / 2, segments: segments),
    'cylinder' => ParametricCylinder(
      radiusTop: size / 2,
      radiusBottom: size / 2,
      height: size,
      segments: segments,
    ),
    'torus' => ParametricTorus(
      radius: size * 0.35,
      tubeRadius: size * 0.15,
      segments: segments,
    ),
    _ => null,
  };

  @override
  Outcome apply(ModelProject project, ProjectSelection selection) {
    final ParametricShape? built = shape;
    if (built == null) {
      return Outcome.refused(
        '"$kind" is not a primitive this builds. It knows '
        '${primitiveKinds.join(', ')}',
      );
    }
    if (size <= 0) return Outcome.refused('a primitive needs a size');
    final next = project.added(
      (int id) => ModelObject(
        id: id,
        name: kind,
        geometry: ParametricGeometry(built),
        transform: Matrix4.translation(at ?? Vector3.zero()),
      ),
    );
    // Selected, because the next thing anybody does after adding a box is move
    // it, and a person who has to click the thing they just made is a person
    // the tool is arguing with.
    return Outcome.done(
      next,
      selection: selection.copyWith(objects: <int>[next.objects.last.id]),
    );
  }
}

/// Turns a shape that still knows its parameters into a mesh that can be
/// edited.
///
/// **One way and no way back, said out loud.** A cylinder with a face pulled
/// out is no longer describable by a radius and a segment count, so this is
/// where "set segments to 32" stops being answerable. Undo puts the parametric
/// object back, because the history keeps documents — but there is no command
/// that turns an edited mesh into a cylinder, and there should not be one that
/// pretends.
final class BakeToMesh extends ModelCommand {
  const BakeToMesh(this.id);

  final int id;

  @override
  String get name => 'bakeToMesh';

  @override
  String get says => 'convert to a mesh';

  @override
  Map<String, Object?> get arguments => <String, Object?>{'id': id};

  @override
  Outcome apply(ModelProject project, ProjectSelection selection) {
    final object = project[id];
    if (object == null) return Outcome.refused('there is no object $id');
    return switch (object.geometry) {
      ParametricGeometry(:final shape) => Outcome.done(
        project.withObject(
          object.copyWith(geometry: EditedGeometry(shape.toEditMesh())),
        ),
      ),
      EditedGeometry() => Outcome.refused('"${object.name}" is already a mesh'),
      // An imported model has vertex buffers and no topology; building one is
      // `importMeshData` and is a different command with different questions —
      // whether to weld, at what distance — which is `doc-11`'s import screen.
      ImportedGeometry() => Outcome.refused(
        '"${object.name}" came from a file, and building topology for it is '
        'an import option rather than a conversion',
      ),
    };
  }
}

/// Hangs one object under another.
final class SetParent extends ModelCommand {
  const SetParent({required this.id, required this.to});

  final int id;

  /// The new parent, or null for the top level.
  final int? to;

  @override
  String get name => 'setParent';

  @override
  String get says => to == null ? 'unparent' : 'parent';

  @override
  Map<String, Object?> get arguments => <String, Object?>{'id': id, 'to': to};

  @override
  Outcome apply(ModelProject project, ProjectSelection selection) {
    final object = project[id];
    if (object == null) return Outcome.refused('there is no object $id');
    if (to == null) {
      return Outcome.done(
        project.withObject(object.copyWith(clearParent: true)),
      );
    }
    if (to == id) return Outcome.refused('an object cannot be its own parent');
    if (project[to!] == null) return Outcome.refused('there is no object $to');
    // Walking up from the new parent rather than down from the object: the
    // question is whether the object is already above it, and a cycle is
    // exactly that. Without this check the hierarchy becomes a ring and every
    // traversal in the application runs for ever.
    for (int? at = to; at != null; at = project[at]?.parent) {
      if (at == id) {
        return Outcome.refused(
          '"${project[to!]!.name}" is already under "${object.name}"',
        );
      }
    }
    return Outcome.done(project.withObject(object.copyWith(parent: to)));
  }
}

/// Turns everything selected about its own middle.
final class RotateBy extends ModelCommand {
  const RotateBy({required this.axis, required this.radians});

  final Vector3 axis;
  final double radians;

  @override
  String get name => 'rotateBy';

  @override
  String get says => 'turn';

  @override
  Map<String, Object?> get arguments => <String, Object?>{
    'axis': <double>[axis.x, axis.y, axis.z],
    'radians': radians,
  };

  @override
  Outcome apply(ModelProject project, ProjectSelection selection) =>
      _aboutTheMiddle(
        project,
        selection,
        'turn',
        () => Matrix4.compose(
          Vector3.zero(),
          Quaternion.axisAngle(axis, radians),
          Vector3.all(1),
        ),
      );
}

/// Scales everything selected about its own middle.
final class ScaleBy extends ModelCommand {
  const ScaleBy(this.by);

  final double by;

  @override
  String get name => 'scaleBy';

  @override
  String get says => 'scale';

  @override
  Map<String, Object?> get arguments => <String, Object?>{'by': by};

  @override
  Outcome apply(ModelProject project, ProjectSelection selection) {
    if (by == 0) {
      // Refused rather than applied: a scale of zero flattens an object into a
      // plane it can never be scaled back out of, because every later scale
      // multiplies by nothing.
      return Outcome.refused('a scale of zero would flatten the object');
    }
    return _aboutTheMiddle(
      project,
      selection,
      'scale',
      () => Matrix4.diagonal3(Vector3.all(by)),
    );
  }
}

/// Applies [build] to everything selected, about the middle of the selection.
///
/// **About the middle rather than each object's own origin.** Three objects
/// turned ninety degrees each about themselves stay where they are and face
/// differently; turned about the middle of the three they swing round each
/// other, which is what a person watching the gizmo expects. Blender, Maya and
/// every other modeller do the second.
Outcome _aboutTheMiddle(
  ModelProject project,
  ProjectSelection selection,
  String what,
  Matrix4 Function() build,
) {
  if (selection.objects.isEmpty) {
    return Outcome.refused('nothing is selected to $what');
  }
  final middle = Vector3.zero();
  var counted = 0;
  for (final int id in selection.objects) {
    final object = project[id];
    if (object == null) continue;
    middle.add(object.transform.getTranslation());
    counted++;
  }
  if (counted == 0) return Outcome.refused('nothing is selected to $what');
  middle.scale(1 / counted);

  // Written in steps because `Matrix4 * Matrix4` is declared to return
  // `dynamic` in vector_math, and a chain of them is a chain of dynamic calls
  // that the analyser is right to complain about: one wrong operand type and
  // the failure arrives at run time as a matrix full of NaN.
  final Matrix4 about = Matrix4.translation(middle);
  about.multiply(build());
  about.multiply(Matrix4.translation(-middle));
  var next = project;
  for (final int id in selection.objects) {
    final object = next[id];
    if (object == null) continue;
    final Matrix4 moved = Matrix4.copy(about)..multiply(object.transform);
    next = next.withObject(object.copyWith(transform: moved));
  }
  return Outcome.done(next);
}
