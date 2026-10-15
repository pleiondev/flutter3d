/// The hooks into what a renderer draws and when: a view's draw list, the
/// level of detail, the frame pacing, the quality row, an image format of a
/// plugin's own and a material's instanced vertex stage (D22b).
///
///     dart test test/engine/render_hooks_test.dart
///
/// Mutation: drop the hook loop from `RenderList.build`'s `consider` and the
/// draw-list test draws both meshes; ignore `policy` in `LodGroup.select`
/// and the level test shows the finest.
library;

import 'dart:typed_data';

import 'package:flutter3d_core/flutter3d_core.dart';
import 'package:flutter3d_hardware/testing.dart';
import 'package:test/test.dart';

/// Keeps only meshes whose name does not start with `hidden`.
final class _HideByName extends DrawListHook {
  const _HideByName();

  @override
  bool keeps(DrawListContext context) =>
      !(context.node.name ?? '').startsWith('hidden');
}

final class _Coarsest extends LodPolicy {
  const _Coarsest();

  @override
  int? select(LodContext context) => context.group.levels.length - 1;
}

final class _AlwaysHold extends PacingPolicy {
  const _AlwaysHold();

  @override
  bool? hold(PacingContext context) => true;
}

final class _Second extends QualityPolicy {
  const _Second();

  @override
  int? choose(QualityContext context) => 1;
}

/// Reads a made-up format: `ACME`, then a width and a height, a byte each,
/// then that many opaque grey pixels.
final class _AcmeCodec extends TextureCodec {
  const _AcmeCodec();

  @override
  String get name => 'acme_pix.pix';

  @override
  bool sniff(Uint8List head) =>
      head.length >= 4 && String.fromCharCodes(head.sublist(0, 4)) == 'ACME';

  @override
  Future<Rgba8Image?> decode(TextureDecodeContext context) async {
    final width = context.bytes[4];
    final height = context.bytes[5];
    return Rgba8Image(
      width: width,
      height: height,
      pixels: Uint8List(width * height * 4)
        ..fillRange(0, width * height * 4, 128),
    );
  }
}

({Renderer renderer, Scene scene, CameraNode camera, FakeBackend device})
_stage() {
  final device = FakeBackend();
  final camera = CameraNode()..setPosition(0.0, 0.0, 5.0);
  final scene = Scene()..add(camera);
  return (
    renderer: Renderer.create(device: device),
    scene: scene,
    camera: camera,
    device: device,
  );
}

FrameResult _draw(
  ({Renderer renderer, Scene scene, CameraNode camera, FakeBackend device}) it,
) => it.renderer.render(
  width: 32,
  height: 32,
  scene: it.scene,
  views: <CameraView>[CameraView(camera: it.camera)],
);

void main() {
  test('a draw-list hook narrows what a view draws', () {
    final it = _stage();
    MeshNode cube(String name) => MeshNode(
      DeviceMesh.upload(it.device, CuboidShape().build()),
      RenderMaterial(),
      name: name,
    );
    it.scene
      ..add(cube('shown'))
      ..add(cube('hidden one'));
    final both = _draw(it).drawCalls;
    it.renderer.hooks.addDrawListHook(const _HideByName());
    expect(_draw(it).drawCalls, lessThan(both));
    expect(it.renderer.renderSteps.companions, contains(it.renderer.hooks));
  });

  test('a level-of-detail policy has the last word', () {
    final device = FakeBackend();
    final mesh = DeviceMesh.upload(device, CuboidShape().build());
    final group = LodGroup(
      levels: <LodLevel>[
        LodLevel(node: MeshNode(mesh, RenderMaterial()), maxScreenFraction: 1),
        LodLevel(
          node: MeshNode(mesh, RenderMaterial()),
          maxScreenFraction: 0.1,
        ),
      ],
    );
    final camera = CameraNode()..setPosition(0.0, 0.0, 2.0);
    expect(group.select(camera), 0);
    expect(group.select(camera, policy: const _Coarsest()), 1);
  });

  test('a pacing policy holds a frame the engine would draw', () {
    final it = _stage();
    it.renderer.pacing = const FramePacing(policy: _AlwaysHold());
    expect(_draw(it).held, isFalse);
    expect(_draw(it).held, isTrue);
  });

  test('a quality policy picks the row', () {
    final table = QualityTable(
      deviceClass: DeviceClass.desktop,
      rows: <QualityRow>[
        for (final s in QualitySetting.grid.take(3))
          QualityRow(s, cost: 1.0, flip: 0.0),
      ],
    );
    final quality = AdaptiveQuality(
      table,
      settings: const AdaptiveQualitySettings(enabled: true),
      policy: const _Second(),
    );
    quality.recordFrame(1000);
    expect(quality.index, 1);
  });

  test(
    'an image format of a plugin\'s own is read before the engine\'s',
    () async {
      final codecs = TextureCodecs()..add(const _AcmeCodec());
      final bytes = Uint8List.fromList(<int>[...'ACME'.codeUnits, 2, 3]);
      final texture = await uploadEncodedImage(
        FakeBackend(),
        bytes,
        decodeImage: (_) async => null,
        codecs: codecs,
      );
      expect((texture.width, texture.height), (2, 3));
      expect(
        ModelDecoders().companions.whereType<TextureCodecs>(),
        hasLength(1),
      );
    },
  );

  test('a material lists the vertex stages it ships for other geometry', () {
    const model = LightingModel(
      'Wind',
      'acme_wind_Wind',
      vertexShaderName: 'acme_wind_WindVertex',
      vertexVariants: <VertexStageVariant>{VertexStageVariant.instanced},
    );
    expect(model.vertexVariants, contains(VertexStageVariant.instanced));
    expect(
      VertexStageVariant.byName('lightmapped'),
      VertexStageVariant.lightmapped,
    );
    expect(MeshVertexLayouts.instanced.buffers, hasLength(2));
  });
}
