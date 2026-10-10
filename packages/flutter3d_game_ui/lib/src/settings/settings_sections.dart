import 'package:flutter/material.dart';
import 'package:flutter3d_audio_core/flutter3d_audio_core.dart' show AudioBus;
import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart' show ActionDeclaration;

import '../l10n/game_localizations.dart';
import 'action_bindings_section.dart';
import 'privacy_section.dart';
import 'settings_panel_controls.dart';

/// One part of a settings screen: a heading and the rows under it, over a
/// [GameSettingsController].
///
/// **What a game offers is a list of these**, handed to `SettingsPanel` or
/// `SettingsOverlay`, rather than a dozen arguments of which a game used
/// some: [standard] is the panel every game had, and a game drops a section,
/// reorders them, or adds one of its own by extending this class.
///
/// `base`: extend it, do not implement it, so a member added in a 1.x
/// release arrives with a body.
abstract base class SettingsSection {
  const SettingsSection();

  /// The rows of this section, reading [settings] and changing it.
  Widget build(
    BuildContext context,
    GameSettingsController settings,
    SettingsState state,
  );

  /// The sections every game's panel had, in its order: the volumes of
  /// [buses], the controls when [defaultActions] is given, accessibility,
  /// [colors], [privacy], the mouse, the gamepad, and [credits].
  static List<SettingsSection> standard({
    List<AudioBus> buses = settableBuses,
    ActionMap Function()? defaultActions,
    bool actionTuning = false,
    String? Function(ActionDeclaration declaration)? actionLabel,
    ColorRoles? colors,
    Consents? privacy,
    required bool padConnected,
    Widget? credits,
  }) => <SettingsSection>[
    VolumesSection(buses: buses),
    if (defaultActions != null)
      ControlsSection(
        defaults: defaultActions,
        showsTuning: actionTuning,
        actionLabel: actionLabel,
      ),
    const AccessibilitySection(),
    if (colors != null && colors.roles.isNotEmpty) ColorsSection(colors),
    if (privacy != null) ConsentsSection(privacy),
    const MouseSection(),
    GamepadSection(isConnected: padConnected),
    if (credits != null) WidgetSection(credits),
  ];
}

/// A volume slider per bus.
///
/// Which buses is the game's: `busesIn(itsOwnBank)` offers the sliders its
/// sounds can reach and no others. A slider that is saved and applied and
/// that nothing in the game is heard through is a lie the panel tells.
final class VolumesSection extends SettingsSection {
  const VolumesSection({this.buses = settableBuses});

  final List<AudioBus> buses;

  @override
  Widget build(
    BuildContext context,
    GameSettingsController settings,
    SettingsState state,
  ) {
    final words = Flutter3dGameLocalizations.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        for (final bus in buses) ...<Widget>[
          SettingsHeading(words.volume(bus.name)),
          Slider(
            value: settings.settings.volumeOf(bus),
            onChanged: (double value) => settings.setVolume(bus, value),
          ),
        ],
      ],
    );
  }
}

/// The controls: an [ActionBindingsSection] over the map the game's devices
/// read, with [defaults] for the day a player wants the shipped ones back.
final class ControlsSection extends SettingsSection {
  const ControlsSection({
    required this.defaults,
    this.showsTuning = false,
    this.actionLabel,
  });

  /// The action map this game ships.
  final ActionMap Function() defaults;

  /// Whether the map's sensitivity and invert rows are shown.
  ///
  /// Off by default because [MouseSection] and [GamepadSection] already turn
  /// the look, and two controls for one number that each apply a factor is a
  /// look that turns at the product of both. A game that shapes its look on
  /// the bindings instead turns this on.
  final bool showsTuning;

  /// What an action of the game's own is called; see
  /// [ActionBindingsSection.actionLabel].
  final String? Function(ActionDeclaration declaration)? actionLabel;

  @override
  Widget build(
    BuildContext context,
    GameSettingsController settings,
    SettingsState state,
  ) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: <Widget>[
      SettingsHeading(Flutter3dGameLocalizations.of(context).controls),
      const SizedBox(height: 8),
      ActionBindingsSection(
        map: settings.rebinding.actions,
        waitingFor: state.waitingFor,
        waitingPart: state.waitingPart,
        conflicts: state.conflicts,
        actionLabel: actionLabel,
        onRebind: (RebindRequest request) =>
            settings.rebind(request.action, part: request.part),
        onReset: () => settings.reset(defaults()),
        onTuning: showsTuning
            ? (TuningChange change) => settings.setTuning(
                change.action,
                change.tuning,
                device: change.device,
              )
            : null,
      ),
    ],
  );
}

/// What a player cannot play without: the camera's motion, a correction for
/// their colour vision, the high-contrast look, and sprinting that latches.
final class AccessibilitySection extends SettingsSection {
  const AccessibilitySection();

  @override
  Widget build(
    BuildContext context,
    GameSettingsController settings,
    SettingsState state,
  ) {
    final words = Flutter3dGameLocalizations.of(context);
    final current = settings.settings;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SettingsHeading(words.accessibility),
        const SizedBox(height: 8),
        SettingsValueSlider(
          label: words.cameraMotion,
          value: current.valueOf(GameSettingKeys.cameraMotion),
          max: 1.0,
          // A camera that flinches on every landing is what makes some
          // players ill, and the following is the game. This turns down the
          // first and leaves the second.
          onChanged: (double value) =>
              settings.setValue(GameSettingKeys.cameraMotion, value),
        ),
        SettingsChoiceRow(
          label: words.colorVision,
          // A correction for the player's own eyes: what their kind of
          // colour blindness runs together is moved to where they can tell
          // it apart. See `ColorVision.correct`.
          choices: words.colorVisionChoices,
          chosen: current.valueOf(GameSettingKeys.colorVision),
          onChanged: (int chosen) =>
              settings.setValue(GameSettingKeys.colorVision, chosen),
        ),
        SettingsSwitchRow(
          label: words.highContrast,
          // Shown as the system's answer until the player gives one of their
          // own, which is what the game will draw: a switch that read off
          // while the look was on would be the panel disagreeing with the
          // screen behind it.
          on: wantsHighContrast(current, Accommodations.of(context)),
          onChanged: (bool on) =>
              settings.setValue(GameSettingKeys.highContrast, on),
        ),
        SettingsSwitchRow(
          label: words.holdToSprint,
          // Reads as the thing being turned off, because that is what a
          // player looks for: they know they cannot hold a key.
          on: !current.valueOf(GameSettingKeys.toggleSprint),
          onChanged: (bool hold) =>
              settings.setValue(GameSettingKeys.toggleSprint, !hold),
        ),
      ],
    );
  }
}

/// The colours the game gives meanings to, each a row the player can change.
final class ColorsSection extends SettingsSection {
  const ColorsSection(this.roles);

  final ColorRoles roles;

  @override
  Widget build(
    BuildContext context,
    GameSettingsController settings,
    SettingsState state,
  ) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: <Widget>[
      SettingsHeading(Flutter3dGameLocalizations.of(context).colors),
      const SizedBox(height: 8),
      // What each colour means, and the colour it is: a player who cannot
      // tell two marks apart moves one of them.
      for (final role in roles.roles)
        SettingsColourRow(
          label: role.label,
          choices: ColorRoles.choices(role),
          chosen: settings.settings.valueOf(role.setting),
          onChanged: (int chosen) => settings.setValue(role.setting, chosen),
        ),
    ],
  );
}

/// The questions about the player's data: cloud saves, and sending runs.
final class ConsentsSection extends SettingsSection {
  const ConsentsSection(this.consents);

  final Consents consents;

  @override
  Widget build(
    BuildContext context,
    GameSettingsController settings,
    SettingsState state,
  ) => PrivacySection(consents: consents);
}

/// The mouse's look speed and its vertical invert.
///
/// **The right stick had a slider and the mouse had nothing.** For a
/// first-person game this is the most adjusted setting the genre has, and an
/// accessibility control as well: a player who cannot make large movements
/// needs it high, and one with a tremor needs it low. The range is a factor
/// either side of the game's own, `×0.25` to `×4`, because a number in
/// radians per pixel is not a thing anybody can set by feel.
final class MouseSection extends SettingsSection {
  const MouseSection();

  @override
  Widget build(
    BuildContext context,
    GameSettingsController settings,
    SettingsState state,
  ) {
    final words = Flutter3dGameLocalizations.of(context);
    final current = settings.settings;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SettingsHeading(words.mouse),
        const SizedBox(height: 8),
        SettingsValueSlider(
          label: words.lookSpeed,
          value: current.valueOf(GameSettingKeys.mouseLook),
          min: 0.25,
          max: 4.0,
          onChanged: (double value) =>
              settings.setValue(GameSettingKeys.mouseLook, value),
        ),
        SettingsSwitchRow(
          label: words.invertVerticalLook,
          on: current.valueOf(GameSettingKeys.mouseInvertY),
          onChanged: (bool on) =>
              settings.setValue(GameSettingKeys.mouseInvertY, on),
        ),
      ],
    );
  }
}

/// The gamepad's dead zone and look speed, saying when no pad is connected.
final class GamepadSection extends SettingsSection {
  const GamepadSection({required this.isConnected});

  /// Whether a controller answered this frame. **Asked, not assumed**: a game
  /// that passes a constant has a panel that says "none connected" over the
  /// sliders that set a stick's dead zone.
  final bool isConnected;

  /// A dead zone above this fraction of the stick's travel is a controller
  /// with a hole in the middle of it.
  /// The range matters more than the default: a dead zone can only be chosen
  /// with a controller in hand, and a range too narrow to reach the player's
  /// own stick would make the slider a decoration.
  static const double maxDeadZone = 0.4;

  @override
  Widget build(
    BuildContext context,
    GameSettingsController settings,
    SettingsState state,
  ) {
    final words = Flutter3dGameLocalizations.of(context);
    final current = settings.settings;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SettingsHeading(words.gamepad(connected: isConnected)),
        const SizedBox(height: 8),
        SettingsValueSlider(
          label: words.deadZone,
          value: current.valueOf(GameSettingKeys.stickDeadZone),
          max: maxDeadZone,
          // Left of the mark a resting stick drifts; right of it there is a
          // hole in the middle of the travel. Both are visible in seconds.
          onChanged: (double value) =>
              settings.setValue(GameSettingKeys.stickDeadZone, value),
        ),
        SettingsValueSlider(
          label: words.lookSpeed,
          value: current.valueOf(GameSettingKeys.padLook),
          min: 200.0,
          max: 2600.0,
          onChanged: (double value) =>
              settings.setValue(GameSettingKeys.padLook, value),
        ),
      ],
    );
  }
}

/// A widget of the game's own as a section: what it owes the people whose
/// work it ships (a `CreditsSection`, since what a credit is differs per
/// game), or a row nothing here offers.
final class WidgetSection extends SettingsSection {
  const WidgetSection(this.child);

  final Widget child;

  @override
  Widget build(
    BuildContext context,
    GameSettingsController settings,
    SettingsState state,
  ) => child;
}
