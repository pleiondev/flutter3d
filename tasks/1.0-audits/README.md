# The audits behind the readiness review

The full notes of the read-only audits that `1.0-readiness-review.md`
and `1.0-product-review.md` condense, as the agents handed them back on
2026-10-09. They describe the
working tree of that day: paths and line numbers are as they were then,
and nothing here is a decision. The decisions are in the review's §6 and
the order of work in `1.0-rc1-plan.md`.

They are kept so that the waves can start from the line-level findings
without auditing again, and so that a later reader can see what was
measured against what.

| File | What it covers | Review section |
|---|---|---|
| `01-plans-vs-tree.md` | Every item of the 1.0 plans against the tree | §2 (throughout), §1 |
| `02-documents.md` | README, ARCHITECTURE, ROADMAP, SUPPORT, SECURITY, CONTRACTS, the site, the CHANGELOGs | §2.8 |
| `03-public-api.md` | The public surface under semver: records, sealed sets, modifiers, naming | §2.4 |
| `04-physical-constants.md` | Hardcoded physics and the materials catalog | §2.6 |
| `05-boundaries.md` | Package layers, re-exports, dependencies, globals | §2.5 |
| `06-renderer.md` | Reversed depth, the physical camera, pacing, TAA, origin shift, resources | §2.1 |
| `07-simulation-formats-tools.md` | Determinism, snapshots, replays, codecs, `.f3d`, convert, migration, network, audio | §2.1, §2.2 |
| `08-tests-ci-publish.md` | The fast suites, CI coverage, goldens and tapes, `pub publish` | §2.3 |
| `09-engine-concerns.md` | Hot path, precision, threads, memory, shaders, platforms, security, crutches | §2.7, §2.2 |
| `10-pipeline-extensibility.md` | What a plugin can reach at every stage of the frame | §2.9 |
| `11-hal-outside-backends.md` | Writing a backend outside the repository | §2.10 |
| `12-engine-patterns.md` | Public API patterns and regrets of twelve other engines | §2.11 |
| `13-surface-inventory.md` | flutter3d's surface along the comparison axes | §2.11 |
| `14-feature-inventory.md` | Every feature, area by area, with status | §2.12 |
| `15-application-requirements.md` | What stable engines ship and what applications ask for | §2.12 |
| `16-reader-beginner.md` | The surface read by a Flutter developer new to 3D | §6, before decision 50 |
| `17-reader-veteran.md` | The surface read by a senior engine programmer | §6, before decision 50 |
| `18-flutter-scene.md` | Against flutter_scene 0.24.3 | §2.13 |
| `19-post-processing-parity.md` | The post stack, effect by effect, against flutter_scene 0.24.3 | §2.13 |

The five below fed `1.0-product-review.md`, the product review of the
target state, the same evening.

| File | What it covers | Product review section |
|---|---|---|
| `20-audiences.md` | The offer for games, twins and laboratories, and the conflicts between them | §2, §6 |
| `21-adoption.md` | The first hour, the manual steps, the documentation plan, versions, migration, the editor | §3 |
| `22-release-definition.md` | What the 1.0 label promises, the gates, the schedule, the freeze risk, platforms, legal | §4, §8.1 |
| `23-twins-labs.md` | What a twin pilot and a school pilot need against the target state; the catalog | §2, §8.2 |
| `24-ecosystem-ops.md` | Publishing, CI, community, the site, MCP, comparison claims, the launch | §5, §8.3 |

The notes are in Russian, as the agents wrote them. Where a note names a
scratchpad path, that scratchpad belonged to the session and is gone.
