/// The modeller's colours and sizes, in one place and stated rather than
/// derived.
///
/// **An explicit `ColorScheme.dark` and not `ColorScheme.fromSeed`.** A seed
/// generates thirty roles from one colour, and the generator is free to change
/// what it generates between Flutter versions: a design that was signed off
/// then arrives a shade different after an upgrade, and nobody can say which of
/// the thirty moved. Every role here is a hex somebody chose, and a test holds
/// each of them to that hex.
///
/// **Where the numbers come from.** The viewport's own colours are already
/// committed to in code that draws them — `#0E1112` behind the model,
/// `#2A3234` for an ordinary grid line, `#3D4A4D` for a tenth one, `#004F58`
/// for a selection wash, `#FF9926` for a selected element — and the panels are
/// built out from those so that the chrome and the picture belong to one
/// palette. The full token table lives in the design hand-over, which is not in
/// this repository; where it disagrees with what is here, it wins, and the
/// place to change is this file and its test together.
library;

import 'package:flutter/material.dart';

/// The sizes the shell is built from, in logical pixels.
///
/// **Constants rather than numbers at the call sites, because the acceptance is
/// a measurement.** `ui-04` asks for a top bar of 52, a rail of 52, a
/// properties panel between 250 and 330 and a status bar of 30, and the test
/// that checks it measures the real `RenderBox`. A literal repeated in the
/// widget and in the test would let both drift together and still agree.
abstract final class ModelerMetrics {
  static const double topBar = 52;
  static const double rail = 52;
  static const double propertiesMin = 250;
  static const double propertiesMax = 330;
  static const double statusBar = 30;

  /// A row in a properties panel, and a button on the rail.
  static const double row = 32;
  static const double railButton = 36;
}

/// The colours that are the modeller's own rather than Material's.
///
/// A `ThemeExtension` and not a set of top-level constants, so a widget reads
/// them the same way it reads every other colour — off the theme — and so a
/// second theme (a light one, a high-contrast one) has somewhere to put its
/// own answers.
@immutable
final class ModelerColors extends ThemeExtension<ModelerColors> {
  const ModelerColors({
    required this.viewport,
    required this.gridMinor,
    required this.gridMajor,
    required this.axisX,
    required this.axisZ,
    required this.wire,
    required this.selected,
    required this.panelEdge,
  });

  /// What the modeller ships with. Every one of these is a colour something in
  /// the viewport already draws with.
  static const ModelerColors dark = ModelerColors(
    viewport: Color(0xFF0E1112),
    gridMinor: Color(0xFF2A3234),
    gridMajor: Color(0xFF3D4A4D),
    axisX: Color(0xFF7A3A48),
    axisZ: Color(0xFF35526E),
    wire: Color(0xFF8C9399),
    selected: Color(0xFFFF9926),
    panelEdge: Color(0xFF232A2C),
  );

  /// Behind the model. Flat, and darker than any panel: every judgement a
  /// person makes about a shape is made against it.
  final Color viewport;

  final Color gridMinor;
  final Color gridMajor;
  final Color axisX;
  final Color axisZ;

  /// An edge of the mesh in the wireframe.
  final Color wire;

  /// A selected element, wherever one is drawn.
  final Color selected;

  /// The hairline between a panel and the picture.
  final Color panelEdge;

  @override
  ModelerColors copyWith({
    Color? viewport,
    Color? gridMinor,
    Color? gridMajor,
    Color? axisX,
    Color? axisZ,
    Color? wire,
    Color? selected,
    Color? panelEdge,
  }) => ModelerColors(
    viewport: viewport ?? this.viewport,
    gridMinor: gridMinor ?? this.gridMinor,
    gridMajor: gridMajor ?? this.gridMajor,
    axisX: axisX ?? this.axisX,
    axisZ: axisZ ?? this.axisZ,
    wire: wire ?? this.wire,
    selected: selected ?? this.selected,
    panelEdge: panelEdge ?? this.panelEdge,
  );

  @override
  ModelerColors lerp(ModelerColors? other, double t) {
    if (other == null) return this;
    return ModelerColors(
      viewport: Color.lerp(viewport, other.viewport, t)!,
      gridMinor: Color.lerp(gridMinor, other.gridMinor, t)!,
      gridMajor: Color.lerp(gridMajor, other.gridMajor, t)!,
      axisX: Color.lerp(axisX, other.axisX, t)!,
      axisZ: Color.lerp(axisZ, other.axisZ, t)!,
      wire: Color.lerp(wire, other.wire, t)!,
      selected: Color.lerp(selected, other.selected, t)!,
      panelEdge: Color.lerp(panelEdge, other.panelEdge, t)!,
    );
  }
}

/// The scheme, role by role.
///
/// The teal ramp is the one the selection wash already uses: `#004F58` is the
/// container, and the rest of the ramp is built around it so a filled button
/// and a selected face are visibly the same colour family. The warm accent is
/// the overlay's own selected colour, which is warm because everything the
/// renderer puts under it — a grey model on a near-black background — is not.
const ColorScheme kModelerScheme = ColorScheme(
  brightness: Brightness.dark,
  primary: Color(0xFF62D4E3),
  onPrimary: Color(0xFF00363D),
  primaryContainer: Color(0xFF004F58),
  onPrimaryContainer: Color(0xFFA2EEFF),
  secondary: Color(0xFFB1CBD0),
  onSecondary: Color(0xFF1C3438),
  secondaryContainer: Color(0xFF334B4F),
  onSecondaryContainer: Color(0xFFCDE7EC),
  tertiary: Color(0xFFFFB86B),
  onTertiary: Color(0xFF4A2800),
  tertiaryContainer: Color(0xFF693C00),
  onTertiaryContainer: Color(0xFFFFDCC0),
  error: Color(0xFFFF5449),
  onError: Color(0xFF690005),
  errorContainer: Color(0xFF93000A),
  onErrorContainer: Color(0xFFFFDAD6),
  surface: Color(0xFF14181A),
  onSurface: Color(0xFFE6E9EA),
  surfaceContainerLowest: Color(0xFF0E1112),
  surfaceContainerLow: Color(0xFF171C1E),
  surfaceContainer: Color(0xFF1B2123),
  surfaceContainerHigh: Color(0xFF1E2426),
  surfaceContainerHighest: Color(0xFF232A2C),
  onSurfaceVariant: Color(0xFF9AA3A6),
  outline: Color(0xFF2A3234),
  outlineVariant: Color(0xFF202729),
  inverseSurface: Color(0xFFE6E9EA),
  onInverseSurface: Color(0xFF14181A),
  inversePrimary: Color(0xFF006874),
  shadow: Color(0xFF000000),
  scrim: Color(0xFF000000),
);

/// The whole theme, assembled.
///
/// `VisualDensity.compact` because a modeller's panels are lists of numbers and
/// the default density spends a third of the panel on air; the row height in
/// [ModelerMetrics] is what the design asked for and is what the component
/// themes below are tuned to hit.
ThemeData modelerTheme() {
  const scheme = kModelerScheme;
  final base = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: scheme,
    visualDensity: VisualDensity.compact,
  );
  return base.copyWith(
    extensions: const <ThemeExtension<dynamic>>[ModelerColors.dark],
    scaffoldBackgroundColor: scheme.surface,
    dividerTheme: const DividerThemeData(
      color: Color(0xFF232A2C),
      thickness: 1,
      space: 1,
    ),
    textTheme: base.textTheme
        .apply(fontSizeFactor: 1.0)
        .copyWith(
          // 400 for anything a person reads and 500 for anything they act on,
          // which is the whole of the weight scale this interface uses. A third
          // weight is a decision to make per label, and per-label decisions are
          // what makes a panel look assembled by different people.
          bodyMedium: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w400,
          ),
          bodySmall: const TextStyle(fontSize: 12, fontWeight: FontWeight.w400),
          labelLarge: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
          labelMedium: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
          titleSmall: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
        ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        visualDensity: VisualDensity.compact,
        textStyle: const WidgetStatePropertyAll<TextStyle>(
          TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
        ),
        side: const WidgetStatePropertyAll<BorderSide>(
          BorderSide(color: Color(0xFF2A3234)),
        ),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        minimumSize: const Size.square(ModelerMetrics.railButton),
        padding: EdgeInsets.zero,
        foregroundColor: scheme.onSurfaceVariant,
      ),
    ),
    tooltipTheme: const TooltipThemeData(waitDuration: Duration(seconds: 1)),
  );
}
