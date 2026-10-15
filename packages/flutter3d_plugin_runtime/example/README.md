# The extension points of the frame, from outside

A plugin written against the published API only, as one from another
package would be: `package:flutter3d_core`, `package:flutter3d_plugin_api`
and `package:flutter3d_plugin_runtime`, no `src/` import. Its namespace is
`acme_sample`, and every name it registers is in it.

`lib/acme_sample.dart` is the Dart half. Installed, it adds

- a light type of its own, `acme_sample.tube`, packed by a `LightTypeHook`;
- a lighting model, `acme_sample.Hair` (its stage `acme_sample__Hair`), written in the material language
  with a uniform block and a texture of its own (its slot table);
- a decal stage, `acme_sample__Decal`;
- a post effect, `acme_sample.smear`, that reads the velocity with the
  temporal resolve and the motion blur both off;
- a shadow technique with a producer of its own;
- a draw-list hook and a level-of-detail policy;
- an image format, `acme_sample.pix`;
- a scene binding and the kind of node it makes;
- a kind of pipeline node, and a pipeline that places one.

`plugin/acme_sample.f3dplugin` is the data half: the same binding and the
same pipeline as a document, read by `DataPluginLoader`.

`lib/acme_editor.dart` is the editor half. Its hints, written against
`package:flutter3d_plugin_api/editor.dart` alone, give the `acme_sample.heat`
component, the `ember` entity kind and the `acme_sample.Hair` lit model
their inspector controls; its editor pieces add a command
(`acme_sample.editor.stoke`, also a tool an agent sees), a gizmo ringing an
ember with its reach, an importer for `.embers` lists and an asset-browser
entry for them. A game installs it with no editor and nothing is added.
`plugin/acme_editor.f3dplugin` says the same hints as data, in an `editor:`
section, and `test/acme_editor_test.dart` holds both halves to each other.

`test/acme_sample_test.dart` installs both, draws a frame with them on a
device with no GPU, takes them out again, and runs the plugin conformance
suite over the Dart half.
