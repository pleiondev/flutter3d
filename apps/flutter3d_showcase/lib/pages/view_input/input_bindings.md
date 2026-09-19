# Bindings and rebinding

A game asks "is jump pressed", not "is the space bar pressed". Between the
two sits a binding: a map from an action's name to whichever key currently
means it. Rebinding is what lets a player change that map while the game
keeps running, instead of the mapping being baked into the code that reads
the keyboard.

> **Note.** `flutter3d_game` is not yet a dependency of this application.
> This page reimplements the same small idea, a map plus a function that
> replaces one entry in it, and says so rather than pretending its
> `Bindings` and `Rebinding` classes are in use.

## Step 1: A map from action to key

Nothing more than a `Map<String, LogicalKeyboardKey>`. Reading it is how the
rest of the game asks "is jump pressed" without caring which physical key
that currently means.

{{code bindings}}

## Step 2: Replace one entry

Rebinding an action means writing a new key over its old one, and leaving
every other action exactly as it was. A binding is not a single value the
whole map resets around; each action owns its own key.

{{code rebind}}

> **Tip.** A real rebinding flow waits for the *next* key pressed, not one
> named by the caller. Waiting is a small state machine: nothing happens
> until a key arrives, then the entry is written and the wait ends.

## Step 3: Try it

Choose an action in the panel and press a key. The label beside the ball
updates to whatever you pressed, and every other action's binding stays
exactly where it was.

{{code rebind}}
