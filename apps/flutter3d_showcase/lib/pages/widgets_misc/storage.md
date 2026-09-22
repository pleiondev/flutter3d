# Storage on every platform

A settings file lives somewhere different on every platform, and getting
that wrong is invisible: a write that silently fails looks exactly like a
player who never changed a setting. `Storage` hides the place behind one
small interface — a name in, text or nothing back — and never throws.

## Step 1: Write and read a document

`defaultStorage` resolves to the right place for whichever platform is
running: a file under the application's own folder on four of them.

{{code text}}

## Step 2: Remove it

{{code remove}}

A document that was removed reads back as nothing, the same answer a name
that was never written gives.

## Step 3: Storage for bytes

`BinaryStorage` is the same idea for a document too large or too binary for
the text form — `localStorage`, which backs `Storage` on the web, is capped
at a few megabytes for a whole origin. On the web, `defaultBinaryStorage`
resolves to an IndexedDB record instead, which has no such ceiling.

{{code binary}}
