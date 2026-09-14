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
