/// What `PassState` emits, and — more importantly — what it does not.
///
/// The second half is the reason the type exists with optional fields. On two
/// of the three backends any `setDepthWrite` call turns writes on, and on the
/// third an omitted setter inherits the previous pass's global GL state. So a
/// state object that helpfully filled in defaults would change several passes
/// at once, in different directions per backend, and the pictures would move on
/// one of them only.
library;

import 'package:flutter3d_graphics/flutter3d_graphics.dart';
import 'package:flutter_test/flutter_test.dart';

/// Records the calls rather than performing them.
final class _Recorder implements PassEncoder {
  final List<String> calls = <String>[];

  @override
  void setViewport(ScreenRect rect) => calls.add('viewport');
  @override
  void setScissor(ScreenRect rect) => calls.add('scissor');
  @override
  void setPrimitiveType(PrimitiveType type) => calls.add('primitive ${type.name}');
  @override
  void setPolygonMode(PolygonMode mode) => calls.add('polygon ${mode.name}');
  @override
  void setCullMode(CullMode mode) => calls.add('cull ${mode.name}');
  @override
  void setWindingOrder(WindingOrder order) => calls.add('winding ${order.name}');
  @override
  void setDepthWrite(bool enabled) => calls.add('depthWrite $enabled');
  @override
  void setDepthCompare(CompareFunction compare) =>
      calls.add('depthCompare ${compare.name}');
  @override
  void setBlend(BlendState? state, {int attachment = 0}) =>
      calls.add('blend ${state == null ? 'off' : 'on'}@$attachment');

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test('an empty state emits nothing at all', () {
    final encoder = _Recorder()..setState(const PassState());
    expect(encoder.calls, isEmpty,
        reason: 'a state that says nothing must say nothing. Filling in '
            'defaults here would turn depth writes on for every pass that '
            'deliberately never mentions them');
  });

  test('only the fields that are set are emitted', () {
    final encoder = _Recorder()
      ..setState(const PassState(
        cullMode: CullMode.none,
        depthWrite: false,
      ));

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
    expect(const PassState(blend: null) == const PassState(), isFalse,
        reason: 'and they are not the same value either');
  });

  test('the order is fixed, whatever order the fields were written in', () {
    final encoder = _Recorder()
      ..setState(const PassState(
        depthCompare: CompareFunction.always,
        blend: BlendState.additive,
        primitiveType: PrimitiveType.triangle,
        depthWrite: false,
        cullMode: CullMode.none,
      ));

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
    expect(changed.setsBlend, isTrue,
        reason: 'copyWith must not quietly stop mentioning blending');
    expect(changed.blend, isNull);
    expect(changed.depthWrite, isTrue);
  });

  test('equal states are equal, and hash alike', () {
    const a = PassState(cullMode: CullMode.backFace, depthWrite: true);
    const b = PassState(cullMode: CullMode.backFace, depthWrite: true);

    expect(a, b);
    expect(a.hashCode, b.hashCode);
  });
}
