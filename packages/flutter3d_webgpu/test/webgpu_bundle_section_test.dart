/// The bundle section, written and read back.
///
/// Runs on both platforms, which is the point of the file it tests: the packer
/// writes it on the VM and the device reads it in a browser, and one codec both
/// import is how the two stay the same document rather than two hand-kept
/// transcriptions of a format nobody wrote down.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:flutter3d_webgpu/src/webgpu_bundle_section.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final stage = WebGpuStage(
    wgsl:
        '@vertex fn main() -> @builtin(position) vec4<f32> '
        '{ return vec4<f32>(0.0); }',
    attributes: const <WebGpuAttribute>[
      WebGpuAttribute(
        name: 'position',
        location: 0,
        format: VertexFormat.float32x3,
      ),
      WebGpuAttribute(
        name: 'texcoord',
        location: 1,
        format: VertexFormat.float32x2,
      ),
    ],
    blocks: const <WebGpuBlock>[
      WebGpuBlock(
        name: 'FrameInfo',
        group: 0,
        binding: 0,
        sizeInBytes: 80,
        members: <WebGpuBlockMember>[
          WebGpuBlockMember(name: 'mvp', offsetInBytes: 0, sizeInBytes: 64),
          WebGpuBlockMember(name: 'tint', offsetInBytes: 64, sizeInBytes: 16),
        ],
      ),
    ],
    samplers: const <WebGpuSampler>[
      WebGpuSampler(
        name: 'sky_texture',
        group: 0,
        textureBinding: 1,
        samplerBinding: 2,
        dimension: WebGpuTextureDimension.cube,
      ),
    ],
  );

  test('a section comes back the way it went in', () {
    final decoded = decodeWebGpuSection(
      encodeWebGpuSection(
        vertex: <String, WebGpuStage>{'MeshVertex': stage},
        fragment: <String, WebGpuStage>{},
      ),
    );

    final back = decoded.vertex['MeshVertex']!;
    expect(decoded.fragment, isEmpty);
    expect(back.wgsl, stage.wgsl);
    expect(
      back.attributes.map((a) => (a.name, a.location, a.format)),
      <(String, int, VertexFormat)>[
        ('position', 0, VertexFormat.float32x3),
        ('texcoord', 1, VertexFormat.float32x2),
      ],
    );
    final block = back.blocks.single;
    expect(
      (block.name, block.group, block.binding, block.sizeInBytes),
      ('FrameInfo', 0, 0, 80),
    );
    expect(
      block.members.map((m) => (m.name, m.offsetInBytes, m.sizeInBytes)),
      <(String, int, int)>[('mvp', 0, 64), ('tint', 64, 16)],
    );
    final sampler = back.samplers.single;
    expect(
      (
        sampler.name,
        sampler.group,
        sampler.textureBinding,
        sampler.samplerBinding,
        sampler.dimension,
      ),
      ('sky_texture', 0, 1, 2, WebGpuTextureDimension.cube),
    );
  });

  test('a sampler carries two bindings, because WGSL needs two', () {
    // The one shape worth restating in a test: `bindTexture('sky_texture', …)`
    // is one call on the contract and two bind group entries underneath, and a
    // section that carried one number would leave the device guessing the
    // other.
    final sampler = stage.samplers.single;
    expect(sampler.samplerBinding, isNot(sampler.textureBinding));
  });

  group('refusals', () {
    ByteData bytes(Object document) => Uint8List.fromList(
      utf8.encode(jsonEncode(document)),
    ).buffer.asByteData();

    test('bytes that are not the document', () {
      expect(
        () => decodeWebGpuSection(bytes(<Object>[])),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => decodeWebGpuSection(bytes(<String, Object>{'vertex': 1})),
        throwsA(isA<FormatException>()),
      );
    });

    test('a stage with no WGSL in it', () {
      expect(
        () => decodeWebGpuSection(
          bytes(<String, Object>{
            'vertex': <String, Object>{
              'A': <String, Object>{
                'attributes': <Object>[],
                'blocks': <Object>[],
                'samplers': <Object>[],
              },
            },
            'fragment': <String, Object>{},
          }),
        ),
        throwsA(isA<FormatException>()),
      );
    });

    test('a vertex format nothing in the contract answers to', () {
      // Not a theoretical refusal: a section written by a newer packer against
      // an older contract would land here, and the alternative to refusing is
      // a pipeline built with a format the device silently picked.
      expect(
        () => decodeWebGpuSection(
          bytes(<String, Object>{
            'vertex': <String, Object>{
              'A': <String, Object>{
                'wgsl': '',
                'attributes': <Object>[
                  <String, Object>{
                    'name': 'position',
                    'location': 0,
                    'format': 'float16x3',
                  },
                ],
                'blocks': <Object>[],
                'samplers': <Object>[],
              },
            },
            'fragment': <String, Object>{},
          }),
        ),
        throwsA(isA<FormatException>()),
      );
    });

    test('a texture dimension this backend has no view for', () {
      expect(
        () => decodeWebGpuSection(
          bytes(<String, Object>{
            'vertex': <String, Object>{},
            'fragment': <String, Object>{
              'A': <String, Object>{
                'wgsl': '',
                'attributes': <Object>[],
                'blocks': <Object>[],
                'samplers': <Object>[
                  <String, Object>{
                    'name': 'volume',
                    'group': 1,
                    'texture': 0,
                    'sampler': 1,
                    'dimension': '3d',
                  },
                ],
              },
            },
          }),
        ),
        throwsA(isA<FormatException>()),
      );
    });
  });
}
