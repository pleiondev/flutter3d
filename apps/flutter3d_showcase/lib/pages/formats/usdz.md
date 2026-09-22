# USDZ export

`.usdz` is the format Quick Look opens on macOS and iOS: a ZIP archive
with a `.usda` text layer inside it. This writer is a spike, geometry
only, and this page writes one, then reads its own text layer back out.

## Step 1: Write the archive

`UsdzWriter` bakes each surface's transform into its positions, the same
way the STL and OBJ writers do, and writes one `Mesh` prim a surface. The
ZIP itself stores every entry uncompressed and aligned to 64 bytes, which
is what lets a real USD reader memory-map a layer straight out of the
file instead of inflating it first.

{{code write}}

> **Note.** No materials and no hierarchy past one flat set of meshes:
> `fmt-27`'s own acceptance line asks for geometry, and growing this
> writer past that is a question for whoever first needs textured
> `.usdz`.

## Step 2: Read the text layer back

Nothing in this engine reads a `.usdz`, but the archive this writer
produces is a plain ZIP with one stored entry, so the `.usda` text sits
at a fixed offset past the local file header this writer wrote first.

{{code unzip}}

## Step 3: Look at both layers

The ZIP signature at the front of the file, and the USD header at the
front of the text it contains.

{{code report}}

## Step 4: Check the claim

An archive that starts with the ZIP signature, a text layer that starts
with `#usda 1.0`, and a `Mesh` prim somewhere inside it.

{{code check}}
