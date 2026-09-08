/// The packer's half of the section document, read back by the device's half.
///
///     flutter test test/wgsl_section_test.dart
///
/// `webgpu_bundle_section_test.dart` holds the codec against itself: what
/// `encodeWebGpuSection` writes, `decodeWebGpuSection` reads. That is the
/// engine's own table, and both ends of it are the same file. A bundle is the
/// other case, and its two ends are two files — `wgsl_section.dart` writes the
/// document because the codec cannot be imported by a `dart run` script, and
/// `webgpu_bundle_section.dart` reads it at the device. This is where those two
/// meet.
///
/// Runs on both platforms, like the codec's own test and for a related reason:
/// the writer is the packer's, which is a VM program, and the reader is the
/// device's, which is a browser one, and a document neither end could be run
/// against on its own platform would be a document only half of it was ever
/// held to.
///
/// What it is looking for is a spelling, not a shape. The writer builds JSON by
/// hand from `PreparedStage`, whose fields name things the way the *preparation*
/// names them; the reader parses JSON into types that name things the way
/// **WebGPU** does. `twoDimensional` and `2d` are the same dimension under two
/// names, and a writer that emitted the first would produce a document that
/// looks entirely reasonable and is refused by `decodeWebGpuSection` at the
/// device, on somebody else's machine, long after the build that wrote it.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:flutter3d_webgpu/src/glsl_to_wgsl.dart';
import 'package:flutter3d_webgpu/src/webgpu_bundle_section.dart';
import 'package:flutter3d_webgpu/src/webgpu_loaded_shaders.dart';
import 'package:flutter3d_webgpu/src/wgsl_section.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // Every field the document has, with values nothing would produce by
  // accident: two attributes of different formats, a block whose members are
  // not at zero, and both sampler dimensions — the pair the spelling check is
  // about.
  const prepared = PreparedStage(
    glsl: '// not read here; the WGSL is what travels',
    attributes: <PreparedAttribute>[
      (name: 'position', location: 0, format: 'float32x3'),
      (name: 'joints', location: 3, format: 'uint32x4'),
    ],
    blocks: <PreparedBlock>[
      (
        name: 'FrameInfo',
        group: kVertexGroup,
        binding: 0,
        sizeInBytes: 80,
        members: <PreparedMember>[
          (name: 'mvp', offsetInBytes: 0, sizeInBytes: 64),
          (name: 'tint', offsetInBytes: 64, sizeInBytes: 16),
        ],
      ),
    ],
    samplers: <PreparedSampler>[
      (
        name: 'base_color_texture',
        group: kVertexGroup,
        textureBinding: 1,
        samplerBinding: 2,
        dimension: kTwoDimensional,
      ),
      (
        name: 'sky_texture',
        group: kVertexGroup,
        textureBinding: 3,
        samplerBinding: 4,
        dimension: kCubeDimension,
      ),
    ],
  );
  const PackedStage stage = (
    wgsl:
        '@vertex fn main() -> @builtin(position) vec4<f32> '
        '{ return vec4<f32>(0.0); }',
    prepared: prepared,
  );

  String document() => wgslSectionDocument(
    vertex: <String, PackedStage>{'MeshVertex': stage},
    fragment: <String, PackedStage>{},
  );

  WebGpuSectionStages read(String text) => decodeWebGpuSection(
    Uint8List.fromList(utf8.encode(text)).buffer.asByteData(),
  );

  test('the packer writes the document the device reads', () {
    final decoded = read(document());
    expect(decoded.fragment, isEmpty);
    final back = decoded.vertex['MeshVertex']!;

    expect(back.wgsl, stage.wgsl);

    expect(back.attributes.map((a) => a.name), <String>['position', 'joints']);
    expect(back.attributes.map((a) => a.location), <int>[0, 3]);
    expect(back.attributes.map((a) => a.format), <VertexFormat>[
      VertexFormat.float32x3,
      VertexFormat.uint32x4,
    ]);

    expect(back.blocks, hasLength(1));
    final block = back.blocks.single;
    expect(block.name, 'FrameInfo');
    expect(block.group, kVertexGroup);
    expect(block.binding, 0);
    expect(block.sizeInBytes, 80);
    expect(block.members.map((m) => m.name), <String>['mvp', 'tint']);
    expect(block.members.map((m) => m.offsetInBytes), <int>[0, 64]);
    expect(block.members.map((m) => m.sizeInBytes), <int>[64, 16]);

    // The spelling this file exists for. The preparation says
    // `twoDimensional`; the document has to say `2d`, because that string is
    // handed to a bind group layout entry as it stands.
    expect(back.samplers.map((s) => s.name), <String>[
      'base_color_texture',
      'sky_texture',
    ]);
    expect(back.samplers.map((s) => s.dimension), <WebGpuTextureDimension>[
      WebGpuTextureDimension.twoDimensional,
      WebGpuTextureDimension.cube,
    ]);
    expect(back.samplers.map((s) => s.textureBinding), <int>[1, 3]);
    expect(back.samplers.map((s) => s.samplerBinding), <int>[2, 4]);
    expect(back.samplers.map((s) => s.group), <int>[
      kVertexGroup,
      kVertexGroup,
    ]);
  });

  test('the document says the version the reader expects', () {
    // The two constants cannot be one: the writer runs where
    // `WebGpuLoadedShaderLibrary` cannot be imported, because that class
    // reaches `flutter3d_hardware`'s barrel and the barrel reaches
    // `package:flutter`. So they are held equal here instead — the day the
    // shape changes, whichever half is bumped first fails this rather than
    // shipping a bundle the other half misreads.
    expect(kSectionVersion, WebGpuLoadedShaderLibrary.sectionVersion);
    expect(
      (jsonDecode(document()) as Map<String, dynamic>)['version'],
      WebGpuLoadedShaderLibrary.sectionVersion,
    );
  });

  test('a dimension neither half knows stops the packer', () {
    // The failure a `switch` with no default would have made a crash and a
    // `?? '2d'` would have made a silently wrong layout. A cube sampled
    // through a `2d` view is refused at pipeline creation with nothing at the
    // build to explain it.
    const odd = PreparedStage(
      glsl: '',
      attributes: <PreparedAttribute>[],
      blocks: <PreparedBlock>[],
      samplers: <PreparedSampler>[
        (
          name: 'volume_texture',
          group: kFragmentGroup,
          textureBinding: 0,
          samplerBinding: 1,
          dimension: 'threeDimensional',
        ),
      ],
    );
    expect(
      () => wgslSectionDocument(
        vertex: <String, PackedStage>{},
        fragment: <String, PackedStage>{'Volume': (wgsl: '', prepared: odd)},
      ),
      throwsA(
        isA<WgslSectionError>().having(
          (e) => e.message,
          'message',
          contains('threeDimensional'),
        ),
      ),
    );
  });
}
