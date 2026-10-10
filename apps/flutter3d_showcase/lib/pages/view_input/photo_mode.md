# Photo mode

Photo mode is four things. The world stops. A free camera flies through the
level but cannot leave it. A filter goes over the game's own grade. And the
picture is drawn at whatever size the player asks for, larger than the
screen and larger than any render target the device will make. The
platformer has it on P, and this page shows each piece on its own.

Switch on **Photo mode**. The crate stops turning, and the view becomes a
free camera. It starts from the orbit camera's place outside the room and
ends up inside it, within its tether of the player. From there it flies a slow loop that keeps
pushing into the walls. **Filter** picks one of the eight looks.

## Step 1: A level with walls in it

The camera is held by the level's collision world, the same one the game
already steps against, so photo mode needs no geometry of its own. This room
is closed on every side, with a pillar and a crate. The page draws the walls
low so the orbit camera can see in, but their colliders are full height
under a ceiling.

{{code room}}

## Step 2: Stop the world

`shouldPause` is the one place a game decides whether its step runs. With
`photoMode` it answers yes whatever the pointer and the pad say, because both
of them are flying the camera now. A game that let the pointer decide would
start running again the moment the player dragged to frame the shot.

{{code pause}}

## Step 3: A free camera that stays inside

`PhotoCamera` flies with `look`, `tilt` and `zoom`, and moves along its own
axes with up being the world's. It is held in three ways at once. A tether
of `reach` metres keeps it round where the player stood. The level's box,
when there is one, keeps it inside. And the walls stop it, because each move
is swept as a small sphere and slides along whatever it meets.

`begin` does not put the camera where the game's camera was. It starts at
the player and sweeps out toward it. A chase camera can be left behind a
wall for a frame when the player turns sharply, and the photo should not
start on the far side of that wall. Here the game's camera is outside the
room entirely, and the free camera starts just inside the wall.

{{code fly}}

Six hundred random flights follow, each a quarter of a second in a random
direction after a random turn. None of them may end inside a solid or outside the room,
and none may end further from the player than the tether.

## Step 4: A picture in tiles

`capturePhoto` draws the picture in tiles on the renderer the game already
has. Each tile is drawn through a `CropProjection` of the camera's own
projection, which takes the whole frame's aspect rather than the tile's, so
a narrow tile at the edge does not squash what it shows. Each tile also has
a margin of picture round it that is drawn and then cropped away, so an
effect that spreads, like bloom, is not cut off at the tile edge. The rows
are handed out a row of tiles at a time, so memory holds one row however
large the picture is, and `PngStripWriter` can write the file a strip at a
time from there.

{{code capture}}

The settings the tiles are drawn with are not quite the screen's.
`photoSettings` holds exposure at what the screen showed, so every tile is
exposed alike. It turns off temporal anti-aliasing, motion blur and render
scale, which make no sense for a still tile, and the capture's report lists
each one it set aside. The filter is composed onto the game's
`LookSettings`, and `PhotoFinish` puts the vignette and the grain back once
over the whole picture rather than once per tile.

## Step 5: Held to a single frame

The check draws the same picture as one 640 by 360 frame with the settings
the capture reports, and compares it pixel by pixel with the four stitched
tiles. Any pixel more than two steps off has to sit on a seam between tiles.
Away from the seams the picture has to be the frame. On the software device
it is within one step everywhere.

{{code whole}}

{{code check}}

> **Note.** Bloom's widest levels reach further than any margin, so a
> capture with bloom is close to the screen rather than equal to it: with a
> 32-pixel margin the seams drop from 53 steps to a few. Chromatic
> aberration is left out of a capture, since no whole-frame version is
> written yet. The share sheet on Android and iOS needs a plugin this
> package does not take, so a game passes its own `PhotoShelf` there. There
> are no touch or pad controls for photo mode yet, the other demos do not
> have it, and the browser share sheet has not been tried in a browser.
