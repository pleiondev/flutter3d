/// A material written as source draws on the software backend — `gfx-84n`.
///
///     flutter test test/material_language_frame_test.dart
///
/// **The strongest statement this row can make, and the reason it is here.**
/// The first test writes `Unlit` in the material language and renders it beside
/// the hand-written `UnlitShader` on the same scene, at zero tolerance. If the
/// evaluator read one surface field differently, or wrote the result through a
/// different call, or rounded anywhere the transcription does not, the two
/// frames would differ — and they are compared pixel for pixel rather than by
/// a bound, because there is nothing here for them to differ *about*.
///
/// The rest is what the language adds: two variants of one source draw
/// differently, in the direction their parameters say, and a variant whose
/// effect is turned off is again identical to the plain one.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:flutter3d_cpu/testing.dart';
import 'package:flutter3d_testing/flutter3d_testing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

const int _width = 96;
const int _height = 72;

/// `Unlit` in the material language: the albedo, written as the light the
/// surface emits. Word for word what `unlit.frag` does and what `UnlitShader`
/// transcribes.
const String _unlitSource = '''
material LangUnlit {
  fragment {
    return vec4(albedo, alpha);
  }
}
''';

/// A rim that brightens towards the silhouette, with both of its parameters
/// left for a variant to set.
const String _rimSource = '''
material Rim {
  param float rimPower = 2.0;
  param vec3 rimColor = vec3(0.6, 0.2, 0.0);

  fragment {
    let facing = clamp(nDotV, 0.0, 1.0);
    let rim = pow(1.0 - facing, rimPower);
    return vec4(albedo + rimColor * rim, alpha);
  }
}
''';

/// The cube every case below draws, with its material pointed at [model].
Future<Uint8List> _render(LightingModel model, CpuStage? stage) async {
  final kit = cpuTestDevice(width: _width, height: _height);
  final device = kit.device;

  final loaded = await GltfLoader().load(
    File('../flutter3d_samples/assets/Box.glb').readAsBytesSync(),
  );
  // The one thing this test changes about the model: which stage shades it.
  final document = PlainModelDocument(
    surfaces: loaded.surfaces,
    materials: <SurfaceMaterial>[
      for (final material in loaded.materials)
        SurfaceMaterial(
          name: material.name,
          baseColor: Vector4(0.8, 0.4, 0.2, 1.0),
          lightingModel: model,
        ),
    ],
    images: loaded.images,
    nodes: loaded.nodes,
    animations: loaded.animations,
    skins: loaded.skins,
    lights: loaded.lights,
    cameras: loaded.cameras,
    warnings: loaded.warnings,
    asset: loaded.asset,
  );

  final asset = await ModelAsset.fromDocument(document, device: device);
  final scene = Scene();
  asset.instantiate(scene);

  final renderer = Renderer.create(
    device: device,
    fallbackAlbedo: kit.albedo,
    fallbackNormal: kit.normal,
    // The seam `gfx-75n` opened: a stage arrives the way an application
    // supplies one, layered over the backend's own library rather than
    // compiled into it.
    materials: stage == null
        ? null
        : CpuShaderLibrary(<String, CpuStage>{model.shaderName: stage}),
  );
  final result = renderer.render(
    width: _width,
    height: _height,
    scene: scene,
    views: <RenderView>[
      RenderView(
        camera: CameraNode(
          projection: const PerspectiveProjection(fovYRadians: 0.9),
        )..setPosition(1.6, 1.2, 2.4),
        clearColor: Vector4(0, 0, 0, 1),
      ),
    ],
  );
  final pixels = await device.readPixels(result.frame);
  if (pixels == null) throw StateError('the frame did not read back');
  return pixels.buffer.asUint8List();
}

MaterialProgram _program(String source, MaterialVariant variant) =>
    specialiseMaterial(parseMaterial(source), variant);

int _differing(Uint8List a, Uint8List b) {
  var count = 0;
  for (var i = 0; i < a.length; i += 4) {
    if (a[i] != b[i] || a[i + 1] != b[i + 1] || a[i + 2] != b[i + 2]) {
      count++;
    }
  }
  return count;
}

void main() {
  test('Unlit written in the language is the hand-written Unlit', () async {
    final builtIn = await _render(LightingModel.unlit, null);
    final written = await _render(
      const LightingModel('Written unlit', 'LangUnlit'),
      CpuStage.fragment(
        MaterialProgramStage(
          _program(_unlitSource, const MaterialVariant('LangUnlit')),
        ),
      ),
    );

    expect(
      _differing(builtIn, written),
      0,
      reason: 'the evaluated material and the transcribed shader disagree',
    );
  });

  test('two variants of one source draw differently', () async {
    final model = const LightingModel('Rim', 'Rim');
    final warm = await _render(
      model,
      CpuStage.fragment(
        MaterialProgramStage(
          _program(_rimSource, const MaterialVariant('Rim')),
        ),
      ),
    );
    final cold = await _render(
      model,
      CpuStage.fragment(
        MaterialProgramStage(
          _program(
            _rimSource,
            const MaterialVariant('Rim', <String, List<double>>{
              'rimColor': <double>[0, 0.2, 0.9],
            }),
          ),
        ),
      ),
    );

    expect(
      _differing(warm, cold),
      greaterThan(0),
      reason: 'the variant\'s colour reached nothing',
    );
    // Warm and cold, in the direction the numbers say: more red in one frame
    // and more blue in the other, summed over the whole picture.
    var warmRed = 0, coldRed = 0, warmBlue = 0, coldBlue = 0;
    for (var i = 0; i < warm.length; i += 4) {
      warmRed += warm[i];
      coldRed += cold[i];
      warmBlue += warm[i + 2];
      coldBlue += cold[i + 2];
    }
    expect(warmRed, greaterThan(coldRed));
    expect(coldBlue, greaterThan(warmBlue));
  });

  test('a rim of no colour is the plain material again', () async {
    // The term is still computed and still added; it is zero. A frame that
    // differed here would mean the evaluator rounding somewhere the
    // arithmetic does not.
    final model = const LightingModel('Rim', 'Rim');
    final plain = await _render(
      const LightingModel('Written unlit', 'LangUnlit'),
      CpuStage.fragment(
        MaterialProgramStage(
          _program(_unlitSource, const MaterialVariant('LangUnlit')),
        ),
      ),
    );
    final dark = await _render(
      model,
      CpuStage.fragment(
        MaterialProgramStage(
          _program(
            _rimSource,
            const MaterialVariant('Rim', <String, List<double>>{
              'rimColor': <double>[0, 0, 0],
            }),
          ),
        ),
      ),
    );
    expect(_differing(plain, dark), 0);
  });
}
