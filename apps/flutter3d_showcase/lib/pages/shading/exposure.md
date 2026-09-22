# Manual exposure

`RenderSettings.exposure` is the linear multiplier the composite pass applies
to a frame before the tone curve rolls it off. It is what a photographer's
exposure dial would be if the scene were a camera: the light in the scene
does not change, only how much of it reaches the picture.

This is the manual knob. `RenderSettings.autoExposure` is a separate meter
that reads the frame's own brightness and moves this same number for you;
this page turns it by hand instead, so the effect is direct and repeatable.

## Step 1: A scene with something bright in it

An emissive box under a modest sun gives the exposure slider something to
work with: raise it and the box's own light grows past what an ordinary
material would show.

{{code scene}}

## Step 2: The knob

Exposure is read fresh every frame, straight out of the settings.

{{code settings}}

## Step 3: What the frame reports back

`FrameResult.exposure` says what the composite actually used. With auto
exposure off, that number is exactly the one this page set, and the page's
own test reads it back to make sure the two never drift apart.

{{code check}}
