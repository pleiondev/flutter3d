# Reduce motion

Somebody who is made ill by moving pictures has already turned Reduce
Motion on, in the system settings, probably years ago. A game that ignores
that and offers its own slider three menus deep asks them to solve the same
problem again, in a menu they may have to get through a moving camera to
reach.

> **Note.** `flutter3d_game`'s real `Accommodations` is not a dependency of
> this app. This page reimplements its nine lines, calling the same
> `MediaQuery.maybeDisableAnimationsOf` Flutter already exposes, so the
> numbers below answer to this device's actual setting.

## Step 1: A default, never an override

{{code value}}

## Step 2: Read what the platform already says

{{code read}}

## Step 3: Compare the two states

{{code compare}}

With the system setting off, a camera's own motion defaults to full. With
it on, the default is nought — a starting point a game's own slider can
still move away from, since this is a fallback and not a lock.
