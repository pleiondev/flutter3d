# Procedural sky

A sky does not need a photograph. Three colours (overhead, at the horizon and
underfoot), a soft glow around the sun and a small bright disc are enough for an
outdoor scene, and the renderer works all of it out per pixel. Nothing is loaded
and nothing has to be kept in step with a file.

## Step 1: A light that agrees with the sun

The sky paints a sun, but it does not light anything. Light still comes from a
`LightNode`. The two are separate on purpose: you can have sunlight with no sky,
or a sky with a moon that lights nothing. When you want them to match, aim the
light the opposite way from where the sun is painted. Here `update` does that
every frame from one number, the sun height.

{{code sun}}

## Step 2: Turn the sky on

The sky is a setting of the frame, not an object in the scene. It is off until
`enabled` is true. `directionToSun` points at the sun, which is the reverse of
the way a light points. `sunIntensity` is the brightness of the disc and
`glowStrength` the soft halo around it. Drag **Sun height** and watch the disc
climb, then drag **Glow** and **Sun disc** to see which part is which.

The colours of the sky itself (`zenith`, `horizon` and `nadir`) have defaults,
so this page leaves them alone.

{{code sky}}

> **Note.** Sky colours are linear light, not the values an eyedropper reads off
> a screenshot. They pass through exposure and the tone curve like everything
> else, so a sky written from a paint swatch will look too bright.

## Step 3: The painted dome

There is an older way that needs no shader: a small dome around the camera with
the gradient painted into its vertices. `paintSky` fills the colours from a
`SkyGradient`, `skyNode` sets the flags a backdrop needs (drawn first, no depth
write, no shadow), and `followCamera` keeps it centred on the eye. Turn on
**Painted dome instead** and the sky setting is switched off so the dome is what
you see.

The dome has no sun disc. Its one advantage is that each view can have a
different sky, which a setting on the whole frame cannot do.

{{code dome}}
