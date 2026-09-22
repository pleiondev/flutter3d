/// A textured sky, and the table nothing in a picture can check.
///
///     flutter test test/sky_cube_test.dart
///
/// **The face order is the whole risk here.** Six images go up as +X, −X, +Y,
/// −Y, +Z, −Z, and a sky with two of them transposed is complete, seamless and
/// wrong — it looks like a sky somebody authored badly. Every backend has its
/// own way of naming a face: Impeller takes a slice index, WebGL takes six
/// consecutive face targets, and the software rasteriser takes the table in
/// `BoundTexture.sampleCube`. Three independent chances to disagree, and no
/// picture that says so.
///
/// So each face is a different colour, and the camera is pointed at six known
/// directions. A wrong entry in any of the three is a wrong colour here.
library;

import 'dart:typed_data';

import 'package:flutter3d/flutter3d.dart' hide Material;
import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:flutter3d_cpu/testing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

const int _width = 64;
const int _height = 64;

/// The six faces, one flat colour each, in the order the interface documents.
///
/// Primary and secondary colours rather than anything subtle: what is being
/// distinguished is *which* face, and a test that had to tell two greys apart
/// would be measuring the filter instead.
const List<List<int>> _faceColours = <List<int>>[
  <int>[255, 0, 0], // +X red
  <int>[0, 255, 0], // -X green
  <int>[0, 0, 255], // +Y blue
  <int>[255, 255, 0], // -Y yellow
  <int>[255, 0, 255], // +Z magenta
  <int>[0, 255, 255], // -Z cyan
];

({CpuDevice device, Renderer renderer}) _engine() {
  final it = cpuTestDevice(width: _width, height: _height);
  return (
    device: it.device,
    renderer: Renderer.create(
      device: it.device,
      fallbackAlbedo: it.albedo,
      fallbackNormal: it.normal,
    ),
  );
}

/// A cube whose faces are the six colours above, [size] square.
TextureHandle _cube(CpuDevice device, {int size = 4}) {
  final faces = <ByteData>[
    for (final colour in _faceColours)
      ByteData.sublistView(
        Uint8List.fromList(<int>[
          for (var i = 0; i < size * size; i++) ...<int>[
            colour[0],
            colour[1],
            colour[2],
            255,
          ],
        ]),
      ),
  ];
  final handle = device.createCubeTextureFromPixels(
    size: size,
    format: TextureFormat.r8g8b8a8UNormInt,
    faces: faces,
  );
  expect(handle, isNotNull, reason: 'the device refused a six-face cube');
  return handle!;
}

/// Draws an empty scene with the cube as its sky, looking along [towards].
Future<Uint8List> _look(
  ({CpuDevice device, Renderer renderer}) it,
  TextureHandle cube,
  Vector3 towards, {
  Vector3? tint,
}) async {
  final scene = Scene();
  final camera = CameraNode(
    projection: const PerspectiveProjection(
      // Narrow, so the whole frame is well inside one face and the edges never
      // come into shot. What is being read is which face, not how it filters.
      fovYRadians: 0.35,
      near: 0.3,
      far: 100.0,
    ),
  )..lookAt(towards);
  scene.add(camera);

  final result = it.renderer.render(
    width: _width,
    height: _height,
    scene: scene,
    views: <RenderView>[
      RenderView(camera: camera, clearColor: Vector4(0.0, 0.0, 0.0, 1.0)),
    ],
    settings: RenderSettings(
      sky: SkySettings(enabled: true, cubemap: cube, tint: tint),
      bloom: const BloomSettings(enabled: false),
      tonemap: false,
      exposure: 1.0,
    ),
  );
  final pixels = await it.device.readPixels(result.frame);
  expect(pixels, isNotNull);
  return pixels!.buffer.asUint8List();
}

/// The colour at the centre of the frame, which is the direction the camera
/// points.
List<int> _centre(Uint8List rgba) {
  final i = ((_height ~/ 2) * _width + _width ~/ 2) * 4;
  return <int>[rgba[i], rgba[i + 1], rgba[i + 2]];
}

/// Which of the six face colours this is nearest to, or -1.
int _whichFace(List<int> rgb) {
  for (var i = 0; i < _faceColours.length; i++) {
    final want = _faceColours[i];
    var close = true;
    for (var c = 0; c < 3; c++) {
      // Wide, because the byte went through sRGB decode, exposure and encode
      // on the way. What is being told apart is red from green, not a shade.
      if ((rgb[c] - want[c]).abs() > 60) close = false;
    }
    if (close) return i;
  }
  return -1;
}

void main() {
  test('a cube is six faces and says so', () {
    final device = CpuDevice(
      width: 4,
      height: 4,
      shaders: CpuShaderLibrary(builtinCpuShaders()),
    );
    final cube = _cube(device);

    expect(cube.type, TextureType.textureCube);
    expect(cube.sliceCount, 6);
    expect(device.supportsCubeTextures, isTrue);
  });

  test('a cube built from the wrong number of faces is refused', () {
    // Null rather than five faces and whatever the allocation held. Mutation:
    // drop the length check — the sixth face is uninitialised memory, which on
    // this backend is black and on a GPU is anything at all.
    final device = CpuDevice(
      width: 4,
      height: 4,
      shaders: CpuShaderLibrary(builtinCpuShaders()),
    );
    final five = <ByteData>[
      for (var i = 0; i < 5; i++) ByteData.sublistView(Uint8List(4 * 4 * 4)),
    ];
    expect(
      device.createCubeTextureFromPixels(
        size: 4,
        format: TextureFormat.r8g8b8a8UNormInt,
        faces: five,
      ),
      isNull,
    );
  });

  test('each direction lands on its own face', () async {
    // The test this file exists for. Six looks, six colours, and the mapping
    // between them is the face table — held identically in three backends and
    // checkable in none of them by eye.
    //
    // Mutation: swap any two entries in `BoundTexture.sampleCube`, or negate
    // one of the `sc`/`tc` assignments. A sign error mirrors a face rather than
    // moving it, so it survives everything except a face whose two halves
    // differ — which is why `_cube` could not use a gradient.
    final it = _engine();
    final cube = _cube(it.device);

    final looks = <(String, Vector3, int)>[
      ('+X', Vector3(1.0, 0.0, 0.0), 0),
      ('-X', Vector3(-1.0, 0.0, 0.0), 1),
      ('+Y', Vector3(0.0, 1.0, 0.0), 2),
      ('-Y', Vector3(0.0, -1.0, 0.0), 3),
      ('+Z', Vector3(0.0, 0.0, 1.0), 4),
      ('-Z', Vector3(0.0, 0.0, -1.0), 5),
    ];

    for (final (name, direction, expected) in looks) {
      final frame = await _look(it, cube, direction);
      final rgb = _centre(frame);
      expect(
        _whichFace(rgb),
        expected,
        reason:
            'looking $name gave $rgb, which is face ${_whichFace(rgb)} '
            'rather than $expected',
      );
    }
  });

  test('every direction samples the texel that was baked for it', () async {
    // The strong version of the test above, and the one that catches a
    // *mirrored* face rather than only a transposed one. A flat colour cannot
    // tell the two apart: flip the sign of `sc` on +X and every direction still
    // lands on red. That mutation survived the colour test, which is how this
    // one came to exist.
    //
    // Each texel is baked with the direction it stands for, encoded as a
    // colour. The baking uses the **inverse** table — texel to direction —
    // written here straight from the GL specification, independently of the
    // forward table in `BoundTexture.sampleCube`. Two independent writings of
    // the same convention; a sign wrong in either makes them disagree.
    //
    // Mutation: any single change to the face table — swap two faces, negate an
    // `sc` or a `tc`, exchange `sc` and `tc` on one face. All of them move the
    // sampled direction away from the baked one.
    const size = 32;

    /// Texel to direction, from the GL spec's table.
    Vector3 directionFor(int face, double u, double v) {
      final s = u * 2.0 - 1.0;
      final t = v * 2.0 - 1.0;
      return switch (face) {
        0 => Vector3(1.0, -t, -s),
        1 => Vector3(-1.0, -t, s),
        2 => Vector3(s, 1.0, t),
        3 => Vector3(s, -1.0, -t),
        4 => Vector3(s, -t, 1.0),
        _ => Vector3(-s, -t, -1.0),
      }..normalize();
    }

    /// A direction as a colour: each axis from -1..1 into 0..255.
    List<int> encode(Vector3 direction) {
      final unit = direction.normalized();
      return <int>[
        ((unit.x * 0.5 + 0.5) * 255).round().clamp(0, 255),
        ((unit.y * 0.5 + 0.5) * 255).round().clamp(0, 255),
        ((unit.z * 0.5 + 0.5) * 255).round().clamp(0, 255),
      ];
    }

    final it = _engine();
    final faces = <ByteData>[
      for (var face = 0; face < 6; face++)
        ByteData.sublistView(
          Uint8List.fromList(<int>[
            for (var y = 0; y < size; y++)
              for (var x = 0; x < size; x++) ...<int>[
                // Texel centres, which is what a texture coordinate addresses.
                ...encode(
                  directionFor(face, (x + 0.5) / size, (y + 0.5) / size),
                ),
                255,
              ],
          ]),
        ),
    ];
    final cube = it.device.createCubeTextureFromPixels(
      size: size,
      format: TextureFormat.r8g8b8a8UNormInt,
      faces: faces,
    )!;

    // Well inside a face, and deliberately **far off its diagonal**: each of
    // these lands at about 0.8 along one axis of the face and 0.1 along the
    // other. Near the diagonal the two axes carry nearly the same value, so
    // exchanging them moves the sample by almost nothing — the first draft used
    // such directions and the swap-`sc`-and-`tc` mutation walked through it.
    final looks = <Vector3>[
      Vector3(1.0, 0.1, -0.8),
      Vector3(-1.0, 0.1, 0.8),
      Vector3(0.8, 1.0, 0.1),
      Vector3(0.8, -1.0, -0.1),
      Vector3(0.8, -0.1, 1.0),
      Vector3(-0.8, -0.1, -1.0),
    ];

    for (final direction in looks) {
      final frame = await _look(it, cube, direction);
      final drawn = _centre(frame);
      final wanted = encode(direction);
      for (var c = 0; c < 3; c++) {
        expect(
          (drawn[c] - wanted[c]).abs(),
          lessThan(14),
          reason: 'looking $direction sampled $drawn, baked $wanted',
        );
      }
    }
  });

  test('the tint multiplies the cube', () async {
    // Mutation: ignore `SkyCubeInfo.tint`. One cube then cannot serve two hours
    // of the day, and the symptom is a setting that does nothing.
    final it = _engine();
    final cube = _cube(it.device);

    final plain = await _look(it, cube, Vector3(1.0, 0.0, 0.0));
    final dimmed = await _look(
      it,
      cube,
      Vector3(1.0, 0.0, 0.0),
      tint: Vector3(0.25, 0.25, 0.25),
    );

    expect(_centre(plain)[0], greaterThan(200));
    expect(_centre(dimmed)[0], lessThan(_centre(plain)[0] - 40));
  });

  test('a cube sky is not a surface either', () async {
    // The same claim `sky.frag` makes, and it has to be made twice because it
    // is two shaders. A cube sky that wrote a surface would have the floor
    // reflecting the horizon as though it were a wall.
    final it = _engine();
    final cube = _cube(it.device);
    final scene = Scene();
    final camera = CameraNode()..lookAt(Vector3(1.0, 0.0, 0.0));
    scene.add(camera);

    final result = it.renderer.render(
      width: _width,
      height: _height,
      scene: scene,
      views: <RenderView>[
        RenderView(camera: camera, clearColor: Vector4(0.0, 0.0, 0.0, 1.0)),
      ],
      settings: RenderSettings(
        sky: SkySettings(enabled: true, cubemap: cube),
        surfaceBuffer: true,
        showSurfaceBuffer: true,
        bloom: const BloomSettings(enabled: false),
        tonemap: false,
      ),
    );
    final pixels = await it.device.readPixels(result.frame);
    final bytes = pixels!.buffer.asUint8List();

    var total = 0;
    for (var i = 0; i < bytes.length; i += 4) {
      total += bytes[i] + bytes[i + 1];
    }
    expect(total / (bytes.length / 4), lessThan(8.0));
  });

  test('a 2D texture handed to the sky is refused, not drawn', () async {
    // Mutation: drop the type check in `_encodeSky`. A 2D texture bound to a
    // cube sampler is black on one backend and rubbish on another, and neither
    // says why.
    final it = _engine();
    final flat = it.device.createTextureFromPixels(
      width: 1,
      height: 1,
      format: TextureFormat.r8g8b8a8UNormInt,
      pixels: ByteData.sublistView(Uint8List.fromList(<int>[255, 0, 0, 255])),
    )!;

    final scene = Scene();
    final camera = CameraNode()..lookAt(Vector3(0.0, 0.0, 1.0));
    scene.add(camera);

    expect(
      () => it.renderer.render(
        width: _width,
        height: _height,
        scene: scene,
        views: <RenderView>[RenderView(camera: camera)],
        settings: RenderSettings(
          sky: SkySettings(enabled: true, cubemap: flat),
        ),
      ),
      throwsStateError,
    );
  });
}
