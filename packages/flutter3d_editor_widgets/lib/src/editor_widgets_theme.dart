/// Row-level sizing shared by every widget in this package: a field's
/// height, a labelled row's own label column, a field's corner radius, a
/// texture thumbnail's edge.
///
/// **Kept off `Theme.of(context)`'s own `textTheme`/`colorScheme`**, because
/// none of Material's roles name a row height or a thumbnail size — colour
/// is what `ColorScheme` is for, and every widget in this package still
/// reads that directly. This is the one axis two applications' own panels
/// disagree on: the modeller draws a 32-tall row, the level editor a denser
/// 28.
library;

import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

/// The sizes a row in a properties panel is built from.
///
/// **`of(context)` never returns null.** A widget from this package dropped
/// into an application that has not registered one on its `ThemeData` still
/// renders at [defaults] — an application opts in only once it wants a size
/// other than the default, the same relation `ColorScheme` has with a widget
/// that never customises it.
@immutable
final class EditorWidgetsTheme extends ThemeExtension<EditorWidgetsTheme> {
  const EditorWidgetsTheme({
    required this.rowHeight,
    required this.labelWidth,
    required this.fieldRadius,
    required this.thumbnailSize,
  });

  /// What every widget in this package falls back to when the ambient
  /// `ThemeData` carries no `EditorWidgetsTheme` of its own.
  static const EditorWidgetsTheme defaults = EditorWidgetsTheme(
    rowHeight: 32,
    labelWidth: 96,
    fieldRadius: 6,
    thumbnailSize: 26,
  );

  /// The height of one row in a properties panel: a `NumberField`, a
  /// `ColorField`'s own swatch, a slider row.
  final double rowHeight;

  /// How wide a row's own leading label column is — `FieldRow`'s own name
  /// column, once it arrives.
  final double labelWidth;

  /// The corner radius a text field or a swatch draws with.
  final double fieldRadius;

  /// The edge of a square texture thumbnail — `TextureSlotRow`'s own
  /// preview, once it arrives.
  final double thumbnailSize;

  /// The `EditorWidgetsTheme` registered on the ambient `ThemeData`, or
  /// [defaults] when none is.
  static EditorWidgetsTheme of(BuildContext context) =>
      Theme.of(context).extension<EditorWidgetsTheme>() ?? defaults;

  /// Whether a field in a row this tall is drawn dense.
  ///
  /// **Derived rather than a field of its own**, because a dense field in a
  /// tall row is the one combination nobody wants: `InputDecorator` sizes
  /// itself to its own padding and ignores the box round it, so a dense
  /// field in a 48-pixel row is a 31-pixel target with a gap above and below
  /// it that a tap falls straight through. Tying the two together is what
  /// makes [rowHeight] mean the row a finger or a cursor actually hits.
  ///
  /// Forty is the boundary because it is between the two heights this is
  /// ever set to — the 28-32 a properties panel is drawn at under a cursor,
  /// and the 48 a touch target has to be.
  bool get denseFields => rowHeight < 40;

  /// The padding a text field in this row takes, so that the field fills the
  /// row rather than floating inside it. [horizontal] is the field's own,
  /// since a number and a hex colour want different room across.
  EdgeInsets fieldPadding({double horizontal = 9}) => EdgeInsets.symmetric(
    horizontal: horizontal,
    // 24 is about what one line of body text plus the border occupies; the
    // rest of the row is split above and below it.
    vertical: denseFields ? 6 : (rowHeight - 24) / 2,
  );

  @override
  EditorWidgetsTheme copyWith({
    double? rowHeight,
    double? labelWidth,
    double? fieldRadius,
    double? thumbnailSize,
  }) => EditorWidgetsTheme(
    rowHeight: rowHeight ?? this.rowHeight,
    labelWidth: labelWidth ?? this.labelWidth,
    fieldRadius: fieldRadius ?? this.fieldRadius,
    thumbnailSize: thumbnailSize ?? this.thumbnailSize,
  );

  @override
  EditorWidgetsTheme lerp(EditorWidgetsTheme? other, double t) {
    if (other == null) return this;
    return EditorWidgetsTheme(
      rowHeight: lerpDouble(rowHeight, other.rowHeight, t)!,
      labelWidth: lerpDouble(labelWidth, other.labelWidth, t)!,
      fieldRadius: lerpDouble(fieldRadius, other.fieldRadius, t)!,
      thumbnailSize: lerpDouble(thumbnailSize, other.thumbnailSize, t)!,
    );
  }
}
