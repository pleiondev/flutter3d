# The build-time converter

`flutter3d_build` is a command line tool, not something this application
runs: it depends on `hooks` and `code_assets` to be a Flutter build
hook, and pulling a build tool into a showcase app would ship it inside
every application that depends on this engine. This page shows what the
tool does by running its two steps, decode then write, by hand.

## Step 1: A model, the way the tool would find one

`dart run flutter3d_build:convert model.obj` reads a file by its
extension and hands it to the matching decoder: glTF, GLB, OBJ or STL in,
`.f3d` out. This page's own source is a small OBJ, so nothing here is
made up beyond not being a file on disk.

{{code source}}

## Step 2: Decode it, then write it

This is the whole of what the real tool does to one file: read it with
the ordinary decoder, then hand the decoded document to `F3dWriter`. The
command line version does this for every recognised model under a
directory, and writes each result beside its source rather than holding
it in memory.

{{code convert}}

> **Note.** The real tool also has a build hook,
> `dart run flutter3d_build:init`, which wires this conversion into a
> project's own `flutter build` so a project never has to run the
> command by hand again. `--textures` compresses images on the way
> through: `bc`, `etc2`, or `universal` for one file the upload
> transcodes on every device.

## Step 3: Compare the sizes

Even a four-vertex tetrahedron is smaller as `.f3d` than as text, because
`.f3d` stores exactly the bytes a GPU wants and nothing has to be parsed
back out of them.

{{code report}}

## Step 4: Check the claim

The source has to actually decode, and the converter has to actually
write something.

{{code check}}
