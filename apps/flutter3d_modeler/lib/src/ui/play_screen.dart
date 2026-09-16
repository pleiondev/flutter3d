/// `ux-50`'s own screen: the document, walked in, over the top of it.
///
/// **A route rather than a window.** The web build has no second window to
/// open and the sandboxed macOS build cannot start a second process, so Play
/// is a page of this application — which also means it is the same renderer,
/// the same device and the same uploaded textures the viewport already has,
/// and a material changed behind it is changed here on the next frame.
library;

import 'package:flutter/material.dart' hide Material;
import 'package:flutter/services.dart';
import 'package:flutter3d/flutter3d.dart' hide Material;
import 'package:flutter3d_model_core/flutter3d_model_core.dart' hide Outcome;
import 'package:vector_math/vector_math.dart' show Vector2;

import '../modeler_viewport.dart';
import '../play/play_session.dart';
import '../play/play_template.dart';

/// Which key does what while Play is running.
///
/// **Not the modeller's own shortcut table.** Those are a person's to
/// rebind; these are the ones a game has had since before there were
/// settings, and a Play that asked somebody to configure movement before it
/// would move is a Play nobody reaches the end of.
/// Not `const`: `LogicalKeyboardKey` overrides `==`, which a constant map's
/// own keys may not.
final Map<LogicalKeyboardKey, ({double x, double y})> kPlayWalkKeys =
    <LogicalKeyboardKey, ({double x, double y})>{
      LogicalKeyboardKey.keyW: (x: 0.0, y: 1.0),
      LogicalKeyboardKey.keyS: (x: 0.0, y: -1.0),
      LogicalKeyboardKey.keyA: (x: -1.0, y: 0.0),
      LogicalKeyboardKey.keyD: (x: 1.0, y: 0.0),
      LogicalKeyboardKey.arrowUp: (x: 0.0, y: 1.0),
      LogicalKeyboardKey.arrowDown: (x: 0.0, y: -1.0),
      LogicalKeyboardKey.arrowLeft: (x: -1.0, y: 0.0),
      LogicalKeyboardKey.arrowRight: (x: 1.0, y: 0.0),
    };

/// Opens Play over whatever is on screen, and comes back when it is stopped.
Future<void> showPlay(
  BuildContext context, {
  required Renderer renderer,
  required ModelProject project,
  required PlayTemplate template,
}) => Navigator.of(context).push(
  MaterialPageRoute<void>(
    fullscreenDialog: true,
    builder: (BuildContext context) =>
        PlayScreen(renderer: renderer, project: project, template: template),
  ),
);

/// The running game.
class PlayScreen extends StatefulWidget {
  const PlayScreen({
    super.key,
    required this.renderer,
    required this.project,
    required this.template,
  });

  final Renderer renderer;
  final ModelProject project;
  final PlayTemplate template;

  @override
  State<PlayScreen> createState() => _PlayScreenState();
}

class _PlayScreenState extends State<PlayScreen> {
  late final PlaySession _session = PlaySession.start(
    device: widget.renderer.device,
    project: widget.project,
    template: widget.template,
  );
  final FocusNode _keys = FocusNode(debugLabel: 'play');
  final Set<LogicalKeyboardKey> _held = <LogicalKeyboardKey>{};

  /// When the last frame ran, so a step is the time that actually passed
  /// rather than a number picked to look right at sixty.
  Duration? _last;

  @override
  void dispose() {
    _keys.dispose();
    super.dispose();
  }

  KeyEventResult _key(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.escape) {
      Navigator.of(context).maybePop();
      return KeyEventResult.handled;
    }
    if (event is KeyDownEvent) {
      _held.add(event.logicalKey);
    } else if (event is KeyUpEvent) {
      _held.remove(event.logicalKey);
    } else {
      return KeyEventResult.ignored;
    }
    // Every key this screen knows is handled, so a W does not also reach the
    // shell's own shortcut for it while a game is running on top.
    return kPlayWalkKeys.containsKey(event.logicalKey) ||
            event.logicalKey == LogicalKeyboardKey.space ||
            event.logicalKey == LogicalKeyboardKey.shiftLeft
        ? KeyEventResult.handled
        : KeyEventResult.ignored;
  }

  PlayInput get _input {
    var x = 0.0;
    var y = 0.0;
    for (final LogicalKeyboardKey key in _held) {
      if (kPlayWalkKeys[key] case final ({double x, double y}) axis) {
        x += axis.x;
        y += axis.y;
      }
    }
    // Clamped rather than left as a sum, or forward and right together would
    // move about 1.41 times as fast as forward alone — `InputState` makes the
    // same correction, and for the same reason.
    final Vector2 move = Vector2(x, y);
    if (move.length2 > 1.0) move.normalize();
    return (
      move: move,
      sprint: _held.contains(LogicalKeyboardKey.shiftLeft),
      jump: _held.contains(LogicalKeyboardKey.space),
    );
  }

  void _frame() {
    final Duration now = Duration(
      microseconds: DateTime.now().microsecondsSinceEpoch,
    );
    final Duration? was = _last;
    _last = now;
    if (was == null) return;
    _session.step((now - was).inMicroseconds / 1e6, _input);
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Scaffold(
      body: Focus(
        focusNode: _keys,
        autofocus: true,
        onKeyEvent: _key,
        child: Stack(
          children: <Widget>[
            Positioned.fill(
              child: ModelerViewport(
                renderer: widget.renderer,
                stage: _session.stage,
                onFrame: _frame,
                // No grid and no gizmos: this is the game's own picture, and
                // the editor's furniture drawn over it would be the one thing
                // Play exists to take away.
                grid: null,
                overlay: false,
              ),
            ),
            // Over the viewport rather than around it, so the drag never
            // reaches the orbit controller underneath — in Play the pointer
            // turns the head, not the camera rig.
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onPanUpdate: (DragUpdateDetails it) =>
                    _session.look(it.delta.dx, it.delta.dy),
              ),
            ),
            Positioned(
              left: 12,
              top: 12,
              child: Row(
                children: <Widget>[
                  FilledButton.tonalIcon(
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: const Icon(Icons.stop),
                    label: const Text('Stop'),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    '${widget.template.label}  ·  WASD to walk, drag to look, '
                    'Esc to stop',
                    style: theme.textTheme.labelSmall,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
