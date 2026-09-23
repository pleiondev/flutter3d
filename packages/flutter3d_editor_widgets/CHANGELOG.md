## 0.8.0

**Moves with the stack to 0.8.0**, whose `flutter3d_hardware` changes
`PassEncoder.bindTexture` to return `bool` and makes every backend forget its
bindings at `bindPipeline`. Nothing in this package changed.

Its `flutter3d_*` dependencies ask for `^0.8.0`.

## 0.7.1

**Released with the rest of the stack at 0.7.1.** Nothing in this package
changed. The release it resolves against builds from pub.dev again and no
longer crashes Metal on the first unlit draw.

Its `flutter3d_*` dependencies ask for `^0.7.1`.

## 0.7.0

- **The first publication, and the number skips.** 0.1.0, 0.2.0 and 0.3.0
  below were numbers this package carried inside the workspace; none of them
  reached pub.dev, so nobody outside saw the ones passed over. It goes out at
  0.7.0 with the rest of the shelf so that one number names one tree and
  `^0.7.0` on any `flutter3d_*` package resolves against every other.
  `doc/boundary-0.7.0.md` has the list of the thirteen that begin here.
- **`flutter3d_formats` is `flutter3d_core`.** The package the hints come from
  was folded into `flutter3d_core`, which is the dependency now, at `^0.7.0`.
  `RangeHint`, `ColorHint`, `TextureHint` and `EnumHint` are imported from
  `package:flutter3d_core/formats.dart`. The invariant stands: never
  `flutter3d_editor_core`, never `flutter3d_model_core`.
- **`NumberField` reads arithmetic and units.** `evaluateNumber(text, unit:)`
  takes the four operators, brackets and `pi`, and a `NumberUnit` of `plain`,
  `metres` or `degrees`. Under `metres` a suffix of `mm`, `cm`, `dm`, `m`,
  `km`, `in` or `ft` converts to metres; under `degrees`, `deg`, `rad` and
  `turn` convert to degrees; `plain` refuses every suffix, and an unknown one
  answers null. A comma is still read as a decimal point and a result that is
  not finite is refused. `NumberField` takes `unit`, and `NumberField.parse`
  takes it as a named parameter, so `parse('1/3')` now returns a value.
- **`NumberField` can be nudged.** Up and Down move the value by `step`, 0.1 by
  default, Shift multiplies that by ten and Ctrl or Cmd by a tenth, and the
  label is a horizontal scrub handle at one step a pixel. `labelWidth` is a
  parameter, default 18.
- **`NumberField.show` stops printing a small number as zero.** It used three
  decimal places for everything, so an STL read at a scale of 0.001 displayed
  `0`. A magnitude of 0.01 and above still gets three places, one of 0.0001
  and above gets six, anything smaller eight.
- **A dense row gets a dense field.** `EditorWidgetsTheme.denseFields` is true
  when `rowHeight` is under 40, and `fieldPadding()` answers 6 pixels of
  vertical padding then and `(rowHeight - 24) / 2` otherwise. The text boxes
  in `NumberField`, `ColorField` and `RangeSliderField` take `isDense` and
  their `contentPadding` from the two. The theme's defaults are unchanged.
- **`RangeSliderField` puts its label above the slider in a narrow row.** When
  the row is narrower than the label, the value box and `kLabelBesideFrom`,
  150 pixels, the label is stacked and the slider keeps its length. The
  constructor is unchanged.
- **Sliders and `SectionLabel` take their look from outside.**
  `RangeSliderField` and `ColorField` no longer wrap themselves in a
  `SliderTheme` with a 3-pixel track and a 6-pixel thumb; they draw with the
  ambient `sliderTheme`. `SectionLabel`'s default style is 11 points, weight
  400, letter spacing 0.88 in `colorScheme.outline`, where it was
  `labelMedium` in `onSurfaceVariant` at 0.6. An application that relied on
  either default sees a different picture and sets the theme or passes
  `style`.

## 0.3.0

- **`TexturePathField`, `ColorSwatchField`, `HintTextBox`/`NumbersRow` and
  `FieldRow` — `ui-27`'s own P2, moved verbatim from
  `apps/flutter3d_editor`'s own `editor_inspector.dart`.** `TexturePathField`
  (with `FilePickerDialog` and the `PathOffers` typedef it takes a listing
  through) is the level editor's own "path on disk" model for a
  `TextureHint`, from before an editor could list a project's own assets for
  a caller to hand in. `ColorSwatchField` (with `ColorPaletteDialog`) is a
  swatch and a twelve-hue grid over a `ColorHint`'s own value — not
  `ColorField`, which is a full HSV picker with a hex box built for a
  different caller; the level format's colour hint never asked for hue and
  saturation sliders. `HintTextBox` and `NumbersRow` are `FieldRow`'s own
  fallback for a value nothing has hinted: one text box, and a row of them
  for a vector, with the same `Focus(onKeyEvent: skipRemainingHandlers)` that
  keeps a name being typed into one of them from being read as a tool
  shortcut by an ancestor.
- `FieldRow` itself is the point of the four: one row, typed by a
  `MaterialHint` when there is one — a slider for a `RangeHint`, a picker for
  a `ColorHint`, a path field for a `TextureHint`, a dropdown for an
  `EnumHint` — and by the value's own type when there is not, assembled from
  `RangeSliderField`/`EnumField` (this package's own P1) and the four widgets
  above. `apps/flutter3d_editor`'s own `EditorInspector` and `MaterialPanel`
  now import it from here rather than keeping their own copy;
  `editor_inspector.dart` re-exports `FieldRow`/`PathOffers`/`nothingToOffer`
  so nothing that already imported them from that file has to change its own
  import. Its own controls draw with `Theme.of(context)`'s defaults rather
  than the level editor's hard-coded dark palette until `ui-27`'s own E1
  gives that application an explicit `ColorScheme` — an accepted, temporary
  mismatch, not a regression: no test here or in `apps/flutter3d_editor`
  checks colour.
- 23 new tests in `field_row_test.dart`, including one pinning the exact
  `Focus`-swallows-the-keystroke behaviour and one pinning `apps/
  flutter3d_editor`'s own colour-hint test's count of exactly four
  `TextField`s per row.

## 0.2.0

- **`RangeSliderField`, `EnumField` and `TextureSlotRow` — `ui-27`'s own P1,
  each merging two existing implementations rather than picking one.**
  `RangeSliderField` reconciles the level editor's hint-driven slider (a
  nullable `step` that snaps and rounds a drag's own value, an `editable`
  text box for a value that may sit outside `[min, max]`) with the
  modeller's own lighter row (an optional internal `label` column, no box —
  a two-decimal number beside the thumb is enough). `EnumField` reconciles
  the editor's "show what a document has, even when the picker's own list
  does not offer it" with the modeller's own fallback for a value nothing
  has set. `TextureSlotRow` merges the modeller's production row — a name or
  `"None"` beside `Choose…`/`Clear` — with a richer, previously unwired row's
  own optional thumbnail, `w×h · weight` subtitle and format badge; the
  three stay out of the row entirely when a caller has none of them to hand
  in yet, so `apps/flutter3d_modeler`'s own material panel renders exactly
  as it did before this step.
- `flutter3d_formats` joins this package's dependencies — the first of the
  three reads `RangeHint`, the second `EnumHintValue`; the package's own
  invariant (never `flutter3d_editor_core`, never `flutter3d_model_core`)
  holds unchanged.

## 0.1.0

- **The first three, moved verbatim.** `SectionLabel`, `NumberField` and
  `ColorField` out of `apps/flutter3d_modeler`, unchanged in behaviour, plus
  `EditorWidgetsTheme` (`rowHeight`/`labelWidth`/`fieldRadius`/
  `thumbnailSize`) so a row's own size comes from one place instead of each
  editor's own constant. `SectionLabel` gains `style`/`padding` overrides
  wide enough to reproduce `apps/flutter3d_editor`'s own denser look, which
  is why the level editor can move onto this widget later without a second
  copy of it — `ui-27`'s P0.
