# flutter3d_editor_widgets

The controls `apps/flutter3d_modeler` and `apps/flutter3d_editor` each drew a
private copy of, moved to one package so the copies stop drifting —
`ui-27`. Three so far:

| Widget | What it is |
|---|---|
| `SectionLabel` | One line of upper-case, letter-spaced text naming a panel section. `style`/`padding` override the default look — wide enough to reproduce the level editor's own denser heading, so it never needs a second copy of this widget |
| `NumberField` | A labelled box that holds one number: a comma and a full stop both read as a decimal point, and it reports only when the person has finished, not on every keystroke |
| `ColorField` | A swatch, a hex box and HSV sliders over a three- or four-channel colour, with an `Alpha` slider only when a fourth channel is there to hold one |

Every widget reads `Theme.of(context)` for colour. Row-level sizing —
how tall a row is, how wide a label column is, a field's corner radius, a
texture thumbnail's edge — comes from `EditorWidgetsTheme.of(context)`
instead, which falls back to `rowHeight: 32, labelWidth: 96, fieldRadius: 6,
thumbnailSize: 26` when the ambient `ThemeData` has not registered one: a
widget from this package dropped into an application that has not opted in
still renders sensibly.

## What is not here

`RangeSliderField`, `EnumField`, `TextureSlotRow`, `TexturePathField`,
`ColorSwatchField`, `HintTextBox` and `FieldRow` are `ui-27`'s later steps —
some of those read a `MaterialHint` from `flutter3d_formats`, which is why
that dependency is not in this package's `pubspec.yaml` yet either. Two
number formatters stay where they are rather than merge: `NumberField.show`
strips a value to three decimal places for an ordinary field, and
`FieldRow.numberText`, once it arrives, formats a value already carrying a
`RangeHint`'s own step — same job, different inputs, kept apart rather than
forced through one signature.

## Depends on nothing but Flutter

No `flutter3d_editor_core` (the `.fmat` gate stays there) and no
`flutter3d_model_core` (its own `ParamHint`/`EnumHint` name a different type
than anything here reads). A widget that seems to need either is a widget
that needs a parameter or a callback added to it, not an import.
