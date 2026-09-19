# Grade through a LUT

A look-up table, or LUT, is a grade written down as data. Instead of a dozen sliders you keep a small picture that says, for every colour that can come in, which colour goes out. Colourists export them from grading tools, and the renderer applies one in its last pass.

This page builds three tables in code, so there is no file to load, and lets you switch between them.

## Step 1: Build a table

A table is a strip of `N` squares side by side, each `N` by `N` pixels. Blue picks the square, red runs across it and green runs down it. `buildIdentityLut` makes the table that changes nothing: the colour stored at each place is the colour that place stands for. Every other table is a departure from it, so the simplest way to make a look is to start from the identity and change each entry.

Here each entry is passed through a small function, once for a sepia brown, once with red and blue swapped and once for a dark night look. The bytes then become a texture.

{{code table}}

## Step 2: Hand it to the look

`LookSettings.lut` takes the texture. `lutStrength` says how much of the result
to use, from 0, where the table is never read, to 1, where the picture is fully
regraded.

{{code apply}}

## Step 3: Switch tables and blend

Use the Table choice to switch between the three built in Step 1. Each is the
same size, so switching costs nothing. Drag Strength from 1 down to 0 and watch
the picture come back from brown to its own colours.

{{code table}}

> **Tip.** A table only sees colours, not places. It cannot darken a corner or
> tint the sky differently from the floor. For that, use the grade sliders on
> the colour grading page.
