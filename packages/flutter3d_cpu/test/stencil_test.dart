/// The stencil, operation by operation.
///
/// Eight operations, two masks, a reference and two faces, each with a
/// fixture small enough to check by eye: one triangle across a four-by-four
/// target, the stencil cleared to a stated byte, one draw, and the byte at
/// the centre read straight off the attachment. The conformance suite checks
/// the shape of the thing on every backend — a mark, then `equal` and
/// `notEqual` against it — and cannot reach the buffer itself; this file can,
/// and it is where "incrementWrap goes to zero past 255" is a line rather
/// than a hope.
library;

import 'dart:typed_data';

import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

const int _size = 4;
const int _centre = (_size ~/ 2) * _size + _size ~/ 2;

/// A stage that discards everything, for the one rule about the stencil
/// that no built-in stage can demonstrate.
final class _DiscardEverything implements CpuFragmentShader {
  const _DiscardEverything();

  @override
  Vector4? run(Float32List v, ShaderBindings b, FragmentContext c) => null;
}

final class _Fixture {
  _Fixture({int stencilClear = 0, bool loadStencil = false, _Fixture? over})
    : device = CpuDevice(
        width: _size,
        height: _size,
        shaders: CpuShaderLibrary(<String, CpuStage>{
          ...builtinCpuShaders(),
          'DiscardEverything': const CpuStage.fragment(_DiscardEverything()),
        }),
      ) {
    colour =
        over?.colour ??
        device.createTexture(
          const RenderTargetSpec(
            width: _size,
            height: _size,
            format: TextureFormat.r16g16b16a16Float,
          ),
        );
    depth =
        over?.depth ??
        device.createTexture(
          const RenderTargetSpec(
            width: _size,
            height: _size,
            format: TextureFormat.d32FloatS8UInt,
          ),
        );
    pass = device.beginRenderPass(
      RenderPassDescriptor(
        colors: <ColorTarget>[
          ColorTarget(
            texture: colour,
            loadAction: LoadAction.clear,
            clearValue: Vector4.zero(),
          ),
        ],
        depth: DepthTarget(
          texture: depth,
          stencilLoadAction: loadStencil ? LoadAction.load : LoadAction.clear,
          stencilClearValue: stencilClear,
        ),
      ),
    );
    vertex = device.shaders['DebugLineVertex']!;
    pass
      ..bindPipeline(
        device.createPipeline(vertex, device.shaders['DebugLine']!),
      )
      ..setPrimitiveType(PrimitiveType.triangle)
      ..setCullMode(CullMode.none)
      ..setDepthCompare(CompareFunction.lessEqual)
      ..setDepthWrite(true);
  }

  final CpuDevice device;
  late final TextureHandle colour;
  late final TextureHandle depth;
  late final CommandEncoder pass;
  late final ShaderHandle vertex;

  /// One triangle covering the target at [z], in [rgb], wound so it faces
  /// the camera — or the other way when [backFacing].
  void draw(
    double z,
    List<double> rgb, {
    bool backFacing = false,
    String fragment = 'DebugLine',
  }) {
    if (fragment != 'DebugLine') {
      pass.bindPipeline(
        device.createPipeline(vertex, device.shaders[fragment]!),
      );
    }
    pass.bindUniformBlock(vertex, 'LineInfo', <String, Float32List>{
      'view_projection': Float32List.fromList(Matrix4.identity().storage),
    });
    final a = <double>[-1, -1, z, ...rgb, 1];
    final b = <double>[3, -1, z, ...rgb, 1];
    final c = <double>[-1, 3, z, ...rgb, 1];
    final corners = backFacing
        ? <double>[...a, ...c, ...b]
        : [...a, ...b, ...c];
    pass
      ..bindVertexData(ByteData.sublistView(Float32List.fromList(corners)), 3)
      ..draw();
  }

  int get stencilAtCentre => (depth.backend as CpuTexture).stencil![_centre];

  double get redAtCentre => (colour.backend as CpuTexture).pixels[_centre * 4];
}

void main() {
  group('each operation lands the value the specification says', () {
    // (starting value, operation, what is stored afterwards), with the
    // reference held at nine so `setToReferenceValue` is told apart from
    // every other outcome.
    const cases = <(int, StencilOperation, int)>[
      (5, StencilOperation.keep, 5),
      (5, StencilOperation.zero, 0),
      (5, StencilOperation.setToReferenceValue, 9),
      (5, StencilOperation.incrementClamp, 6),
      (255, StencilOperation.incrementClamp, 255),
      (5, StencilOperation.decrementClamp, 4),
      (0, StencilOperation.decrementClamp, 0),
      (0x0F, StencilOperation.invert, 0xF0),
      (255, StencilOperation.incrementWrap, 0),
      (0, StencilOperation.decrementWrap, 255),
    ];
    for (final (start, op, expected) in cases) {
      test('${op.name} takes $start to $expected', () {
        final fixture = _Fixture(stencilClear: start);
        fixture.pass
          ..setStencilReference(9)
          ..setStencil(StencilState(passOp: op));
        fixture.draw(0.5, <double>[1, 0, 0]);
        fixture.pass.submit();
        expect(fixture.stencilAtCentre, expected);
        expect(
          fixture.redAtCentre,
          1.0,
          reason: 'the test was `always`, so the colour landed too',
        );
      });
    }
  });

  test('the write mask keeps the bits it does not name', () {
    final fixture = _Fixture(stencilClear: 0xAA);
    fixture.pass
      ..setStencilReference(0xFF)
      ..setStencil(
        const StencilState(
          passOp: StencilOperation.setToReferenceValue,
          writeMask: 0x0F,
        ),
      );
    fixture.draw(0.5, <double>[1, 0, 0]);
    fixture.pass.submit();
    expect(fixture.stencilAtCentre, 0xAF);
  });

  test('a reference wider than a byte keeps its low eight bits', () {
    // The one place all three backends could have disagreed and none of them
    // would have said so: masking wraps 0x109 to 9, GL's `stencilFunc` clamps
    // it to 255, and flutter_gpu forwards it. `StencilState.narrowReference`
    // is the one answer now, and this reads it off an attachment — the only
    // backend where it can be read at all.
    //
    // **What this can and cannot catch, because the two are not the same.**
    // Deleting the narrowing here changes nothing: the stencil attachment is
    // a `Uint8List`, so it truncates whatever it is handed and arrives at the
    // same 9. What this bites is the *other* answer — a backend that took up
    // GL's clamp would store 255 and this would fail. The call itself is
    // pinned where it is made, in `flutter3d_hardware`'s `pass_state_test`.
    final fixture = _Fixture(stencilClear: 0);
    fixture.pass
      ..setStencilReference(0x109)
      ..setStencil(
        const StencilState(passOp: StencilOperation.setToReferenceValue),
      );
    fixture.draw(0.5, <double>[1, 0, 0]);
    fixture.pass.submit();
    expect(fixture.stencilAtCentre, 9, reason: 'not 255, and not 0x109');
  });

  test('the read mask hides bits from the comparison', () {
    // Stored 0x10 against a reference of zero: unequal as bytes, equal once
    // the low nibble is all that is compared.
    final masked = _Fixture(stencilClear: 0x10);
    masked.pass
      ..setStencilReference(0)
      ..setStencil(
        const StencilState(compare: CompareFunction.equal, readMask: 0x0F),
      );
    masked.draw(0.5, <double>[1, 0, 0]);
    masked.pass.submit();
    expect(masked.redAtCentre, 1.0, reason: 'masked, the two compare equal');

    final unmasked = _Fixture(stencilClear: 0x10);
    unmasked.pass
      ..setStencilReference(0)
      ..setStencil(const StencilState(compare: CompareFunction.equal));
    unmasked.draw(0.5, <double>[1, 0, 0]);
    unmasked.pass.submit();
    expect(unmasked.redAtCentre, 0.0, reason: 'unmasked, they do not');
  });

  test('equal and notEqual read a mark that keepDestination wrote', () {
    // The x-ray stage's own shape: a mark that leaves the picture alone, a
    // draw that lands only on the mark, a draw that lands only off it.
    final fixture = _Fixture();
    fixture.pass
      ..setStencilReference(1)
      ..setStencil(
        const StencilState(passOp: StencilOperation.setToReferenceValue),
      )
      ..setBlend(BlendState.keepDestination);
    fixture.draw(0.5, <double>[1, 1, 1]);
    expect(fixture.stencilAtCentre, 1);
    expect(
      fixture.redAtCentre,
      0.0,
      reason: 'keepDestination: the mark painted nothing',
    );

    fixture.pass
      ..setBlend(null)
      ..setStencil(const StencilState(compare: CompareFunction.notEqual));
    fixture.draw(0.5, <double>[0, 1, 0]);
    expect(fixture.redAtCentre, 0.0, reason: 'notEqual fails on the mark');

    fixture.pass.setStencil(const StencilState(compare: CompareFunction.equal));
    fixture.draw(0.5, <double>[1, 0, 0]);
    fixture.pass.submit();
    expect(fixture.redAtCentre, 1.0, reason: 'equal passes on the mark');
  });

  test('the stencil-fail operation applies where the test rejects', () {
    final fixture = _Fixture();
    fixture.pass
      ..setStencilReference(1)
      ..setStencil(
        const StencilState(
          compare: CompareFunction.never,
          failOp: StencilOperation.incrementClamp,
        ),
      );
    fixture.draw(0.5, <double>[1, 0, 0]);
    fixture.pass.submit();
    expect(fixture.stencilAtCentre, 1);
    expect(fixture.redAtCentre, 0.0, reason: 'and the colour did not land');
  });

  test('the depth-fail operation applies where the depth test rejects', () {
    final fixture = _Fixture();
    fixture.draw(0.2, <double>[1, 0, 0]);
    fixture.pass.setStencil(
      const StencilState(depthFailOp: StencilOperation.incrementClamp),
    );
    // Behind the first: the stencil passes, the depth does not.
    fixture.draw(0.8, <double>[0, 1, 0]);
    fixture.pass.submit();
    expect(fixture.stencilAtCentre, 1);
    expect(fixture.redAtCentre, 1.0, reason: 'the first draw stayed');
  });

  test('a back face is tested with its own state', () {
    final fixture = _Fixture();
    fixture.pass
      ..setStencilReference(7)
      ..setStencil(
        const StencilState(passOp: StencilOperation.keep),
        back: const StencilState(passOp: StencilOperation.setToReferenceValue),
      );
    fixture.draw(0.5, <double>[1, 0, 0], backFacing: true);
    expect(fixture.stencilAtCentre, 7, reason: 'the back state wrote');
    fixture.pass.setStencilReference(3);
    fixture.draw(0.5, <double>[1, 0, 0]);
    fixture.pass.submit();
    expect(fixture.stencilAtCentre, 7, reason: 'the front state kept');
  });

  test('a discarded fragment writes no stencil', () {
    // The rule every backend keeps and none can be asked about: a fragment
    // the stage discards updates nothing, whichever operation it earned.
    final fixture = _Fixture();
    fixture.pass
      ..setStencilReference(1)
      ..setStencil(
        const StencilState(
          compare: CompareFunction.never,
          failOp: StencilOperation.setToReferenceValue,
        ),
      );
    fixture.draw(0.5, <double>[1, 0, 0], fragment: 'DiscardEverything');
    fixture.pass.submit();
    expect(fixture.stencilAtCentre, 0);
  });

  test('a pass that never mentions the stencil leaves the clear alone', () {
    final fixture = _Fixture(stencilClear: 7);
    fixture.draw(0.5, <double>[1, 0, 0]);
    fixture.pass.submit();
    expect(fixture.stencilAtCentre, 7);
    expect(fixture.redAtCentre, 1.0);
  });

  test('a pass that loads the stencil sees what the last one stored', () {
    final first = _Fixture();
    first.pass
      ..setStencilReference(4)
      ..setStencil(
        const StencilState(passOp: StencilOperation.setToReferenceValue),
      );
    first.draw(0.5, <double>[1, 0, 0]);
    first.pass.submit();

    final second = _Fixture(loadStencil: true, over: first);
    second.pass.setStencil(const StencilState(compare: CompareFunction.equal));
    second.pass.setStencilReference(4);
    second.draw(0.5, <double>[0, 1, 0]);
    second.pass.submit();
    expect(second.stencilAtCentre, 4);
    expect(
      (second.colour.backend as CpuTexture).pixels[_centre * 4 + 1],
      1.0,
      reason: 'equal against the loaded four let the green through',
    );

    final cleared = _Fixture(over: first);
    cleared.pass.submit();
    expect(cleared.stencilAtCentre, 0, reason: 'and a clear is a clear');
  });

  test('a pass with no depth attachment has no stencil to test', () {
    // Specified to pass always, and here it does so by never being asked:
    // there is no buffer, so a `never` compare rejects nothing.
    final device = CpuDevice(
      width: _size,
      height: _size,
      shaders: CpuShaderLibrary(builtinCpuShaders()),
    );
    final colour = device.createTexture(
      const RenderTargetSpec(
        width: _size,
        height: _size,
        format: TextureFormat.r16g16b16a16Float,
      ),
    );
    final pass = device.beginRenderPass(
      RenderPassDescriptor(
        colors: <ColorTarget>[
          ColorTarget(texture: colour, clearValue: Vector4.zero()),
        ],
      ),
    );
    final vertex = device.shaders['DebugLineVertex']!;
    pass
      ..bindPipeline(
        device.createPipeline(vertex, device.shaders['DebugLine']!),
      )
      ..setPrimitiveType(PrimitiveType.triangle)
      ..setCullMode(CullMode.none)
      ..setStencil(const StencilState(compare: CompareFunction.never))
      ..bindUniformBlock(vertex, 'LineInfo', <String, Float32List>{
        'view_projection': Float32List.fromList(Matrix4.identity().storage),
      })
      ..bindVertexData(
        ByteData.sublistView(
          Float32List.fromList(<double>[
            -1, -1, 0.5, 1, 0, 0, 1, //
            3, -1, 0.5, 1, 0, 0, 1,
            -1, 3, 0.5, 1, 0, 0, 1,
          ]),
        ),
        3,
      )
      ..draw()
      ..submit();
    expect((colour.backend as CpuTexture).pixels[_centre * 4], 1.0);
  });
}
