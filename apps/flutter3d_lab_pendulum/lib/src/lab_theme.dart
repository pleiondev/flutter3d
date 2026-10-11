import 'dart:ui' show Color;

/// What a student has to tell apart in the lab, named as two of
/// [LabTheme]'s colours and whether it is read ([text]) or only found.
///
/// The test holds each one to WCAG 2.2's ratio over every grey frame from
/// black to white, with `flutter3d_game_ui`'s `ContrastPair`: text to 4.5,
/// a control or a ring to 3.
typedef LabContrast = ({
  String name,
  Color foreground,
  Color background,
  bool text,
  Color? edge,
});

/// The lab's colours, the only place it types one in.
///
/// **Readable over any frame, and held to it.** The pause button sits on
/// the scene and the focus ring is drawn straight onto it, so a colour here
/// is not a look but a pair with a ratio to keep, named in [pairs] and
/// checked by `test/theme_contrast_test.dart`. A colour added here and to no
/// pair fails that test too. The scene's own colours (the bob, the string,
/// the pivot) are materials, lit, and not here.
abstract final class LabTheme {
  /// Behind the scene, the loading and the error screens.
  static const Color background = Color(0xFF14161A);

  /// What went wrong, on [background].
  static const Color error = Color(0xFFFF8A80);

  /// Under the pause button.
  static const Color scrim = Color(0xCC0E1013);

  /// The pause button's glyph, on [scrim].
  static const Color onScrim = Color(0xFFFFFFFF);

  /// The ring round the scene while it has keyboard focus, drawn straight
  /// onto the frame.
  static const Color focusRing = Color(0xFFFFFFFF);

  /// The dark rim outside [focusRing], which carries it over a light frame.
  static const Color focusRingEdge = Color(0xFF0E1013);

  /// The panel in the scene, opaque: the texture its words are drawn on.
  static const Color panel = Color(0xFF15181C);

  /// The panel's heading, `STRING LENGTH`.
  static const Color panelLabel = Color(0xFF8FA0B3);

  /// The panel's readout, the length in metres.
  static const Color panelReadout = Color(0xFFE7C46E);

  /// The face of the panel's `-` and `+`.
  static const Color panelButton = Color(0xFF283040);

  /// The `-` and `+` on [panelButton], which are what a student finds the
  /// buttons by.
  static const Color panelButtonText = Color(0xFFE6EAF0);

  /// Every colour above, so the test can ask that each is in a pair.
  static const List<Color> tokens = <Color>[
    background,
    error,
    scrim,
    onScrim,
    focusRing,
    focusRingEdge,
    panel,
    panelLabel,
    panelReadout,
    panelButton,
    panelButtonText,
  ];

  /// Every pair a student has to tell apart.
  static const List<LabContrast> pairs = <LabContrast>[
    (
      name: 'error on background',
      foreground: error,
      background: background,
      text: true,
      edge: null,
    ),
    (
      name: 'pause glyph on scrim',
      foreground: onScrim,
      background: scrim,
      text: false,
      edge: null,
    ),
    (
      name: 'focus ring over the scene',
      foreground: focusRing,
      background: Color(0x00000000),
      text: false,
      edge: focusRingEdge,
    ),
    (
      name: 'panel label on panel',
      foreground: panelLabel,
      background: panel,
      text: true,
      edge: null,
    ),
    (
      name: 'panel readout on panel',
      foreground: panelReadout,
      background: panel,
      text: true,
      edge: null,
    ),
    (
      name: 'panel button glyph on its face',
      foreground: panelButtonText,
      background: panelButton,
      text: true,
      edge: null,
    ),
  ];
}
