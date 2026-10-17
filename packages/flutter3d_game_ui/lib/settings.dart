/// The settings a player opens over a game: the panel, the overlay it sits
/// in, and the sections it is made of.
///
/// * [SettingsOverlay]: the gear and the panel it opens, over the game.
/// * [SettingsPanel]: the panel alone, for a game that places it itself.
/// * [SettingsSection] and the standard ones — [VolumesSection],
///   [ControlsSection], [AccessibilitySection], [ColorsSection],
///   [ConsentsSection], [MouseSection], [GamepadSection] — with
///   [WidgetSection] for a game's own rows.
/// * [ActionBindingsSection]: the rebinding list, which takes a key or a pad
///   button, with what it asks for ([RebindRequest], [TuningChange]).
/// * [PrivacySection], [askWhichRun] and [syncBeforeBegin]: what a game asks
///   before anything of the player's leaves the device.
///
/// **The widgets, not the settings.** What a player chose (`GameSettings`),
/// the controller that writes it (`GameSettingsController`), the file it is
/// kept in (`SettingsFile`) and the rebinding in progress (`Rebinding`) are
/// `flutter3d_game`'s, which a game without a screen — a test, a replaying
/// server — reads the same way.
library;

export 'src/settings/action_bindings_section.dart';
export 'src/settings/privacy_section.dart';
export 'src/settings/settings_overlay.dart';
export 'src/settings/settings_panel.dart';
export 'src/settings/settings_sections.dart';
