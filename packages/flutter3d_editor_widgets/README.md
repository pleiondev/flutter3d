# flutter3d_editor_widgets

The controls `apps/flutter3d_modeler` and `apps/flutter3d_editor` each drew a
private copy of, moved to one package so the copies stop drifting —
`ui-27`. Ten so far, plus the row they assemble into:

| Widget | What it is |
|---|---|
| `SectionLabel` | One line of upper-case, letter-spaced text naming a panel section. `style`/`padding` override the default look — wide enough to reproduce the level editor's own denser heading, so it never needs a second copy of this widget |
| `NumberField` | A labelled box that holds one number: a comma and a full stop both read as a decimal point, and it reports only when the person has finished, not on every keystroke |
| `ColorField` | A swatch, a hex box and HSV sliders over a three- or four-channel colour, with an `Alpha` slider only when a fourth channel is there to hold one |
| `RangeSliderField` | A slider between `min` and `max`, an optional internal `label`, a nullable `step` that snaps and rounds a drag's own value (null keeps it bit for bit), and an `editable` text box for a value that may sit outside its own ends |
| `EnumField` | A dropdown over `options`, with a bound `value` shown even when nothing in `options` names it, and a null `value` falling back to the first option rather than refusing to draw |
| `TextureSlotRow` | A texture slot: a label, a name or `"None"`, `Choose…`/`Clear` — and, once a caller has them, a thumbnail, a `w×h · weight` subtitle and a format badge |
| `TexturePathField` | A `TextureHint`'s own "path on disk" row: a box to type a path into, and — when `PathOffers` names any — a button opening `FilePickerDialog` over them. A path that does not fit the hint's own extensions is said, not refused |
| `ColorSwatchField` | A `ColorHint`'s own row: a swatch that opens `ColorPaletteDialog` (a twelve-hue, four-brightness grid, plus a row of greys), beside one number box per channel. Not `ColorField` — see below |
| `HintTextBox` / `NumbersRow` | `FieldRow`'s own fallback for a value nothing has hinted: one text box that reports on Enter or on losing focus, and a row of them for a vector. `HintTextBox`'s own `Focus(onKeyEvent: skipRemainingHandlers)` keeps a keystroke typed into it from also reaching an ancestor that reads bare letters as a tool shortcut |
| `FieldRow` | One field: its name, and whatever the six above draw when a `MaterialHint` calls for one of them, or — failing that — whatever `HintTextBox`/`NumbersRow` draws for the value's own type. `apps/flutter3d_editor`'s own inspector panel and material panel are its two callers |

Every widget reads `Theme.of(context)` for colour. Row-level sizing —
how tall a row is, how wide a label column is, a field's corner radius, a
texture thumbnail's edge — comes from `EditorWidgetsTheme.of(context)`
instead, which falls back to `rowHeight: 32, labelWidth: 96, fieldRadius: 6,
thumbnailSize: 26` when the ambient `ThemeData` has not registered one: a
widget from this package dropped into an application that has not opted in
still renders sensibly.

## Not `ColorField`

`ColorSwatchField` and `ColorField` both edit a colour and neither is built
from the other. `ColorField` is a full HSV picker with a hex box, meant for a
caller that wants that whole surface inline over a three- or four-channel
value. `ColorSwatchField` is the level editor's own lighter row from before
that picker existed: a swatch that opens a flat grid of pre-mixed swatches to
land roughly on a colour, with the exact numbers typed beside it — because a
level's colour hint never asked for hue and saturation sliders, only for
"pick roughly the right paint, then type the exact number". Unifying them
would mean picking one interaction for both callers; keeping two lets each
row stay the shape its own document actually wants.

## Two number formatters, kept apart

`NumberField.show` and `numberText` (used by `FieldRow`, `HintTextBox` and
`NumbersRow`) both turn a number into short text, and neither calls the
other. `NumberField.show` fixes an ordinary field to three decimal places and
strips the trailing zeros — a position of `1` reads as `1`, one of
`0.3333…` stops at `0.333`, and the field decides how much precision a
number this size is worth showing. `numberText` never rounds: `2` stays `2`
and `2.5` stays `2.5` however many digits are actually in it, because a
number a document already carries — a field's raw value, a `RangeHint`'s own
`min`/`max` printed beside an out-of-range value — has to be shown exactly as
the document has it, not rounded to what a slider's own precision would
otherwise be enough to show. Moved here as they already stood, one from each
side, rather than forced through a shared signature that would have had to
take a rounding policy as a parameter for one caller and ignore it for the
other.

## Depends on `flutter` and `flutter3d_formats`

`RangeSliderField`'s own `step`, `EnumField`'s own `options`, and
`TexturePathField`/`ColorSwatchField`/`FieldRow`'s own hints read
`RangeHint`/`EnumHintValue`/`TextureHint`/`ColorHint`/`MaterialHint` off
`flutter3d_formats` — never `flutter3d_editor_core` (the `.fmat` gate stays
there) and never `flutter3d_model_core` (its own `ParamHint`/`EnumHint` name
a different type than anything here reads). A widget that seems to need
either of those two is a widget that needs a parameter or a callback added to
it, not an import.
