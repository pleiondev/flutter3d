# 0.7.0 release-day checklist

`doc/boundary-0.7.0.md` is the decision record — why the tree is shaped this
way, which packages move, what breaks for an importer. This is the doer's
list for the day `rel-16`'s gate opens, in order. Nothing here argues for
anything the other document does not already argue for; this only says
*when*.

- [ ] **Publish the modeller** to models.pleion.dev, and let the cohort of
      five to ten people walk its tutorial (`rel-16`). Nothing below starts
      before the owner reads that cohort's run as a pass.
- [ ] **Publish the nine tiers** to pub.dev in the order `ARCHITECTURE.md`
      §16 ("The order, used on the day") gives. Run
      `dart run tool/structure.dart` between tiers if a publish takes more
      than a sitting — `the publishing order names every package` is the
      rule that would catch a tier gone out of order.
- [ ] **Mark the four discontinued names** — `flutter3d_backend`,
      `flutter3d_screens`, `flutter3d_session`, `flutter3d_bridge` —
      `discontinued` on pub.dev with the `replaced_by` each one names in
      `doc/boundary-0.7.0.md`'s "Names that end" table.
- [ ] **Tag `v0.7.0`** on the commit that was actually published, not the
      commit that happened to be at the tip when publishing started.
- [ ] **Bump the three tutorial pins.** `site/content/platformer/tutorial.md`,
      `site/content/shooter/tutorial.md` and `site/content/racing/tutorial.md`
      still name `^0.6.0` in their pubspec snippets — deliberately, until
      this point (see `doc/boundary-0.7.0.md`'s deploy-obligation note).
- [ ] **Retire the quickstart warning.** `site/content/quickstart.md` carries
      a `<div class="warn">` above its pubspec example, added only because
      `^0.7.0` resolved nowhere on pub.dev before this day. Once it does,
      that paragraph describes a state that no longer holds — remove it, or
      rewrite it past tense if the history is worth keeping on the page.
- [ ] **Re-deploy the site** once the two steps above land, so a reader
      following the quickstart the same day gets the `^0.7.0` the page has
      meant all along, not a warning about a gap that just closed.

## What is not on this list

`rel-06` itself — the decision to publish at all — is not a checklist item;
it is the gate the first line above is standing in front of. Nothing here
should be actioned before that gate opens, and nothing here is optional once
it has.
