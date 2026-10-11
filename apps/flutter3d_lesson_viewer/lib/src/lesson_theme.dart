import 'dart:ui' show Color;

/// What a student has to tell apart in the viewer, named as two of
/// [LessonTheme]'s colours and whether it is read ([text]) or only found.
///
/// The test holds each one to WCAG 2.2's ratio over every grey frame from
/// black to white, with `flutter3d_game_ui`'s `ContrastPair`: text to 4.5,
/// a control or a ring to 3.
typedef LessonContrast = ({
  String name,
  Color foreground,
  Color background,
  bool text,
  Color? edge,
});

/// The viewer's colours, the only place it types one in.
///
/// **Readable over any frame, and held to it.** The caption and the
/// question sit on [scrim] over whatever the lesson's scene shows, so a
/// colour here is not a look but a pair with a ratio to keep, named in
/// [pairs] and checked by `test/theme_contrast_test.dart`. A colour added
/// here and to no pair fails that test too.
abstract final class LessonTheme {
  /// Behind the loading and the error screens.
  static const Color background = Color(0xFF14161A);

  /// What went wrong, on [background].
  static const Color error = Color(0xFFFF8A80);

  /// Under the caption, the question and the scene's own caption panel.
  static const Color scrim = Color(0xCC0E1013);

  /// What is read on [scrim]: a caption, a question, a typed answer.
  static const Color text = Color(0xFFFFFFFF);

  /// The answer field's hint and its underline, quieter than [text].
  static const Color hint = Color(0xB3FFFFFF);

  /// The word that says an answer was right.
  static const Color correct = Color(0xFF69F0AE);

  /// The line that gives the answer once the attempts are spent.
  static const Color revealed = Color(0xFFFFAB40);

  /// The ring round the scene while it has keyboard focus, drawn straight
  /// onto the frame.
  static const Color focusRing = Color(0xFFFFFFFF);

  /// The dark rim outside [focusRing], which carries it over a light frame.
  static const Color focusRingEdge = Color(0xFF0E1013);

  /// Every colour above, so the test can ask that each is in a pair.
  static const List<Color> tokens = <Color>[
    background,
    error,
    scrim,
    text,
    hint,
    correct,
    revealed,
    focusRing,
    focusRingEdge,
  ];

  /// Every pair a student has to tell apart.
  static const List<LessonContrast> pairs = <LessonContrast>[
    (
      name: 'error on background',
      foreground: error,
      background: background,
      text: true,
      edge: null,
    ),
    (
      name: 'text on scrim',
      foreground: text,
      background: scrim,
      text: true,
      edge: null,
    ),
    (
      name: 'hint on scrim',
      foreground: hint,
      background: scrim,
      text: true,
      edge: null,
    ),
    (
      name: 'correct on scrim',
      foreground: correct,
      background: scrim,
      text: true,
      edge: null,
    ),
    (
      name: 'revealed on scrim',
      foreground: revealed,
      background: scrim,
      text: true,
      edge: null,
    ),
    (
      name: 'focus ring over the scene',
      foreground: focusRing,
      background: Color(0x00000000),
      text: false,
      edge: focusRingEdge,
    ),
  ];
}
