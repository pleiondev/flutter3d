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

import '../../../l10n/app_localizations.dart';
import '../modeler_viewport.dart';
import '../play/play_control.dart';
import '../play/play_session.dart';
import '../play/play_template.dart';
import 'budget_bars.dart';

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
///
/// [projectNow] is read again on every Reload rather than captured once:
/// the document behind this route keeps being edited while it is open, and
/// reading a copy taken at Play time would make Reload redraw what was
/// already on screen.
Future<void> showPlay(
  BuildContext context, {
  required Renderer renderer,
  required ModelProject Function() projectNow,
  required PlayTemplate template,
  PlayControl? control,
}) => Navigator.of(context).push(
  MaterialPageRoute<void>(
    fullscreenDialog: true,
    builder: (BuildContext context) => PlayScreen(
      renderer: renderer,
      projectNow: projectNow,
      template: template,
      control: control,
    ),
  ),
);

/// The running game.
class PlayScreen extends StatefulWidget {
  const PlayScreen({
    super.key,
    required this.renderer,
    required this.projectNow,
    required this.template,
    this.control,
  });

  final Renderer renderer;

  /// The live document, read fresh on every Reload.
  final ModelProject Function() projectNow;

  final PlayTemplate template;

  /// `ux-52`: where this screen registers itself so an agent can reload,
  /// stop and ask about it. Null in a test that only wants the picture.
  final PlayControl? control;

  @override
  State<PlayScreen> createState() => _PlayScreenState();
}

class _PlayScreenState extends State<PlayScreen> {
  late final PlaySession _session = PlaySession.start(
    device: widget.renderer.device,
    project: widget.projectNow(),
    template: widget.template,
  );
  final FocusNode _keys = FocusNode(debugLabel: 'play');
  final Set<LogicalKeyboardKey> _held = <LogicalKeyboardKey>{};

  /// When the last frame ran, so a step is the time that actually passed
  /// rather than a number picked to look right at sixty.
  Duration? _last;

  @override
  void initState() {
    super.initState();
    widget.control?.running = (
      template: widget.template,
      reload: _reload,
      stop: () => Navigator.of(context).maybePop(),
      where: () => _session.position,
    );
  }

  @override
  void dispose() {
    // Cleared here rather than by whoever pushed the route: a person
    // pressing Escape and an agent calling `play.stop` both end up here,
    // and a flag cleared in only one of those paths is a `play.reload` that
    // reloads a game nobody is looking at.
    widget.control?.running = null;
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

  /// What the budget card is drawn from, recomputed only when the document
  /// this screen has been handed changes — a report per frame would measure
  /// every mesh in the project sixty times a second.
  late ProfileBudgetReport _budget = ProfileBudgetReport.of(
    widget.projectNow(),
  );

  void _reload() {
    final ModelProject now = widget.projectNow();
    _session.reload(now);
    setState(() => _budget = ProfileBudgetReport.of(now));
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
    final AppLocalizations l = AppLocalizations.of(context);
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
                    label: Text(l.playStop),
                  ),
                  const SizedBox(width: 8),
                  // `ux-51`: the document again, with the body left where it
                  // is. **Keeping the state is the whole point of a Reload
                  // button** — Play stopped and started again would do the
                  // reload as well, and would put the player back at the
                  // spawn, which is the walk they just made taken away.
                  FilledButton.tonalIcon(
                    onPressed: _reload,
                    icon: const Icon(Icons.refresh),
                    label: Text(l.playReload),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    l.playHint(widget.template.label),
                    style: theme.textTheme.labelSmall,
                  ),
                ],
              ),
            ),
            // `ux-51`: the profile's budgets beside the running game, which
            // is where they answer the question they are for — "will this
            // run on the machine I am making it for" is asked while looking
            // at it running, not while looking at a panel of numbers.
            Positioned(
              right: 12,
              top: 12,
              width: 240,
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: BudgetBars(report: _budget),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
