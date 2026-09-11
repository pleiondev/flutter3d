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

  @override
  Map<String, ParamHint> get hints => const <String, ParamHint>{
    'size': DoubleHint(min: 0.001, step: 0.1, unit: 'm'),
    'segments': IntHint(min: 3, max: 256),
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

/// Adds a shape turned from a profile on the (radius, height) half-plane.
///
/// **Separate from [AddPrimitive] because a lathe has no size.** Every other
/// primitive answers one number and a segment count; a lathe answers a list of
/// points, which is the thing a profile editor draws and the thing nothing else
/// in the menu takes. Folding it into the primitive kinds would give that
/// command an argument that is meaningless for five of its six values.
///
/// **A glass, a bottle, a chair leg and a plate are one shape here**, and that
/// is why it earns a command of its own rather than waiting for a mesh: turning
/// the profile is exactly the operation somebody wants to adjust after seeing
/// it, and a parametric object is the only kind that can be adjusted.
final class AddLathe extends ModelCommand {
  const AddLathe({
    required this.profile,
    this.segments = 32,
    this.closedProfile = false,
    this.shapeName = 'lathe',
    this.at,
  });

  /// Points in the (radius, height) half-plane, bottom to top.
  final List<Vector2> profile;
  final int segments;

  /// Whether the last point joins back to the first, as a torus's does.
  final bool closedProfile;

  /// What the object is called, and what the shape calls itself: a glass and a
  /// chair leg are the same operation, and the only thing that tells them apart
  /// in an outliner is the word somebody chose.
  final String shapeName;

  /// Where it goes, or the origin.
  final Vector3? at;

  @override
  String get name => 'addLathe';

  @override
  String get says => 'add a $shapeName';

  @override
  Map<String, Object?> get arguments => <String, Object?>{
    'profile': <List<double>>[
      for (final Vector2 point in profile) <double>[point.x, point.y],
    ],
    'segments': segments,
    'closedProfile': closedProfile,
    // `label` and not `name`, because `toJson` writes the command's own name
    // under that key and spreads these over it: a lathe that called its word
    // `name` would write itself down as a command called "glass", which
    // nothing reads back.
    'label': shapeName,
    if (at case final Vector3 where) 'at': <double>[where.x, where.y, where.z],
  };

  @override
  Map<String, ParamHint> get hints => const <String, ParamHint>{
    'segments': IntHint(min: 3, max: 256),
    'closedProfile': BoolHint(),
  };

  @override
  Outcome apply(ModelProject project, ProjectSelection selection) {
    if (profile.length < 2) {
      return Outcome.refused(
        'a profile needs at least two points to turn into a surface',
      );
    }
    if (segments < 3) {
      return Outcome.refused('a turn of fewer than three segments is a fan');
    }
    if (profile.any((Vector2 point) => point.x < 0)) {
      return Outcome.refused(
        'a profile point at a negative radius would turn the surface through '
        'its own axis',
      );
    }
    final next = project.added(
      (int id) => ModelObject(
        id: id,
        name: shapeName,
        geometry: ParametricGeometry(
          ParametricLathe(
            profile: List<Vector2>.unmodifiable(profile),
            segments: segments,
            closedProfile: closedProfile,
            name: shapeName,
          ),
        ),
        transform: Matrix4.translation(at ?? Vector3.zero()),
      ),
    );
    return Outcome.done(
      next,
      selection: selection.copyWith(objects: <int>[next.objects.last.id]),
    );
  }
}

/// Replaces the parameters of a shape that still has them.
///
/// **This is the operation card, and it is why parametric objects exist at
/// all.** A cylinder that came back from a file knowing it is a cylinder of
/// thirty-two segments can be made one of forty-eight; a cylinder that came
/// back as faces cannot. `ModelHistory.amend` re-runs this against the document
/// as it was, so dragging a slider adjusts one step instead of leaving sixty.
///
/// **It refuses a mesh by name rather than baking one.** Somebody who converted
/// a shape and then reached for the card is asking for something the document
/// no longer holds, and quietly replacing their edited geometry with a fresh
/// primitive would throw the edit away with no step of history to say so.
final class SetParametric extends ModelCommand {
  const SetParametric({required this.id, required this.to});

  final int id;
  final ParametricShape to;

  @override
  String get name => 'setParametric';

  @override
  String get says => 'change the ${to.name}';

  @override
  Map<String, Object?> get arguments => <String, Object?>{
    'id': id,
    'to': parametricShapeJson(to),
  };

  @override
  Outcome apply(ModelProject project, ProjectSelection selection) {
    final ModelObject? object = project[id];
    if (object == null) return Outcome.refused('there is no object $id');
    return switch (object.geometry) {
      ParametricGeometry() => Outcome.done(
        project.withObject(object.copyWith(geometry: ParametricGeometry(to))),
      ),
      EditedGeometry() => Outcome.refused(
        '"${object.name}" is a mesh now, and a mesh has no parameters to set',
      ),
      ImportedGeometry() => Outcome.refused(
        '"${object.name}" came from a file and was never described by numbers',
      ),
    };
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

/// Turns everything selected.
final class RotateBy extends ModelCommand {
  const RotateBy({
    required this.axis,
    required this.radians,
    this.pivot = TransformPivot.median,
    this.space = TransformSpace.global,
  });

  final Vector3 axis;
  final double radians;

  /// The point the turn happens about.
  final TransformPivot pivot;

  /// Whose axes [axis] is given in.
  final TransformSpace space;

  @override
  String get name => 'rotateBy';

  @override
  String get says => 'turn';

  @override
  Map<String, Object?> get arguments => <String, Object?>{
    'axis': <double>[axis.x, axis.y, axis.z],
    'radians': radians,
    'pivot': pivot.name,
    'space': space.name,
  };

  @override
  Map<String, ParamHint> get hints => <String, ParamHint>{
    'axis': const Vector3Hint(step: 0.01),
    'radians': const DoubleHint(unit: 'rad', step: 0.01),
    'pivot': EnumHint(<String>[for (final p in TransformPivot.values) p.name]),
    'space': EnumHint(<String>[for (final s in TransformSpace.values) s.name]),
  };

  @override
  Outcome apply(ModelProject project, ProjectSelection selection) =>
      _aboutThePivot(
        project,
        selection,
        'turn',
        pivot: pivot,
        space: space,
        build: () => Matrix4.compose(
          Vector3.zero(),
          Quaternion.axisAngle(axis, radians),
          Vector3.all(1),
        ),
      );
}

/// Scales everything selected.
///
/// **No [TransformSpace] here, and that is arithmetic rather than an
/// omission.** [by] is one number, so the matrix it builds is a multiple of the
/// identity — and sandwiching that in any basis gives it back unchanged, since
/// `R · sI · R⁻¹` is `sI` for every rotation there is. An argument that
/// provably cannot change the answer is one an agent would set and then wonder
/// why nothing moved. The day a scale takes three numbers it will need one.
final class ScaleBy extends ModelCommand {
  const ScaleBy(this.by, {this.pivot = TransformPivot.median});

  final double by;

  /// The point the scale happens about.
  final TransformPivot pivot;

  @override
  String get name => 'scaleBy';

  @override
  String get says => 'scale';

  @override
  Map<String, Object?> get arguments => <String, Object?>{
    'by': by,
    'pivot': pivot.name,
  };

  @override
  Map<String, ParamHint> get hints => <String, ParamHint>{
    'by': const DoubleHint(min: 0.001, step: 0.01),
    'pivot': EnumHint(<String>[for (final p in TransformPivot.values) p.name]),
  };

  @override
  Outcome apply(ModelProject project, ProjectSelection selection) {
    if (by == 0) {
      // Refused rather than applied: a scale of zero flattens an object into a
      // plane it can never be scaled back out of, because every later scale
      // multiplies by nothing.
      return Outcome.refused('a scale of zero would flatten the object');
    }
    return _aboutThePivot(
      project,
      selection,
      'scale',
      pivot: pivot,
      build: () => Matrix4.diagonal3(Vector3.all(by)),
    );
  }
}

/// Applies [build] to everything selected, about [pivot] and along [space]'s
/// axes.
///
/// **[TransformPivot.median] is the default because it is what a person
/// watching the gizmo expects.** Three objects turned ninety degrees each about
/// themselves stay where they are and face differently; turned about the middle
/// of the three they swing round each other, and the gizmo sitting at that
/// middle is the promise that they will. [TransformPivot.individual] is the
/// other answer, and it is a real one — laying out a row of chairs and turning
/// every one of them to face the same way is exactly it.
///
/// The middle is walked for even when the pivot is individual, because a
/// selection all of whose objects have gone has to refuse rather than quietly
/// do nothing, and counting them is how that is known. That selection does not
/// arrive from [ModelHistory], which filters through `ProjectSelection.within`
/// before a command sees anything — it arrives from an agent's tool call or a
/// journal entry replayed against a project that has moved on, which is where
/// [ModelCommand.apply] is called with a selection nobody has checked. Without
/// the count the division is by nothing, the middle comes out as NaN, and the
/// command reports success on a project it did not touch.
Outcome _aboutThePivot(
  ModelProject project,
  ProjectSelection selection,
  String what, {
  required TransformPivot pivot,
  required Matrix4 Function() build,
  TransformSpace space = TransformSpace.global,
}) {
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

  var next = project;
  for (final int id in selection.objects) {
    final object = next[id];
    if (object == null) continue;
    final Vector3 about = switch (pivot) {
      TransformPivot.median => middle,
      TransformPivot.individual => object.transform.getTranslation(),
    };
    final Matrix4 moved = _sandwiched(
      about,
      space == TransformSpace.local ? _basisOf(object.transform) : null,
      build(),
    )..multiply(object.transform);
    next = next.withObject(object.copyWith(transform: moved));
  }
  return Outcome.done(next);
}

/// Where an object's own origin sits, for [SetOrigin].
///
/// **Three because three is what a person actually asks for.** The middle of
/// the bounds is what a spin wants; the middle of the bottom is what anything
/// standing on a floor wants, and it is the one an engine expects of a prop;
/// the world origin is how a model that was authored off-centre gets put back
/// where the exporter assumes it is.
enum OriginPlacement { boundsCentre, boundsBottom, worldOrigin }

/// Moves an object's origin without moving the object.
///
/// **What "set origin" means, said in one line: the geometry moves one way and
/// the node moves the other.** Everything a person can see stays exactly where
/// it was — the point of the operation is the pivot the next rotation turns
/// about, and a pivot that moved the model as well would be a pivot nobody
/// could aim.
///
/// **Children are compensated, and that is not optional.** A child's transform
/// is local to its parent, so pushing a translation into the parent's node
/// would carry every child along with it — the wheels would follow the car's
/// pivot to the middle of the car. Each direct child gets the inverse of the
/// same step, and everything under it comes along for free.
///
/// **It refuses a shape that still knows its parameters**, for the reason every
/// mesh command does: a cylinder's origin is part of what a cylinder is, and
/// moving the vertices out from under the radius leaves a description that no
/// longer describes the thing.
final class SetOrigin extends ModelCommand {
  const SetOrigin({required this.id, this.to = OriginPlacement.boundsCentre});

  final int id;
  final OriginPlacement to;

  @override
  String get name => 'setOrigin';

  @override
  String get says => 'set the origin';

  @override
  Map<String, Object?> get arguments => <String, Object?>{
    'id': id,
    'to': to.name,
  };

  @override
  Outcome apply(ModelProject project, ProjectSelection selection) {
    final found = _editableObject(project, id);
    if (found.refused != null) return Outcome.refused(found.refused!);
    final ModelObject object = found.object!;
    final EditMesh mesh = found.mesh!;

    final Selection vertices = _everything(mesh, ElementLevel.vertex);
    if (vertices.isEmpty) {
      return Outcome.refused('"${object.name}" has no geometry to sit in');
    }

    final Vector3 origin = switch (to) {
      OriginPlacement.worldOrigin => -object.transform.getTranslation(),
      _ => _localOrigin(
        mesh,
        vertices,
        bottom: to == OriginPlacement.boundsBottom,
      ),
    };
    if (origin.length2 < 1e-20) {
      return Outcome.refused('the origin of "${object.name}" is already there');
    }

    mesh.beginStep();
    final OpResult moved = translateSelection(mesh, vertices, by: -origin);
    if (!moved.ok) {
      if (mesh.endStep()) mesh.undo();
      return Outcome.refused(moved.reason!);
    }
    mesh.endStep();

    final Matrix4 node = object.transform.clone()
      ..multiply(Matrix4.translation(origin));
    var next = project.withObject(
      object.copyWith(geometry: EditedGeometry(mesh), transform: node),
    );
    next = _compensateChildren(next, id, Matrix4.translation(-origin));

    return Outcome.done(next, meshTouched: mesh);
  }

  /// The point in the mesh's own coordinates that the origin should move to.
  static Vector3 _localOrigin(
    EditMesh mesh,
    Selection vertices, {
    required bool bottom,
  }) {
    final at = Vector3.zero();
    final Vector3 low = Vector3.all(double.infinity);
    final Vector3 high = Vector3.all(double.negativeInfinity);
    for (final int vertex in vertices.ids) {
      mesh.positionOf(vertex, at);
      Vector3.min(low, at, low);
      Vector3.max(high, at, high);
    }
    final Vector3 centre = (low + high) * 0.5;
    return bottom ? Vector3(centre.x, low.y, centre.z) : centre;
  }
}

/// Bakes an object's transform into its geometry and stands the node at the
/// world's own axes.
///
/// **The step before an export, and the one everybody forgets.** An engine that
/// reads a node's scale and a physics shape that does not are the commonest
/// pair of disagreeing readers there is, and a model whose transform is the
/// identity cannot be read two ways.
///
/// **A mirrored transform turns the surface inside out, and this puts it
/// back.** A scale with a negative determinant reverses the winding of every
/// face; leaving it would give a model that looks right in the viewport, where
/// the transform is still being applied, and inside out the moment anything
/// reads the vertices on their own.
final class ApplyTransform extends ModelCommand {
  const ApplyTransform(this.id);

  final int id;

  @override
  String get name => 'applyTransform';

  @override
  String get says => 'apply the transform';

  @override
  Map<String, Object?> get arguments => <String, Object?>{'id': id};

  @override
  Outcome apply(ModelProject project, ProjectSelection selection) {
    final found = _editableObject(project, id);
    if (found.refused != null) return Outcome.refused(found.refused!);
    final ModelObject object = found.object!;
    final EditMesh mesh = found.mesh!;

    final Matrix4 node = object.transform;
    if (_isIdentity(node)) {
      return Outcome.refused(
        '"${object.name}" already stands in the world\'s own axes',
      );
    }

    final Selection vertices = _everything(mesh, ElementLevel.vertex);
    if (vertices.isEmpty) {
      return Outcome.refused('"${object.name}" has no geometry to bake into');
    }

    mesh.beginStep();
    final OpResult moved = transformSelection(mesh, vertices, by: node);
    if (!moved.ok) {
      if (mesh.endStep()) mesh.undo();
      return Outcome.refused(moved.reason!);
    }
    if (node.determinant() < 0) mesh.flipNormals();
    mesh.endStep();

    var next = project.withObject(
      object.copyWith(
        geometry: EditedGeometry(mesh),
        transform: Matrix4.identity(),
      ),
    );
    next = _compensateChildren(next, id, node);

    return Outcome.done(next, meshTouched: mesh);
  }
}

/// The object [id] with a mesh of its own, or the sentence to refuse with.
///
/// The same four questions `_meshTarget` asks, against a named object rather
/// than against the selection: these two commands act on the object a person
/// pointed at in the outliner, which is not always the one the mesh mode is in.
({ModelObject? object, EditMesh? mesh, String? refused}) _editableObject(
  ModelProject project,
  int id,
) {
  final ModelObject? object = project[id];
  if (object == null) {
    return (object: null, mesh: null, refused: 'there is no object $id');
  }
  return switch (object.geometry) {
    EditedGeometry(:final mesh) => (object: object, mesh: mesh, refused: null),
    ParametricGeometry(:final shape) => (
      object: null,
      mesh: null,
      refused:
          '"${object.name}" is still a ${shape.name}, and its origin is part '
          'of what that means. Convert it to a mesh first',
    ),
    ImportedGeometry() => (
      object: null,
      mesh: null,
      refused: '"${object.name}" came from a file and has no vertices to move',
    ),
  };
}

/// [project] with every direct child of [parent] pre-multiplied by [by], so
/// that a change to the parent's node leaves the children where they are.
ModelProject _compensateChildren(ModelProject project, int parent, Matrix4 by) {
  var next = project;
  for (final ModelObject child in project.objects) {
    if (child.parent != parent) continue;
    next = next.withObject(
      child.copyWith(transform: by.clone()..multiply(child.transform)),
    );
  }
  return next;
}

/// Whether [matrix] is the identity, to within what single-precision positions
/// can tell apart.
bool _isIdentity(Matrix4 matrix) {
  final Matrix4 unit = Matrix4.identity();
  for (var i = 0; i < 16; i++) {
    if ((matrix[i] - unit[i]).abs() > 1e-9) return false;
  }
  return true;
}
