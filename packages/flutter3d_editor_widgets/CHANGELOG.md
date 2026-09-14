## 0.1.0

- **The first three, moved verbatim.** `SectionLabel`, `NumberField` and
  `ColorField` out of `apps/flutter3d_modeler`, unchanged in behaviour, plus
  `EditorWidgetsTheme` (`rowHeight`/`labelWidth`/`fieldRadius`/
  `thumbnailSize`) so a row's own size comes from one place instead of each
  editor's own constant. `SectionLabel` gains `style`/`padding` overrides
  wide enough to reproduce `apps/flutter3d_editor`'s own denser look, which
  is why the level editor can move onto this widget later without a second
  copy of it — `ui-27`'s P0.
