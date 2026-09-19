# WebGPU

WebGPU is the fourth backend this engine has, and the only one that is not
tried unless a build asks for it by name. This page reads whatever device is
actually open, the same as every other backend page here; on the app you are
looking at right now that may well not be WebGPU at all.

## Step 1: A flag, not a fallback

Finding out whether a browser will hand out a WebGPU adapter means asking,
and asking means shipping the code that can ask. A build that never opts in
never carries it.

{{code flag}}

> **Note.** The measured cost of carrying WebGPU in an ordinary web build was
> close to fifteen percent more script, for a backend most visitors would
> never reach an adapter for. That is what the flag is pricing, not whether
> WebGPU works.

## Step 2: What it declines, and says so

WebGPU has no polygon fill mode at all, and its blend factors have no way to
split a constant between colour and alpha the way this engine's blend states
ask. Both are declared false rather than approximated.

{{code read}}

## Step 3: Read the device in front of you

The panel shows what the device that actually opened for this page answers,
not a description of WebGPU as a specification. On a browser that opted in
and got an adapter, that is WebGPU; everywhere else it is whatever
`openDevice`'s fallback chain settled on instead.

{{code read}}
