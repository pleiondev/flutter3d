/// Screen 26, "Agent session" — `tut-16`'s own fix.
///
/// `doc/design/modeler-handoff/README-addendum.md` row 26, and screen 26 of
/// `designs/Экраны редактора - дополнение.dc.html`, draw three things beside
/// the ordinary shell while `--mcp-port` is open: a live feed of every tool
/// call an agent makes, a history list badged by who made each step, and a
/// contact sheet of what a `render`/`renderSheet` call last drew — "what the
/// agent gets instead of numbers," in the hand-off's own words. `mcp-16d`
/// shipped the seven `ui.*` tools this reads calls from and `mcp-10n` the
/// author-restricted undo underneath the button here; this file is the panel
/// that finally shows either to a person watching.
///
/// **[AgentSessionPanel] is appended after the ordinary properties panel,
/// never in place of it.** A person keeps editing the same document an agent
/// is also calling tools against, and still wants the object/mesh/material
/// controls `PropertiesPanel` already draws — this is extra, not a
/// replacement, which is also why `ModelerShell`'s own new `agentPanel` slot
/// is nullable and additive rather than a second `properties`.
///
/// **[AgentContactSheet] reads the same feed's own pictures, not a second,
/// live six-camera render.** The hand-off's screen 26 draws six thumbnails —
/// perspective, front, side, top, wireframe, normals — but nothing in this
/// app renders more than one view at a time outside `render`/`renderSheet`
/// themselves (`mcp-06n`/`mcp-07n`, `flutter3d_model_mcp`), and standing up a
/// second, parallel multi-camera renderer purely to mirror six fixed labels
/// is a far larger thing than this row asks for. What the sheet actually
/// shows instead is exactly as true to "what the agent gets instead of
/// numbers": every picture a `render`/`renderSheet` call has actually drawn
/// this session, most recent first, labelled by the view/mode it was asked
/// for — real answers an agent received, not a live camera rig standing by
/// for a call that may never come.
library;

import 'package:flutter/material.dart';
import 'package:flutter3d_model_core/flutter3d_model_core.dart';

import '../../../l10n/app_localizations.dart';
import '../modeler_state.dart' show AgentToolCall;
import 'theme.dart';

/// The tool-call feed and the author-badged history, screen 26's own right
/// column.
class AgentSessionPanel extends StatefulWidget {
  const AgentSessionPanel({
    super.key,
    required this.calls,
    required this.history,
    required this.onUndoAgentSteps,
    this.clientName,
    this.onClose,
    this.paused = false,
    this.onPaused,
  });

  /// Whether agent calls are being refused right now — `ux-45`.
  final bool paused;

  /// Flips [paused]. Null hides the switch, which is what a test pumping the
  /// panel without a server behind it wants.
  final ValueChanged<bool>? onPaused;

  /// What the connected agent called itself — `ux-05`'s own `initialize`.
  /// Null in a test that has no client to name.
  final String? clientName;

  /// Closes the panel. Null leaves it with no close button, which is what a
  /// test pumping the panel on its own wants.
  final VoidCallback? onClose;

  /// `ModelerCubit.agentToolCalled`'s own bounded feed, oldest call first.
  final List<AgentToolCall> calls;

  /// The live document history — read directly rather than copied, the same
  /// "live, mutated in place" `ModelerReady.history` itself already is.
  final ModelHistory history;

  /// `mcp-10n`'s own restriction, offered a button: enabled only while
  /// [ModelHistory.topStepAuthor] is [StepAuthor.agent]. `ux-45` made it take
  /// back the whole run rather than one step.
  final VoidCallback onUndoAgentSteps;

  @override
  State<AgentSessionPanel> createState() => _AgentSessionPanelState();
}

class _AgentSessionPanelState extends State<AgentSessionPanel> {
  /// Which tab is showing. `ux-05` moved the contact sheet in here from the
  /// shell's own bottom slot: it is a thing about the agent session, and it
  /// was taking a third of the viewport's height whether or not there was an
  /// agent or a render to show.
  bool _renders = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final List<AgentToolCall> calls = widget.calls;
    final ModelHistory history = widget.history;
    final steps = history.steps;
    final AppLocalizations l = AppLocalizations.of(context);
    final int agentSteps = steps
        .where((HistoryStep step) => step.author == StepAuthor.agent)
        .length;
    final int personSteps = steps.length - agentSteps;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 8, 8),
          child: Row(
            children: <Widget>[
              Icon(Icons.smart_toy, size: 18, color: kModelerScheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  widget.clientName == null
                      ? 'Agent session'
                      : 'Agent · ${widget.clientName}',
                  style: theme.textTheme.titleSmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (widget.onClose case final VoidCallback close)
                IconButton(
                  tooltip: l.agentHide,
                  onPressed: close,
                  iconSize: 18,
                  icon: const Icon(Icons.close),
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: SegmentedButton<bool>(
            segments: <ButtonSegment<bool>>[
              ButtonSegment<bool>(value: false, label: Text(l.agentSession)),
              ButtonSegment<bool>(value: true, label: Text(l.agentRenders)),
            ],
            selected: <bool>{_renders},
            showSelectedIcon: false,
            onSelectionChanged: (Set<bool> it) =>
                setState(() => _renders = it.first),
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: _renders
              ? AgentContactSheet(calls: calls)
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  children: <Widget>[
                    _SectionLabel(l.agentToolCalls),
                    if (calls.isEmpty)
                      const _EmptyHint('No tool calls yet this session')
                    else
                      for (final AgentToolCall call in calls)
                        _ToolCallRow(call),
                    const SizedBox(height: 18),
                    _SectionLabel(l.agentHistoryAuthor),
                    if (steps.isEmpty)
                      const _EmptyHint('Nothing done yet')
                    else
                      for (final HistoryStep step in steps.reversed)
                        _HistoryRow(step),
                    const SizedBox(height: 12),
                  ],
                ),
        ),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 12, 10),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  l.agentSteps(agentSteps, personSteps),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              TextButton(
                onPressed: history.topStepAuthor == StepAuthor.agent
                    ? widget.onUndoAgentSteps
                    : null,
                child: Text(l.agentUndoSteps),
              ),
            ],
          ),
        ),
        // `ux-45`: the brake, under the numbers it is about. A person who
        // wants an agent to stop has, until now, had the choice of killing
        // the process or closing the window — one loses the session, the
        // other loses the work.
        if (widget.onPaused case final ValueChanged<bool> onPaused)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 12, 12),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    widget.paused
                        ? 'Paused — calls are being refused'
                        : 'Pause agent',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: widget.paused
                          ? theme.colorScheme.error
                          : theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                Switch(value: widget.paused, onChanged: onPaused),
              ],
            ),
          ),
      ],
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Text(
      text.toUpperCase(),
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
        letterSpacing: 1.0,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    ),
  );
}

class _EmptyHint extends StatelessWidget {
  const _EmptyHint(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Text(
      text,
      style: Theme.of(
        context,
      ).textTheme.bodySmall?.copyWith(fontStyle: FontStyle.italic),
    ),
  );
}

/// One entry in the "tool calls" feed — `tool(args)`, how long it took, and
/// what it said, coloured by whether it did anything at all.
class _ToolCallRow extends StatelessWidget {
  const _ToolCallRow(this.call);

  final AgentToolCall call;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      key: ValueKey<AgentToolCall>(call),
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(
                Icons.smart_toy,
                size: 15,
                color: call.did
                    ? kModelerScheme.primary
                    : theme.colorScheme.error,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${call.tool}(${_argsSummary(call.arguments)})',
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                _elapsedLabel(call.elapsed),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            call.says,
            style: theme.textTheme.bodySmall?.copyWith(
              color: call.did
                  ? theme.colorScheme.onSurfaceVariant
                  : theme.colorScheme.error,
            ),
          ),
        ],
      ),
    );
  }
}

/// One entry in the author-badged history — `mcp-10n`'s own [StepAuthor],
/// finally on screen: newest first, the same order a person reading down an
/// undo stack already expects the top entry to be the one ⌘Z takes next.
class _HistoryRow extends StatelessWidget {
  const _HistoryRow(this.step);

  final HistoryStep step;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bool agent = step.author == StepAuthor.agent;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: <Widget>[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: agent
                  ? kModelerScheme.primaryContainer
                  : theme.colorScheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              agent ? 'Agent' : 'You',
              style: theme.textTheme.labelSmall?.copyWith(
                color: agent
                    ? kModelerScheme.onPrimaryContainer
                    : theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              step.command.says,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}

String _argsSummary(Map<String, Object?> arguments) => arguments.isEmpty
    ? ''
    : arguments.entries
          .map((MapEntry<String, Object?> e) => '${e.key}: ${e.value}')
          .join(', ');

String _elapsedLabel(Duration elapsed) {
  final int ms = elapsed.inMilliseconds;
  return ms < 1000 ? '${ms}ms' : '${(ms / 1000).toStringAsFixed(1)}s';
}

/// Screen 26's own contact sheet, drawn into `ModelerShell.bottom` — see
/// this file's own library comment for what it actually shows and why.
class AgentContactSheet extends StatelessWidget {
  const AgentContactSheet({super.key, required this.calls});

  /// The same feed [AgentSessionPanel] reads — only the entries carrying a
  /// picture (`render`/`renderSheet`) are ever drawn here.
  final List<AgentToolCall> calls;

  static const int _maxThumbnails = 6;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final AppLocalizations l = AppLocalizations.of(context);
    final List<AgentToolCall> pictures = <AgentToolCall>[
      for (final AgentToolCall call in calls.reversed)
        if (call.png != null) call,
    ].take(_maxThumbnails).toList(growable: false);
    return ColoredBox(
      color: theme.colorScheme.surfaceContainer,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Text(
                  l.agentContactSheet,
                  style: theme.textTheme.labelSmall?.copyWith(
                    letterSpacing: 1.0,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(width: 8),
                // Flexible since `ux-05` moved this out of the shell's own
                // full-width bottom slot and into a column about three
                // hundred pixels across: the subtitle is a gloss on the
                // label above it, and a gloss that overflows its panel is
                // worse than one that ellipsises.
                Flexible(
                  child: Text(
                    l.agentInsteadOfNumbers,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Expanded(
              child: pictures.isEmpty
                  ? Center(
                      child: Text(
                        l.agentNoRenderYet,
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    )
                  : Row(
                      children: <Widget>[
                        for (final AgentToolCall call in pictures)
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.only(right: 10),
                              child: _Thumbnail(call),
                            ),
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

class _Thumbnail extends StatelessWidget {
  const _Thumbnail(this.call);

  final AgentToolCall call;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ClipRRect(
      key: ValueKey<AgentToolCall>(call),
      borderRadius: BorderRadius.circular(10),
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          ColoredBox(
            color: theme.colorScheme.surface,
            child: Image.memory(call.png!, fit: BoxFit.contain),
          ),
          Positioned(
            left: 6,
            bottom: 6,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.72),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                _labelFor(call),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A short label for one contact-sheet thumbnail — the view/mode it was
/// asked for, read straight off [AgentToolCall.arguments] rather than a
/// second copy of `render`/`renderSheet`'s own argument-reading.
String _labelFor(AgentToolCall call) {
  final Object? view = call.arguments['view'];
  final Object? mode = call.arguments['mode'];
  if (call.tool == 'renderSheet') {
    return mode is String && mode != 'material' ? 'sheet · $mode' : 'sheet';
  }
  final String viewLabel = view is String ? view : 'iso';
  return mode is String && mode != 'material'
      ? '$viewLabel · $mode'
      : viewLabel;
}
