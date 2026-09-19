# An FBX, refused with a reason

FBX is Autodesk's format, and a lot of models still arrive in it. This
engine recognises one and says plainly that it does not read it yet,
rather than crashing on the attempt or silently loading nothing.

## Step 1: The bytes of a real binary FBX header

Every binary FBX file, since the format's 2005 introduction, starts with
the same twenty-one bytes: the string `Kaydara FBX Binary` and two
spaces. This page never reads past that.

{{code magic}}

## Step 2: The decoder recognises its own format

`FbxDecoder.handles` checks the binary magic, the `.fbx` extension, and
the ASCII dialect's own header comment. It answers true here on the
magic alone.

{{code handles}}

## Step 3: And refuses to read it

`decode` throws a `FormatException` naming what it is and what to do
about it, rather than returning an empty document or crashing partway
through a format nobody has written a reader for yet.

{{code refuse}}

> **Warning.** This is a stub, not a partial reader. `FbxDecoder`
> recognises every FBX file this way; none of them decode.

## Step 4: Check the claim

The decoder has to recognise its own magic, and the message it refuses
with has to actually say what to do instead.

{{code check}}
