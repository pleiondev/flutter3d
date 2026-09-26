# flutter3d_model_core

The headless half of [flutter3d](https://flutter3d.pleion.dev)'s model editor:
the project being edited, the commands that change it, the history that takes
them back, and the rules about whether the result can leave.

Plain Dart, with no Flutter, no renderer and no disk. This is the same split
`flutter3d_editor_core` made for levels, for the same reason: the programs that
most want to check a document are the ones with no window in them.

## What is here today

Only the library header. The package was registered before it was filled, so the
structure scan, the publishing order and the container check have covered it
since the first commit instead of from whenever somebody remembered to add it.

What it will hold is in `doc/model-editor-plan.md` §2.2: `ModelProject` and its
objects, the sealed `ModelCommand` every edit is one of, `ModelHistory`, the
project file format, and `ExportReadiness`.

## Licence

MIT.
