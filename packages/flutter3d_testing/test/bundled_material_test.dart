/// A bundle built from a `.f3dmat`, loaded with nothing registered by hand —
/// `P8`.
///
///     flutter test test/bundled_material_test.dart
///
/// The build keeps each material's source in the bundle beside its compiled
/// sections. These claims are about what that buys: the software backend
/// compiles the source itself, a runtime reads the material's lighting model
/// out of it, and a reload of the bundle reaches a draw already holding the
/// stage.
library;

import 'dart:typed_data';

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_app/flutter3d_app.dart' show materialLanguageCompiler;
import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

const int _size = 32;

/// A material that paints its surface one flat [color].
String _flat(String name, String color) =>
    '''
material $name {
  fragment {
    return vec4($color, 1.0);
  }
}
''';

/// A bundle as the build writes one for [sources]: their stages, and their
/// text in the material section. The compiled sections are left out: the
/// software backend reads none of them.
ByteData _bundle(Map<String, String> sources) => ShaderBundle(
  name: 'materials',
  sdk: '',
  stages: <ShaderBundleStage>[
    for (final name in sources.keys) ShaderBundleStage(name, fragment: true),
  ],
  sections: <String, ByteData>{
    ShaderBundle.materialSection: encodeMaterialSection(sources),
  },
).encode();

CpuDevice _device({CpuMaterialCompiler? compiler}) => CpuDevice(
  width: _size,
  height: _size,
  shaders: CpuShaderLibrary(builtinCpuShaders()),
  materialCompiler: compiler,
);

/// The middle pixel of a frame of one cube drawn with [lighting], through a
/// renderer whose materials are [library].
Future<Vector3> _center(
  CpuDevice device,
  LoadedShaderLibrary? library,
  LightingModel lighting, {
  Map<String, Float32List> parameters = const <String, Float32List>{},
  Renderer? renderer,
}) async {
  final camera = CameraNode()..setPosition(0.0, 0.0, 3.0);
  final scene = Scene()
    ..add(camera)
    ..add(
      MeshNode(
        DeviceMesh.upload(device, CuboidShape().build()),
        RenderMaterial(lighting: lighting)..parameters.addAll(parameters),
      ),
    );
  final drawing =
      renderer ?? Renderer.create(device: device, materials: library);
  final result = drawing.render(
    width: _size,
    height: _size,
    scene: scene,
    views: <RenderView>[RenderView(camera: camera)],
    settings: const RenderSettings(
      bloom: BloomSettings(enabled: false),
      tonemap: false,
      look: LookSettings(dither: 0.0),
    ),
  );
  final pixels = await device.readback(result.frame);
  final at = ((_size ~/ 2) * _size + _size ~/ 2) * 4;
  return Vector3(
    pixels.getUint8(at) / 255.0,
    pixels.getUint8(at + 1) / 255.0,
    pixels.getUint8(at + 2) / 255.0,
  );
}

void main() {
  test('the material section reads back what was written', () {
    final bundle = ShaderBundle.decode(
      _bundle(<String, String>{'Red': _flat('Red', 'vec3(1.0, 0.0, 0.0)')}),
    );
    expect(decodeMaterialSection(bundle), <String, String>{
      'Red': _flat('Red', 'vec3(1.0, 0.0, 0.0)'),
    });
    final none = ShaderBundle(
      name: 'hand-written',
      sdk: '',
      stages: const <ShaderBundleStage>[],
    );
    expect(decodeMaterialSection(none), isEmpty);
  });

  test(
    'the software backend draws a built material with nothing registered',
    () async {
      // Mutation: leave the material section out of `compileMaterial` in
      // `flutter3d_build`, or the compile out of `CpuLoadedShaderLibrary`, and
      // the bundle is refused here, as it was before the section existed.
      final device = _device(compiler: materialLanguageCompiler);
      final bytes = _bundle(<String, String>{
        'Red': _flat('Red', 'vec3(1.0, 0.0, 0.0)'),
      });
      final library = await device.loadShaders(bytes);
      final lighting = BundledMaterials.read(bytes)['Red'];

      final center = await _center(device, library, lighting);
      expect(center.x, closeTo(1.0, 0.01));
      expect(center.y, closeTo(0.0, 0.01));
    },
  );

  test('without a compiler the bundle is refused by name', () {
    expect(
      () => _device().loadShaders(
        _bundle(<String, String>{'Red': _flat('Red', 'vec3(1.0, 0.0, 0.0)')}),
      ),
      throwsA(
        isA<ShaderBundleException>().having(
          (ShaderBundleException r) => r.reason,
          'reason',
          contains('materialCompiler'),
        ),
      ),
    );
  });

  test('a reload reaches a draw already holding the stage', () async {
    // Mutation: build a new stage on a reload instead of pointing the one
    // handed out at the new source, and the renderer's pipeline keeps the
    // old colour.
    final device = _device(compiler: materialLanguageCompiler);
    final library = await device.loadShaders(
      _bundle(<String, String>{'Paint': _flat('Paint', 'vec3(1.0, 0.0, 0.0)')}),
    );
    final lighting = BundledMaterials.read(
      _bundle(<String, String>{'Paint': _flat('Paint', 'vec3(1.0, 0.0, 0.0)')}),
    )['Paint'];
    final handle = library['Paint'];

    expect((await _center(device, library, lighting)).x, closeTo(1.0, 0.01));
    library.refresh(
      _bundle(<String, String>{'Paint': _flat('Paint', 'vec3(0.0, 0.0, 1.0)')}),
    );
    expect(identical(library['Paint'], handle), isTrue);
    final after = await _center(device, library, lighting);
    expect(after.x, closeTo(0.0, 0.01));
    expect(after.z, closeTo(1.0, 0.01));
  });

  test('a source that does not compile leaves the library as it was', () async {
    final device = _device(compiler: materialLanguageCompiler);
    final library = await device.loadShaders(
      _bundle(<String, String>{'Paint': _flat('Paint', 'vec3(1.0, 0.0, 0.0)')}),
    );
    expect(
      () => library.refresh(
        _bundle(<String, String>{'Paint': 'material Paint { fragment { } '}),
      ),
      throwsA(isA<ShaderBundleException>()),
    );
    final lighting = BundledMaterials.read(
      _bundle(<String, String>{'Paint': _flat('Paint', 'vec3(1.0, 0.0, 0.0)')}),
    )['Paint'];
    expect((await _center(device, library, lighting)).x, closeTo(1.0, 0.01));
  });

  test('a lighting model is the program\'s own answer about its maps', () {
    // A material that samples a map is bound with it, and the light list it
    // never declares is not: a hand-built model that defaulted the list to
    // its maps is the bind failure `MaterialBindings` exists to prevent.
    final textured = BundledMaterials.read(
      _bundle(<String, String>{
        'Mapped': '''
material Mapped {
  texture tex = base_color_texture;
  fragment {
    return vec4(sample(tex, uv).rgb, 1.0);
  }
}
''',
      }),
    )['Mapped'];
    expect(textured.usesAlbedoTexture, isTrue);
    expect(textured.usesLightList, isFalse);
    expect(
      () => BundledMaterials.read(
        _bundle(<String, String>{'Mapped': _flat('Mapped', 'vec3(0.5)')}),
      )['Other'],
      throwsArgumentError,
    );
  });

  test('a uniform takes the value set on the material', () async {
    // `P8`: the value a game sets in `RenderMaterial.parameters`, bound as
    // `MaterialParams`, reaches the software stage as it reaches the GPU's.
    const source = '''
material Tinted {
  uniform vec3 tint = vec3(1.0, 0.0, 0.0);
  fragment {
    return vec4(tint, 1.0);
  }
}
''';
    final device = _device(compiler: materialLanguageCompiler);
    final bytes = _bundle(<String, String>{'Tinted': source});
    final library = await device.loadShaders(bytes);
    final materials = BundledMaterials.read(bytes);
    final lighting = materials['Tinted'];
    expect(lighting.usesMaterialParameters, isTrue);

    final defaults = materials.parameters('Tinted');
    expect(defaults['tint'], <double>[1.0, 0.0, 0.0]);
    final center = await _center(
      device,
      library,
      lighting,
      parameters: <String, Float32List>{
        'tint': Float32List.fromList(<double>[0.0, 1.0, 0.0]),
      },
    );
    expect(center.x, closeTo(0.0, 0.01));
    expect(center.y, closeTo(1.0, 0.01));
  });

  group('more than one bundle — P8', () {
    test('two bundles added to one renderer both draw', () async {
      // Each `.f3dmat` the hook compiles is a bundle of its own.
      //
      // Mutation: make `RendererSteps.addMaterials` keep only the latest library
      // — the first bundle's material is a missing stage.
      final device = _device(compiler: materialLanguageCompiler);
      final red = _bundle(<String, String>{
        'Red': _flat('Red', 'vec3(1.0, 0.0, 0.0)'),
      });
      final blue = _bundle(<String, String>{
        'Blue': _flat('Blue', 'vec3(0.0, 0.0, 1.0)'),
      });
      final renderer = Renderer.create(device: device);
      renderer.renderSteps
        ..addMaterials(await device.loadShaders(red))
        ..addMaterials(await device.loadShaders(blue));

      final first = await _center(
        device,
        null,
        BundledMaterials.read(red)['Red'],
        renderer: renderer,
      );
      final second = await _center(
        device,
        null,
        BundledMaterials.read(blue)['Blue'],
        renderer: renderer,
      );
      expect(first.x, closeTo(1.0, 0.01));
      expect(second.z, closeTo(1.0, 0.01));
    });

    test('the one added later wins a name, and taking it out gives the name '
        'back', () async {
      // Mutation: keep `_fragmentShaders` across `addMaterials` — the stage
      // the renderer resolved first goes on drawing after the name changed
      // hands.
      final device = _device(compiler: materialLanguageCompiler);
      final red = await device.loadShaders(
        _bundle(<String, String>{
          'Paint': _flat('Paint', 'vec3(1.0, 0.0, 0.0)'),
        }),
      );
      final green = await device.loadShaders(
        _bundle(<String, String>{
          'Paint': _flat('Paint', 'vec3(0.0, 1.0, 0.0)'),
        }),
      );
      final lighting = BundledMaterials.read(
        _bundle(<String, String>{
          'Paint': _flat('Paint', 'vec3(1.0, 0.0, 0.0)'),
        }),
      )['Paint'];
      final renderer = Renderer.create(device: device, materials: red);

      Future<Vector3> paint() =>
          _center(device, null, lighting, renderer: renderer);
      expect((await paint()).x, closeTo(1.0, 0.01));
      final added = renderer.renderSteps.addMaterials(green);
      expect((await paint()).y, closeTo(1.0, 0.01));
      added.cancel();
      expect((await paint()).x, closeTo(1.0, 0.01));
      // Cancelling twice takes nothing else out.
      added.cancel();
      expect((await paint()).x, closeTo(1.0, 0.01));
    });
  });

  test('each copy of a batch reads its own numbers as instance — P8', () async {
    // Two instances of one cube, the left given red and the right green as
    // their own four numbers; the material paints what it reads.
    //
    // Mutation: write nought for `kVInstance` in the software backend's
    // instanced vertex stage — both copies draw black.
    const source = '''
material Painted {
  fragment {
    return vec4(instance.rgb, 1.0);
  }
}
''';
    final device = _device(compiler: materialLanguageCompiler);
    final bytes = _bundle(<String, String>{'Painted': source});
    final library = await device.loadShaders(bytes);
    final batch =
        InstancedMeshNode(
            DeviceMesh.upload(device, CuboidShape().build()),
            RenderMaterial(lighting: BundledMaterials.read(bytes)['Painted']),
            capacity: 2,
          )
          ..addInstance(
            Matrix4.translationValues(-0.8, 0.0, 0.0)
              ..scaleByDouble(0.6, 0.6, 0.6, 1.0),
            data: Vector4(1.0, 0.0, 0.0, 0.0),
          )
          ..addInstance(
            Matrix4.translationValues(0.8, 0.0, 0.0)
              ..scaleByDouble(0.6, 0.6, 0.6, 1.0),
            data: Vector4(0.0, 1.0, 0.0, 0.0),
          );
    final camera = CameraNode()..setPosition(0.0, 0.0, 3.0);
    final scene = Scene()
      ..add(camera)
      ..add(batch);
    final result = Renderer.create(device: device, materials: library).render(
      width: _size,
      height: _size,
      scene: scene,
      views: <RenderView>[RenderView(camera: camera)],
      settings: const RenderSettings(
        bloom: BloomSettings(enabled: false),
        tonemap: false,
        look: LookSettings(dither: 0.0),
      ),
    );
    final pixels = await device.readback(result.frame);
    List<int> at(int x) {
      final i = ((_size ~/ 2) * _size + x) * 4;
      return <int>[pixels.getUint8(i), pixels.getUint8(i + 1)];
    }

    expect(at(_size ~/ 2 - 8), <int>[255, 0]);
    expect(at(_size ~/ 2 + 8), <int>[0, 255]);
  });
}
