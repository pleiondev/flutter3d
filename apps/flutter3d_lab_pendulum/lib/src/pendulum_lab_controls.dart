import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'lab_theme.dart';

/// The lab's controls for a student who does not tap the panel in the
/// scene: a keyboard, a screen reader, or a switch.
///
/// **The panel is a texture.** `PendulumLabPanel` is drawn into a
/// `WidgetSurface` and reached by a raycast from a pointer; no focus and no
/// semantics cross into it. So the scene itself carries the one number the
/// panel changes, as a slider: a screen reader reads and moves it, the
/// arrow keys and plus and minus move it while it has focus, and a ring
/// shows when it does.
///
/// **The swing can be paused**, by a button or by Space, and it starts
/// paused when the system asks for reduced motion
/// (`MediaQuery.disableAnimationsOf`): a pendulum that swings on its own is
/// motion that starts by itself, and a student who asked for less of it
/// starts the swing when ready.
class PendulumLabControls extends StatefulWidget {
  /// Controls wrapped around [child], the scene, moving the same length the
  /// panel in it does.
  const PendulumLabControls({
    super.key,
    required this.lengthMeters,
    required this.onChangeLength,
    required this.running,
    required this.child,
    this.onScenePointerDown,
    this.step = 0.1,
    this.minLength = 0.2,
    this.maxLength = 3.0,
  });

  /// The pendulum's length in metres, as the lab holds it; read to show the
  /// readout, never written here.
  final ValueListenable<double> lengthMeters;

  /// Called with the new length in metres, already clamped to
  /// [minLength]..[maxLength]; the lab sets the simulation from it.
  final ValueChanged<double> onChangeLength;

  /// Whether the pendulum swings; the controls write it, the lab's ticker
  /// reads it.
  final ValueNotifier<bool> running;

  /// The scene.
  final Widget child;

  /// A pointer pressed on the scene, which the lab casts into it to reach
  /// the panel there; null for none.
  final PointerDownEventListener? onScenePointerDown;

  /// How far one press or key moves the length, in metres.
  final double step;

  /// The shortest length a press or key can reach, in metres.
  final double minLength;

  /// The longest length a press or key can reach, in metres.
  final double maxLength;

  /// The ring drawn around the scene while it has keyboard focus.
  static const Key focusRingKey = ValueKey<String>('pendulum-focus-ring');

  @override
  State<PendulumLabControls> createState() => _PendulumLabControlsState();
}

class _PendulumLabControlsState extends State<PendulumLabControls> {
  final FocusNode _sceneFocus = FocusNode(debugLabel: 'String length');

  /// The reduced-motion flag is read once, when the lab first shows: a
  /// student who then starts the swing has answered it.
  bool _motionRead = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_motionRead) return;
    _motionRead = true;
    if (MediaQuery.disableAnimationsOf(context)) widget.running.value = false;
  }

  @override
  void dispose() {
    _sceneFocus.dispose();
    super.dispose();
  }

  double _nudged(double by) => (widget.lengthMeters.value + by)
      .clamp(widget.minLength, widget.maxLength)
      .toDouble();

  void _nudge(double by) => widget.onChangeLength(_nudged(by));

  void _toggle() => widget.running.value = !widget.running.value;

  static String _meters(double value) => '${value.toStringAsFixed(2)} m';

  static const String _hint =
      'Arrow keys or plus and minus change it; Space pauses the swing.';

  KeyEventResult _onSceneKey(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowUp ||
        key == LogicalKeyboardKey.arrowRight ||
        key == LogicalKeyboardKey.equal ||
        key == LogicalKeyboardKey.add ||
        key == LogicalKeyboardKey.numpadAdd) {
      _nudge(widget.step);
    } else if (key == LogicalKeyboardKey.arrowDown ||
        key == LogicalKeyboardKey.arrowLeft ||
        key == LogicalKeyboardKey.minus ||
        key == LogicalKeyboardKey.numpadSubtract) {
      _nudge(-widget.step);
    } else if (key == LogicalKeyboardKey.space) {
      _toggle();
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) => FocusTraversalGroup(
    policy: OrderedTraversalPolicy(),
    child: Stack(
      fit: StackFit.expand,
      children: <Widget>[
        FocusTraversalOrder(
          order: const NumericFocusOrder(1),
          child: ValueListenableBuilder<double>(
            valueListenable: widget.lengthMeters,
            // The pointer's way in, a tap on the panel in the scene, sits
            // under the slider's name: it changes the same one number.
            builder: (context, length, scene) => Semantics(
              container: true,
              slider: true,
              label: 'String length',
              value: _meters(length),
              increasedValue: _meters(_nudged(widget.step)),
              decreasedValue: _meters(_nudged(-widget.step)),
              hint: _hint,
              onIncrease: () => _nudge(widget.step),
              onDecrease: () => _nudge(-widget.step),
              child: Listener(
                onPointerDown: widget.onScenePointerDown,
                child: scene,
              ),
            ),
            child: Focus(
              focusNode: _sceneFocus,
              onKeyEvent: _onSceneKey,
              child: ListenableBuilder(
                listenable: _sceneFocus,
                builder: (context, scene) => Stack(
                  fit: StackFit.expand,
                  children: <Widget>[
                    scene!,
                    if (_sceneFocus.hasFocus)
                      const IgnorePointer(
                        child: _FocusRing(
                          key: PendulumLabControls.focusRingKey,
                        ),
                      ),
                  ],
                ),
                child: widget.child,
              ),
            ),
          ),
        ),
        Positioned(
          top: 16.0,
          left: 16.0,
          child: FocusTraversalOrder(
            order: const NumericFocusOrder(2),
            child: ValueListenableBuilder<bool>(
              valueListenable: widget.running,
              builder: (context, running, _) => IconButton(
                icon: Icon(running ? Icons.pause : Icons.play_arrow),
                tooltip: running ? 'Pause the swing' : 'Start the swing',
                color: LabTheme.onScrim,
                style: IconButton.styleFrom(backgroundColor: LabTheme.scrim),
                onPressed: _toggle,
              ),
            ),
          ),
        ),
      ],
    ),
  );
}

/// The ring round the scene while it has keyboard focus: [LabTheme]'s
/// light ring inside a dark rim, so one of the two stands out over any
/// frame the lab shows.
class _FocusRing extends StatelessWidget {
  const _FocusRing({super.key});

  @override
  Widget build(BuildContext context) => const DecoratedBox(
    decoration: BoxDecoration(
      border: Border.fromBorderSide(
        BorderSide(color: LabTheme.focusRingEdge, width: 2.0),
      ),
    ),
    child: Padding(
      padding: EdgeInsets.all(2.0),
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border.fromBorderSide(
            BorderSide(color: LabTheme.focusRing, width: 3.0),
          ),
        ),
      ),
    ),
  );
}
