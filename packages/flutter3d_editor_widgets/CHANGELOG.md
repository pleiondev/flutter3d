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
