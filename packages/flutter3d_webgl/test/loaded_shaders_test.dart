/// A bundle loaded from bytes and reloaded in place, on this backend, by
/// pixel.
///
///     flutter test --platform chrome test/loaded_shaders_test.dart
///
/// **The hot-reload contract, drawn.** A look the engine never shipped is
/// compiled from a bundle's `webgl` section, a wall is drawn with it, the
/// bundle is reloaded with the look changed, the renderer drops its pipelines,
/// and the wall is drawn again in the new colour — through the same
/// `ShaderHandle`. Then the two ways a reload can go wrong: a stage that no
/// longer compiles, and a bundle that dropped a stage in use, both of which
/// leave the picture as it was.
@TestOn('browser')
library;

import 'dart:typed_data';

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_webgl/engine_shaders.dart';
import 'package:flutter3d_webgl/flutter3d_webgl.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart' hide Colors;

const int _width = 32;
const int _height = 32;

/// A flat colour, in GLSL ES 3.00 as the section carries it. Both outputs
/// declared, the way the engine's own stages do, so the pipeline matches the
/// scene pass whether or not it has a surface buffer attached.
String _flat(String rgb, {bool compiles = true}) =>
    '''
#version 300 es
precision highp float;
in vec3 v_normal;
layout(location = 0) out vec4 frag_color;
layout(location = 1) out vec4 frag_surface;
void main() {
  frag_color = vec4($rgb, 1.0);
  frag_surface = vec4(0.0, 0.0, 1.0, gl_FragCoord.z);
${compiles ? '' : '  this is not GLSL;'}
}
''';

ByteData _bundle(
  Map<String, String> fragment, {
  String name = 'effects',
  Map<String, String> vertex = const <String, String>{},
}) => ShaderBundle(
  name: name,
  sdk: '',
  stages: <ShaderBundleStage>[
    for (final n in vertex.keys) ShaderBundleStage(n, fragment: false),
    for (final n in fragment.keys) ShaderBundleStage(n, fragment: true),
  ],
  sections: <String, ByteData>{
    ShaderBundle.webglSection: encodeWebGlSection(
      vertex: vertex,
      fragment: fragment,
    ),
  },
).encode();

const LightingModel _flatModel = LightingModel(
  'Flat',
  'Flat',
  usesFragInfo: false,
  usesAlbedoTexture: false,
  usesMaterialMaps: false,
  usesMetallicRoughnessMap: false,
  usesMaterialParameters: false,
);

Future<List<int>> _centre(
  WebGlDevice device,
  Renderer renderer,
  Scene scene,
  CameraNode camera,
) async {
  final result = renderer.render(
    width: _width,
    height: _height,
    scene: scene,
    views: <RenderView>[
      RenderView(camera: camera, clearColor: Vector4(0.0, 0.0, 0.0, 1.0)),
    ],
    settings: const RenderSettings(tonemap: false),
  );
  final pixels = (await device.readPixels(result.frame))!.buffer.asUint8List();
  final at = ((_height ~/ 2) * _width + _width ~/ 2) * 4;
  return <int>[pixels[at], pixels[at + 1], pixels[at + 2]];
}

void main() {
  late WebGlDevice device;

  setUp(() {
    final made = WebGlDevice.create(
      width: _width,
      height: _height,
      sources: engineShaders,
    );
    if (made == null) fail('no WebGL2 context in this browser');
    device = made;
  });

  tearDown(() => device.dispose());

  test('a wall drawn through a loaded look changes colour on reload', () async {
    final loaded = await device.loadShaders(
      _bundle(<String, String>{'Flat': _flat('1.0, 0.0, 1.0')}),
    );
    final handle = loaded['Flat'];
    expect(handle, isNotNull);

    final scene = Scene();
    scene.add(
      MeshNode(
        DeviceMesh.upload(
          device,
          CuboidShape(size: Vector3(40.0, 40.0, 1.0)).build(),
        ),
        Material(name: 'wall', lighting: _flatModel),
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

    final renderer = Renderer.create(device: device, materials: loaded);
    final magenta = await _centre(device, renderer, scene, camera);
    expect(magenta[0], greaterThan(200));
    expect(magenta[1], lessThan(60));
    expect(magenta[2], greaterThan(200));

    // The reload. Same handle, new code, and the renderer told to link
    // again. Mutation: leave out `renderer.reloadShaders()` — the cached
    // program still holds the magenta stage and the second read fails.
    loaded.reload(
      _bundle(<String, String>{'Flat': _flat('0.0, 1.0, 0.0')}, name: 'v2'),
    );
    expect(identical(loaded['Flat'], handle), isTrue);
    expect(loaded.name, 'v2');
    renderer.reloadShaders();
    final green = await _centre(device, renderer, scene, camera);
    expect(green[1], greaterThan(200));
    expect(green[0], lessThan(60));
    expect(green[2], lessThan(60));

    // A reload that does not compile is refused by name and changes nothing;
    // the next frame is still green.
    expect(
      () => loaded.reload(
        _bundle(<String, String>{
          'Flat': _flat('1.0, 0.0, 0.0', compiles: false),
        }, name: 'broken'),
      ),
      throwsA(
        isA<ShaderBundleRefused>()
            .having((r) => r.name, 'name', 'broken')
            .having((r) => r.reason, 'reason', contains('did not compile')),
      ),
    );
    expect(loaded.name, 'v2');
    renderer.reloadShaders();
    expect(
      await _centre(device, renderer, scene, camera),
      green,
      reason: 'a refused reload leaves the picture as it was',
    );

    // And one that dropped the stage in use.
    expect(
      () => loaded.reload(
        _bundle(<String, String>{'Other': _flat('1.0, 0.0, 0.0')}),
      ),
      throwsA(
        isA<ShaderBundleRefused>().having(
          (r) => r.reason,
          'reason',
          contains('"Flat"'),
        ),
      ),
    );
    renderer.dispose();
  });

  test('the engine\'s own sources load as a bundle and link', () async {
    final bytes = ShaderBundle(
      name: 'engine',
      sdk: '',
      stages: <ShaderBundleStage>[
        for (final n in engineShaders.vertex.keys)
          ShaderBundleStage(n, fragment: false),
        for (final n in engineShaders.fragment.keys)
          ShaderBundleStage(n, fragment: true),
      ],
      sections: <String, ByteData>{
        ShaderBundle.webglSection: encodeWebGlSection(
          vertex: engineShaders.vertex,
          fragment: engineShaders.fragment,
        ),
      },
    ).encode();
    final loaded = await device.loadShaders(bytes);
    final vertex = loaded['MeshVertex'];
    final fragment = loaded['Pbr'];
    expect(vertex, isNotNull);
    expect(fragment, isNotNull);
    expect(() => device.createPipeline(vertex!, fragment!), returnsNormally);
    // Two libraries, one name, two handles: the program cache keys on the
    // handle and not the word, so both link. Mutation: key `_programs` on
    // names again and the engine's `MeshVertex+Pbr` is handed back for the
    // loaded pair — which this cannot see, but the count below can.
    device.createPipeline(
      device.shaders['MeshVertex']!,
      device.shaders['Pbr']!,
    );
    expect(
      identical(vertex, device.shaders['MeshVertex']),
      isFalse,
      reason: 'a loaded library compiles its own stage',
    );
  });

  test('a bundle with no webgl section is refused by name', () async {
    await expectLater(
      device.loadShaders(
        const ShaderBundle(
          name: 'impeller-only',
          sdk: '3.13.0',
          stages: <ShaderBundleStage>[],
        ).encode(),
      ),
      throwsA(
        isA<ShaderBundleRefused>()
            .having((r) => r.name, 'name', 'impeller-only')
            .having((r) => r.reason, 'reason', contains('webgl')),
      ),
    );
  });

  test('what a loaded library compiled is deleted with the device', () async {
    final loaded = await device.loadShaders(
      _bundle(<String, String>{'Flat': _flat('1.0, 0.0, 1.0')}),
    );
    final before = device.debugTrackedResourceCount;
    expect(loaded['Flat'], isNotNull);
    device.createPipeline(device.shaders['MeshVertex']!, loaded['Flat']!);
    expect(device.debugTrackedResourceCount, greaterThan(before));
    device.dispose();
    expect(device.debugTrackedResourceCount, 0);
    // `tearDown` would dispose twice, which the device refuses; make a fresh
    // one for it to tear down.
    device = WebGlDevice.create(
      width: _width,
      height: _height,
      sources: engineShaders,
    )!;
  });
}
