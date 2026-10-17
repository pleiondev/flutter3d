import 'package:flutter/foundation.dart';
import 'package:flutter3d_audio_core/flutter3d_audio_core.dart' show AudioBus;
import 'package:flutter3d_sim/flutter3d_sim.dart';

import '../config/game_config.dart';
import '../input/action_map.dart';
import '../input/bindings.dart' show InputSource;
import 'rebinding.dart';
import 'settings_file.dart';

/// What the settings screen is doing.
///
/// **Small on purpose.** The settings themselves are the controller's
/// [GameSettingsController.settings], one value replaced on every change;
/// this holds what is genuinely screen state and nothing else, plus a
/// [revision] that changes whenever the settings did — what a widget that
/// listens to the state rather than to the settings rebuilds on.
final class SettingsState {
  const SettingsState({
    this.isOpen = false,
    this.waitingFor,
    this.waitingPart,
    this.revision = 0,
    this.lastWriteFailed = false,
    this.conflicts = const <BindingConflict>[],
  });

  /// Whether the panel is up. The pause gate reads this, so it is state and not
  /// a widget's private flag — a game that goes on being played behind its own
  /// settings is a bug both of these applications have shipped.
  final bool isOpen;

  /// The action, of any kind, listening for its new control — see
  /// [GameSettingsController.rebind].
  final InputAction<Object>? waitingFor;

  /// Which part of a composite is listening, if any.
  final CompositePart? waitingPart;

  /// Who had the source the last rebind took — for a line under the
  /// controls that says `J` was jump's. Empty when nothing was in the way.
  final List<BindingConflict> conflicts;

  /// Bumped whenever the settings changed.
  final int revision;

  /// Whether the last write to disk was refused.
  ///
  /// **Nothing read this before**, and it is not decoration: a write fails
  /// when a browser's quota has run out or a disk has filled, and a settings
  /// document that cannot be written looks exactly like a player who changed
  /// nothing. The panel can now say so instead of losing it silently.
  final bool lastWriteFailed;

  /// A copy with the fields given changed. [clearWaiting] empties
  /// [waitingFor] and [waitingPart], which a null cannot say.
  SettingsState copyWith({
    bool? isOpen,
    InputAction<Object>? waitingFor,
    CompositePart? waitingPart,
    bool clearWaiting = false,
    int? revision,
    bool? lastWriteFailed,
    List<BindingConflict>? conflicts,
  }) => SettingsState(
    isOpen: isOpen ?? this.isOpen,
    waitingFor: clearWaiting ? null : (waitingFor ?? this.waitingFor),
    waitingPart: clearWaiting ? null : (waitingPart ?? this.waitingPart),
    revision: revision ?? this.revision,
    lastWriteFailed: lastWriteFailed ?? this.lastWriteFailed,
    conflicts: conflicts ?? this.conflicts,
  );
}

/// The settings screen as a state machine rather than as `setState`.
///
/// **What this replaces, in two applications at once.** Opening the panel,
/// closing it, moving a slider, starting a rebind, taking the key that answers
/// it, cancelling, and putting the controls back were sixteen `setState` calls
/// spread through two thousand-line widgets — and not one of them was reachable
/// from a test, because neither `main.dart` is imported by anything. The rules
/// are not complicated; they were simply somewhere nothing could ask them.
///
/// **A [ValueListenable] of [SettingsState]**, so a widget listens with a
/// `ValueListenableBuilder` and a test reads [value] after a call. It was a
/// cubit from a state-management package, which put that package's major
/// version into this one's contract; the state machine is the same and the
/// listening is Flutter's own.
///
/// **The settings are a value**, [settings], replaced by a `copyWith` on
/// every change: a slider, a switch, a rebind. [apply] is the one seam to
/// the live systems — the mixer's volumes, the pad's dead zone, the sprint
/// toggle — and is handed each new value after it replaced the old one and
/// before the write.
///
/// **The action map is the one live object.** [actions] is the map the
/// devices read, edited in place by a rebind so it takes effect on the next
/// key press; the settings keep a copy of it, taken on each change, so the
/// value a widget was built from never moves under it.
///
/// Writing to disk happens on every change rather than on close, which is what
/// both games already did — a player who changes a volume and quits by closing
/// the window has still changed it.
final class GameSettingsController extends ChangeNotifier
    implements ValueListenable<SettingsState> {
  /// Starts from [settings], writes each change to [file] and puts it onto
  /// the game through [apply].
  ///
  /// [actions] is the map the game's devices read — the one a rebind edits.
  /// Without one, it is a copy of the settings' saved map, or a map over
  /// [ActionSet.common] when they have none.
  GameSettingsController({
    required GameSettings settings,
    required this.file,
    required this.apply,
    ActionMap? actions,
    Rebinding? rebinding,
  }) : _settings = settings,
       actions =
           actions ??
           rebinding?.actions ??
           settings.actions?.copy() ??
           ActionMap(actions: ActionSet.common) {
    this.rebinding = rebinding ?? Rebinding(actions: this.actions);
  }

  /// The settings as they are now.
  GameSettings get settings => _settings;
  GameSettings _settings;

  /// The action map the game's devices read, which a rebind edits in place.
  final ActionMap actions;

  final SettingsFile file;

  /// Puts the settings onto whatever is playing: the mixer, the pad, the
  /// input.
  final void Function(GameSettings settings) apply;

  late final Rebinding rebinding;

  SettingsState _state = const SettingsState();
  bool _disposed = false;

  @override
  SettingsState get value => _state;

  void _emit(SettingsState next) {
    if (_disposed) return;
    _state = next;
    notifyListeners();
  }

  void show() => _emit(_state.copyWith(isOpen: true));

  /// Takes the panel down.
  void hide() {
    // A panel closed while an action was still listening would leave the next
    // key press being eaten by a screen nobody can see.
    rebinding.cancel();
    _emit(_state.copyWith(isOpen: false, clearWaiting: true));
  }

  void toggle() => _state.isOpen ? hide() : show();

  /// Sets [bus] to [volume], a fraction in `[0, 1]`, and saves.
  void setVolume(AudioBus bus, double volume) =>
      update((GameSettings s) => s.withVolume(bus, volume));

  /// Sets [key] to [value] and saves.
  void setValue<T extends Object>(SettingKey<T> key, T value) =>
      update((GameSettings s) => s.withValue(key, value));

  /// Forgets the player's choice for [key] and saves.
  void clearValue(SettingKey<Object> key) =>
      update((GameSettings s) => s.withoutValue(key));

  /// Replaces the settings with what [change] makes of them, and saves.
  void update(GameSettings Function(GameSettings settings) change) {
    _settings = change(_settings);
    _changed(keepSettings: true);
  }

  /// Starts listening for the control [action] — of any kind — should move
  /// to, or for one [part] of its composite. Null cancels.
  void rebind(InputAction<Object>? action, {CompositePart? part}) {
    if (action == null) {
      rebinding.cancel();
      _emit(_state.copyWith(clearWaiting: true));
      return;
    }
    rebinding.start(action, part: part);
    _emit(
      SettingsState(
        isOpen: _state.isOpen,
        waitingFor: action,
        waitingPart: part,
        revision: _state.revision,
        lastWriteFailed: _state.lastWriteFailed,
      ),
    );
  }

  /// Puts [tuning] on [action]'s analogue bindings from [device] — the
  /// mouse's look sensitivity, the pad's inverted look — and saves.
  void setTuning(
    InputAction<Object> action,
    AxisSettings tuning, {
    String? device,
  }) {
    if (rebinding.actions.setTuning(action, tuning, device: device) == 0) {
      return;
    }
    _changed();
  }

  /// Puts the whole action map back the way it shipped, buttons and axes.
  void reset(ActionMap defaults) {
    rebinding.reset(defaults);
    _changed(clearWaiting: true);
  }

  /// Offers [source] to whatever is waiting.
  ///
  /// Returns whether it was taken, so a caller can go on treating the key press
  /// as its own if nothing was listening — which is what makes this safe to
  /// call from the keyboard handler unconditionally.
  bool capture(InputSource source) {
    if (!rebinding.capture(source)) return false;
    if (rebinding.waitingFor != null) {
      // Refused for a conflict: nothing changed, and the screen says why.
      _emit(_state.copyWith(conflicts: rebinding.lastConflicts));
      return true;
    }
    _changed(clearWaiting: true, conflicts: rebinding.lastConflicts);
    return true;
  }

  /// The write the last change started, for a caller (a test, a quit
  /// handler) that has to know it finished. Never fails: a refused write is
  /// [SettingsState.lastWriteFailed].
  Future<void> get saved => _saved;
  Future<void> _saved = Future<void>.value();

  void _changed({
    bool clearWaiting = false,
    List<BindingConflict> conflicts = const <BindingConflict>[],
    bool keepSettings = false,
  }) {
    // A rebind edited the live map: the settings take a copy of it.
    if (!keepSettings) _settings = _settings.copyWith(actions: actions.copy());
    apply(_settings);
    final revision = _state.revision + 1;
    _emit(
      _state.copyWith(
        revision: revision,
        clearWaiting: clearWaiting,
        conflicts: conflicts,
      ),
    );
    _saved = file
        .write(_settings)
        .then((bool kept) => _wrote(revision, failed: !kept));
  }

  /// Records how the write of [revision] went, unless a later change has
  /// started a later write whose answer is the one that matters.
  void _wrote(int revision, {required bool failed}) {
    if (_state.revision != revision || _state.lastWriteFailed == failed) {
      return;
    }
    _emit(_state.copyWith(lastWriteFailed: failed));
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
