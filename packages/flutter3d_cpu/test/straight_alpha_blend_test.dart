/// glTF's blend mode is Porter and Duff's over on straight colour: a pane at
/// alpha α shows α of its own light and 1 − α of what is behind it.
///
///     dart test test/straight_alpha_blend_test.dart
///
/// Held as a relation between three frames of the same scene rather than as
/// numbers: the pane blended, the pane opaque, and no pane. In linear light
/// the first is α of the second plus 1 − α of the third, at every pixel, and
/// that stays true through lighting, exposure and fog. The frames are read
/// through the extended output, which skips the tone curve, so the sRGB
/// transfer is all there is to undo.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter3d_core/flutter3d_core.dart';
import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

const int _size = 32;

/// The pane's straight colour, and its opacity when it blends.
final Vector3 _tint = Vector3(0.2, 0.6, 0.9);
const double _alpha = 0.2;

/// What the pane is drawn as, if it is drawn.
enum _Pane { none, opaque, blended }

/// The frame of a pane in front of a grey wall, in linear light.
///
/// [paneAlpha] is the alpha on the pane's own tint, whatever its mode: an
/// opaque pane with an alpha under one is how the mode is shown to decide.
Float32List _render({
  required _Pane pane,
  double paneAlpha = _alpha,
  LightingModel lighting = LightingModel.unlit,
  TransparencyMode transparency = TransparencyMode.sorted,
  double fogDensity = 0.0,
}) {
  final device = CpuDevice(
    width: _size,
    height: _size,
    shaders: CpuShaderLibrary(builtinCpuShaders()),
    hdrOutputFormats: const <TextureFormat>[TextureFormat.r16g16b16a16Float],
  );
  final camera = CameraNode()..setPosition(0.0, 0.0, 1.0);
  final scene = Scene()
    ..add(camera)
    ..add(LightNode(intensity: 3.0)..setRotationYawPitchRoll(0.3, -0.4, 0.0))
    ..add(
      MeshNode(
          DeviceMesh.upload(
            device,
            const PlaneShape(width: 8, depth: 8).build(),
          ),
          Material(
            lighting: LightingModel.unlit,
            baseColor: Vector4(0.45, 0.45, 0.45, 1.0),
            doubleSided: true,
          ),
        )
        ..setPosition(0.0, 0.0, -3.0)
        ..setRotationYawPitchRoll(0.0, math.pi / 2, 0.0),
    );
  if (pane != _Pane.none) {
    scene.add(
      MeshNode(
          DeviceMesh.upload(
            device,
            const PlaneShape(width: 1.2, depth: 1.2).build(),
          ),
          Material(
            lighting: lighting,
            baseColor: Vector4(_tint.x, _tint.y, _tint.z, paneAlpha),
            alphaMode: pane == _Pane.blended
                ? MaterialAlphaMode.blend
                : MaterialAlphaMode.opaque,
            doubleSided: true,
          ),
        )
        ..setPosition(0.0, 0.0, -1.5)
        ..setRotationYawPitchRoll(0.0, math.pi / 2, 0.0),
    );
  }
  final result = Renderer.create(device: device).render(
    width: _size,
    height: _size,
    scene: scene,
    views: <RenderView>[RenderView(camera: camera)],
    settings: RenderSettings(
      bloom: const BloomSettings(enabled: false),
      outputTransform: OutputTransform.extendedSrgb,
      transparency: transparency,
      fog: FogSettings(density: fogDensity),
    ),
  );
  final encoded = device.readHdrPixels(result.frame);
  return Float32List.fromList(<double>[
    for (var i = 0; i < encoded.length; i++)
      i % 4 == 3 ? encoded[i] : _linear(encoded[i]),
  ]);
}

/// The sRGB transfer undone, extended past one as the output extends it.
double _linear(double c) =>
    c <= 0.04045 ? c / 12.92 : math.pow((c + 0.055) / 1.055, 2.4).toDouble();

/// The largest amount by which [blended] misses α·[opaque] + (1 − α)·[bare]
/// in any colour channel.
double _overError(Float32List blended, Float32List opaque, Float32List bare) {
  var worst = 0.0;
  for (var i = 0; i < blended.length; i++) {
    if (i % 4 == 3) continue;
    final over = _alpha * opaque[i] + (1.0 - _alpha) * bare[i];
    worst = math.max(worst, (blended[i] - over).abs());
  }
  return worst;
}

/// The centre pixel's red, green and blue.
List<double> _centre(Float32List frame) {
  final i = ((_size ~/ 2) * _size + _size ~/ 2) * 4;
  return <double>[frame[i], frame[i + 1], frame[i + 2]];
}

void main() {
  // Mutation for every relation below: drop the `* weight` in `writeLit`
  // (`WriteSurface` in `color.glsl`). The pane then adds all of its light
  // over 1 − α of the wall, and misses the relation by about 0.8 of the
  // opaque pane's colour.
  test('a fifth-opaque pane shows a fifth of its colour over the wall', () {
    final blended = _render(pane: _Pane.blended);
    final opaque = _render(pane: _Pane.opaque, paneAlpha: 1.0);
    final bare = _render(pane: _Pane.none);
    // Not vacuous: the pane is there, and not the same as the wall.
    expect(_centre(blended), isNot(orderedEquals(_centre(bare))));
    expect(_overError(blended, opaque, bare), lessThan(2e-3));
  });

  test('lit, the specular and diffuse are weighted alike', () {
    final blended = _render(pane: _Pane.blended, lighting: LightingModel.pbr);
    final opaque = _render(
      pane: _Pane.opaque,
      paneAlpha: 1.0,
      lighting: LightingModel.pbr,
    );
    final bare = _render(pane: _Pane.none);
    expect(_overError(blended, opaque, bare), lessThan(2e-3));
  });

  test('the x-ray model, which writes no surface, is weighted too', () {
    // `xray.frag` calls `WriteSurface` like the rest, so its mirror has to
    // weight as `writeLit` does. Mutation: drop the weight in `XrayShader`.
    final blended = _render(pane: _Pane.blended, lighting: LightingModel.xray);
    final opaque = _render(
      pane: _Pane.opaque,
      paneAlpha: 1.0,
      lighting: LightingModel.xray,
    );
    final bare = _render(pane: _Pane.none);
    expect(_overError(blended, opaque, bare), lessThan(2e-3));
  });

  test('weighted blended transparency composites the same over', () {
    // One layer: the weight divides back out, and the resolve lays the
    // premultiplied colour over 1 − α of the wall.
    final blended = _render(
      pane: _Pane.blended,
      transparency: TransparencyMode.weightedBlended,
    );
    final opaque = _render(pane: _Pane.opaque, paneAlpha: 1.0);
    final bare = _render(pane: _Pane.none);
    expect(_overError(blended, opaque, bare), lessThan(2e-3));
  });

  test('a fogged pane adds α of the fog, not all of it', () {
    // Mutation: weight the colour before `applyFog` instead of after. The
    // fog is then mixed in whole over a dimmed pane.
    const density = 0.4;
    final blended = _render(pane: _Pane.blended, fogDensity: density);
    final opaque = _render(
      pane: _Pane.opaque,
      paneAlpha: 1.0,
      fogDensity: density,
    );
    final bare = _render(pane: _Pane.none, fogDensity: density);
    expect(_overError(blended, opaque, bare), lessThan(2e-3));
  });

  test('an opaque surface keeps its colour whole, whatever its alpha', () {
    // glTF: alpha is ignored in the opaque mode. Mutation: weight every
    // surface by its alpha in `writeLit`, not only a blended one's. This
    // pane then darkens to 0.4 of itself. The alpha channel is left out: an
    // opaque draw writes its alpha as it stands, which is not this item.
    List<double> colour(Float32List frame) => <double>[
      for (var i = 0; i < frame.length; i++)
        if (i % 4 != 3) frame[i],
    ];
    expect(
      colour(_render(pane: _Pane.opaque, paneAlpha: 0.4)),
      orderedEquals(colour(_render(pane: _Pane.opaque, paneAlpha: 1.0))),
    );
  });
}
