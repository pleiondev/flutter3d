import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'rebinding.dart';
import 'settings_file.dart';

/// What the settings screen is doing.
///
/// **Small on purpose.** The settings themselves are a [GameConfig], which is a
/// mutable object shared with the input layer, the mixer and the pad — copying
/// it into a state class would mean two answers to "what is the volume", and
/// the one the game plays at would be the copy nobody looked at.
///
/// So this holds what is genuinely screen state and nothing else, plus a
/// [revision] that changes whenever the config underneath did. That counter is
/// what makes a rebuild happen at all: an in-place edit of a shared object does
/// not change the state's identity, and without it a slider would move and
/// nothing would redraw.
final class SettingsState {
  const SettingsState({
    this.isOpen = false,
    this.waitingFor,
    this.revision = 0,
    this.lastWriteFailed = false,
  });

  /// Whether the panel is up. The pause gate reads this, so it is state and not
  /// a widget's private flag — a game that goes on being played behind its own
  /// settings is a bug both of these applications have shipped.
  final bool isOpen;

  /// The action listening for its new control, if any.
  final GameAction? waitingFor;

  /// Bumped whenever the shared [GameConfig] was edited in place.
  final int revision;

  /// Whether the last write to disk was refused.
  ///
  /// **Nothing read this before**, and it is not decoration: `Storage.write`
  /// returns false when a browser's quota has run out or a disk has filled, and
  /// a settings document that cannot be written looks exactly like a player who
  /// changed nothing. The panel can now say so instead of losing it silently.
  final bool lastWriteFailed;

  SettingsState copyWith({
    bool? isOpen,
    GameAction? waitingFor,
    bool clearWaiting = false,
    int? revision,
    bool? lastWriteFailed,
  }) =>
      SettingsState(
        isOpen: isOpen ?? this.isOpen,
        waitingFor: clearWaiting ? null : (waitingFor ?? this.waitingFor),
        revision: revision ?? this.revision,
        lastWriteFailed: lastWriteFailed ?? this.lastWriteFailed,
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
/// [apply] is the one seam to the live systems: the mixer's volumes, the pad's
/// dead zone, the sprint toggle. Both games already had a method that did
/// exactly this and called it from four places; it is called from one now, and
/// always after the config changed and before the write.
///
/// Writing to disk happens on every change rather than on close, which is what
/// both games already did — a player who changes a volume and quits by closing
/// the window has still changed it.
final class SettingsCubit extends Cubit<SettingsState> {
  SettingsCubit({
    required this.config,
    required this.file,
    required this.apply,
    Rebinding? rebinding,
  })  : rebinding = rebinding ?? Rebinding(bindings: config.bindings),
        super(const SettingsState());

  /// The live document. Shared with the input layer on purpose — see
  /// [SettingsState].
  final GameConfig config;

  final SettingsFile file;

  /// Puts the config onto whatever is playing: the mixer, the pad, the input.
  final void Function(GameConfig config) apply;

  final Rebinding rebinding;

  void show() => emit(state.copyWith(isOpen: true));

  /// Takes the panel down.
  ///
  /// Not `close`, which `BlocBase` already has and which disposes the cubit —
  /// a name collision the compiler catches, and one worth a sentence because
  /// `open`/`close` is the pair anybody would reach for first.
  void hide() {
    // A panel closed while an action was still listening would leave the next
    // key press being eaten by a screen nobody can see.
    rebinding.cancel();
    emit(state.copyWith(isOpen: false, clearWaiting: true));
  }

  void toggle() => state.isOpen ? hide() : show();

  void setVolume(String bus, double volume) {
    config.setVolume(bus, volume);
    _changed();
  }

  void setSetting(String name, double value) {
    config.setSetting(name, value);
    _changed();
  }

  /// Starts listening for the control [action] should move to. Null cancels.
  void rebind(GameAction? action) {
    if (action == null) {
      rebinding.cancel();
      emit(state.copyWith(clearWaiting: true));
      return;
    }
    rebinding.start(action);
    emit(state.copyWith(waitingFor: action));
  }

  /// Offers [source] to whatever is waiting.
  ///
  /// Returns whether it was taken, so a caller can go on treating the key press
  /// as its own if nothing was listening — which is what makes this safe to
  /// call from the keyboard handler unconditionally.
  bool capture(InputSource source) {
    if (!rebinding.capture(source)) return false;
    _changed(clearWaiting: true);
    return true;
  }

  /// Puts the controls back the way they shipped.
  void resetControls(Bindings defaults) {
    rebinding.reset(defaults);
    _changed(clearWaiting: true);
  }

  void _changed({bool clearWaiting = false}) {
    apply(config);
    final wrote = file.write(config);
    emit(state.copyWith(
      revision: state.revision + 1,
      lastWriteFailed: !wrote,
      clearWaiting: clearWaiting,
    ));
  }
}
