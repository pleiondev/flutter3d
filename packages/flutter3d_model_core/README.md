# flutter3d_model_core

The headless half of [flutter3d](https://flutter3d.pleion.dev)'s model editor:
the project being edited, the commands that change it, the history that takes
them back, and the rules about whether the result can leave.

**Plain Dart.** No Flutter, no renderer, no disk — the same split
`flutter3d_editor_core` made for levels, for the same reason: the programs that
most want to check a document are the ones with no window in them.

## What is here today

Nothing but the library header. The package is registered before it is filled,
so the structure scan, the publishing order and the container check cover it
from the first commit rather than from whenever somebody remembers.

What it will hold is in `doc/model-editor-plan.md` §2.2: `ModelProject` and its
objects, the sealed `ModelCommand` every edit is one of, `ModelHistory`, the
project file format, and `ExportReadiness`.

## Licence

MIT.
