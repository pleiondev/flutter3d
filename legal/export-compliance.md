---
title: Export Compliance and Sanctions Notice
description: Publicly available open-source software with no cryptography of its own — the classification, the App Store export answers that follow from it, and the sanctions obligation that is yours.
version: 1.0
effective: 2026-09-16
---

# Export Compliance and Sanctions Notice

Version 1.0, effective 16 September 2026.

## 1. What this software is, for classification purposes

The **flutter3d Modeler** and the `flutter3d` libraries are publicly available
open-source software: a 3D modelling application and a rendering engine,
distributed free of charge, with the complete source code published at
<https://github.com/pleiondev/flutter3d> under the MIT Licence.

**The software contains no cryptography of its own.** It implements no
encryption algorithm, ships no cryptographic library, and has no encryption
feature. Where a platform underneath it uses encryption — an operating system's
file encryption, a browser's TLS when you fetch a model from a URL — that is
the platform's, used through its ordinary public interfaces, and is not a
capability this software adds.

## 2. United States (EAR)

We consider the software to be publicly available under § 734.7 of the US
Export Administration Regulations and therefore **not subject to the EAR**: the
source is published and available to all without restriction, at no cost, and
without a licence agreement restricting redistribution.

Were a classification nonetheless required, the appropriate one would be
**ECCN 5D992.c** (mass-market software) or **EAR99**, and not a controlled
entry, because the software implements no encryption function.

For Apple's App Store export compliance questionnaire, the answers that follow
from the above are:

- "Does your app use encryption?" — **No.** The app implements no encryption
  and does not call platform encryption APIs beyond standard HTTPS/TLS made by
  the operating system on the app's behalf.
- Consequently no CCATS, no ERN and no annual self-classification report is
  required.

These answers are ours as the developer, and are stated here so that anyone
distributing a build can check them against the source rather than take them on
trust.

## 3. European Union

Under Regulation (EU) 2021/821 (the EU dual-use recast), software "in the
public domain" — generally available and not subject to restriction on further
dissemination — falls outside the control lists by the General Software Note.
The Modeller is published in exactly that way. No export authorisation is
required for its download or redistribution.

## 4. Sanctions

Whoever downloads, uses or redistributes this software is responsible for
complying with the sanctions law that applies to them. That includes, without
limitation:

- European Union restrictive measures, including the sectoral and territorial
  measures in force at the time you act;
- United States sanctions administered by OFAC, including the Specially
  Designated Nationals list and comprehensive territorial programmes;
- United Kingdom sanctions administered by OFSI;
- any equivalent regime in your own jurisdiction.

**By using the software you represent** that you are not a person or entity
designated under any of those regimes, that you are not acting on behalf of
one, and that you are not located in a territory subject to a comprehensive
embargo where doing so would breach the law that applies to you.

We do not operate a server, a store or an account system, and therefore run no
screening of our own: there is nobody to screen, because there is no
transaction. This section states an obligation on you, not a check we perform.

## 5. App store distribution

Apple and Google apply their own export and sanctions screening to the
territories they distribute an application in, and a build obtained from a
store is distributed under those controls in addition to this notice.

## 6. This is a statement, not advice

This notice records our own classification of our own software and the basis
for it. It is not legal advice, and it does not decide your position: if you
redistribute this software commercially, bundle it into a product, or operate
in a regulated sector, take your own advice on your own facts.

Questions about this notice: legal@pleion.dev.
