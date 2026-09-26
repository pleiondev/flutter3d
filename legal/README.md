# Legal documents

The source of truth for every legal text the Modeller and the site publish.

The documents are in English only, on purpose. The application's interface is
translated into Russian and will be translated further; these documents are
not. A translated legal text is a second legal text: it can drift from the
original, and when the two disagree a reader has no way of knowing which one
binds. So there is one authentic version, in the language the licence, the
repository and the rest of the documentation are already written in. The
application shows these texts in English whatever its interface language is
set to, and says so where it shows them.

These files are the documents, not legal advice. They were drafted against
what the software actually does, checked against the source rather than copied
from a template, and no lawyer has reviewed them. Before the first store
submission, have one read them. The sections most worth an hour of somebody
qualified are the EULA's limitation of liability, the privacy policy's legal
bases, and the DMCA procedure in the content policy.

## What is here

| Document | Covers | Where it is published |
|---|---|---|
| `eula.md` | The licence to use the Modeller, the MIT licence it rests on, warranty, liability, Apple's required terms | Site `/legal/eula/`; in the app under Help → Legal |
| `privacy.md` | What the Modeller processes (almost nothing), the three network calls, website logs, GDPR rights, children | Site `/legal/privacy/`; in the app; the URL App Store Connect and Play Console require |
| `cookies.md` | Why there is no cookie banner, what `localStorage` holds and why it is strictly necessary | Site `/legal/cookies/`; linked from the site footer |
| `terms.md` | Use of the website itself: documentation, gallery, demos | Site `/legal/terms/` |
| `content-policy.md` | What is not welcome in our spaces, and the copyright notice and counter-notice procedure | Site `/legal/content-policy/` |
| `export-compliance.md` | Public-availability classification, "no encryption", sanctions | Site `/legal/export-compliance/`; the basis for the App Store export answers |

The third-party licence list is not a document here: it is generated from what
is actually linked into the build, and the application shows it under Help →
Legal → Third-party licences.

## Before publishing: the open items

Everything below is a fact about the world that the documents assert and that
somebody has to make true. None of it can be settled from the source tree.

- [ ] `privacy@pleion.dev` and `legal@pleion.dev` have to exist and reach a
      mailbox somebody reads. Every document names them, and a GDPR request
      sent to an address that bounces is a breach of Article 12(3) on its own.
- [ ] Name the hosting provider in section 3 of the privacy policy, and have
      its data processing agreement on file (Article 28 GDPR). The text
      currently says the identity "is stated on the published version of this
      page", which is a placeholder for a real name.
- [ ] Confirm the log retention the provider actually applies. The policy
      promises "in no case longer than 30 days"; if the provider keeps logs
      longer, the number in the policy changes, not the provider's behaviour.
- [ ] Name the country of residence where the EULA and the terms say "the
      Licensor's country of residence in the European Union", once it is
      settled. A governing-law clause that names no country is weaker than one
      that does.
- [ ] Decide whether an imprint is required where you live. Germany
      (§ 5 DDG), Austria and a few other member states require an
      `/impressum/` page with a postal address for a site that is more than
      purely private. A personal open-source documentation site is usually
      below that threshold, but it depends on where the operator sits.
- [ ] Publish the pages before the first store submission. Both stores check
      that the privacy policy URL resolves.

## The store questionnaire answers

They are kept here so they can be checked against the privacy policy rather
than remembered, and so the next submission does not re-derive them.

**Apple App Privacy ("nutrition label").** *Data Not Collected.* No data
types are collected: no contact info, no identifiers, no usage data, no
diagnostics. The app has no account, no analytics SDK and no crash reporting
service; the "Report a problem" button opens a browser and sends nothing
itself.

**Apple export compliance.** The answer to "Does your app use encryption?" is
No. The basis is in `export-compliance.md` § 2.

**Apple age rating.** 4+. No user-generated content shared between users, no
unrestricted web access, no ads, no in-app purchases, no gambling, no
contests, no location.

**Google Play Data safety.** No data collected, no data shared. Data is not
encrypted in transit because no data is transmitted. Users cannot request
deletion of collected data because none is collected; the app's own "Clear
local data" removes what is on the device.

**Google Play content rating (IARC).** Utility/productivity, general
audience, no interactive elements, no data sharing, no location sharing, no
user-to-user communication.

**Google Play ads.** The app contains no ads.

**Google Play target audience.** 13+ (and 16+ in the EU per Article 8 GDPR
where a member state has not lowered it). The app is not designed for
children, so the Families policy and its SDK requirements do not apply.

## Changing a document

One document, one commit. Bump the `version` and `effective` lines in the front
matter, and say in the commit message what changed for a reader, not what
changed in the file. The documents point at the repository's history as their
change log, so a rewrite that loses that history breaks that promise.
