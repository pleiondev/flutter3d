/// The values a pass is described with since 1.0.0-rc.1: a viewport with
/// a depth range, a clear colour that holds every integer, and the
/// topologies, index widths and blend factors that became capabilities.
///
/// Each check is the shared one every backend calls on the way in, so the
/// refusals are the same words everywhere; what is held here is that each
/// value asks for exactly its own feature and nothing else.
library;

import 'package:flutter3d_foundation/flutter3d_foundation.dart'
    show UnsupportedCapabilityException;
import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:test/test.dart';

Matcher _refusedFor(DeviceFeature feature) => throwsA(
  isA<UnsupportedCapabilityException>().having(
    (UnsupportedCapabilityException e) => e.feature,
    'feature',
    feature,
  ),
);

DeviceFeatures _only(DeviceFeature feature) =>
    DeviceFeatures(<DeviceFeature>[feature]);

void main() {
  group('PassViewport', () {
    test('whole pixels need nothing, a fraction needs its feature', () {
      // Mutation: make `isWholePixels` ignore `width`. A WebGL2 device would
      // then round a 10.5-pixel viewport down without a word.
      const whole = PassViewport(
        x: 2,
        y: 3,
        width: 10,
        height: 20,
        maxDepth: 0.5,
      );
      whole.checkFeatures(DeviceFeatures.none, backend: 'Null');
      expect(
        () => const PassViewport(
          width: 10.5,
          height: 20,
        ).checkFeatures(DeviceFeatures.none, backend: 'Null'),
        _refusedFor(DeviceFeature.fractionalViewport),
      );
      const PassViewport(
        x: 0.25,
        width: 10,
        height: 20,
      ).checkFeatures(_only(DeviceFeature.fractionalViewport), backend: 'Null');
    });

    test('ofRect is the same pixels with the whole depth range', () {
      final viewport = PassViewport.ofRect(
        const ScreenRect(x: 1, y: 2, width: 30, height: 40),
      );
      expect(
        viewport.rect,
        const ScreenRect(x: 1, y: 2, width: 30, height: 40),
      );
      expect(viewport.coversFullDepth, isTrue);
      expect(viewport, const PassViewport(x: 1, y: 2, width: 30, height: 40));
      expect(
        viewport,
        isNot(
          const PassViewport(x: 1, y: 2, width: 30, height: 40, minDepth: 0.1),
        ),
        reason: 'the depth range takes part in equality',
      );
    });

    test('a depth range outside [0, 1], or reversed, is refused', () {
      expect(
        () => PassViewport(width: 1, height: 1, minDepth: 0.6, maxDepth: 0.4),
        throwsA(isA<AssertionError>()),
      );
      expect(
        () => PassViewport(width: 1, height: 1, maxDepth: 1.5),
        throwsA(isA<AssertionError>()),
      );
    });
  });

  group('ClearColor', () {
    test('an integer clear keeps every bit a float32 would lose', () {
      // 2^24 + 1 is the first integer a float32 cannot hold: the id buffer's
      // clear was off by one there when the value was a Vector4.
      const id = ClearColor.uint(16777217, 0, 0, 0);
      expect(id.kind, ClearColorKind.uint);
      expect(id.red, 16777217);
      expect(id.channels.first, 16777217.0);
      expect(
        const ClearColor.uint(1, 0, 0, 0),
        isNot(const ClearColor(1, 0, 0, 0)),
        reason: 'the kind takes part in equality',
      );
      expect(const ClearColor.sint(-1, 0, 0, 0).red, -1);
    });

    test('the kinds are an open set with names', () {
      expect(ClearColorKind.values, <ClearColorKind>[
        ClearColorKind.float,
        ClearColorKind.uint,
        ClearColorKind.sint,
      ]);
      expect(ClearColorKind.byName('sint'), ClearColorKind.sint);
      expect(ClearColorKind.byName('half'), isNull);
    });
  });

  group('topologies and index widths', () {
    test('lists need nothing, strips and points their own feature', () {
      // Mutation: let `checkFeatures` accept a strip without
      // `primitiveStrips`, and the software rasteriser of 1.0 could be handed
      // one by a caller that never asked.
      for (final type in <PrimitiveType>[
        PrimitiveType.triangle,
        PrimitiveType.line,
      ]) {
        type.checkFeatures(DeviceFeatures.none, backend: 'Null');
      }
      for (final type in <PrimitiveType>[
        PrimitiveType.triangleStrip,
        PrimitiveType.lineStrip,
      ]) {
        expect(
          () => type.checkFeatures(
            _only(DeviceFeature.pointPrimitives),
            backend: 'Null',
          ),
          _refusedFor(DeviceFeature.primitiveStrips),
        );
        expect(type.isStrip, isTrue);
      }
      expect(
        () => PrimitiveType.point.checkFeatures(
          _only(DeviceFeature.primitiveStrips),
          backend: 'Null',
        ),
        _refusedFor(DeviceFeature.pointPrimitives),
      );
    });

    test(
      '32-bit indices are a feature, and each width restarts on all ones',
      () {
        IndexType.int16.checkFeatures(DeviceFeatures.none, backend: 'Null');
        expect(
          () => IndexType.int32.checkFeatures(
            DeviceFeatures.none,
            backend: 'Null',
          ),
          _refusedFor(DeviceFeature.indexUint32),
        );
        expect(IndexType.int16.restartIndex, 0xFFFF);
        expect(IndexType.int32.restartIndex, 0xFFFFFFFF);
      },
    );
  });

  group('the blend constant', () {
    test('the colour pair needs blendConstant, the alpha pair both', () {
      // Mutation: ask for `blendConstantAlpha` from `usesBlendColor`. WebGPU,
      // which has the colour pair and not the alpha one, would then refuse
      // every state that reads the constant, as it did before the split.
      const colour = BlendState(
        sourceColorFactor: BlendFactor.blendColor,
        destinationColorFactor: BlendFactor.oneMinusBlendColor,
      );
      colour.checkFeatures(_only(DeviceFeature.blendConstant), backend: 'Null');
      expect(
        () => colour.checkFeatures(DeviceFeatures.none, backend: 'Null'),
        _refusedFor(DeviceFeature.blendConstant),
      );

      const alpha = BlendState(sourceColorFactor: BlendFactor.blendAlpha);
      expect(alpha.usesBlendAlpha, isTrue);
      expect(colour.usesBlendAlpha, isFalse);
      expect(
        () => alpha.checkFeatures(
          _only(DeviceFeature.blendConstant),
          backend: 'Null',
        ),
        _refusedFor(DeviceFeature.blendConstantAlpha),
      );
      alpha.checkFeatures(
        DeviceFeatures(<DeviceFeature>[
          DeviceFeature.blendConstant,
          DeviceFeature.blendConstantAlpha,
        ]),
        backend: 'Null',
      );
    });
  });
}
