---
title: Cookie and Local Storage Notice
description: This site sets no cookies, so there is no banner. What the browser build keeps in localStorage instead, why it is strictly necessary, and how to remove it.
version: 1.0
effective: 2026-09-16
---

# Cookie and Local Storage Notice

Version 1.0, effective 16 September 2026. Covers
<https://flutter3d.pleion.dev> and the browser build of the **flutter3d
Modeler**.

## Why there is no cookie banner

**This site sets no cookies** of any kind: first-party or third-party, for
analytics, for advertising, or to record that you dismissed a "we value your
privacy" banner.

Article 5(3) of the ePrivacy Directive, the rule those banners exist to
satisfy, requires consent before storing information on your device or reading
information already stored there, **except** where the storage is strictly
necessary to provide a service you explicitly requested. A consent banner for
storage that falls under that exception would ask for a permission we do not
need and cannot act on, and it would train you to click through the banners
that matter. So there is no banner, and there is this page instead.

## What is stored on your device

The browser build of the Modeller uses the browser's **`localStorage`**, not
cookies. The difference that counts here is that `localStorage` is never
attached to a network request, so nothing stored in it is sent to any server,
ours or anybody else's, at any point.

| Key | What it holds | Why it is strictly necessary | Lifetime |
|---|---|---|---|
| `flutter3d/modeler/documents` | The project you have open and its autosave | Without it a refresh, a crash or a closed tab loses the work you asked the Modeller to keep | Until you clear site data |
| `flutter3d/modeler/settings` | Keymap preset, camera scheme, panel widths, language, recent files | Without it the editor resets to defaults on every load, which is not a working editor | Until you clear site data |

Both are first-party, both are read and written only by code running on this
origin, and both fall squarely inside the "strictly necessary" exception: they
exist to deliver the editing service you opened the page for, and for nothing
else.

Other flutter3d demos served from this origin use the same mechanism under
their own `flutter3d/<app>/…` keys, for the same reason: a saved game and a
settings file.

## What is not stored

The site stores no analytics, session or advertising identifier, takes no device
fingerprint, and keeps no "consent string". It loads no third-party pixel,
beacon, tag, script, font or embedded player, so no third party is in a
position to set anything.

## How to remove it

Clearing site data for `flutter3d.pleion.dev` in your browser removes every
`flutter3d/*` key. **This deletes any project you had only in the browser**, so
export what you want to keep first. The Modeller also offers "Clear local data"
in Settings, which does the same thing from inside the application.

Blocking storage for this origin entirely also works. The Modeller checks
whether the browser allowed a write and, if it did not, carries on without
persistence instead of refusing to start. You will lose your work on refresh,
and the Modeller will tell you so.

## Server logs

Delivering a page is not covered by the storage rule above, but it is still
processing: our hosting provider records standard access logs. What is in them,
why, for how long and on what legal basis is in section 3 of the Privacy
Policy.

## If this ever changes

If a future version of the site adds analytics, an embedded video, a hosted
font or anything else that stores or reads non-essential information on your
device, **a consent mechanism will be added at the same time** and this page
will be rewritten to describe it. That promise is the reason this page exists,
and the version number and date at the top are how you can tell whether it
still holds.

Questions: privacy@pleion.dev.
