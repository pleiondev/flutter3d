/// A look an application adds without changing the engine.
///
///     flutter test test/custom_material_test.dart
///
/// **The gap this closes, stated plainly:** until now every non-standard
/// appearance meant editing this repository. Six lighting models shipped, a
/// material picked one of them, and there was no way in.
///
/// There turned out to be very little to build, because two thirds of the way
/// in was already open and documented as deliberate. [LightingModel] is a class
/// with a public constructor whose own docstring says "there is no longer a
/// complete list to have"; a material can already name a stage the engine never
/// heard of. What was missing was only that the name was resolved against the
/// *backend's* bundle and nowhere else. A renderer that consults an
/// application's library first is the whole of the mechanism.
library;

import 'dart:typed_data';

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

const int _width = 32;
const int _height = 32;

/// An application's own shading, configured by the application's own uniform.
///
/// Reads `Tint.colour` and writes it. Nothing in the engine knows what `Tint`
/// is or what its member means; the material carries the values and the encoder
/// binds them by name.
final class _TintShader implements CpuFragmentShader {
  const _TintShader();

  @override
  Vector4? run(Float32List v, ShaderBindings bindings, FragmentContext c) {
    final tint = bindings.vec4('Tint', 'colour', Vector4(0.0, 0.0, 0.0, 1.0));
    return Vector4(tint.x, tint.y, tint.z, 1.0);
  }
}

/// An application's own shading, sampling the application's own texture.
///
/// Reads the slot `ramp_texture`, which is a name no engine shader has and no
/// engine code knows. The material lists it under [Material.extraTextures] and
/// the encoder binds it there; if the encoder did not, the fallback below is
/// what a frame would show.
final class _RampShader implements CpuFragmentShader {
  const _RampShader();

  @override
  Vector4? run(Float32List v, ShaderBindings bindings, FragmentContext c) {
    final ramp = bindings.textures['ramp_texture'];
    if (ramp == null) return Vector4(0.0, 0.0, 0.0, 1.0);
    final texel = ramp.sample(0.5, 0.5);
    return Vector4(texel.x, texel.y, texel.z, 1.0);
  }
}

/// An application's own shading: flat magenta, and nothing the engine ships is.
///
/// A fragment stage is a function from varyings and bindings to a colour, so an
/// application's is too. On this backend that is Dart; on Impeller it is a
/// compiled stage in the application's own bundle and on WebGL a source string
/// it hands the context — three ways to answer the same one-method interface.
final class _MagentaShader implements CpuFragmentShader {
  const _MagentaShader();

  @override
  Vector4? run(Float32List v, ShaderBindings bindings, FragmentContext c) =>
      Vector4(1.0, 0.0, 1.0, 1.0);
}

/// The model a material names to reach it.
///
/// Nothing about this is registered anywhere: the string is the whole binding,
/// and it is resolved against the library handed to the renderer.
const LightingModel _magenta = LightingModel(
  'Magenta',
  'Magenta',
  usesFragInfo: false,
  usesAlbedoTexture: false,
  usesMaterialMaps: false,
  usesMetallicRoughnessMap: false,
  usesMaterialParameters: false,
);

/// The model the tint shader is reached by.
const LightingModel _tint = LightingModel(
  'Tint',
  'Tint',
  usesFragInfo: false,
  usesAlbedoTexture: false,
  usesMaterialMaps: false,
  usesMetallicRoughnessMap: false,
  usesMaterialParameters: false,
);

/// The model the ramp shader is reached by.
const LightingModel _ramp = LightingModel(
  'Ramp',
  'Ramp',
  usesFragInfo: false,
  usesAlbedoTexture: false,
  usesMaterialMaps: false,
  usesMetallicRoughnessMap: false,
  usesMaterialParameters: false,
);

/// A one-texel texture of a colour nothing else in this file is.
TextureHandle _texel(CpuDevice device, int r, int g, int b) =>
    device.createTextureFromPixels(
      width: 1,
      height: 1,
      format: TextureFormat.r8g8b8a8UNormInt,
      pixels: ByteData.sublistView(Uint8List.fromList(<int>[r, g, b, 255])),
    )!;

({CpuDevice device, Scene scene, CameraNode camera}) _wall(
  LightingModel model,
) {
  final device = CpuDevice(
    width: _width,
    height: _height,
    shaders: CpuShaderLibrary(builtinCpuShaders()),
  );

  final scene = Scene();
  scene.add(
    MeshNode(
      DeviceMesh.upload(
        device,
        CuboidShape(size: Vector3(40.0, 40.0, 1.0)).build(),
      ),
      Material(
        name: 'wall',
        baseColor: Vector4(0.5, 0.5, 0.5, 1.0),
        lighting: model,
      ),
      name: 'wall',
    )..setPosition(0.0, 0.0, -8.0),
  );

  final camera = CameraNode(
    projection: const PerspectiveProjection(
      fovYRadians: 1.0,
      near: 0.1,
      far: 60.0,
    ),
  );
  camera.lookAt(Vector3(0.0, 0.0, -1.0));
  scene.add(camera);

  return (device: device, scene: scene, camera: camera);
}

Future<Uint8List> _draw(
  ({CpuDevice device, Scene scene, CameraNode camera}) it, {
  ShaderLibrary? materials,
}) async {
  final renderer = Renderer.create(device: it.device, materials: materials);
  final result = renderer.render(
    width: _width,
    height: _height,
    scene: it.scene,
    views: <RenderView>[
      RenderView(camera: it.camera, clearColor: Vector4(0.0, 0.0, 0.0, 1.0)),
    ],
    // Tone mapping off, so a shader's output is compared with what it wrote
    // rather than with what a curve made of it.
    settings: const RenderSettings(tonemap: false),
  );
  final pixels = await it.device.readPixels(result.frame);
  expect(pixels, isNotNull, reason: 'the frame could not be read back');
  return pixels!.buffer.asUint8List();
}

/// Red, green, blue at the middle of the frame.
List<int> _centre(Uint8List pixels) {
  final at = ((_height ~/ 2) * _width + _width ~/ 2) * 4;
  return <int>[pixels[at], pixels[at + 1], pixels[at + 2]];
}

void main() {
  test('an application can configure its own shader with its own uniform', () async {
    // **The other half of a custom material.** A stage of one's own is not much
    // use if it can only ever be a constant; this is how it is told a colour, a
    // wave height or a scroll speed without the engine knowing what any of them
    // mean.
    //
    // Mutation: drop the `bindUniformBlock` call for `material.parameters` —
    // the shader falls back to the black default it was given and this fails.
    final device = CpuDevice(
      width: _width,
      height: _height,
      shaders: CpuShaderLibrary(builtinCpuShaders()),
    );
    final scene = Scene();
    scene.add(
      MeshNode(
        DeviceMesh.upload(
          device,
          CuboidShape(size: Vector3(40.0, 40.0, 1.0)).build(),
        ),
        Material(
          name: 'tinted',
          lighting: _tint,
          parameterBlock: 'Tint',
          parameters: <String, Float32List>{
            'colour': Float32List.fromList(<double>[0.0, 0.85, 0.2, 1.0]),
          },
        ),
      )..setPosition(0.0, 0.0, -8.0),
    );
    final camera = CameraNode(
      projection: const PerspectiveProjection(
        fovYRadians: 1.0,
        near: 0.1,
        far: 60.0,
      ),
    );
    camera.lookAt(Vector3(0.0, 0.0, -1.0));
    scene.add(camera);

    final pixels = await _draw(
      (device: device, scene: scene, camera: camera),
      materials: CpuShaderLibrary(<String, CpuStage>{
        'Tint': const CpuStage.fragment(_TintShader()),
      }),
    );

    final rgb = _centre(pixels);
    expect(rgb[1], greaterThan(200), reason: 'the tint it was given is green');
    expect(rgb[0], lessThan(60), reason: 'and not red');
  });

  test('an application can hand its own shader its own texture', () async {
    // **The other half of the seam, and the half nothing ran.** `parameters`
    // above is the safe one: a block the shader has not got is reported and
    // skipped. `extraTextures` is not — a sampler slot a compiled shader does
    // not have is a native crash on at least one backend — and it was reachable
    // from `flutter3d.dart`, documented as the way to feed a custom stage, and
    // bound by no test, no golden and no application on any of the three.
    //
    // Mutation: drop the `material.extraTextures` loop in
    // `renderer_mesh_encode.dart` — the slot arrives empty, the shader takes
    // its black fallback and this fails on every channel.
    final device = CpuDevice(
      width: _width,
      height: _height,
      shaders: CpuShaderLibrary(builtinCpuShaders()),
    );
    final scene = Scene();
    scene.add(
      MeshNode(
        DeviceMesh.upload(
          device,
          CuboidShape(size: Vector3(40.0, 40.0, 1.0)).build(),
        ),
        Material(
          name: 'ramped',
          lighting: _ramp,
          extraTextures: <String, TextureHandle>{
            'ramp_texture': _texel(device, 0, 0, 255),
          },
        ),
      )..setPosition(0.0, 0.0, -8.0),
    );
    final camera = CameraNode(
      projection: const PerspectiveProjection(
        fovYRadians: 1.0,
        near: 0.1,
        far: 60.0,
      ),
    );
    camera.lookAt(Vector3(0.0, 0.0, -1.0));
    scene.add(camera);

    final pixels = await _draw(
      (device: device, scene: scene, camera: camera),
      materials: CpuShaderLibrary(<String, CpuStage>{
        'Ramp': const CpuStage.fragment(_RampShader()),
      }),
    );

    final rgb = _centre(pixels);
    expect(rgb[2], greaterThan(200), reason: 'the texel it was handed is blue');
    expect(rgb[0], lessThan(20), reason: 'and not white, and not the fallback');
  });

  test('an application can add a look the engine never shipped', () async {
    // **The feature, in one assertion.** No entry in `LightingModel.builtIn`,
    // no case added to a switch, no file of this repository touched.
    //
    // Mutation: drop the `materials` argument from `Renderer.create` and the
    // renderer throws for want of a "Magenta" stage — which is the right
    // failure and not this one.
    final it = _wall(_magenta);
    final pixels = await _draw(
      it,
      materials: CpuShaderLibrary(<String, CpuStage>{
        'Magenta': const CpuStage.fragment(_MagentaShader()),
      }),
    );

    final rgb = _centre(pixels);
    expect(rgb[0], greaterThan(200), reason: 'magenta is red');
    expect(rgb[1], lessThan(60), reason: 'and not green');
    expect(rgb[2], greaterThan(200), reason: 'and blue');
  });

  test("and the application's stage wins a name the engine also has", () async {
    // Replacing rather than only adding. An application that wants its own
    // `Unlit` should get its own `Unlit`; a collision it did not intend then
    // shows up at once as its shader running where it did not expect, which is
    // visible — where the other order would make a new shader appear to do
    // nothing at all.
    //
    // Mutation: swap the two libraries in `LayeredShaderLibrary` — the engine's
    // Unlit wins, the wall comes back grey and this fails.
    final it = _wall(LightingModel.unlit);
    final pixels = await _draw(
      it,
      materials: CpuShaderLibrary(<String, CpuStage>{
        'Unlit': const CpuStage.fragment(_MagentaShader()),
      }),
    );

    final rgb = _centre(pixels);
    expect(rgb[0], greaterThan(200));
    expect(rgb[2], greaterThan(200));
  });

  test('and a renderer given no library behaves as it always did', () async {
    // The promise the goldens rest on. Mutation: layer an empty library in
    // unconditionally — harmless in principle, and this is what would catch it
    // stopping being harmless.
    final it = _wall(LightingModel.unlit);
    final plain = await _draw(it);

    final again = _wall(LightingModel.unlit);
    expect(
      await _draw(again, materials: CpuShaderLibrary(<String, CpuStage>{})),
      equals(plain),
    );
  });
}
