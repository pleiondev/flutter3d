/// The commands that change a project's own [SceneLighting].
///
/// **The same index-addressed shape [material_commands.dart] uses for its
/// own table**, for the same reason: a light has no id of its own, nothing
/// ever names one out of order, and a row that is only ever appended or
/// collapsed is a row a caller can predict without being handed one back.
part of 'command.dart';

/// Adds a light to the project's own lighting, with nothing lit in
/// particular.
final class AddLight extends ModelCommand {
  const AddLight({this.type = ProjectLightType.directional});

  final ProjectLightType type;

  @override
  String get name => 'addLight';

  @override
  String get says => 'add a light';

  @override
  Map<String, Object?> get arguments => <String, Object?>{'type': type.name};

  @override
  Outcome apply(ModelProject project, ProjectSelection selection) =>
      Outcome.done(
        project.copyWith(
          lighting: project.lighting.copyWith(
            lights: <ProjectLight>[
              ...project.lighting.lights,
              ProjectLight(type: type),
            ],
          ),
        ),
      );
}

/// Drops a light out of the project's own lighting.
///
/// **This is a document edit, not a scene edit.** The `LightNode` a synced
/// viewport built for it comes down the next time `LightingSync.sync` runs
/// against the project this command produced — this command itself never
/// touches a scene graph, the same way every command in this package
/// leaves the engine to whatever reads the document next.
final class RemoveLight extends ModelCommand {
  const RemoveLight(this.index);

  final int index;

  @override
  String get name => 'removeLight';

  @override
  String get says => 'remove a light';

  @override
  Map<String, Object?> get arguments => <String, Object?>{'index': index};

  @override
  Outcome apply(ModelProject project, ProjectSelection selection) {
    final List<ProjectLight> lights = project.lighting.lights;
    if (index < 0 || index >= lights.length) {
      return Outcome.refused('there is no light $index');
    }
    final next = List<ProjectLight>.of(lights)..removeAt(index);
    return Outcome.done(
      project.copyWith(lighting: project.lighting.copyWith(lights: next)),
    );
  }
}

/// Sets one field of one light by name.
///
/// **The same "reject rather than crash or silently drop" shape
/// [SetMaterialField] already gives its own fields** — see `_lightFieldSet`.
final class SetLightField extends ModelCommand {
  const SetLightField({
    required this.index,
    required this.field,
    required this.value,
  });

  final int index;
  final String field;

  /// A number, a string (`type`), a bool, or a list of three numbers
  /// (`color`), depending on [field]. See `_lightFieldSet` for which.
  final Object? value;

  @override
  String get name => 'setLightField';

  @override
  String get says => 'set $field';

  @override
  Map<String, Object?> get arguments => <String, Object?>{
    'index': index,
    'field': field,
    'value': value,
  };

  @override
  Outcome apply(ModelProject project, ProjectSelection selection) {
    final List<ProjectLight> lights = project.lighting.lights;
    if (index < 0 || index >= lights.length) {
      return Outcome.refused('there is no light $index');
    }
    final ProjectLight? next = _lightFieldSet(lights[index], field, value);
    if (next == null) {
      return Outcome.refused(
        '"$field" is not a light field, or its value is the wrong shape',
      );
    }
    return Outcome.done(
      project.copyWith(
        lighting: project.lighting.copyWith(
          lights: <ProjectLight>[
            for (var i = 0; i < lights.length; i++)
              i == index ? next : lights[i],
          ],
        ),
      ),
    );
  }
}

/// Puts a transform on one light, replacing whatever it had — the same
/// shape [SetTransform] gives an object, scoped to [SceneLighting.lights]'
/// own index addressing the way [RemoveLight] and [SetLightField] already
/// are.
///
/// **A dedicated command rather than a `SetLightField` case.** Every other
/// field `_lightFieldSet` dispatches on on is a number, a bool, or a
/// three-number colour; a transform is sixteen numbers read through
/// `_doubles(value, 16)` the same way [SetTransform] itself reads one, which
/// is a different shape from anything `SetLightField`'s `value` already
/// carries — mirroring `SetTransform` exactly keeps that reader in the one
/// place it already exists rather than teaching `_lightFieldSet` a second
/// one.
final class SetLightTransform extends ModelCommand {
  const SetLightTransform({required this.index, required this.to});

  final int index;
  final Matrix4 to;

  @override
  String get name => 'setLightTransform';

  @override
  String get says => 'move a light';

  @override
  Map<String, Object?> get arguments => <String, Object?>{
    'index': index,
    'to': to.storage.toList(),
  };

  @override
  Outcome apply(ModelProject project, ProjectSelection selection) {
    final List<ProjectLight> lights = project.lighting.lights;
    if (index < 0 || index >= lights.length) {
      return Outcome.refused('there is no light $index');
    }
    final ProjectLight next = lights[index].copyWith(
      transform: Matrix4.copy(to),
    );
    return Outcome.done(
      project.copyWith(
        lighting: project.lighting.copyWith(
          lights: <ProjectLight>[
            for (var i = 0; i < lights.length; i++)
              i == index ? next : lights[i],
          ],
        ),
      ),
    );
  }
}

/// Sets the project's own built-in sky.
final class SetEnvironment extends ModelCommand {
  const SetEnvironment(this.preset);

  final SceneEnvironmentPreset preset;

  @override
  String get name => 'setEnvironment';

  @override
  String get says => 'set the environment';

  @override
  Map<String, Object?> get arguments => <String, Object?>{
    'preset': preset.name,
  };

  @override
  Outcome apply(ModelProject project, ProjectSelection selection) =>
      Outcome.done(
        project.copyWith(
          lighting: project.lighting.copyWith(environment: preset),
        ),
      );
}

/// Sets one scene-wide lighting field by name — everything on
/// [SceneLighting] that is not a light or the environment: `ambientIntensity`,
/// `shadows`, `exposure`.
final class SetSceneLightingField extends ModelCommand {
  const SetSceneLightingField({required this.field, required this.value});

  final String field;
  final Object? value;

  @override
  String get name => 'setSceneLightingField';

  @override
  String get says => 'set $field';

  @override
  Map<String, Object?> get arguments => <String, Object?>{
    'field': field,
    'value': value,
  };

  @override
  Outcome apply(ModelProject project, ProjectSelection selection) {
    final SceneLighting? next = _sceneLightingFieldSet(
      project.lighting,
      field,
      value,
    );
    if (next == null) {
      return Outcome.refused(
        '"$field" is not a scene lighting field, or its value is the wrong '
        'shape',
      );
    }
    return Outcome.done(project.copyWith(lighting: next));
  }
}

ProjectLight? _lightFieldSet(ProjectLight l, String field, Object? value) {
  switch (field) {
    case 'type':
      if (value is! String) return null;
      for (final ProjectLightType t in ProjectLightType.values) {
        if (t.name == value) return l.copyWith(type: t);
      }
      return null;
    case 'color':
      return switch (_doubles(value, 3)) {
        final List<double> c => l.copyWith(color: Vector3(c[0], c[1], c[2])),
        _ => null,
      };
    case 'intensity':
      return value is num ? l.copyWith(intensity: value.toDouble()) : null;
    case 'range':
      return value is num ? l.copyWith(range: value.toDouble()) : null;
    case 'castsShadow':
      return value is bool ? l.copyWith(castsShadow: value) : null;
    case 'innerConeAngle':
      return value is num
          ? l.copyWith(innerConeAngle: value.toDouble())
          : null;
    case 'outerConeAngle':
      return value is num
          ? l.copyWith(outerConeAngle: value.toDouble())
          : null;
    default:
      return null;
  }
}

SceneLighting? _sceneLightingFieldSet(
  SceneLighting s,
  String field,
  Object? value,
) {
  switch (field) {
    case 'ambientIntensity':
      return value is num ? s.copyWith(ambientIntensity: value.toDouble()) : null;
    case 'shadows':
      return value is bool ? s.copyWith(shadows: value) : null;
    case 'exposure':
      return value is num ? s.copyWith(exposure: value.toDouble()) : null;
    default:
      return null;
  }
}
