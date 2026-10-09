import 'package:flutter/material.dart';
import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';

import '../l10n/game_localizations.dart';
import '../theme/game_ui_theme.dart';
import 'settings_panel_controls.dart';

/// What [ActionBindingsSection.onRebind] is asked: start listening for
/// [action]'s new control (or for [part] of it, on a composite), or stop.
///
/// **An object, so a request can grow.** It was two positional arguments,
/// and the next thing a rebinding screen wants to say (which device the
/// player is on, say) would have broken every handler; a field added here
/// does not.
final class RebindRequest {
  /// Listening for [action], or for [part] of it.
  const RebindRequest({required InputAction<Object> this.action, this.part});

  const RebindRequest._cancel() : action = null, part = null;

  /// Stop listening: the waiting row was tapped again.
  static const RebindRequest cancel = RebindRequest._cancel();

  /// The action to listen for; null when this is [cancel].
  final InputAction<Object>? action;

  /// Which part of [action], for an axis or dual axis bound to keys; null for
  /// the whole action.
  final CompositePart? part;

  /// Whether this stops listening rather than starting: what a game's own
  /// handler asks before it reads [action].
  bool get isCancel => action == null;

  @override
  bool operator ==(Object other) =>
      other is RebindRequest && other.action == action && other.part == part;

  @override
  int get hashCode => Object.hash(action, part);
}

/// What [ActionBindingsSection.onTuning] is asked: shape [action]'s analogue
/// bindings on [device] with [tuning].
///
/// An object for [RebindRequest]'s reason: a field added later does not
/// break a handler.
final class TuningChange {
  const TuningChange({
    required this.action,
    required this.tuning,
    required this.device,
  });

  /// The action whose analogue bindings change.
  final InputAction<Object> action;

  /// The shaping they take.
  final AxisSettings tuning;

  /// The device the bindings read, as `InputSource.device` names it.
  final String device;

  @override
  bool operator ==(Object other) =>
      other is TuningChange &&
      other.action == action &&
      other.tuning == tuning &&
      other.device == device;

  @override
  int get hashCode => Object.hash(action, tuning, device);
}

/// The controls part of a settings screen, over an [ActionMap]: every
/// rebindable action the game declares, of every kind, with what it is bound
/// to, a way to move it, and the shaping of its analogue sources.
///
/// * a **button** is one row, as it always was;
/// * an **axis** bound to two keys is a row per end, `lift −` and `lift +`;
/// * a **dual axis** bound to four keys is a row per direction, and one bound
///   to a stick or the mouse gets a sensitivity slider and the two inverts;
/// * a **conflict** the last rebind met is said underneath — "`J` was
///   jump's" — because a key that silently stopped doing what it did is the
///   bug report a rebinding screen otherwise produces.
///
/// It holds no state: what is waiting and what conflicted are the
/// [GameSettingsController]'s, passed in, and every change goes out through the
/// callbacks — so the same section sits in the engine's [SettingsPanel] and
/// in a game's own screen.
class ActionBindingsSection extends StatelessWidget {
  const ActionBindingsSection({
    super.key,
    required this.map,
    required this.waitingFor,
    required this.onRebind,
    required this.onReset,
    this.waitingPart,
    this.conflicts = const <BindingConflict>[],
    this.onTuning,
    this.actionLabel,
  });

  /// What an action is called, for an action of the game's own.
  ///
  /// **A declaration's label is a message id**, resolved through
  /// [Flutter3dGameLocalizations.actionLabel]: the engine's actions are said
  /// in the player's language without this. A game whose actions have words
  /// of its own answers them here, from its own localizations, and returns
  /// null for the rest.
  final String? Function(ActionDeclaration declaration)? actionLabel;

  String _labelOf(
    ActionDeclaration declaration,
    Flutter3dGameLocalizations w,
  ) =>
      actionLabel?.call(declaration) ??
      w.actionLabel(declaration.label ?? declaration.action.name);

  final ActionMap map;

  /// What is listening for its new control, if anything.
  final InputAction<Object>? waitingFor;

  /// Which part of it, for a composite.
  final CompositePart? waitingPart;

  /// Asked to start listening for an action's new control, or to stop:
  /// see [RebindRequest].
  final void Function(RebindRequest request) onRebind;

  final VoidCallback onReset;

  /// What the last rebind took from another action.
  final List<BindingConflict> conflicts;

  /// Asked to change the shaping of an action's analogue bindings on one
  /// device: see [TuningChange]. Null leaves the sliders out.
  final void Function(TuningChange change)? onTuning;

  @override
  Widget build(BuildContext context) {
    final words = Flutter3dGameLocalizations.of(context);
    final rows = <Widget>[
      for (final declaration in map.actions.rebindable)
        ..._rowsFor(declaration, words),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        ...rows,
        if (conflicts.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Semantics(
              liveRegion: true,
              child: Text(
                conflicts.map((c) => _sayConflict(c, words)).join(' '),
                style: TextStyle(color: GameUiTheme.of(context).warning),
              ),
            ),
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            onPressed: onReset,
            child: Text(words.resetControls),
          ),
        ),
      ],
    );
  }

  List<Widget> _rowsFor(
    ActionDeclaration declaration,
    Flutter3dGameLocalizations words,
  ) {
    final action = declaration.action;
    final label = _labelOf(declaration, words);
    final bindings = map.bindingsFor(action);
    final composites = bindings.where(
      (b) => b is AxisComposite || b is DualAxisComposite,
    );
    final parts = switch (action) {
      AxisAction() => const <CompositePart>[
        CompositePart.negative,
        CompositePart.positive,
      ],
      DualAxisAction() => const <CompositePart>[
        CompositePart.up,
        CompositePart.down,
        CompositePart.left,
        CompositePart.right,
      ],
      GameAction() => const <CompositePart>[],
    };
    return <Widget>[
      if (action is GameAction)
        _row(label, action, null, map.sourcesFor(action))
      else if (action is DualAxisAction && action.isDelta)
        // Motion has no keys to move it to: shown, shaped below, not rebound.
        SettingsBindingRow(
          label: label,
          sources: map.sourcesFor(action),
          waiting: false,
        )
      else
        for (final part in parts)
          _row('$label ${words.part(part)}', action, part, <InputSource>[
            for (final composite in composites)
              if (composite.sourceAt(part) != InputSource.none)
                composite.sourceAt(part),
          ]),
      if (onTuning != null)
        for (final binding in bindings)
          ...switch (binding) {
            AxisBinding(:final source, :final tuning) ||
            DualAxisBinding(
              :final source,
              :final tuning,
            ) => _tuningRows(label, action, source, tuning, words),
            _ => const <Widget>[],
          },
    ];
  }

  Widget _row(
    String label,
    InputAction<Object> action,
    CompositePart? part,
    List<InputSource> sources,
  ) {
    final waiting = waitingFor == action && waitingPart == part;
    return SettingsBindingRow(
      label: label,
      sources: sources,
      waiting: waiting,
      onTap: () => onRebind(
        waiting
            ? RebindRequest.cancel
            : RebindRequest(action: action, part: part),
      ),
    );
  }

  List<Widget> _tuningRows(
    String label,
    InputAction<Object> action,
    InputSource source,
    AxisSettings tuning,
    Flutter3dGameLocalizations words,
  ) {
    final change = onTuning!;
    final device = source.device;
    final on = words.source(source);
    return <Widget>[
      SettingsValueSlider(
        label: words.sensitivity(label, on),
        value: tuning.sensitivity,
        min: 0.25,
        max: 4.0,
        onChanged: (double value) => change(
          TuningChange(
            action: action,
            tuning: tuning.copyWith(sensitivity: value),
            device: device,
          ),
        ),
      ),
      if (action is DualAxisAction)
        SettingsSwitchRow(
          label: words.invertVertically(label, on),
          on: tuning.invertY,
          onChanged: (bool invert) => change(
            TuningChange(
              action: action,
              tuning: tuning.copyWith(invertY: invert),
              device: device,
            ),
          ),
        ),
      SettingsSwitchRow(
        label: action is DualAxisAction
            ? words.invertHorizontally(label, on)
            : words.invert(label, on),
        on: tuning.invertX,
        onChanged: (bool invert) => change(
          TuningChange(
            action: action,
            tuning: tuning.copyWith(invertX: invert),
            device: device,
          ),
        ),
      ),
    ];
  }

  String _sayConflict(
    BindingConflict conflict,
    Flutter3dGameLocalizations words,
  ) {
    final name = switch (map.actions.declarationOf(conflict.action)) {
      final ActionDeclaration declaration => _labelOf(declaration, words),
      null => words.actionLabel(conflict.action.name),
    };
    final part = conflict.part == null ? '' : ' ${words.part(conflict.part!)}';
    return words.conflict(words.source(conflict.source), '$name$part');
  }
}
