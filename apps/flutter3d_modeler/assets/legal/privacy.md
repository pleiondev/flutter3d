---
title: Privacy Policy
description: No accounts, no servers of ours, no analytics. What stays on your device, the three network calls you start yourself, and your rights under the GDPR.
version: 1.0
effective: 2026-09-16
---

# Privacy Policy

Version 1.0, effective 16 September 2026. Covers the **flutter3d Modeler**
application (`dev.flutter3d.modeler`) on macOS, iOS, Android and the web, and
the website at <https://flutter3d.pleion.dev>.

## The short version

The Modeller has no accounts, no servers of ours, no analytics and no
advertising. **Your models, projects, autosaves and settings stay on the device
you are using and are never sent to us.** We do not know who you are, how often
you use the Modeller, or what you make with it.

Three things reach a network, and you start every one of them yourself: opening
a model from a URL you typed, pressing "Report a problem" (which opens a
pre-filled form in your browser, sending nothing until you press submit in
GitHub), and connecting an AI assistant over the local agent port. Each is
described below.

This document is longer than that paragraph because the law requires a
controller to say specific things in a specific way. The paragraph is still
the accurate summary.

## 1. Who is responsible

The controller for the processing described here is:

**Dmitrii Zolotov**, a natural person acting as an independent developer,
resident in the European Union.

- Privacy enquiries and data subject requests: **privacy@pleion.dev**
- Other legal enquiries: legal@pleion.dev

We have not appointed a Data Protection Officer: the scale and nature of the
processing described below does not meet the threshold in Article 37 GDPR.

## 2. What the Modeller processes, and what it does not

### 2.1 What stays on your device

| What | Where it is kept | Why |
|---|---|---|
| Projects, models, meshes, materials, textures | Where you saved them, or the application's own container | So the work exists |
| Autosaves and the emergency save written after a crash | The application's own container (`path_provider` on desktop and mobile; `localStorage` in the browser) | So a crash or a power cut does not cost a session |
| Settings: keymap preset, camera scheme, panel widths, language, recent files | The same place | So the Modeller opens the way you left it |
| The local command journal (what you did, in order) | The same place, beside the project | So undo works and a crash can be reconstructed |

**None of it is transmitted to us.** There is no code path in the Modeller that
uploads a document, a setting, a crash report, an identifier or a usage event.
This is checkable rather than a promise: the source is public, and the only
outbound network calls in the application are the three named in section 2.2.

We therefore hold **no personal data about users of the Modeller at all**, and
there is nothing for us to disclose, retain, or hand over in response to a legal
request, because we never receive it.

### 2.2 The three times a network is touched

**Opening a model from a URL.** If you paste a link to a model file, the
Modeller fetches it. The request goes to the server you named, and that server
sees what any web server sees: your IP address, the time, and the file you
asked for. We are not that server and receive nothing.

**"Report a problem".** This opens your browser at a GitHub issue form with the
environment fields pre-filled (Flutter version, platform). **Nothing is sent
when you press the button** — the report exists only once you review it and
submit it on GitHub, at which point GitHub's own privacy policy applies and
what you typed becomes a public issue. Crash details, including an excerpt of
your command journal, are shown to you first and go only where you choose to
paste them.

**The local agent port.** Started only when you run the Modeller with
`--mcp-port`, this binds a server on your own machine (localhost) so an AI
assistant can read and edit the open document. We receive nothing from it. If
the assistant you connect sends its context to a model provider's servers, your
document content goes to that provider under their privacy policy — that
transfer is between you and them, and is worth understanding before you connect
an assistant to a document you care about.

### 2.3 What the Modeller never does

No analytics or product telemetry. No crash reporting service. No advertising,
ad identifiers, or ad SDKs. No fingerprinting. No profiling and no automated
decision-making in the sense of Article 22 GDPR. No sale or sharing of personal
information as those terms are used in US state privacy law. No third-party SDK
that contacts a server on its own.

## 3. The website

The website at flutter3d.pleion.dev is a set of static pages. It sets **no
cookies**, embeds no analytics, and loads no third-party trackers or fonts from
a third-party CDN. See the Cookie and Local Storage Notice for the detail.

Like every website, it is delivered by a hosting provider whose servers keep
standard access logs — IP address, timestamp, requested URL, user agent, and
response status — for the purposes of delivering the page, keeping the service
available, and defending against abuse and attack.

- **Legal basis:** Article 6(1)(f) GDPR, our legitimate interest in operating
  and securing the site. IP addresses in these logs are personal data.
- **Retention:** as short as the provider's own rotation allows, and in no case
  longer than 30 days, after which the logs are deleted or aggregated beyond
  re-identification.
- **Processor:** the hosting provider acts as our processor under Article 28
  GDPR. Its identity is stated on the published version of this page.

The web build of the Modeller is served from the same site and uses the
browser's `localStorage` for your own documents and settings, as described in
the Cookie and Local Storage Notice.

## 4. If you write to us

If you send an email to privacy@pleion.dev or legal@pleion.dev, or open a
GitHub issue, we process what you sent — your address, your name if you gave
one, and the content of the message — in order to answer.

- **Legal basis:** Article 6(1)(b) GDPR where your message concerns the
  agreement between us; Article 6(1)(f) GDPR, our legitimate interest in
  answering correspondence, otherwise; Article 6(1)(c) GDPR where answering is
  a legal obligation, as with a data subject request.
- **Retention:** as long as the matter is open, and then for as long as we may
  need to show that it was handled properly — normally no more than three
  years, and longer only where a limitation period requires it.
- **Recipients:** our email provider, as a processor. Correspondence in a
  GitHub issue is public by its nature and is processed by GitHub, Inc. under
  its own policy.

## 5. Transfers outside the European Economic Area

We do not transfer personal data outside the EEA ourselves, because for the
Modeller there is no personal data to transfer.

Where you choose to use a service that is outside the EEA — submitting a GitHub
issue, fetching a model from a server abroad, connecting an AI assistant — that
transfer is yours to make and is governed by that service's own terms and
safeguards. Where a processor we engage for the website or for email is outside
the EEA, the transfer rests on the European Commission's Standard Contractual
Clauses or on an adequacy decision, and we will name the mechanism on request.

## 6. Children

The Modeller is a professional 3D tool and is **not directed at children**. We
do not knowingly collect personal data from anyone, and therefore do not
knowingly collect it from a child.

- In the European Union, Article 8 GDPR sets the age for a child's own consent
  to information society services at 16, or as low as 13 where a member state
  has legislated for it. We ask that users under that age use the Modeller only
  with a parent or guardian's involvement.
- In the United States, COPPA applies to services directed at children under
  13. The Modeller is not such a service and collects nothing from anyone.
- For store rating purposes the Modeller contains no user-generated content
  shared between users, no chat, no ads, no in-app purchases and no location
  features. It is rated for general audiences; the applicable answers we give
  to Apple's and Google's questionnaires are listed in `legal/README.md` in the
  source repository so that they can be checked against this document.

If you believe a child has sent us personal data — by writing to us, for
instance — tell us at privacy@pleion.dev and we will delete it.

## 7. Your rights

Under the GDPR you have the right to request access to your personal data,
rectification, erasure, restriction of processing, portability, and to object
to processing based on our legitimate interest. You may withdraw consent at any
time where processing rests on consent, without affecting the lawfulness of
what was done before.

In practice, for a Modeller user, **these rights have almost nothing to attach
to** — we hold nothing about you. They matter for correspondence and for
website logs, and we will honour them there. We answer within one month, and
tell you if we need the extension Article 12(3) allows.

**How to erase what the Modeller keeps on your device**, which is not something
you need us for:

- **macOS, Windows, Linux:** delete the application's support directory, or use
  the Modeller's own Settings → "Clear local data".
- **iOS, Android:** delete the app, or clear its storage in the system
  settings.
- **In a browser:** clear site data for flutter3d.pleion.dev, which removes the
  `flutter3d/*` keys from `localStorage`. This deletes any project you had only
  in the browser, so export first.

You also have the right to lodge a complaint with a supervisory authority — in
the EU, the authority of your habitual residence, place of work, or of the
place where you believe an infringement occurred. The list is at
<https://edpb.europa.eu/about-edpb/about-edpb/members_en>.

## 8. Security

The Modeller stores your work through the operating system's own facilities and
inherits the protection of your device: file permissions, full-disk encryption
where you have it on, and the browser's same-origin policy for the web build.
We do not add a second layer of our own, and we do not hold a copy from which
your data could leak.

What you can do to protect your work: keep backups, turn on disk encryption,
and think before connecting an AI assistant to a document under NDA.

Security reports about the software itself go to the process in `SECURITY.md`
in the source repository.

## 9. Changes

We will update this policy when the software or the law changes. The version
number and effective date at the top say which version you are reading; every
version is kept in the public repository under `legal/`, so the changes between
any two of them are readable in full. Where a change materially affects you, we
will say so on the website and in the application's release notes rather than
changing the text quietly.

## 10. Contact

- Privacy and data subject requests: **privacy@pleion.dev**
- Other legal enquiries: legal@pleion.dev
- Source and issues: <https://github.com/pleiondev/flutter3d>
