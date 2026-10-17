# Colour vision

About one man in twelve is missing one kind of cone, or has one that sees
the wrong colours. A game that tells danger from safe ground by red against
green tells those players nothing. The engine has three tools for this.
`ColorVision` draws the picture as such a player sees it, or shifted so they
can tell apart what they would otherwise run together. `ColorRoles` gives
each colour a meaning, so a player can change what danger looks like
without changing everything else. `ColorVision.confusions` is a lint that
finds the pairs told apart by hue alone.

This page has four marks in a row: danger, safe ground, loot and water.
**Picture** chooses how the frame is drawn. **The player's own colours**
repaints the marks in the colours a player picked instead.

## Step 1: Colours that mean something

A `ColorRole` is a name, a label for the settings panel and a default
colour. A HUD asks for the role and is given whatever the player has chosen
for it. The choice is a number kept in the game's settings under
`colour.<name>`. Nought is the role's own colour. One to eight are Okabe
and Ito's palette, eight colours that stay apart for every common kind of
colour blindness. A short list a player can go through works better than a
free colour picker here, because most of the colours in a picker are the
problem.

The second config is a player who has been through the Colours section of
the shared settings panel and picked four of the eight.

{{code roles}}

## Step 2: Paint with the role, never with the colour

Each mark's material is set from `ColorRoles.of`, which answers the
player's choice or the role's default. The swatches are display colours, so
they are taken to linear light before they go into a material.

{{code paint}}

## Step 3: Simulate for yourself, correct for the player

`ColorVision.simulate` is the picture as someone missing the long (protan),
middle (deutan) or short (tritan) cone sees it, using the matrices of
Machado, Oliveira and Fernandes, blended by severity. Use it to look at your
own game. `ColorVision.correct` takes what that player would lose and moves
it onto the channels they still tell apart, after Fidaner. That is the one
to offer a player, and the shared settings panel offers it as **Colour
vision**.

Both are a 3×3 matrix in linear light. `upload` bakes the matrix into the
colour table that `LookSettings.lut` reads after the tone map. No pass is
added, so every backend draws it through the table pass it already has, and
the software renderer's frame matches what `ColorVision` predicts to within
the table's interpolation. A device cannot free a texture, so the page
makes each table once and keeps it, the way `ColorVisionLook` does in a
game.

{{code table}}

## Step 4: The lint

`ColorVision.confusions` takes a palette by name. It answers the pairs that
normal eyes tell apart and a protan, deutan or tritan does not, measured as
CIE 1976 ΔE with twenty as the threshold. `ColorRoles.confusions` runs it
on the roles in the colours a given player has them. The fix for a pair it
finds is a second cue, such as a letter, a shape or a pattern, rather than
a third colour. The page also measures one pair directly: how far apart
danger and safe ground look to a deutan.

{{code lint}}

## Step 5: What has to hold

In the game's colours the lint has to find danger against safe ground for a
deutan. In the player's colours it has to find nothing. Seen by a deutan,
red and green have to come out under twenty apart. The player's vermillion
and blue have to be more than three times as far apart, and the correction
has to move red and green further apart than they were. Measured, the gaps
are about 11, 108 and 50.

{{code check}}

> **Note.** The correction is not a cure. It moves a difference the player
> cannot see to one they can, and the colours it gives look wrong to
> everybody else, which is why it is a setting and off by default. The
> table comes after the tone map. A game with a grade of its own has to bake
> both into one table with `toStrip(grade:)`, because `LookSettings` holds
> one table. Roles change the marks a game paints from them. In the dungeon
> the key marks in the HUD are roles, but the keys lying in the world keep
> the game's colours.
