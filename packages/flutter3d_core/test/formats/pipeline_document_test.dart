/// `f3d.pipeline`: the frame written down, read back, and applied to a
/// renderer (D44).
///
///     dart test test/formats/pipeline_document_test.dart
///
/// Mutation: drop the anchors' loop from `RendererSteps.fromDocument` and
/// the applied node has nowhere to stand; skip `takeBack` on a refusal and
/// the half-applied anchor stays.
library;

import 'dart:io';

import 'package:flutter3d_core/data_plugins.dart';
import 'package:flutter3d_core/flutter3d_core.dart';
import 'package:flutter3d_hardware/testing.dart';
import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart'
    show
        DataSectionContext,
        DataSectionRead,
        DocumentFormatException,
        RenderAnchor;
import 'package:test/test.dart';

final class _Streak extends RenderNode {
  _Streak(this.name, this.length);

  @override
  final String name;

  final int length;

  @override
  List<ResourceId> get reads => const <ResourceId>[FrameResourceIds.hdrColor];

  @override
  List<ResourceId> get writes => const <ResourceId>[FrameResourceIds.hdrColor];

  @override
  void execute(RenderFrame frame) {}
}

final class _StreakKind extends PipelineNodeKind {
  const _StreakKind();

  @override
  String get name => 'acme_glow.streak';

  @override
  RenderNode create(PipelineNodeContext context) => _Streak(
    context.node.name,
    (context.node.options['length'] as num? ?? 4).toInt(),
  );
}

PipelineDocument _standard({int version = pipelineVersion}) =>
    PipelineDocument.parse(
      File('test/fixtures/v$version/standard.pipeline.json').readAsStringSync(),
    );

({Renderer renderer, Scene scene, List<CameraView> views}) _stage() {
  final camera = CameraNode();
  return (
    renderer: Renderer.create(device: FakeBackend()),
    scene: Scene()..add(camera),
    views: <CameraView>[CameraView(camera: camera)],
  );
}

final PipelineDocument _glow = PipelineDocument.fromJson(<String, Object?>{
  'format': 'f3d.pipeline',
  'version': 1,
  'anchors': <Object?>[
    <String, Object?>{'name': 'acme_glow.after glow', 'after': 'after bloom'},
  ],
  'nodes': <Object?>[
    <String, Object?>{
      'name': 'acme_glow.streak',
      'kind': 'acme_glow.streak',
      'anchor': 'acme_glow.after glow',
      'options': <String, Object?>{'length': 8},
    },
  ],
  'off': <Object?>['bloom'],
});

void main() {
  test('the standard pipeline reads, and writes back as it was', () {
    final standard = _standard();
    expect(standard.name, 'standard');
    expect(standard.nodes.every((node) => node.engine), isTrue);
    final again = PipelineDocument.fromJson(standard.toJson());
    expect(again.encode(), standard.encode());
  });

  test('a key a later minor put on a node is kept through a save', () {
    // Mutation: build the node without `unknown`, and an editor of this
    // build saving a 1.1 pipeline drops what 1.1 said about each node.
    final json = _standard().toJson();
    final nodes = json['nodes']! as List<Object?>;
    nodes[0] = <String, Object?>{
      ...(nodes[0]! as Map<String, Object?>),
      'perView': true,
    };
    final read = PipelineDocument.fromJson(json);
    expect(read.nodes.first.unknown, <String, Object?>{'perView': true});
    expect(
      (read.toJson()['nodes']! as List<Object?>).first,
      containsPair('perView', true),
    );
    expect(read.nodes[1].unknown, isEmpty);
  });

  test('the version 1 pipeline reads as version 2, every engine word with '
      'f3d. before it', () {
    // Mutation: drop `_engineWords` from the format's migrations, and the v1
    // anchors, steps and resources keep their old spelling.
    final v1 = _standard(version: 1);
    expect(v1.encode(), _standard().encode());
    final first = v1.nodes.first;
    expect(first.anchor, RenderAnchor.beforeShadows.name);
    expect(first.anchor, 'f3d.before_shadows');
    expect(first.step, RenderStep.shadows.name);
    expect(first.keeps, <String>[FrameResourceIds.cubeShadowStatic.name]);
    // The node's own name is what the frame reports, and stays.
    expect(first.name, 'point shadows (static)');
  });

  test('a renderer with nothing added describes the standard pipeline', () {
    final it = _stage();
    final described = it.renderer.describePipeline(
      scene: it.scene,
      views: it.views,
      name: 'standard',
    );
    final standard = _standard();
    // Every pass the standard pipeline names stands where it stood: a 1.x
    // renderer adds passes and never moves or drops one.
    for (final node in standard.nodes) {
      final now = described.nodes.where((n) => n.name == node.name);
      expect(now, hasLength(1), reason: node.name);
      expect(now.single.anchor, node.anchor, reason: node.name);
    }
  });

  test('a document is applied, described again, and taken back', () {
    final it = _stage();
    final steps = it.renderer.renderSteps;
    it.renderer.pipelineNodeKinds.add(const _StreakKind());
    final applied = steps.fromDocument(_glow);
    final anchor = steps.anchorNamed('acme_glow.after glow')!;
    expect(steps.nodesAt(anchor), <String>['acme_glow.streak']);

    final settings = steps.settingsFor(_glow, const RenderSettings());
    expect(
      RenderStep.bloom.isOn(RenderStepContext(settings: settings)),
      isFalse,
    );

    final described = it.renderer.describePipeline(
      scene: it.scene,
      views: it.views,
    );
    final streak = described.nodes.singleWhere(
      (n) => n.name == 'acme_glow.streak',
    );
    expect(streak.kind, 'acme_glow.streak');
    expect(streak.anchor, 'acme_glow.after glow');
    expect(described.anchors.single.after, RenderAnchor.afterBloom.name);

    applied.cancel();
    expect(steps.anchorNamed('acme_glow.after glow'), isNull);
    expect(steps.nodesAt(anchor), isEmpty);
  });

  test('a kind nobody registered is refused, and nothing is left behind', () {
    final steps = _stage().renderer.renderSteps;
    expect(() => steps.fromDocument(_glow), throwsArgumentError);
    expect(steps.anchorNamed('acme_glow.after glow'), isNull);
  });

  test('a newer document is refused, naming both versions', () {
    expect(
      () => PipelineDocument.fromJson(<String, Object?>{
        'format': 'f3d.pipeline',
        'version': 3,
      }),
      throwsA(
        isA<DocumentFormatException>().having(
          (e) => e.message,
          'message',
          allOf(contains('version 3'), contains('(2)')),
        ),
      ),
    );
  });

  test('a data plugin\'s pipeline section reads and writes its body', () {
    expect(renderDataSections, contains(pipelineSection));
    const context = DataSectionContext(plugin: 'acme_glow');
    final body = <String, Object?>{
      'anchors': <Object?>[
        <String, Object?>{
          'name': 'acme_glow.after glow',
          'after': 'after bloom',
        },
      ],
      'nodes': <Object?>[
        <String, Object?>{
          'name': 'acme_glow.streak',
          'anchor': 'acme_glow.after glow',
          'kind': 'acme_glow.streak',
        },
      ],
    };
    final read =
        pipelineSection.read(DataSectionRead(body, context: context))
            as PipelineDocument;
    expect(read.added.single.kind, 'acme_glow.streak');
    // A body from before the prefix reads, and is written in the new words.
    expect(read.anchors.single.after, RenderAnchor.afterBloom.name);
    expect(pipelineSection.write(read), <String, Object?>{
      ...body,
      'anchors': <Object?>[
        <String, Object?>{
          'name': 'acme_glow.after glow',
          'after': 'f3d.after_bloom',
        },
      ],
    });
  });
}
