/// Mapping an action to a key, and letting a player replace that mapping
/// while the game keeps running.
///
/// **`flutter3d_game` is not a dependency of this app yet.** Its `Bindings`
/// map a `GameAction` to whatever pressed it and its `Rebinding` waits for
/// the next key and writes it into that map; this page cannot import either
/// (see the showcase's own report on this row), so it reimplements the same
/// small idea, a map from an action name to a key plus a function that
/// replaces one entry, against Flutter's own `LogicalKeyboardKey`.
///
/// Quoted by `input_bindings.md` and shown whole in the Source tab.
library;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_showcase/src/demo/demo.dart';
import 'package:vector_math/vector_math.dart';

final class InputBindingsDemo extends ShowcaseDemo {
  // #region bindings
  /// One key per action. A real `Bindings` also carries a gamepad route and
  /// a mouse action beside the keyboard; this page keeps only the keyboard
  /// half, which is the part `Rebinding` changes.
  Map<String, LogicalKeyboardKey> bindings = <String, LogicalKeyboardKey>{
    'jump': LogicalKeyboardKey.space,
    'crouch': LogicalKeyboardKey.controlLeft,
  };
  // #endregion bindings

  String? waitingFor;

  @override
  Scene build(DemoContext context) {
    final Material stone = Material(
      name: 'stone',
      baseColor: Vector4(0.6, 0.5, 0.55, 1.0),
      roughness: 0.7,
    );
    final MeshNode ball = MeshNode(
      DeviceMesh.upload(
        context.device,
        SphereShape(segments: 24, rings: 12).build(),
      ),
      stone,
      name: 'ball',
    );
    return Scene()
      ..add(ball)
      ..add(
        LightNode(name: 'sun', intensity: 3.0)
          ..setLocalForward(Vector3(-0.4, -1.0, -0.3)),
      );
  }

  // #region rebind
  /// Replaces the key bound to [action], and only that one: every other
  /// action keeps the key it already had. This is what a real `Rebinding`
  /// writes into a `Bindings` map once the next key arrives.
  Map<String, LogicalKeyboardKey> rebind(
    Map<String, LogicalKeyboardKey> current,
    String action,
    LogicalKeyboardKey key,
  ) => <String, LogicalKeyboardKey>{...current, action: key};
  // #endregion rebind

  @override
  Widget? customBody(BuildContext buildContext, DemoContext context) => Focus(
    autofocus: true,
    onKeyEvent: (FocusNode node, KeyEvent event) {
      final String? action = waitingFor;
      if (action == null || event is! KeyDownEvent) {
        return KeyEventResult.ignored;
      }
      bindings = rebind(bindings, action, event.logicalKey);
      waitingFor = null;
      return KeyEventResult.handled;
    },
    child: Container(
      color: const Color(0xFF14161A),
      padding: const EdgeInsets.all(24),
      alignment: Alignment.topLeft,
      child: DefaultTextStyle(
        style: const TextStyle(color: Color(0xFFE8E8EC), fontSize: 16),
        child: Text(
          'flutter3d_game is not wired into this app. The bindings below are '
          'a plain map from action to key.\n\n'
          '${bindings.entries.map((MapEntry<String, LogicalKeyboardKey> e) => '${e.key}: ${e.value.keyLabel}').join('\n')}\n\n'
          '${waitingFor == null ? 'Use the panel to rebind an action.' : 'Waiting for a key for "$waitingFor"...'}',
        ),
      ),
    ),
  );

  @override
  List<DemoControl> controls(DemoContext context) => <DemoControl>[
    for (final String action in bindings.keys)
      ToggleControl(
        'Rebind $action',
        value: () => waitingFor == action,
        onChanged: (bool _) => waitingFor = action,
      ),
  ];

  @override
  void verify(Scene scene, FrameResult frame) {
    if (frame.drawCalls < 1) {
      throw StateError('the ball was not drawn');
    }
    // Rebinding "jump" must replace only "jump". "crouch" is the control
    // group: it has to come out exactly as it went in.
    final Map<String, LogicalKeyboardKey> before = bindings;
    final Map<String, LogicalKeyboardKey> after = rebind(
      before,
      'jump',
      LogicalKeyboardKey.keyE,
    );
    if (after['jump'] != LogicalKeyboardKey.keyE) {
      throw StateError('rebind did not change the action it was asked to');
    }
    if (after['crouch'] != before['crouch']) {
      throw StateError('rebind changed an action it was not asked to');
    }
  }
}
