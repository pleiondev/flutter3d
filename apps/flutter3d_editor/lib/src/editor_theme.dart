/// The editor's own colours, stated as an explicit `ColorScheme.dark`.
///
/// **Why this exists now and not earlier.** `flutter3d_editor_widgets`
/// (`ui-27`) reads `Theme.of(context)` for every colour it draws with —
/// `EditorApp` never set one, so every widget from that package rendered
/// under `MaterialApp`'s own default light scheme, drawn over panels this
/// application paints dark by hand (`editor_bar.dart`, `editor_inspector.dart`
/// and the rest, each with its own `Color(0xFF...)` literals). A `Dropdown`
/// or a `TextField` filled light against a dark panel is the tell; this file
/// is what removes it, ahead of `E2` wiring the panels themselves onto the
/// package's `FieldRow`/`SectionLabel`.
///
/// **Where the five roles below come from.** Each hex is one this
/// application (or, since `P0`–`P2`, the shared package the application's own
/// widgets moved into) already draws with today — not a new palette:
///
///  - `0xFF8A93A0` — a row's own label and a dialog's own muted text
///    (`field_row.dart`, `texture_path_field.dart`, `color_swatch_field.dart`)
///    → [ColorScheme.onSurfaceVariant].
///  - `0xFF171A1F` — a text field's own fill and a dropdown's own menu
///    (`hint_text_box.dart`, `material_panel.dart`'s material picker)
///    → [ColorScheme.surfaceContainerHighest].
///  - `0xFF2A2F37` — the ring around a colour swatch (`color_swatch_field.dart`)
///    → [ColorScheme.outline].
///  - `0xFFD98F4A` — the one warm accent in the palette, today a mismatch
///    warning under a texture path (`texture_path_field.dart`)
///    → [ColorScheme.primary].
///  - `0xFF15181D` — a dialog's own background, the darkest neutral in the
///    set (`texture_path_field.dart`'s file picker,
///    `color_swatch_field.dart`'s palette) → [ColorScheme.surface].
///
/// Every other role is `ColorScheme.dark`'s own default — this file states
/// only the roles this application has an opinion on.
library;

import 'package:flutter/material.dart';
import 'package:flutter3d_editor_widgets/flutter3d_editor_widgets.dart';

/// The editor's scheme, role by role — see the library doc for where each
/// hex comes from.
const ColorScheme kEditorScheme = ColorScheme.dark(
  primary: Color(0xFFD98F4A),
  surface: Color(0xFF15181D),
  surfaceContainerHighest: Color(0xFF171A1F),
  onSurfaceVariant: Color(0xFF8A93A0),
  outline: Color(0xFF2A2F37),
);

/// The editor's own row height: 28, denser than
/// [EditorWidgetsTheme.defaults]'s 32 — a level's properties panel packs more
/// rows into less width than the modeller's does. Every other size below is
/// [EditorWidgetsTheme.defaults]'s own value, repeated rather than derived
/// because the constructor's fields are all required and a const context
/// cannot read an instance field off another const.
const EditorWidgetsTheme kEditorWidgetsTheme = EditorWidgetsTheme(
  rowHeight: 28,
  labelWidth: 96,
  fieldRadius: 6,
  thumbnailSize: 26,
);

/// The whole theme, assembled — what `EditorApp` hands `MaterialApp.theme`.
ThemeData editorTheme() {
  final base = ThemeData(useMaterial3: true, colorScheme: kEditorScheme);
  return base.copyWith(
    scaffoldBackgroundColor: kEditorScheme.surface,
    extensions: const <ThemeExtension<dynamic>>[kEditorWidgetsTheme],
  );
}
