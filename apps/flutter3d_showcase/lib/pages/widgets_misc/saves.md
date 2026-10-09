# Saves that survive an update

A save outlives the build that wrote it. Between releases a health bar
becomes a row of hearts and a key ring appears, and the save from last
month still has to open. It has to open the way the player left it, not
with the renamed field quietly back at its default. A save also lives in
more than one place, a phone and a tablet say, and sooner or later the two
copies differ.

Three pieces cover this. `SaveSchema` in `flutter3d_sim` is a game's list
of migrations. `Autosave` in `flutter3d_game` writes the run at the moments
a session tends to end. `SaveSync` keeps a copy in the cloud and settles
the two copies by step and digest.

The page keeps everything in memory: the storage is a map and the cloud is
one slot. The two blocks are the run on this device and the run in the
cloud, as tall as their step counts, and the hearts are what an old save's
health became.

## Step 1: A schema is its migrations

A migration takes the run's fields at one version and returns them at the
next. There is no version number to bump, because the version is the number
of migrations. A number kept beside the list could be raised without
writing one, and a save from the version in between would then be read as
current, which is the failure this exists to stop. A change that needs no
rewriting is a migration that returns its argument, so the history stays
complete.

{{code schema}}

## Step 2: Old saves come up, newer ones are left alone

`SaveRecord` is the save document: the level, the snapshot, the schema it
was written at, the step the run has reached and a digest of the level and
the run. `SaveRecord.read` never throws. A document with no schema in it was
written before games had one, so it reads as version 0 and goes through
every migration. A document from a newer build is refused as newer. That is
somebody's real progress, which this build must not misread and must not
write over.

{{code migrate}}

## Step 3: The game reads it through its session

A game already describes itself to `RunSession`: how a level opens, how it
is written down and put back. `stepOf` is the one addition. It says how far
the run has got, in simulation steps across all its levels, and it is what
two copies are compared by later. `SaveFile` takes the schema, so `begin`
resumes from a migrated save without the game knowing it was old.

{{code session}}

{{code load}}

## Step 4: Autosave at the moments a session ends

`Autosave` writes at three moments. The first is on the way into a pause,
since a pause comes before most of the ways a session ends. The second is at
a checkpoint, when the game says one was reached. The third is when the
application goes to the background, which on a phone is the only warning
before the system ends the process; `watchLifecycle` hears it. Nothing is
written every frame or on a timer, because a write inside the frame budget is
a stutter and a save from the middle of a jump restores in the air.

`SaveFile` keeps the digest of the last run it wrote and skips writing the
same run again. Opening and closing the menu costs nothing.

{{code autosave}}

## Step 5: The cloud, with the player's yes

`SaveSync` sends nothing until the player agrees. The answer is kept in a
document of its own, `cloud_saves.json`, and it is off on a fresh install.
Without it no store is called at all, not even to look. With it, each sync
fetches the cloud's copy and hands both to `resolveSaves`, along with the
digest the two sides last agreed on.

That base is what makes this more than "the further run wins". If one copy
is still the base, only the other has moved since the two last met, and that
one wins whatever its step: a player who went back to an earlier checkpoint
on the tablet meant to. Only when both moved is the step compared. Two
different runs at the same step come back as `SyncOutcome.ask`, because
either automatic answer throws away somebody's evening, and `settle` carries
out the player's choice. If another device wrote between the fetch and the
write, the sync tries once more against what it wrote. A cloud save from a
newer build is left where it is.

{{code sync}}

The store here is one slot in memory. A game passes `HttpCloudSaves`, which
uses `GET` and `PUT` on `saves/<game>/<slot>` with `ETag` preconditions, or
`PlatformCloudSaves` for Play Games and iCloud.

## Step 6: What the page holds itself to

The version-0 save comes up at version 2 with two hearts, a key ring and its
900 steps, and it loads into the game. The newer one is refused as newer.
The autosave writes once on entering the pause, not again while paused, not
for a checkpoint that changed nothing, and again for one that did. The sync
goes through not consented, uploaded, downloaded, ask and uploaded, never
calling the store before consent, and both sides end on the same run.

{{code check}}

> **Note.** The native halves of the `flutter3d/cloud_saves` channel are
> not written yet. Play Games snapshots in Kotlin and CloudKit or the iCloud
> key-value store in Swift still need a plugin package to carry them, so
> `PlatformCloudSaves` answers that the store is unavailable for now. The
> reference server in `cloud/` has no `saves/` routes yet either, and no
> accounts for them to belong to.
