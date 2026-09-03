/// What `PassState` emits, and — more importantly — what it does not.
///
/// The second half is the reason the type exists with optional fields. On the
/// WebGL backend an omitted setter inherits the previous pass's global GL
/// state, so a state object that helpfully filled in defaults would change
/// several passes at once and the pictures would move on one backend only.
///
/// Until SDK 3.47 there was a second reason — any `setDepthWrite` call turned
/// writes on, on two backends out of three — and the fields stayed optional
/// when it went away, because what is being protected is that a pass emits
/// exactly what it means and nothing it does not.
library;

import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:flutter_test/flutter_test.dart';

/// Records the calls rather than performing them.
final class _Recorder implements PassEncoder {
  final List<String> calls = <String>[];

  @override
  void setViewport(ScreenRect rect) => calls.add('viewport');
  @override
  void setScissor(ScreenRect rect) => calls.add('scissor');
  @override
  void setPrimitiveType(PrimitiveType type) =>
      calls.add('primitive ${type.name}');
  @override
  void setPolygonMode(PolygonMode mode) => calls.add('polygon ${mode.name}');
  @override
  void setCullMode(CullMode mode) => calls.add('cull ${mode.name}');
  @override
  void setWindingOrder(WindingOrder order) =>
      calls.add('winding ${order.name}');
  @override
  void setDepthWrite(bool enabled) => calls.add('depthWrite $enabled');
  @override
  void setDepthCompare(CompareFunction compare) =>
      calls.add('depthCompare ${compare.name}');
  @override
  void setBlend(BlendState? state, {int attachment = 0}) =>
      calls.add('blend ${state == null ? 'off' : 'on'}@$attachment');
  @override
  void setStencil(StencilState front, {StencilState? back}) => calls.add(
    'stencil ${front.compare.name}'
    '${back == null ? '' : ' back ${back.compare.name}'}',
  );
  @override
  void setStencilReference(int value) => calls.add('stencilReference $value');

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test('an empty state emits nothing at all', () {
    final encoder = _Recorder()..setState(const PassState());
    expect(
      encoder.calls,
      isEmpty,
      reason:
          'a state that says nothing must say nothing. Filling in '
          'defaults here would turn depth writes on for every pass that '
          'deliberately never mentions them',
    );
  });

  test('only the fields that are set are emitted', () {
    final encoder = _Recorder()
      ..setState(const PassState(cullMode: CullMode.none, depthWrite: false));

    expect(encoder.calls, <String>['cull none', 'depthWrite false']);
  });

  test('blend off and blend unmentioned are different', () {
    // `setBlend(null)` disables blending; omitting it leaves the pass alone.
    // A plain `BlendState?` field cannot tell those apart, which is what the
    // sentinel in the constructor is for.
    final off = _Recorder()..setState(const PassState(blend: null));
    final quiet = _Recorder()..setState(const PassState());

    expect(off.calls, <String>['blend off@0']);
    expect(quiet.calls, isEmpty);
    expect(
      const PassState(blend: null) == const PassState(),
      isFalse,
      reason: 'and they are not the same value either',
    );
  });

  test('the order is fixed, whatever order the fields were written in', () {
    final encoder = _Recorder()
      ..setState(
        const PassState(
          depthCompare: CompareFunction.always,
          blend: BlendState.additive,
          primitiveType: PrimitiveType.triangle,
          depthWrite: false,
          cullMode: CullMode.none,
        ),
      );

    expect(encoder.calls, <String>[
      'primitive triangle',
      'cull none',
      'blend on@0',
      'depthWrite false',
      'depthCompare always',
    ]);
  });

  test('copyWith keeps what it is not given, including blend', () {
    const base = PassState(cullMode: CullMode.none, blend: null);

    final changed = base.copyWith(depthWrite: true);

    expect(changed.cullMode, CullMode.none);
    expect(
      changed.setsBlend,
      isTrue,
      reason: 'copyWith must not quietly stop mentioning blending',
    );
    expect(changed.blend, isNull);
    expect(changed.depthWrite, isTrue);
  });

  test('equal states are equal, and hash alike', () {
    const a = PassState(cullMode: CullMode.backFace, depthWrite: true);
    const b = PassState(cullMode: CullMode.backFace, depthWrite: true);

    expect(a, b);
    expect(a.hashCode, b.hashCode);
  });

  test('the stencil comes last, and the reference after it', () {
    // After depth, because that is the order the questions are asked in —
    // and after everything, because a stencil that went first would sit
    // between nothing: no other field reads it.
    final encoder = _Recorder()
      ..setState(
        const PassState(
          stencilReference: 1,
          depthCompare: CompareFunction.greater,
          stencil: StencilState(compare: CompareFunction.notEqual),
          depthWrite: false,
        ),
      );

    expect(encoder.calls, <String>[
      'depthWrite false',
      'depthCompare greater',
      'stencil notEqual',
      'stencilReference 1',
    ]);
  });

  test('a back face rides on the same call as the front', () {
    final encoder = _Recorder()
      ..setState(
        const PassState(
          stencil: StencilState(compare: CompareFunction.equal),
          stencilBack: StencilState(compare: CompareFunction.never),
        ),
      );

    expect(encoder.calls, <String>['stencil equal back never']);
  });

  test('a back face without a front is refused', () {
    // One call carries both, so a state with only the back half has nothing
    // to emit it on. Silently emitting nothing would be a mask that never
    // arrived, which is the shape of bug every optional field here exists to
    // make visible.
    expect(
      () => PassState(
        stencilBack: const StencilState(compare: CompareFunction.equal),
      ),
      throwsA(isA<AssertionError>()),
    );
  });

  test('copyWith carries the stencil fields, and equality reads them', () {
    const marked = StencilState(
      compare: CompareFunction.always,
      passOp: StencilOperation.setToReferenceValue,
    );
    const base = PassState(stencil: marked, stencilReference: 1);

    final changed = base.copyWith(depthWrite: false);

    expect(changed.stencil, marked);
    expect(changed.stencilReference, 1);
    expect(changed, isNot(base));
    expect(
      const PassState(stencil: marked, stencilReference: 1),
      base,
      reason: 'two states naming the same stencil are the same state',
    );
    expect(
      const PassState(stencil: marked, stencilReference: 2),
      isNot(base),
      reason: 'and a different reference is a different state',
    );
  });

  test('StencilState defaults to the test switched off', () {
    // What a pass starts with, and what a caller says to switch it back off:
    // the two have to be the same value or a pass could not tell whether it
    // was done.
    const fresh = StencilState();
    expect(fresh, StencilState.disabled);
    expect(fresh.compare, CompareFunction.always);
    expect(fresh.failOp, StencilOperation.keep);
    expect(fresh.depthFailOp, StencilOperation.keep);
    expect(fresh.passOp, StencilOperation.keep);
    expect(fresh.readMask, 0xFF);
    expect(fresh.writeMask, 0xFF);
    expect(
      const StencilState(writeMask: 0x0F),
      isNot(StencilState.disabled),
      reason: 'every field takes part in equality',
    );
    expect(
      const StencilState(passOp: StencilOperation.invert).hashCode,
      const StencilState(passOp: StencilOperation.invert).hashCode,
    );
  });

  test('a stencil reference is narrowed to eight bits, not clamped', () {
    // The contract's own answer, in the one place all three backends read it
    // from. Clamping is what GL would have done left to itself, so the pair
    // below is the distinction the function exists to remove.
    expect(StencilState.narrowReference(1), 1);
    expect(StencilState.narrowReference(0xFF), 0xFF);
    expect(StencilState.narrowReference(0x101), 1, reason: 'not 255');
    expect(StencilState.narrowReference(0x100), 0);
  });

  test('the formats that carry a stencil are exactly the three', () {
    // Every depth format the engine names packs one, which is why nothing
    // above the backends ever had to ask — and why a backend opening a pass
    // can enable the test whenever there is a depth attachment at all.
    final withStencil = TextureFormat.values.where((f) => f.hasStencil);
    expect(withStencil, <TextureFormat>[
      TextureFormat.s8UInt,
      TextureFormat.d24UnormS8Uint,
      TextureFormat.d32FloatS8UInt,
    ]);
  });
}
