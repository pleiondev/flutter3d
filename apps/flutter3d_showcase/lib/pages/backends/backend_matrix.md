# What differs between them

Every other page in this showcase asks the device a capability question
before it draws something that depends on the answer. This page is the list
those questions come from, read live off whichever device is actually open.

## Step 1: Ask every question

`GraphicsDevice` has one getter per capability the engine ever needs to
decide with: wireframe, cube textures, mip maps, rendering into a mip level,
a stencil buffer, a blend constant and offscreen multisampling, plus three
numbers rather than yes-or-no answers.

{{code rows}}

## Step 2: Where a number says more than yes or no

Anisotropic filtering and multiple colour attachments are not yes-or-no
questions. "Does it work" and "how much" are different questions, and a
device that only answered the first would still leave a caller guessing how
far to push it. `maxAnisotropy` and `maxColorAttachments` answer both at
once, as does `preferredSampleCount` for multisampling.

{{code rows}}

> **Note.** Nothing on this page reads the device's name or its runtime
> type. Every line in the table above comes from asking a question the
> interface defines, which is the same rule every other page in this
> showcase follows.

## Step 3: It should not drift mid-frame

A capability is a property of the device, not of the frame that happened to
run. Reading the same questions again after a frame has drawn has to give
back the same answers this page started with.

{{code stable}}
