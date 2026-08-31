import 'package:flutter3d_game/flutter3d_game.dart';

/// The one table of controls: the one the devices read and the one the file
/// saves.
///
/// ## The bug this is named after
///
/// Both games did this, and both shipped it:
///
/// ```dart
/// _config = _settingsFile.read();
/// _devices = DesktopInput(
///   bindings: _config.bindings.length > 0 ? _config.bindings : defaults(),
/// );
/// ```
///
/// Read that on a **first launch**. The saved config is empty, so the ternary
/// takes the other branch and the keyboard is handed a *fresh* table. The
/// rebinding screen then edits the table the keyboard holds — correctly, so the
/// new key works immediately — and the save writes `_config`, which is the
/// empty one nobody has touched.
///
/// So on a first launch **a rebind worked until you quit, and then it was
/// gone**. On every launch after that the config is non-empty, the ternary
/// takes the first branch, both are the same object and everything works. That
/// is why it survived: it is invisible to anyone who has ever changed a setting
/// before, which includes everyone who wrote the code.
///
/// The pad's defaults went the same way. `PadInput.addDefaultsTo` was handed
/// the devices' table, so on a first launch a controller's bindings were also
/// added to a table that was never written.
///
/// ## What this does instead
///
/// The config owns the table, always. An empty one is filled with [defaults]
/// **in place**, so there is nothing to choose between and no branch to get
/// backwards.
Bindings ownedBindings(GameConfig config, Bindings Function() defaults) {
  if (config.bindings.length == 0) config.bindings.takeFrom(defaults());
  return config.bindings;
}
