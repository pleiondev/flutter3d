/// The light loop's hooks: a light type of a plugin's own, packed by its
/// hook with a code of its own, and a decal painted through a stage of a
/// plugin's own with the per-draw limits as settings (D22).
///
///     dart test test/engine/light_loop_hooks_test.dart
///
/// Mutation: drop `_hookSlot` from `LightBuffer._pack` and the packing test
/// reads the base's code; let `_DecalBatch.admits` ignore the stage and the
/// decal test links no pipeline for the plugin's stage.
library;

import 'dart:typed_data';

import 'package:flutter3d_core/flutter3d_core.dart';
import 'package:flutter3d_core/src/engine/scene/light_buffer.dart';
import 'package:flutter3d_hardware/testing.dart';
import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart'
    show
        PluginApiVersion,
        PluginException,
        PluginManifest,
        PluginScope,
        Registration;
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

const LightType _tube = LightType.custom(
  'acme_lamps.tube',
  base: LightType.point,
);

/// Packs a tube's length into the free component of the cone row.
final class _TubeHook extends LightTypeHook {
  const _TubeHook();

  @override
  LightType get type => _tube;

  @override
  void pack(LightPackContext context) {
    context.row[15] = 2.5;
    // Writing the code is the engine's; this is overwritten.
    context.row[3] = 99.0;
  }
}

void main() {
  group('light types', () {
    test('a hooked type is packed by its hook, with a code of its own', () {
      final types = LightTypes();
      types.register(const _TubeHook());
      final code = types.codeOf(_tube);
      expect(code, greaterThanOrEqualTo(LightTypes.firstPluginCode));
      expect(types.codeOf(LightType.spot), 2);

      final buffer = LightBuffer()
        ..lightTypes = types
        ..gather(<LightNode>[LightNode(type: _tube)]);
      expect(buffer.positions[3], code.toDouble());
      expect(buffer.cones[3], 2.5);

      // The light-list row is packed the same way.
      final row = Float32List(16);
      buffer.writeCandidateRow(0, row, 0);
      expect(row[3], code.toDouble());
      expect(row[15], 2.5);
    });

    test('without a hook a custom type is packed as its base', () {
      final buffer = LightBuffer()
        ..lightTypes = LightTypes()
        ..gather(<LightNode>[LightNode(type: _tube)]);
      expect(buffer.positions[3], 1.0);
    });

    test('codes are never handed out twice', () {
      final types = LightTypes();
      final first = types.register(const _TubeHook());
      final code = types.codeOf(_tube);
      first.cancel();
      types.register(const _TubeHook());
      expect(types.codeOf(_tube), code + 1);
    });

    test('a built-in type, and a plugin\'s outside its namespace, refused', () {
      final types = LightTypes();
      expect(() => types.register(_Bare(LightType.point)), throwsArgumentError);
      final renderer = Renderer.create(device: FakeBackend());
      expect(renderer.renderSteps.companions, contains(renderer.lightTypes));
      expect(
        () =>
            _scopedRegister(renderer, 'other_lamps.flicker', const _TubeHook()),
        throwsA(isA<PluginException>()),
      );
    });
  });

  group('decals', () {
    test('the limits per draw are settings, within what the stage holds', () {
      const settings = DecalSettings(enabled: true);
      expect(settings.decalsPerDraw, DecalSettings.maxDecalsPerDraw);
      expect(settings.picturesPerDraw, DecalSettings.maxPicturesPerDraw);
      expect(settings.copyWith(decalsPerDraw: 4).decalsPerDraw, 4);
    });

    test('a decal of a plugin\'s own stage is painted through it', () {
      final device = FakeBackend(maxColorAttachments: 4);
      final camera = CameraNode()..setPosition(0.0, 3.0, 0.0);
      camera.lookAt(Vector3.zero());
      const ink = LightingModel('Ink decal', 'acme_ink_Decal');
      final scene = Scene()
        ..add(
          MeshNode(
            DeviceMesh.upload(device, const PlaneShape().build()),
            RenderMaterial(),
          ),
        )
        ..add(DecalNode(lighting: ink)..setScale(2.0, 2.0, 2.0))
        ..add(DecalNode()..setScale(2.0, 2.0, 2.0))
        ..add(camera);
      Renderer.create(device: device).render(
        width: 32,
        height: 32,
        scene: scene,
        settings: const RenderSettings(decals: DecalSettings(enabled: true)),
        views: <RenderView>[RenderView(camera: camera)],
      );
      expect(device.linkedPipelines, contains(endsWith('+acme_ink_Decal')));
      expect(device.linkedPipelines, contains(endsWith('+Decal')));
    });
  });
}

final class _Bare extends LightTypeHook {
  const _Bare(this.type);

  @override
  final LightType type;
}

/// Registers [hook] with [renderer]'s light types as the plugin [id] would.
void _scopedRegister(Renderer renderer, String id, LightTypeHook hook) {
  final scoped = renderer.lightTypes.forPlugin(_Scope(id));
  scoped.register(hook);
}

final class _Scope extends PluginScope {
  _Scope(this.id);

  final String id;

  @override
  PluginManifest get manifest =>
      PluginManifest(id: id, apiVersion: PluginApiVersion.current);

  @override
  int get rank => 0;

  @override
  void track(Registration registration) {}
}
