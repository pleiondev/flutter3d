import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter3d_game/flutter3d_game.dart';

import 'settings_cubit.dart';

/// The keys that belong to the settings rather than to the game.
///
/// Returns null when the event is none of the settings' business, which is the
/// caller's cue to offer it to its own clauses and then to the game.
///
/// **The order is the whole of it, and all three games had written it out.**
/// Three clauses, in a sequence that was arrived at by getting it wrong:
///
///  1. A rebinding takes the next key **before anything else looks at it**,
///     including Escape — which is how a player says "not that one".
///  2. Escape opens the panel as well as closing it, so a player on a
///     controller, who never took the pointer, has a way in. [opening] runs
///     first: on desktop that is the pointer being let go, because a panel you
///     cannot point at has no way out of it, and on the web and on a phone —
///     where there is no pointer to release — it is the held keys being
///     dropped, without which closing the panel sent the player walking off on
///     their own.
///  3. **With the panel open the keys belong to the panel.** Handing them to
///     the game costs two things at once: Flutter's focus traversal never sees
///     Tab or the arrows, so a player with no mouse cannot reach a slider at
///     all, and a key held as the panel opened stays held in the [InputState].
///
/// The platformer had rule 1 written down and broke it: its own restart clause
/// sat above the rebinding, so a player at the end of a run could not bind R to
/// anything — the key restarted the run instead of being taken. Asking here
/// first is what fixes that, and it is the reason the game's own clauses now
/// come after this call rather than before it.
///
/// [canOpen] is for a game with a screen the panel adds nothing to: the
/// platformer's title card carries the same credits, so Escape there does what
/// it always did and gives the pointer back.
KeyEventResult? settingsKeys(
  KeyEvent event,
  SettingsCubit settings, {
  required void Function() opening,
  bool canOpen = true,
}) {
  if (event is! KeyDownEvent) {
    return settings.state.isOpen ? KeyEventResult.ignored : null;
  }

  if (settings.state.waitingFor != null) {
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      settings.rebind(null);
    } else {
      settings.capture(InputSource.key(event.logicalKey.keyId));
    }
    return KeyEventResult.handled;
  }

  if (event.logicalKey == LogicalKeyboardKey.escape &&
      (canOpen || settings.state.isOpen)) {
    if (!settings.state.isOpen) opening();
    settings.toggle();
    return KeyEventResult.handled;
  }

  return settings.state.isOpen ? KeyEventResult.ignored : null;
}
