/// The files an older build wrote, read by this one: `.f3dtrace` and the
/// F3SB shader bundle.
///
///     dart test test/format_fixture_test.dart
///
/// The bytes under `test/fixtures/v<N>/` are minted once and never re-minted
/// (decision 8 of `tasks/1.0-stability.md`). A trace is a document somebody
/// attaches to a bug report and replays a year later, so every 1.x build reads
/// every 1.x trace. A bundle is a build artifact, so a version it does not
/// match is a rebuild: the container still reads every version up to its own,
/// and a newer one is refused as stale.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:flutter3d_hardware/trace.dart';
import 'package:test/test.dart';

Uint8List _bytes(String name, int version) =>
    File('test/fixtures/v$version/$name').readAsBytesSync();

/// A copy of the trace [bytes] whose version word says [version].
Uint8List _withVersion(Uint8List bytes, int version) {
  final copy = Uint8List.fromList(bytes);
  ByteData.sublistView(copy).setUint32(8, version, Endian.little);
  return copy;
}

/// The offset just past the first occurrence of [text] in [bytes]: where a
/// stage's kind byte sits after its name.
int _indexAfter(Uint8List bytes, String text) {
  final needle = ascii.encode(text);
  for (var i = 0; i + needle.length <= bytes.length; i++) {
    var match = true;
    for (var j = 0; j < needle.length && match; j++) {
      match = bytes[i + j] == needle[j];
    }
    if (match) return i + needle.length;
  }
  throw StateError('$text is not in the fixture');
}

void main() {
  group('.f3dtrace', () {
    test('the version 1 fixture decodes to the frame it recorded', () {
      final trace = Trace.decode(_bytes('frame.f3dtrace', 1));

      // Mutation: refuse anything but the current version, then bump it.
      expect(trace.metadata['backend'], 'fixture');
      expect(trace.events.map((TraceEvent e) => e.kind), <String>[
        'beginFrame',
        'loadShaders',
        'draw',
        'submit',
      ]);
      expect((trace.events[2] as TraceDraw).instanceCount, 2);
      final shaders = trace.events[1] as TraceLoadShaders;
      expect(ascii.decode(shaders.bytes.buffer.asUint8List()), 'F3SB');
    });

    test('the version 2 fixture keeps the layer, the depth and the shape', () {
      final trace = Trace.decode(_bytes('frame.f3dtrace', 2));

      // Mutation: drop the `layer` key from the reader, or read a created
      // texture as a pool's target, and the replay draws a different frame.
      final created = trace.events.whereType<TraceCreateTexture>().toList();
      expect(created.first.spec.dimension, TextureDimension.d2Array);
      expect(created.first.spec.depthOrArrayLayers, 2);
      expect(created.first.spec.label, 'layers');
      expect(created.last.spec, isA<RenderTargetDescriptor>());
      final pass = trace.events.whereType<TraceBeginRenderPass>().single;
      expect(pass.colors.single.layer, 1);
      expect(pass.depth!.depthReadOnly, isTrue);
      expect(pass.depth!.loadAction, LoadAction.load);
    });

    test('a version 1 header is lifted unchanged', () {
      // Version 2 only added keys a version 1 header lacks, so the lift
      // rewrites nothing: the same header read as either version is the
      // same frame. Mutation: a lift that filled or dropped a key.
      final v2 = _bytes('frame.f3dtrace', 2);
      expect(
        Trace(Trace.decode(_withVersion(v2, 1)).events).encode(),
        Trace(Trace.decode(v2).events).encode(),
      );
    });

    test('a trace newer than this build is refused', () {
      // Mutation: drop the upper bound and a future trace half-replays.
      expect(
        () => Trace.decode(
          _withVersion(_bytes('frame.f3dtrace', 2), Trace.formatVersion + 1),
        ),
        throwsA(isA<TraceFormatException>()),
      );
    });

    test('every version up to this build has a fixture', () {
      // Mutation: bump `Trace.formatVersion` with no new fixture minted.
      for (var v = 1; v <= Trace.formatVersion; v++) {
        expect(Trace.decode(_bytes('frame.f3dtrace', v)).events, isNotEmpty);
      }
    });
  });

  group('F3SB', () {
    test('the version 1 fixture decodes with its stage and section', () {
      final bundle = ShaderBundle.decode(
        ByteData.sublistView(_bytes('effects.f3shaders', 1)),
      );

      // Mutation: put back the exact-version gate, then bump it.
      expect(bundle.name, 'effects');
      expect(bundle.sdk, '3.13.0');
      expect(bundle.names, <String>['Glow']);
      expect(decodeMaterialSection(bundle).keys, <String>['Glow']);
    });

    test('the version 2 fixture says each stage kind', () {
      final bundle = ShaderBundle.decode(
        ByteData.sublistView(_bytes('effects.f3shaders', 2)),
      );

      // Mutation: write `fragment ? 1 : 0` again, and the kernel reads back
      // as a vertex stage.
      expect(
        <String, ShaderStageKind>{
          for (final stage in bundle.stages) stage.name: stage.kind,
        },
        <String, ShaderStageKind>{
          'Glow': ShaderStageKind.fragment,
          'Spread': ShaderStageKind.compute,
        },
      );
      expect(decodeMaterialSection(bundle).keys, <String>['Glow']);
    });

    test('a version 1 bundle reads its stages as it always did', () {
      final bytes = Uint8List.fromList(_bytes('effects.f3shaders', 1));
      expect(
        ShaderBundle.decode(ByteData.sublistView(bytes)).stages.single.kind,
        ShaderStageKind.fragment,
      );
      // A version 1 packer wrote 1 for a fragment stage and 0 for anything
      // else; any other byte reads as the vertex stage a version 1 reader
      // took it for, not as a kind version 2 gave that code.
      bytes[_indexAfter(bytes, 'Glow')] = 2;
      expect(
        ShaderBundle.decode(ByteData.sublistView(bytes)).stages.single.kind,
        ShaderStageKind.vertex,
      );
    });

    test('a stage kind this reader does not know is refused as stale', () {
      final bytes = Uint8List.fromList(_bytes('effects.f3shaders', 2));
      bytes[_indexAfter(bytes, 'Spread')] = 0xF0;

      // Mutation: read an unknown code as a vertex stage.
      expect(
        () => ShaderBundle.decode(ByteData.sublistView(bytes)),
        throwsA(
          isA<ShaderBundleException>()
              .having((ShaderBundleException r) => r.stale, 'stale', isTrue)
              .having((ShaderBundleException r) => r.name, 'name', 'effects')
              .having(
                (ShaderBundleException r) => r.reason,
                'reason',
                allOf(contains('"Spread"'), contains('kind 240')),
              ),
        ),
      );
    });

    test('every version up to this build has a fixture', () {
      // Mutation: bump `ShaderBundle.formatVersion` with no new fixture.
      for (var v = 1; v <= ShaderBundle.formatVersion; v++) {
        final bytes = ByteData.sublistView(_bytes('effects.f3shaders', v));
        expect(ShaderBundle.decode(bytes).name, 'effects');
      }
    });

    test('a newer container is refused as stale, which a rebuild cures', () {
      final bytes = ByteData.sublistView(
        Uint8List.fromList(_bytes('effects.f3shaders', 1)),
      )..setUint32(4, ShaderBundle.formatVersion + 1, Endian.little);

      // Mutation: drop `stale: true` and the caller cannot tell a bundle the
      // build will remake from bytes that were never a bundle.
      expect(
        () => ShaderBundle.decode(bytes),
        throwsA(
          isA<ShaderBundleException>()
              .having((ShaderBundleException r) => r.stale, 'stale', isTrue)
              .having(
                (ShaderBundleException r) => r.reason,
                'reason',
                contains('rebuild'),
              ),
        ),
      );
    });

    test('bytes that are not a bundle are refused, and not as stale', () {
      // Mutation: mark every refusal stale and a corrupt download reads as
      // something a rebuild would fix.
      expect(
        () => ShaderBundle.decode(ByteData(16)),
        throwsA(
          isA<ShaderBundleException>().having(
            (ShaderBundleException r) => r.stale,
            'stale',
            isFalse,
          ),
        ),
      );
    });

    test('a newer material payload is refused as stale', () {
      final payload = utf8.encode(
        jsonEncode(<String, Object?>{
          'version': materialSectionVersion + 1,
          'stages': <String, String>{'Glow': ''},
        }),
      );
      final bundle = ShaderBundle(
        name: 'effects',
        sdk: '',
        stages: const <ShaderBundleStage>[
          ShaderBundleStage('Glow', fragment: true),
        ],
        sections: <String, ByteData>{
          ShaderBundle.materialSection: ByteData.sublistView(payload),
        },
      );

      // Mutation: compare the payload version with `!=` and bump it.
      expect(
        () => decodeMaterialSection(bundle),
        throwsA(
          isA<ShaderBundleException>().having(
            (ShaderBundleException r) => r.stale,
            'stale',
            isTrue,
          ),
        ),
      );
    });
  });
}
