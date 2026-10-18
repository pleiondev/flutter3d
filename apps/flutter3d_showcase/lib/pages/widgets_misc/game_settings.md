# Settings, config and saves

A player's choices and a player's progress are two different documents on
purpose: wiping a corrupt save should not cost anybody their key bindings.
`GameSettings` holds the first as a value: a volume per audio bus, typed
settings under namespaced keys, and the player's action map, each change a
copy. `SaveFile` holds the second as a level path and a snapshot, and
`SettingsPanel` is the Flutter widget, made of `SettingsSection`s, that lets
a player change the first.

> **Note.** `SaveFile` is thinner than it looks: underneath its own few lines
> it is entirely the real `Storage` and `Snapshot`, so this page calls those
> directly. `SettingsPanel` is described here rather than built.

## Step 1: A setting of the game's own

{{code config}}

## Step 2: A save that is mostly real storage

{{code save}}

## Step 3: Use both

{{code use}}

A bus nobody has set defaults to full volume, and a setting nobody chose
reads as its key's fallback. The file is written in the format envelope, and
a key this build does not know is kept for the next write. A save written, read back and
cleared answers exactly what each of those should: the level and state it
was given, then nothing at all.
