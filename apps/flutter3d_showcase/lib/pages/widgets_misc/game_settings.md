# Settings, config and saves

A player's choices and a player's progress are two different documents on
purpose: wiping a corrupt save should not cost anybody their key bindings.
`GameConfig` holds the first as two maps of numbers, `SaveFile` holds the
second as a level path and a snapshot, and `SettingsPanel` is the Flutter
widget that lets a player change the first.

> **Note.** None of the three real classes is a dependency of this app.
> `GameConfig` is reimplemented here in full, since it is nothing but two
> maps. `SaveFile` is thinner than it looks: underneath its own few lines it
> is entirely the real `Storage` and `Snapshot` this app already depends on,
> so this page calls those directly. `SettingsPanel` needs a `Bindings` and
> a gamepad's dead zone from packages this app does not have, so it is
> described here rather than built.

## Step 1: A config with no file behind it

{{code config}}

## Step 2: A save that is mostly real storage

{{code save}}

## Step 3: Use both

{{code use}}

A bus nobody has set defaults to full volume. A save written, read back and
cleared answers exactly what each of those should: the level and state it
was given, then nothing at all.
