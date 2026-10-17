import 'package:flutter/material.dart';

import 'contrast.dart';

/// The colours of a game's own screens: the settings panel, the heads-up
/// display, the sheets around play, the maps and the touch controls.
///
/// **A [ThemeExtension], not constructor defaults.** Every widget here typed
/// its colours in — a white at three quarters for a heading, an amber for a
/// row waiting for its key, a yellow for a HUD line that just came true — so
/// a game with a palette of its own had to pass a colour to every widget
/// that took one and could not reach those that did not. Put one of these in
/// the app's theme and every widget reads it:
///
/// ```dart
/// MaterialApp(
///   theme: ThemeData(
///     extensions: const <ThemeExtension<Object?>>[
///       GameUiTheme(accent: Color(0xFF7FDBFF)),
///     ],
///   ),
/// );
/// ```
///
/// Without one, [of] answers [fallback].
///
/// **Readable over any frame, and held to it.** The colours are tokens with
/// a contrast to keep: a heads-up line is drawn on [panel] over whatever the
/// camera sees, a touch control's face over the same, so each pair a player
/// has to tell apart is named in [contrastPairs] with the ratio WCAG 2.2 asks
/// at level AA, and a test holds [fallback] to every one of them over every
/// grey from black to white. A game that restyles the widgets can ask the
/// same of its own theme. Until 1.0.0-rc.1 the touch controls were a third
/// of white over the picture, which on a bright sky was white on white.
@immutable
final class GameUiTheme extends ThemeExtension<GameUiTheme> {
  const GameUiTheme({
    this.text = const Color(0xFFFFFFFF),
    this.label = const Color(0xD9FFFFFF),
    this.heading = const Color(0xBFFFFFFF),
    this.faint = const Color(0x99FFFFFF),
    this.scrim = const Color(0xB8000000),
    this.panel = const Color(0xB8000000),
    this.sheet = const Color(0xC7000000),
    this.waiting = const Color(0xFFFFC107),
    this.warning = const Color(0xFFFFCC80),
    this.error = const Color(0xFFFFA8A0),
    this.accent = const Color(0xFFFFD166),
    this.notice = const Color(0xD9FFC107),
    this.hudLabel = const Color(0xFFB8C2CF),
    this.hudLabelWidth = 72.0,
    this.mapFloor = const Color(0xFF8A8274),
    this.mapWall = const Color(0xFF231F1C),
    this.mapPlayer = const Color(0xFFFFE680),
    this.mapBackdrop = const Color(0xD9000000),
    this.miniMapTrack = const Color(0xFF9AA3AF),
    this.miniMapPlayer = const Color(0xFFFFFFFF),
    this.miniMapOthers = const Color(0xFFFF6A50),
    this.miniMapBackdrop = const Color(0xB8000000),
    this.touchTrack = const Color(0x99000000),
    this.touchFill = const Color(0x99000000),
    this.touchUnavailable = const Color(0x40000000),
    this.touchOutline = const Color(0xF2FFFFFF),
    this.touchHeld = const Color(0xD9333333),
    this.touchPressed = const Color(0xD9333333),
    this.touchKnob = const Color(0xE6FFFFFF),
    this.touchGlyph = const Color(0xFFFFFFFF),
    this.touchOn = const Color(0xF2FFFFFF),
    this.touchOnGlyph = const Color(0xFF101010),
  });

  /// What is read: a value, a binding's name.
  final Color text;

  /// The label beside a slider or a switch.
  final Color label;

  /// A section's heading.
  final Color heading;

  /// What is there to be read when wanted: a binding's sources, a line of
  /// explanation under a switch.
  final Color faint;

  /// What a full-screen panel puts over the game.
  final Color scrim;

  /// A small panel's background: the heads-up display's, a banner's, a
  /// subtitle's, the photo bar's.
  final Color panel;

  /// What a title or an ending sheet puts over the game: darker than
  /// [scrim], because the game stops there.
  final Color sheet;

  /// A row listening for its new key.
  final Color waiting;

  /// Something that did not happen and should be said: a write that failed,
  /// a conflict a rebind met.
  final Color warning;

  /// An answer that could not be kept.
  final Color error;

  /// A heads-up line that has just become true.
  final Color accent;

  /// A line worth saying out loud on a sheet: a saved run waiting, time the
  /// machine lost.
  final Color notice;

  /// A heads-up line's label.
  final Color hudLabel;

  /// How wide a heads-up line's label column is, in logical pixels: wide
  /// enough for a seven-letter label at thirteen points, bold, with a point
  /// and a half of tracking.
  final double hudLabelWidth;

  /// The automap's floor where the player has walked.
  final Color mapFloor;

  /// The automap's walls.
  final Color mapWall;

  /// The automap's arrow where the player stands.
  final Color mapPlayer;

  /// What the automap is drawn over.
  final Color mapBackdrop;

  /// A mini-map's course line.
  final Color miniMapTrack;

  /// A mini-map's dot for the player.
  final Color miniMapPlayer;

  /// A mini-map's dots for everyone else.
  final Color miniMapOthers;

  /// A mini-map's box.
  final Color miniMapBackdrop;

  /// What a moving touch part travels over: a stick's base, a steering band's track, a pedal at rest.
  final Color touchTrack;

  /// A touch button or toggle at rest, and a slot that can be chosen.
  final Color touchFill;

  /// A touch slot that cannot be chosen.
  final Color touchUnavailable;

  /// A touch control's rim, and the label of a slot that cannot be chosen.
  final Color touchOutline;

  /// A pedal held down.
  final Color touchHeld;

  /// A touch button held down.
  final Color touchPressed;

  /// A stick's knob and a steering band's thumb.
  final Color touchKnob;

  /// A touch control's label.
  final Color touchGlyph;

  /// A toggle that is on, and a slot that is held.
  final Color touchOn;

  /// The label on a control drawn [touchOn], and its rim.
  final Color touchOnGlyph;

  /// The colours the widgets have without a theme.
  static const GameUiTheme fallback = GameUiTheme();

  /// The theme's [GameUiTheme], or [fallback].
  static GameUiTheme of(BuildContext context) =>
      Theme.of(context).extension<GameUiTheme>() ?? fallback;

  /// [base] for Flutter's own controls on this theme's dark panels: the
  /// settings panel's sliders, switches, chips and buttons, the share
  /// strip's field.
  ///
  /// **Dark whatever the app is**, because the panels are: an app in a light
  /// theme put a purple button and black field text on [scrim], at two to
  /// one. The scheme is Material's dark one seeded from [accent], which
  /// keeps its own text pairs at AA, and the app's theme extensions, this
  /// one among them, are carried over.
  ThemeData controlsTheme(ThemeData base) => ThemeData.from(
    colorScheme: ColorScheme.fromSeed(
      seedColor: accent,
      brightness: Brightness.dark,
    ),
    useMaterial3: base.useMaterial3,
  ).copyWith(extensions: base.extensions.values);

  /// Every pair of these colours a player has to tell apart, as the widgets
  /// draw them, with the ratio each has to keep over any frame.
  ///
  /// Text is held to [Wcag.textContrast]; a control's face, with its rim,
  /// and a mark on a map to [Wcag.nonTextContrast]. A touch slot the player
  /// does not own yet is left out, as WCAG leaves out a control that cannot
  /// be used.
  List<ContrastPair> get contrastPairs => <ContrastPair>[
    for (final (name, color) in <(String, Color)>[
      ('text', text),
      ('label', label),
      ('heading', heading),
      ('faint', faint),
      ('waiting', waiting),
      ('warning', warning),
      ('error', error),
    ])
      ContrastPair('$name on scrim', foreground: color, background: scrim),
    for (final (name, color) in <(String, Color)>[
      ('text', text),
      ('label', label),
      ('faint', faint),
      ('notice', notice),
    ])
      ContrastPair('$name on sheet', foreground: color, background: sheet),
    for (final (name, color) in <(String, Color)>[
      ('text', text),
      ('label', label),
      ('faint', faint),
      ('hudLabel', hudLabel),
      ('accent', accent),
    ])
      ContrastPair('$name on panel', foreground: color, background: panel),
    for (final (name, face) in <(String, Color)>[
      ('touchFill', touchFill),
      ('touchTrack', touchTrack),
      ('touchHeld', touchHeld),
      ('touchPressed', touchPressed),
    ]) ...<ContrastPair>[
      ContrastPair(
        'touchGlyph on $name',
        foreground: touchGlyph,
        background: face,
      ),
      ContrastPair(
        '$name with touchOutline',
        foreground: face,
        edge: touchOutline,
        minimum: Wcag.nonTextContrast,
      ),
    ],
    ContrastPair(
      'touchOnGlyph on touchOn',
      foreground: touchOnGlyph,
      background: touchOn,
    ),
    ContrastPair(
      'touchOn with touchOnGlyph',
      foreground: touchOn,
      edge: touchOnGlyph,
      minimum: Wcag.nonTextContrast,
    ),
    ContrastPair(
      'touchKnob on touchTrack',
      foreground: touchKnob,
      background: touchTrack,
      minimum: Wcag.nonTextContrast,
    ),
    ContrastPair(
      'mapPlayer on mapFloor',
      foreground: mapPlayer,
      background: mapFloor,
      minimum: Wcag.nonTextContrast,
    ),
    ContrastPair(
      'mapWall on mapFloor',
      foreground: mapWall,
      background: mapFloor,
      minimum: Wcag.nonTextContrast,
    ),
    ContrastPair(
      'mapFloor on mapBackdrop',
      foreground: mapFloor,
      background: mapBackdrop,
      minimum: Wcag.nonTextContrast,
    ),
    for (final (name, color) in <(String, Color)>[
      ('miniMapTrack', miniMapTrack),
      ('miniMapPlayer', miniMapPlayer),
      ('miniMapOthers', miniMapOthers),
    ])
      ContrastPair(
        '$name on miniMapBackdrop',
        foreground: color,
        background: miniMapBackdrop,
        minimum: Wcag.nonTextContrast,
      ),
  ];

  @override
  GameUiTheme copyWith({
    Color? text,
    Color? label,
    Color? heading,
    Color? faint,
    Color? scrim,
    Color? panel,
    Color? sheet,
    Color? waiting,
    Color? warning,
    Color? error,
    Color? accent,
    Color? notice,
    Color? hudLabel,
    double? hudLabelWidth,
    Color? mapFloor,
    Color? mapWall,
    Color? mapPlayer,
    Color? mapBackdrop,
    Color? miniMapTrack,
    Color? miniMapPlayer,
    Color? miniMapOthers,
    Color? miniMapBackdrop,
    Color? touchTrack,
    Color? touchFill,
    Color? touchUnavailable,
    Color? touchOutline,
    Color? touchHeld,
    Color? touchPressed,
    Color? touchKnob,
    Color? touchGlyph,
    Color? touchOn,
    Color? touchOnGlyph,
  }) => GameUiTheme(
    text: text ?? this.text,
    label: label ?? this.label,
    heading: heading ?? this.heading,
    faint: faint ?? this.faint,
    scrim: scrim ?? this.scrim,
    panel: panel ?? this.panel,
    sheet: sheet ?? this.sheet,
    waiting: waiting ?? this.waiting,
    warning: warning ?? this.warning,
    error: error ?? this.error,
    accent: accent ?? this.accent,
    notice: notice ?? this.notice,
    hudLabel: hudLabel ?? this.hudLabel,
    hudLabelWidth: hudLabelWidth ?? this.hudLabelWidth,
    mapFloor: mapFloor ?? this.mapFloor,
    mapWall: mapWall ?? this.mapWall,
    mapPlayer: mapPlayer ?? this.mapPlayer,
    mapBackdrop: mapBackdrop ?? this.mapBackdrop,
    miniMapTrack: miniMapTrack ?? this.miniMapTrack,
    miniMapPlayer: miniMapPlayer ?? this.miniMapPlayer,
    miniMapOthers: miniMapOthers ?? this.miniMapOthers,
    miniMapBackdrop: miniMapBackdrop ?? this.miniMapBackdrop,
    touchTrack: touchTrack ?? this.touchTrack,
    touchFill: touchFill ?? this.touchFill,
    touchUnavailable: touchUnavailable ?? this.touchUnavailable,
    touchOutline: touchOutline ?? this.touchOutline,
    touchHeld: touchHeld ?? this.touchHeld,
    touchPressed: touchPressed ?? this.touchPressed,
    touchKnob: touchKnob ?? this.touchKnob,
    touchGlyph: touchGlyph ?? this.touchGlyph,
    touchOn: touchOn ?? this.touchOn,
    touchOnGlyph: touchOnGlyph ?? this.touchOnGlyph,
  );

  @override
  GameUiTheme lerp(covariant GameUiTheme? other, double t) {
    if (other == null) return this;
    return GameUiTheme(
      text: Color.lerp(text, other.text, t)!,
      label: Color.lerp(label, other.label, t)!,
      heading: Color.lerp(heading, other.heading, t)!,
      faint: Color.lerp(faint, other.faint, t)!,
      scrim: Color.lerp(scrim, other.scrim, t)!,
      panel: Color.lerp(panel, other.panel, t)!,
      sheet: Color.lerp(sheet, other.sheet, t)!,
      waiting: Color.lerp(waiting, other.waiting, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      error: Color.lerp(error, other.error, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      notice: Color.lerp(notice, other.notice, t)!,
      hudLabel: Color.lerp(hudLabel, other.hudLabel, t)!,
      hudLabelWidth: t < 0.5 ? hudLabelWidth : other.hudLabelWidth,
      mapFloor: Color.lerp(mapFloor, other.mapFloor, t)!,
      mapWall: Color.lerp(mapWall, other.mapWall, t)!,
      mapPlayer: Color.lerp(mapPlayer, other.mapPlayer, t)!,
      mapBackdrop: Color.lerp(mapBackdrop, other.mapBackdrop, t)!,
      miniMapTrack: Color.lerp(miniMapTrack, other.miniMapTrack, t)!,
      miniMapPlayer: Color.lerp(miniMapPlayer, other.miniMapPlayer, t)!,
      miniMapOthers: Color.lerp(miniMapOthers, other.miniMapOthers, t)!,
      miniMapBackdrop: Color.lerp(miniMapBackdrop, other.miniMapBackdrop, t)!,
      touchTrack: Color.lerp(touchTrack, other.touchTrack, t)!,
      touchFill: Color.lerp(touchFill, other.touchFill, t)!,
      touchUnavailable: Color.lerp(
        touchUnavailable,
        other.touchUnavailable,
        t,
      )!,
      touchOutline: Color.lerp(touchOutline, other.touchOutline, t)!,
      touchHeld: Color.lerp(touchHeld, other.touchHeld, t)!,
      touchPressed: Color.lerp(touchPressed, other.touchPressed, t)!,
      touchKnob: Color.lerp(touchKnob, other.touchKnob, t)!,
      touchGlyph: Color.lerp(touchGlyph, other.touchGlyph, t)!,
      touchOn: Color.lerp(touchOn, other.touchOn, t)!,
      touchOnGlyph: Color.lerp(touchOnGlyph, other.touchOnGlyph, t)!,
    );
  }
}
