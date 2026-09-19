# The software rasteriser

Every page in this showcase, including this one, is proven on a device with
no GPU behind it at all: a rasteriser written in Dart, sharing nothing with
either hardware backend. This is the reason the golden pictures the engine
is checked against can be recorded in seconds under a plain `dart test`
rather than a twelve-minute run of a real application.

## Step 1: Why a third, unrelated backend

Two backends that agree prove less than they seem to when both are hardware
rasterisers driven by a C API underneath. The software backend shares no
driver, no shading language and no command buffer with either, so whatever
the interface still quietly assumed about graphics hardware has to show up
here, where there is no hardware to hide behind.

{{code read}}

## Step 2: What it says about itself

Reading the device rather than its name works exactly the same way here as
on every other backend page: it is a `GraphicsDevice`, and it answers the
same questions.

{{code read}}

> **Note.** `preferredSampleCount` answers one and `supportsOffscreenMsaa`
> answers false: this backend never multisamples, and says so rather than
> quietly drawing a picture that looks like it did.

## Step 3: A fact that has to hold

A backend that answers "no multisampling" and then multisamples anyway
would be exactly the silent substitution capability questions exist to
prevent. This page checks that its own two answers agree with each other.

{{code verify}}
