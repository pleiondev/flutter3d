/// The commands over one object's own [ShapeSet] — `anim-19`'s own row.
///
/// A `part` of `command.dart` for the reason every other command file
/// gives: [ModelCommand] is sealed, and a journal writer's exhaustive
/// `switch` is only exhaustive if the compiler can see every case inside
/// one library.
///
/// **What is not here.** The row's own "строки экрана 15" (a panel) and
/// the golden frame `modeler-morphs` are both app-layer, outside a command
/// file's own scope — see `HANDOFF.md` for why this row stays `partial`.
part of 'command.dart';

/// The object [id] names, and its shape set — or the sentence to refuse
/// with.
({ModelObject? object, String? refused}) _shapeTarget(
  ModelProject project,
  int id,
) {
  final object = project[id];
  if (object == null) return (object: null, refused: 'there is no object $id');
  return (object: object, refused: null);
}

/// Sets [shapeIndex]'s current preview weight to [weight] on [id]'s own
/// shape set — a live value, blended by [ShapeKey.blend] wherever the
/// object is drawn, not a keyframe; [KeyShape] is what records one of
/// those, from whatever this last set.
final class SetShapeWeight extends ModelCommand {
  const SetShapeWeight({
    required this.id,
    required this.shapeIndex,
    required this.weight,
  });

  final int id;
  final int shapeIndex;
  final double weight;

  @override
  String get name => 'setShapeWeight';

  @override
  String get says => 'change a shape key\'s weight';

  @override
  Map<String, Object?> get arguments => <String, Object?>{
    'id': id,
    'shapeIndex': shapeIndex,
    'weight': weight,
  };

  @override
  Outcome apply(ModelProject project, ProjectSelection selection) {
    final (:object, :refused) = _shapeTarget(project, id);
    if (object == null) return Outcome.refused(refused!);
    final shapes = object.shapeSet;
    if (shapeIndex < 0 || shapeIndex >= shapes.keys.length) {
      return Outcome.refused(
        '"${object.name}" has ${shapes.keys.length} shape keys; $shapeIndex is '
        'not one of them',
      );
    }
    final weights = List<double>.of(shapes.weights)..[shapeIndex] = weight;
    return Outcome.done(
      project.withObject(
        object.copyWith(shapeSet: shapes.copyWith(weights: weights)),
      ),
    );
  }
}

/// Adds a new shape key to [id]'s own shape set, seeded from the object's
/// *current* mesh positions — the standard "sculpt it, then capture it"
/// shape-key workflow, `ShapeKey`'s constructor read straight off
/// [EditMesh.positionOf] rather than from anywhere a caller has to build a
/// `Float32List` by hand first.
final class AddShapeFromMesh extends ModelCommand {
  const AddShapeFromMesh({required this.id, required this.shapeName});

  final int id;
  final String shapeName;

  @override
  String get name => 'addShapeFromMesh';

  @override
  String get says => 'add a shape key from the mesh';

  @override
  Map<String, Object?> get arguments => <String, Object?>{
    'id': id,
    'shapeName': shapeName,
  };

  @override
  Outcome apply(ModelProject project, ProjectSelection selection) {
    final (:object, :refused) = _shapeTarget(project, id);
    if (object == null) return Outcome.refused(refused!);
    if (object.geometry case EditedGeometry(:final mesh)) {
      final positions = Float32List(mesh.vertexSlotCount * 3);
      final position = Vector3.zero();
      for (var v = 0; v < mesh.vertexSlotCount; v++) {
        mesh.positionOf(v, position);
        positions[v * 3] = position.x;
        positions[v * 3 + 1] = position.y;
        positions[v * 3 + 2] = position.z;
      }
      final shapes = object.shapeSet;
      return Outcome.done(
        project.withObject(
          object.copyWith(
            shapeSet: shapes.copyWith(
              keys: <ShapeKey>[...shapes.keys, ShapeKey(shapeName, positions)],
              weights: <double>[...shapes.weights, 0.0],
            ),
          ),
        ),
      );
    }
    return Outcome.refused(
      '"${object.name}" has no mesh to sculpt a shape from',
    );
  }
}

/// Renames [shapeIndex] in [id]'s own shape set.
final class RenameShape extends ModelCommand {
  const RenameShape({
    required this.id,
    required this.shapeIndex,
    required this.to,
  });

  final int id;
  final int shapeIndex;
  final String to;

  @override
  String get name => 'renameShape';

  @override
  String get says => 'rename a shape key to "$to"';

  @override
  Map<String, Object?> get arguments => <String, Object?>{
    'id': id,
    'shapeIndex': shapeIndex,
    'to': to,
  };

  @override
  Outcome apply(ModelProject project, ProjectSelection selection) {
    final (:object, :refused) = _shapeTarget(project, id);
    if (object == null) return Outcome.refused(refused!);
    final shapes = object.shapeSet;
    if (shapeIndex < 0 || shapeIndex >= shapes.keys.length) {
      return Outcome.refused(
        '"${object.name}" has ${shapes.keys.length} shape keys; $shapeIndex is '
        'not one of them',
      );
    }
    if (to.trim().isEmpty) {
      return Outcome.refused('a shape key needs a name');
    }
    final keys = List<ShapeKey>.of(shapes.keys);
    final old = keys[shapeIndex];
    final positions = Float32List(old.vertexCount * 3);
    final position = Vector3.zero();
    for (var v = 0; v < old.vertexCount; v++) {
      position.setFrom(old.positionOf(v));
      positions[v * 3] = position.x;
      positions[v * 3 + 1] = position.y;
      positions[v * 3 + 2] = position.z;
    }
    keys[shapeIndex] = ShapeKey(to, positions);
    return Outcome.done(
      project.withObject(
        object.copyWith(shapeSet: shapes.copyWith(keys: keys)),
      ),
    );
  }
}

/// Removes [shapeIndex] from [id]'s own shape set, shifting every later
/// shape's index down by one — and, in every clip, dropping that same
/// component from any `weights` track driving this object, so a track built
/// for four shapes comes out driving three rather than reading one of
/// them's slot as whatever the deleted shape's neighbour now occupies.
///
/// [id]'s own [ModelObject.shapeDrivers] move the same way, in this same
/// step: a driver naming the deleted [shapeIndex] is dropped along with the
/// shape it had nothing left to drive, and a driver naming a later shape has
/// its own [ShapeDriver.shapeIndex] shifted down by one — `anim-34d`'s own
/// row, done here rather than as a second command so a shape and its own
/// driver leave the document in one undo step, never a shape gone and a
/// driver still pointing at whatever now sits in its old slot.
final class DeleteShape extends ModelCommand {
  const DeleteShape({required this.id, required this.shapeIndex});

  final int id;
  final int shapeIndex;

  @override
  String get name => 'deleteShape';

  @override
  String get says => 'delete a shape key';

  @override
  Map<String, Object?> get arguments => <String, Object?>{
    'id': id,
    'shapeIndex': shapeIndex,
  };

  @override
  Outcome apply(ModelProject project, ProjectSelection selection) {
    final (:object, :refused) = _shapeTarget(project, id);
    if (object == null) return Outcome.refused(refused!);
    final shapes = object.shapeSet;
    if (shapeIndex < 0 || shapeIndex >= shapes.keys.length) {
      return Outcome.refused(
        '"${object.name}" has ${shapes.keys.length} shape keys; $shapeIndex is '
        'not one of them',
      );
    }
    final keys = List<ShapeKey>.of(shapes.keys)..removeAt(shapeIndex);
    final weights = List<double>.of(shapes.weights)..removeAt(shapeIndex);
    final drivers = <ShapeDriver>[
      for (final driver in object.shapeDrivers)
        if (driver.shapeIndex != shapeIndex)
          driver.shapeIndex > shapeIndex
              ? driver.copyWith(shapeIndex: driver.shapeIndex - 1)
              : driver,
    ];
    final next = object.copyWith(
      shapeSet: shapes.copyWith(keys: keys, weights: weights),
      shapeDrivers: drivers,
    );

    final clips = <ProjectClip>[
      for (final clip in project.clips)
        ProjectClip(
          name: clip.name,
          extras: clip.extras,
          tracks: <ProjectTrack>[
            for (final track in clip.tracks)
              if (track.objectId == id &&
                  track.track.path == AnimationPath.weights)
                ...?_withComponentDropped(track, shapeIndex)
              else
                track,
          ],
        ),
    ];

    return Outcome.done(project.withObject(next).copyWith(clips: clips));
  }
}

/// [track] with component [dropped] removed from every key's values and
/// tangents, or `null` when that was the track's only component — a
/// `weights` track with nothing left to drive is not a track, it is a
/// leftover.
List<ProjectTrack>? _withComponentDropped(ProjectTrack track, int dropped) {
  final table = KeyTable.fromAnimationTrack(track.track);
  if (dropped < 0 || dropped >= table.componentCount) {
    return <ProjectTrack>[track];
  }
  if (table.componentCount <= 1) return null;

  List<double>? without(List<double>? values) {
    if (values == null) return null;
    return List<double>.of(values)..removeAt(dropped);
  }

  final shrunk = KeyTable(
    componentCount: table.componentCount - 1,
    interpolation: table.interpolation,
    keys: <Key>[
      for (final key in table.keys)
        Key(
          time: key.time,
          values: without(key.values)!,
          inTangent: without(key.inTangent),
          outTangent: without(key.outTangent),
        ),
    ],
  );
  return <ProjectTrack>[
    ProjectTrack(
      objectId: track.objectId,
      track: shrunk.toAnimationTrack(
        nodeIndex: track.track.nodeIndex,
        path: AnimationPath.weights,
      ),
    ),
  ];
}

/// Records [id]'s own *current* shape weights as a keyframe at [time], in
/// clip [clipIndex] — `KeyShape`'s own row, an auto-key from whatever
/// [SetShapeWeight] last set rather than a value handed in separately, the
/// same "capture the live state" shape every auto-key in this plan takes.
///
/// Creates the object's `weights` track in that clip when it does not have
/// one yet, sized to the shape set's own current key count.
final class KeyShape extends ModelCommand {
  const KeyShape({
    required this.id,
    required this.clipIndex,
    required this.time,
  });

  final int id;
  final int clipIndex;
  final double time;

  @override
  String get name => 'keyShape';

  @override
  String get says => 'key the shape weights';

  @override
  Map<String, Object?> get arguments => <String, Object?>{
    'id': id,
    'clipIndex': clipIndex,
    'time': time,
  };

  @override
  Outcome apply(ModelProject project, ProjectSelection selection) {
    final (:object, :refused) = _shapeTarget(project, id);
    if (object == null) return Outcome.refused(refused!);
    if (clipIndex < 0 || clipIndex >= project.clips.length) {
      return Outcome.refused('there is no clip $clipIndex');
    }
    final shapes = object.shapeSet;
    if (shapes.keys.isEmpty) {
      return Outcome.refused('"${object.name}" has no shape keys to key');
    }

    final clip = project.clips[clipIndex];
    final existingIndex = clip.tracks.indexWhere(
      (t) => t.objectId == id && t.track.path == AnimationPath.weights,
    );
    final table = existingIndex >= 0
        ? KeyTable.fromAnimationTrack(clip.tracks[existingIndex].track)
        : KeyTable(componentCount: shapes.keys.length);
    if (table.componentCount != shapes.keys.length) {
      return Outcome.refused(
        'the weights track has ${table.componentCount} components and '
        '"${object.name}" now has ${shapes.keys.length} shape keys',
      );
    }
    table.setKey(time, List<double>.of(shapes.weights));

    final newTrack = ProjectTrack(
      objectId: id,
      track: table.toAnimationTrack(nodeIndex: 0, path: AnimationPath.weights),
    );
    final tracks = List<ProjectTrack>.of(clip.tracks);
    if (existingIndex >= 0) {
      tracks[existingIndex] = newTrack;
    } else {
      tracks.add(newTrack);
    }
    final clips = List<ProjectClip>.of(project.clips)
      ..[clipIndex] = ProjectClip(
        name: clip.name,
        extras: clip.extras,
        tracks: tracks,
      );

    return Outcome.done(project.copyWith(clips: clips));
  }
}

/// Adds [driver] to [id]'s own [ModelObject.shapeDrivers] — `anim-34d`'s own
/// row, the project-side half of a shape key that tracks a joint's rotation
/// instead of a person's slider. [ShapeDriver.shapeIndex] has to name one of
/// [id]'s own current shape keys and [ShapeDriver.jointId] one of the
/// project's own objects, the same two things a driver evaluated against a
/// live clip (`shape_driver.dart`'s own `evaluateShapeDriversLive`) would
/// otherwise silently read as "nothing" for.
final class AddShapeDriver extends ModelCommand {
  const AddShapeDriver({required this.id, required this.driver});

  final int id;
  final ShapeDriver driver;

  @override
  String get name => 'addShapeDriver';

  @override
  String get says => 'add a shape driver';

  @override
  Map<String, Object?> get arguments => <String, Object?>{
    'id': id,
    'driver': driver.toJson(),
  };

  @override
  Outcome apply(ModelProject project, ProjectSelection selection) {
    final (:object, :refused) = _shapeTarget(project, id);
    if (object == null) return Outcome.refused(refused!);
    final shapes = object.shapeSet;
    if (driver.shapeIndex < 0 || driver.shapeIndex >= shapes.keys.length) {
      return Outcome.refused(
        '"${object.name}" has ${shapes.keys.length} shape keys; '
        '${driver.shapeIndex} is not one of them',
      );
    }
    if (project[driver.jointId] == null) {
      return Outcome.refused('there is no object ${driver.jointId}');
    }
    return Outcome.done(
      project.withObject(
        object.copyWith(
          shapeDrivers: <ShapeDriver>[...object.shapeDrivers, driver],
        ),
      ),
    );
  }
}

/// Removes [index] from [id]'s own [ModelObject.shapeDrivers], shifting
/// every later driver's own index down by one — the same "index into a
/// list" shape [DeleteShape] and [RemoveModifier] already give their own
/// stacks. Unlike [DeleteShape], nothing else in the document names a
/// driver by its position, so there is nothing further to shift.
final class RemoveShapeDriver extends ModelCommand {
  const RemoveShapeDriver({required this.id, required this.index});

  final int id;
  final int index;

  @override
  String get name => 'removeShapeDriver';

  @override
  String get says => 'remove a shape driver';

  @override
  Map<String, Object?> get arguments => <String, Object?>{
    'id': id,
    'index': index,
  };

  @override
  Outcome apply(ModelProject project, ProjectSelection selection) {
    final (:object, :refused) = _shapeTarget(project, id);
    if (object == null) return Outcome.refused(refused!);
    final drivers = object.shapeDrivers;
    if (index < 0 || index >= drivers.length) {
      return Outcome.refused(
        '"${object.name}" has ${drivers.length} shape drivers; $index is '
        'not one of them',
      );
    }
    final next = List<ShapeDriver>.of(drivers)..removeAt(index);
    return Outcome.done(
      project.withObject(object.copyWith(shapeDrivers: next)),
    );
  }
}

/// [driver] with [field] set to [value], or null when [field] does not name
/// one of [ShapeDriver]'s own fields or [value] is the wrong shape for it —
/// the same contract `_modifierFieldSet` keeps for a modifier's own fields.
ShapeDriver? _shapeDriverFieldSet(
  ShapeDriver driver,
  String field,
  Object? value,
) => switch (field) {
  'shapeIndex' => value is int ? driver.copyWith(shapeIndex: value) : null,
  'jointId' => value is int ? driver.copyWith(jointId: value) : null,
  'axis' => switch (value) {
    'x' => driver.copyWith(axis: DriverAxis.x),
    'y' => driver.copyWith(axis: DriverAxis.y),
    'z' => driver.copyWith(axis: DriverAxis.z),
    _ => null,
  },
  'from' => value is num ? driver.copyWith(from: value.toDouble()) : null,
  'to' => value is num ? driver.copyWith(to: value.toDouble()) : null,
  _ => null,
};

/// Changes one [field] of the shape driver at [index] on [id]'s own
/// [ModelObject.shapeDrivers] — `anim-34d`'s own generic setter, the same
/// shape [SetModifierField] gives a modifier's own fields.
///
/// **[from]/[to] stay radians all the way through.** [hints] labels them
/// `rad` for the same reason `RotateBy`'s own `radians` argument does; a
/// panel showing degrees (screen 15, `T4.5`'s own row) converts at its own
/// edge the way `transform_fields.dart` already does for a turn, rather
/// than this command ever holding, journaling or replaying anything but the
/// angle the maths itself uses.
final class SetShapeDriverField extends ModelCommand {
  const SetShapeDriverField({
    required this.id,
    required this.index,
    required this.field,
    required this.value,
  });

  final int id;
  final int index;
  final String field;
  final Object? value;

  @override
  String get name => 'setShapeDriverField';

  @override
  String get says => 'set $field';

  @override
  Map<String, Object?> get arguments => <String, Object?>{
    'id': id,
    'index': index,
    'field': field,
    'value': value,
  };

  @override
  Map<String, ParamHint> get hints => switch (field) {
    'from' || 'to' => const <String, ParamHint>{
      'value': DoubleHint(unit: 'rad', step: 0.01),
    },
    'axis' => const <String, ParamHint>{
      'value': EnumHint(<String>['x', 'y', 'z']),
    },
    _ => const <String, ParamHint>{},
  };

  @override
  Outcome apply(ModelProject project, ProjectSelection selection) {
    final (:object, :refused) = _shapeTarget(project, id);
    if (object == null) return Outcome.refused(refused!);
    final drivers = object.shapeDrivers;
    if (index < 0 || index >= drivers.length) {
      return Outcome.refused(
        '"${object.name}" has ${drivers.length} shape drivers; $index is '
        'not one of them',
      );
    }
    final next = _shapeDriverFieldSet(drivers[index], field, value);
    if (next == null) {
      return Outcome.refused(
        '"$field" is not a field of a shape driver, or its value is the '
        'wrong shape',
      );
    }
    final updated = List<ShapeDriver>.of(drivers)..[index] = next;
    return Outcome.done(
      project.withObject(object.copyWith(shapeDrivers: updated)),
    );
  }
}
