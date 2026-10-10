# The extension points of the frame, from outside

A plugin written against the published API only, as one from another
package would be: `package:flutter3d_core`, `package:flutter3d_plugin_api`
and `package:flutter3d_plugin_runtime`, no `src/` import. Its namespace is
`acme_sample`, and every name it registers is in it.

`lib/acme_sample.dart` is the Dart half. Installed, it adds

- a light type of its own, `acme_sample.tube`, packed by a `LightTypeHook`;
- a lighting model, `acme_sample_Hair`, written in the material language
  with a uniform block and a texture of its own (its slot table);
- a decal stage, `acme_sample_Decal`;
- a post effect, `acme_sample.smear`, that reads the velocity with the
  temporal resolve and the motion blur both off;
- a shadow technique with a producer of its own;
- a draw-list hook and a level-of-detail policy;
- an image format, `acme_sample.pix`;
- a scene binding and the kind of node it makes;
- a kind of pipeline node, and a pipeline that places one.

`plugin/acme_sample.f3dplugin` is the data half: the same binding and the
same pipeline as a document, read by `DataPluginLoader`.

`test/acme_sample_test.dart` installs both, draws a frame with them on a
device with no GPU, takes them out again, and runs the plugin conformance
suite over the Dart half.
