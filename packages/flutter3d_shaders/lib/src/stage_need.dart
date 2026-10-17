/// Which of the engine's shader stages a project carries, and the refusal
/// when one it left out is asked for.
///
/// **One bundle for every application was 8.5 MB in every binary**, and 6 MB
/// of it lighting models most games never draw with: the layered PBR, the
/// toon, the Blinn-Phong and the Lambert, each twice. A project's build hook
/// now writes a bundle of the stages the project needs, and a need is
/// declared, not guessed: by a material that lights with a model, by the
/// project's manifest for what its settings switch on, by a plugin for what
/// it draws with. [ShaderStageNeed.base] is what every renderer reaches for
/// whatever it draws, and it is always carried.
///
/// **A stage left out is refused by name, not drawn as nothing.** The renderer
/// asks for a stage when it first draws with it; a stage the project's bundle
/// does not hold is a [MissingShaderStageException] that names the stage and
/// the need that brings it, which is the line to add to the manifest.
library;

import 'package:flutter3d_foundation/flutter3d_foundation.dart'
    show ResourceException;

import '../flutter3d_shaders.dart' show requiredShaders;

/// A set of shader stages something declares it needs: a lighting model, an
/// effect, a plugin's stages.
///
/// The engine's own are the static constants, named as a project's manifest
/// writes them (`shaders: [toon, pbrLayered]`). A plugin declares its own with
/// a name prefixed by its id, `<pluginId>.<name>`, as every registration of a
/// plugin is; a need is a value, so two with the same [name] are the same
/// need.
///
/// An open set: a minor release may add an engine need, and nothing switches
/// over the constants.
final class ShaderStageNeed {
  const ShaderStageNeed(this.name, this.stages);

  /// The need's wire name: what a manifest lists and a refusal names.
  final String name;

  /// The entry points it brings.
  final List<String> stages;

  /// What every renderer reaches for whatever it draws: the mesh and skinned
  /// vertex stages, the default lighting (`Pbr`, `Unlit`), the shadow, sky,
  /// post-processing and probe passes. Always carried; every engine stage no
  /// other engine need names.
  static final ShaderStageNeed base = ShaderStageNeed('base', <String>[
    for (final shader in requiredShaders)
      if (!_optional.contains(shader.name)) shader.name,
  ]);

  /// `LightingModel.pbrLayered`: the clear-coat, sheen and anisotropy model.
  static const ShaderStageNeed pbrLayered = ShaderStageNeed(
    'pbrLayered',
    <String>['PbrLayered', 'PbrLayeredOpaque'],
  );

  /// `LightingModel.blinnPhong`.
  static const ShaderStageNeed blinnPhong = ShaderStageNeed(
    'blinnPhong',
    <String>['BlinnPhong', 'BlinnPhongOpaque'],
  );

  /// `LightingModel.lambert`.
  static const ShaderStageNeed lambert = ShaderStageNeed('lambert', <String>[
    'Lambert',
    'LambertOpaque',
  ]);

  /// `LightingModel.toon`, and the toon look `flutter3d_post` switches to.
  static const ShaderStageNeed toon = ShaderStageNeed('toon', <String>[
    'Toon',
    'ToonOpaque',
  ]);

  /// Impostors: the billboard a level-of-detail chain ends in, which the
  /// asset build bakes when a rule says `impostor: true`.
  static const ShaderStageNeed impostor = ShaderStageNeed('impostor', <String>[
    'ImpostorVertex',
    'Impostor',
  ]);

  /// The engine's needs a project may declare, [base] not among them.
  ///
  /// Only lighting a project chooses: the x-ray look, the normals view and
  /// the planar mirror are drawn by the renderer itself when a setting or a
  /// node asks, which a build cannot see, so they stay in [base].
  static const List<ShaderStageNeed> engine = <ShaderStageNeed>[
    pbrLayered,
    blinnPhong,
    lambert,
    toon,
    impostor,
  ];

  static final Set<String> _optional = <String>{
    for (final need in engine) ...need.stages,
  };

  /// The engine need named [name] — [base] or one of [engine] — or null.
  static ShaderStageNeed? byName(String name) => name == base.name
      ? base
      : engine.where((need) => need.name == name).firstOrNull;

  /// The engine need that brings [stage], or null for a stage the engine does
  /// not have.
  static ShaderStageNeed? bringing(String stage) {
    for (final need in <ShaderStageNeed>[base, ...engine]) {
      if (need.stages.contains(stage)) return need;
    }
    return null;
  }

  /// Every stage [needs] bring, [base]'s always among them, in the order the
  /// engine lists them and then the order the needs were given.
  static List<String> stagesFor(Iterable<ShaderStageNeed> needs) => <String>{
    ...base.stages,
    for (final need in needs) ...need.stages,
  }.toList();

  @override
  bool operator ==(Object other) =>
      other is ShaderStageNeed && other.name == name;

  @override
  int get hashCode => name.hashCode;

  @override
  String toString() => 'ShaderStageNeed.$name';
}

/// A shader stage was asked for that the loaded bundle does not hold.
///
/// Thrown when the stage is first asked for — the renderer drawing with a
/// lighting model, a plugin's material on Impeller — rather than when the
/// bundle loads, because a bundle written for a project's needs leaves stages
/// out on purpose and only the one actually asked for is an error. [need] is
/// the declaration that would have brought it, when the engine knows one: the
/// word to add under `shaders:` in `flutter3d_assets.yaml`.
final class MissingShaderStageException extends ResourceException {
  const MissingShaderStageException(
    this.stage, {
    this.need,
    this.backend,
    this.detail,
  });

  /// The refusal for [stage], with the engine need that brings it filled in
  /// when there is one.
  factory MissingShaderStageException.forStage(
    String stage, {
    String? backend,
    String? detail,
  }) => MissingShaderStageException(
    stage,
    need: ShaderStageNeed.bringing(stage)?.name,
    backend: backend,
    detail: detail,
  );

  /// The entry point that was asked for.
  final String stage;

  /// The need that brings it, by [ShaderStageNeed.name]: an engine need or a
  /// plugin's; null when nothing known declares it.
  final String? need;

  /// The backend whose bundle lacks it, when the thrower knows.
  final String? backend;

  /// What else is worth saying: who asked for it, what to rebuild.
  final String? detail;

  @override
  String get message {
    final where = backend == null ? '' : ' on $backend';
    final why = switch (need) {
      null =>
        'nothing this build knows declares it; rebuild the bundle with the '
            'stage in, or with --full-shaders',
      'base' =>
        'it is one of the stages every bundle carries, so the bundle was not '
            'built by this flutter3d; rebuild it',
      final need =>
        'it comes with the need "$need": list it under "shaders:" in '
            'flutter3d_assets.yaml, or build with --full-shaders',
    };
    final more = detail == null ? '' : ' $detail';
    return 'the shader stage "$stage" is not in the bundle$where: $why.$more';
  }

  @override
  String toString() => 'MissingShaderStageException: $message';
}
