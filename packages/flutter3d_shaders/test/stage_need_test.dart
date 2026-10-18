/// The engine's shader needs cover the manifest, once each (D15).
///
///     dart test test/stage_need_test.dart
///
/// Mutation: list `Toon` in `ShaderStageNeed.lambert` as well, and the stage
/// is brought by two needs.
library;

import 'package:flutter3d_foundation/flutter3d_foundation.dart'
    show Flutter3dException, ResourceException;
import 'package:flutter3d_shaders/flutter3d_shaders.dart';
import 'package:test/test.dart';

void main() {
  final names = <String>{for (final shader in requiredShaders) shader.name};

  test('every entry point is brought by exactly one need', () {
    final needs = <ShaderStageNeed>[
      ShaderStageNeed.base,
      ...ShaderStageNeed.engine,
    ];
    for (final name in names) {
      final bringing = <String>[
        for (final need in needs)
          if (need.stages.contains(name)) need.name,
      ];
      expect(bringing, hasLength(1), reason: '$name is brought by $bringing');
    }
  });

  test('a need names only stages the manifest has', () {
    for (final need in ShaderStageNeed.engine) {
      for (final stage in need.stages) {
        expect(names, contains(stage), reason: '${need.name} names $stage');
      }
    }
  });

  test(
    'the default lighting and every pass the renderer opens with are base',
    () {
      for (final stage in <String>[
        'MeshVertex',
        'MeshSkinnedVertex',
        'Pbr',
        'PbrOpaque',
        'Unlit',
        // Drawn by the renderer itself when a setting or a node asks.
        'Xray',
        'Normals',
        'PlanarReflection',
        'Composite',
        'FullscreenVertex',
        'ShadowDepth',
      ]) {
        expect(ShaderStageNeed.bringing(stage), ShaderStageNeed.base);
      }
    },
  );

  test('a need is found by its name, and stages are collected once', () {
    expect(ShaderStageNeed.byName('toon'), ShaderStageNeed.toon);
    expect(ShaderStageNeed.byName('base'), ShaderStageNeed.base);
    expect(ShaderStageNeed.byName('acme.glow'), isNull);
    final stages = ShaderStageNeed.stagesFor(<ShaderStageNeed>[
      ShaderStageNeed.toon,
      ShaderStageNeed.toon,
      const ShaderStageNeed('acme.glow', <String>['AcmeGlow']),
    ]);
    expect(stages, containsAll(ShaderStageNeed.base.stages));
    expect(stages.where((s) => s == 'Toon'), hasLength(1));
    expect(stages.last, 'AcmeGlow');
    expect(stages, isNot(contains('PbrLayered')));
  });

  test('a missing stage names the need that brings it', () {
    final missing = MissingShaderStageException.forStage(
      'ToonOpaque',
      backend: 'Impeller',
    );
    expect(missing, isA<ResourceException>());
    expect(missing, isA<Flutter3dException>());
    expect(missing.need, 'toon');
    expect(missing.message, contains('"ToonOpaque"'));
    expect(missing.message, contains('"toon"'));
    expect(missing.message, contains('flutter3d_assets.yaml'));
    expect(
      MissingShaderStageException.forStage('AcmeGlow').message,
      contains('--full-shaders'),
    );
  });
}
