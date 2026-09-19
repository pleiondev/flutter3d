# .fmat material files

A `.fmat` is a material as a file of its own, separate from any model that
wears it. That is what lets a studio's brushed steel be edited once and
shared by every mesh that uses it, instead of being re-exported into each
one of them by hand. `readFmat` and `writeFmat` are the two ends of it, and
what one writes, the other reads back equal.

## Step 1: A material

Metallic, rough, and tinted a cool grey. Nothing exotic, which is the point:
most of what a `.fmat` carries is exactly this handful of scalars.

{{code document}}

## Step 2: Write it, and read it back

`writeFmat` turns the document into the JSON text a person would edit by
hand. `readFmat` turns that text back into a document, and the two are
supposed to agree on every field.

{{code roundtrip}}

## Step 3: A file with a typo in it

An unknown key does not fail the whole file. `roughnesss`, misspelled, is
recorded as a warning and every field this reader does understand still
loads with it.

{{code typo}}

## Step 4: The report

The page shows the written text and both warning lists directly, in place
of the usual viewport: a material file is something to read, not something
to spin around.

{{code report}}

## Step 5: What this page checks

The round trip has to leave `metallic` and `roughness` exactly where they
started, a clean file has to produce no warnings, and the misspelled file
has to produce at least one.

{{code check}}
