/// `RenderSettings.anisotropy` reaches the sampler a material's texture is
/// bound with — and reaches only the samplers it should.
///
///     flutter test test/anisotropy_test.dart
///
/// The setting is applied at bind time, inside the one procedure every mesh
/// goes through, so the questions are the ones a recorded pass can answer:
/// which slots got the taps, whether a sampler that blends no levels was left
/// alone, whether a level the bridge already chose was respected, and whether
/// the device's ceiling was honoured before the backend had to.
library;

import 'dart:typed_data';

import 'package:flutter3d/flutter3d.dart' hide Material;
import 'package:flutter3d/flutter3d.dart' as engine show Material;
import 'package:flutter3d_hardware/testing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

/// Draws one textured box through [device] with [settings] and returns the
/// sampler each texture slot was bound with, by slot name.
Map<String, SamplerOptions?> _bind(
  FakeBackend device, {
  required SamplerOptions? albedoSampler,
  required RenderSettings settings,
}) {
  final texel = device.createTextureFromPixels(
    width: 1,
    height: 1,
    format: TextureFormat.r8g8b8a8UNormInt,
    pixels: ByteData(4),
  )!;
  final renderer = Renderer.create(
    device: device,
    fallbackAlbedo: texel,
    fallbackNormal: texel,
  );

  final scene = Scene(name: 'anisotropy');
  final camera = scene.add(CameraNode(name: 'eye'))
    ..lookAt(Vector3(0.0, 0.0, 1.0));
  scene.add(
    MeshNode(
      DeviceMesh.upload(device, CuboidShape(size: Vector3.all(1.0)).build()),
      engine.Material(name: 'box', lighting: LightingModel.pbr)
        ..albedo = texel
        ..albedoSampler = albedoSampler
        ..normal = texel
        ..normalSampler = albedoSampler,
      name: 'box',
    )..setPosition(0.0, 0.0, 5.0),
  );
  renderer.render(
    width: 64,
    height: 48,
    scene: scene,
    views: <RenderView>[RenderView(camera: camera)],
    settings: settings.copyWith(
      bloom: const BloomSettings(enabled: false),
      shadows: const ShadowSettings(enabled: false),
    ),
  );

  return <String, SamplerOptions?>{
    for (final pass in device.passes)
      for (final command in pass.commands.whereType<RecordedTexture>())
        command.slot: command.sampler,
  };
}

void main() {
  test('a trilinear material sampler gets the setting\'s taps', () {
    // Mutation: bind `material.albedoSampler` directly. The setting then
    // changes nothing anywhere, and the only witness is a floor that stays
    // blurred with the slider all the way up.
    final bound = _bind(
      FakeBackend(maxAnisotropy: 16),
      albedoSampler: SamplerOptions.trilinearRepeat,
      settings: const RenderSettings(anisotropy: 8),
    );
    expect(bound['base_color_texture']?.anisotropy, 8);
    expect(bound['normal_texture']?.anisotropy, 8);
    // The rest of the sampler is the material's own.
    expect(
      bound['base_color_texture'],
      SamplerOptions.trilinearRepeat.withAnisotropy(8),
    );
  });

  test('the default setting leaves every sampler as loaded', () {
    // One tap, which is every textured golden in three sets.
    final bound = _bind(
      FakeBackend(maxAnisotropy: 16),
      albedoSampler: SamplerOptions.trilinearRepeat,
      settings: const RenderSettings(),
    );
    expect(bound['base_color_texture'], SamplerOptions.trilinearRepeat);
  });

  test('a bilinear sampler is left alone whatever the setting says', () {
    // No chain to take taps across, and flutter_gpu would refuse the bind.
    // Mutation: drop the filter checks from `_anisotropic` — this is then an
    // `AssertionError` out of the sampler constructor on the first frame.
    final bound = _bind(
      FakeBackend(maxAnisotropy: 16),
      albedoSampler: SamplerOptions.linearRepeat,
      settings: const RenderSettings(anisotropy: 8),
    );
    expect(bound['base_color_texture'], SamplerOptions.linearRepeat);
  });

  test('a null sampler stays null', () {
    // Null means the backend's linear-and-repeat default, which blends no
    // levels; it is not this layer's to replace with something else.
    final bound = _bind(
      FakeBackend(maxAnisotropy: 16),
      albedoSampler: null,
      settings: const RenderSettings(anisotropy: 8),
    );
    expect(bound.containsKey('base_color_texture'), isTrue);
    expect(bound['base_color_texture'], isNull);
  });

  test('a sampler that already carries a level keeps it', () {
    // The bridge's: sized to the device at load, and not turned up or down
    // by a setting meant for the models that had no way to ask.
    final bound = _bind(
      FakeBackend(maxAnisotropy: 16),
      albedoSampler: SamplerOptions.trilinearRepeat.withAnisotropy(4),
      settings: const RenderSettings(anisotropy: 16),
    );
    expect(bound['base_color_texture']?.anisotropy, 4);
  });

  test('the device\'s ceiling is honoured', () {
    // A backend clamps too, but a request above the ceiling is one the frame
    // should not keep re-making. On a device that answers one the sampler is
    // the material's own object, allocated nowhere.
    expect(
      _bind(
        FakeBackend(maxAnisotropy: 4),
        albedoSampler: SamplerOptions.trilinearRepeat,
        settings: const RenderSettings(anisotropy: 16),
      )['base_color_texture']?.anisotropy,
      4,
    );
    expect(
      _bind(
        FakeBackend(maxAnisotropy: 1),
        albedoSampler: SamplerOptions.trilinearRepeat,
        settings: const RenderSettings(anisotropy: 16),
      )['base_color_texture'],
      same(SamplerOptions.trilinearRepeat),
    );
  });
}
