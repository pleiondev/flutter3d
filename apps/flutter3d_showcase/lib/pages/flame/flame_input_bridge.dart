/// `FlameInputBridge` translating a Flame keyboard event into the same
/// `Bindings`/`InputState` pair `flutter3d_game`'s own desktop input writes
/// into.
///
/// Quoted by `flame_input_bridge.md` and shown whole in the Source tab.
library;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_flame/flutter3d_flame.dart';
import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter3d_showcase/src/demo/demo.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:vector_math/vector_math.dart';

final class FlameInputBridgeDemo extends ShowcaseDemo {
  late final String _report;
  late final bool _consumed;
  late final bool _heldByTheSharedState;
  late final double _actorX;

  @override
  Scene build(DemoContext context) {
    final (String report, bool consumed, bool held, double actorX) = _run();
    _report = report;
    _consumed = consumed;
    _heldByTheSharedState = held;
    _actorX = actorX;

    final node = MeshNode(
      DeviceMesh.upload(context.device, SphereShape(segments: 16).build()),
      Material(name: 'walker', baseColor: Vector4(0.5, 0.7, 0.9, 1.0)),
    )..setPosition(_actorX, 0.0, 0.0);

    return Scene()
      ..add(node)
      ..add(
        LightNode(name: 'sun', intensity: 2.5)
          ..setLocalForward(Vector3(-0.3, -0.6, -0.4)),
      );
  }

  static (String, bool, bool, double) _run() {
    // #region shared
    // The same table and the same state a rebind screen edits and
    // `DesktopInput` reads natively — a bridged game and a native one share
    // one rebinding UI and one saved binding file, not two.
    final bindings = Bindings()
      ..bind(
        InputSource.key(LogicalKeyboardKey.keyD.keyId),
        GameAction.moveRight,
      );
    final inputState = InputState();
    final bridge = FlameInputBridge(bindings: bindings, inputState: inputState);
    // #endregion shared

    // #region press
    // `onKeyEvent` returns false when it consumed the key, matching
    // `KeyboardHandler`'s own polarity.
    final bool consumed = !bridge.onKeyEvent(
      const KeyDownEvent(
        physicalKey: PhysicalKeyboardKey.keyD,
        logicalKey: LogicalKeyboardKey.keyD,
        timeStamp: Duration.zero,
      ),
      const <LogicalKeyboardKey>{},
    );
    // #endregion press

    // #region reactions
    // The Flame side already knows it consumed the key; the flutter3d side
    // reads the very same `InputState` the press just wrote into, the way an
    // actor's own movement would.
    final bool held = inputState.held(GameAction.moveRight);
    final double actorX = held ? 1.5 : 0.0;
    // #endregion reactions

    return (
      'the Flame key handler consumed the press: $consumed; the flutter3d '
          'side reads the same action held: $held',
      consumed,
      held,
      actorX,
    );
  }

  @override
  Widget? customBody(BuildContext buildContext, DemoContext context) =>
      Container(
        color: const Color(0xFF14161A),
        padding: const EdgeInsets.all(24),
        alignment: Alignment.topLeft,
        child: DefaultTextStyle(
          style: const TextStyle(color: Color(0xFFE8E8EC), fontSize: 16),
          child: Text(_report),
        ),
      );

  @override
  void verify(Scene scene, FrameResult frame) {
    if (frame.drawCalls < 1) {
      throw StateError('the walker marker was not drawn');
    }
    // Compared as booleans, not read back out of `_report`: see
    // `sim_audio_xr/actors.dart` for why.
    if (!_consumed) {
      throw StateError('a bound key should be consumed, not passed through');
    }
    if (!_heldByTheSharedState) {
      throw StateError(
        'the flutter3d side should read the same InputState the Flame '
        'bridge just pressed',
      );
    }
    if (_actorX != 1.5) {
      throw StateError('the flutter3d-side reaction should have moved');
    }
  }
}
