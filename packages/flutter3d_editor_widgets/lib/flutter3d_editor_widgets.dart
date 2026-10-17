/// Editor controls shared between the modeller and the level editor —
/// `ui-27`'s own package. `SectionLabel`, `NumberField`, `ColorField`,
/// `RangeSliderField`, `EnumField`, `TextureSlotRow`, `TexturePathField`,
/// `ColorSwatchField`, `HintTextBox`/`NumbersRow` and `FieldRow` so far, all
/// reading `Theme.of(context)` for colour and [EditorWidgetsTheme] for
/// row-level sizing. And the shell an editor's window is made of: panels
/// docked around a picture (`DockLayout`) and a command palette
/// (`showCommandPalette`), with the panels plugins add to it
/// (`EditorPanels`).
///
/// Depends on `flutter` and `flutter3d_formats`, for the `RangeHint`/
/// `ColorHint`/`TextureHint`/`EnumHint`/`EnumHintValue`/`MaterialHint` a
/// hint-driven row reads, and on `flutter3d_plugin_api`, the contract a
/// plugin's panel is registered through — never `flutter3d_editor_core`
/// (the `.fmat` gate stays there) or `flutter3d_model_core` (its own
/// `ParamHint`/`EnumHint` name a different type than anything here reads).
library;

export 'src/color_field.dart';
export 'src/color_swatch_field.dart';
export 'src/command_palette.dart';
export 'src/dock_layout.dart';
export 'src/editor_panels.dart';
export 'src/editor_widgets_theme.dart';
export 'src/enum_field.dart';
export 'src/field_row.dart';
export 'src/hint_text_box.dart';
export 'src/number_expression.dart';
export 'src/number_field.dart';
export 'src/range_slider_field.dart';
export 'src/section_label.dart';
export 'src/texture_path_field.dart';
export 'src/texture_slot_row.dart';
