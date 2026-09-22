# Export, read back, compare

A writer that draws a nice picture in a viewer proves nothing about
whether it round-trips. `exportChecked` writes a document, reads the
result straight back through the matching loader, and reports what
changed. This page runs it against three formats at once.

## Step 1: Write, read back, and compare

`exportToGlb`, `exportToObj` and `exportToStl` are all the same function,
`exportChecked`, with a writer already chosen. Each answers an
`ExportReport`: the files it wrote, what the writer already knew it could
not carry, and what `compareModelDocuments` found reading the file back.

{{code checked}}

> **Note.** A clean report with warnings in it is a writer working as
> documented, dropping only what it already said it would. Warnings with
> more differences than they explain is a writer with a real bug.

## Step 2: Check the file's own bookkeeping

Reading a file back proves the geometry survived, but a glTF accessor also
declares its own `min`/`max`, and a reader trusts that declaration rather
than recomputing it from the data. `validateGltfExport` checks the one
thing every reader silently relies on a writer to get right.

{{code validate}}

## Step 3: Put the numbers where they can be read

Three formats, three reports. The page prints each one as a short line:
clean or not, how many warnings, how many differences.

{{code report}}

## Step 4: Check the claim this page makes

A cube is about as simple as a document gets, so this page's own claim is
strict: the GLB round trip has to be clean, and its declared bounds have to
match its data.

{{code check}}
