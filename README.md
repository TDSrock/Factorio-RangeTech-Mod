# Range Tech

Range research for **every** turret, in categories. Built to work with quality turrets and
modded turrets, which is where similar mods tend to fall short.

Factorio 2.0, Space Age supported (optional).

## What it does

Every turret is put into exactly one category, based on its **ammo type**. If the ammo type is
unknown, the main **damage type** it deals is used. Rules, first match wins:

1. Your override setting.
2. Artillery turrets are always ignored.
3. Explicit rules for specific modded turrets (e.g. repair turrets are ignored, their reach is not
   a normal turret range).
4. The ammo category: exact names first, then name fragments, so modded ammo categories such as
   `my-mod-rocket` or `frost-shell` are recognised too. Generic vanilla categories that mods reuse
   for other weapons (`electric` for lasers, `flamethrower` for acid throwers) are refined by the
   damage type, which is read from the turret's projectiles, streams and beams.
5. The main damage type, again exact names first, then fragments (cold/frost/cryo, acid/poison,
   fire, laser, electric, ...).
6. Otherwise `other`.

| Category | Examples (vanilla / Space Age) |
| --- | --- |
| Bullet | gun turret |
| Shotgun | shotgun-shell turrets from mods |
| Cannon | cannon-shell turrets from mods |
| Railgun | railgun turret |
| Grenade | grenade turrets from mods |
| Missile | rocket turret |
| Flame | flamethrower turret |
| Laser | laser turret |
| Electric | tesla turret |
| Cold | modded turrets with cold/frost/cryo ammo or damage |
| Acid | modded turrets with acid/poison ammo or damage (acid throwers) |
| Support | medic turrets that heal instead of damage |
| Other | modded turrets that fit none of the above |
| Ignored | artillery turrets, and turrets that are not compatible with this mod (see below). The mod does nothing with these |

Categories without any turret get no research. The rules and name fragments live in
`lib/categories.lua`; supporting a new mod usually means adding one line there. Every decision and
its reason is written to `factorio-current.log` (lines starting with `[range-tech]`), including
warnings for turrets that ended up in `other` because their ammo or damage type is unknown.

Each category (except Ignored) gets its own chain of range researches:

- The number of levels is a setting (default 5).
- Level 1 needs the science packs of the category's easiest turret to unlock. Later levels add
  packs gradually until the last level needs the packs of the hardest turret in the category.
- Every level costs more than the previous one (default: 100 packs, growing 1.5x per level).
- Each level adds a flat number of tiles or a percentage of the turret's base range.

## Modded turrets

Turrets that this mod cannot work with are put in **Ignored** on purpose, with the reason stored
and shown by `/rangetech` and in the log. Currently:

- **Additional Turrets** (original and revived): the heavy howitzers (`at_A1_*`, `at_A2_*`), the
  cannon/rocket turret (`at_CR_*`) and the laser/capsule turret (`at_LC_*`). Their script expands
  one placed turret into several helper entities and fires the weapon itself, so a longer
  prototype range and this mod's entity swapping do not apply. *Not compatible.*
- **Repair turrets**: their reach is not a normal turret range.
- **Universal Turret**: it swaps the turret's weapon type at runtime.

Supported as normal turrets: the other Additional Turrets turrets (cannon, rocket, gatling,
acid thrower, electron beam, advanced laser) and Rampant Arsenal (laser turrets are recognised as
Laser, acid turrets as Acid, medic turrets as Support, capsule turrets as Grenade).

## Settings (startup)

- **Preset**: `Percent` (+10% of base range per level, all categories), `Flat tiles` (+3 tiles per
  level, all categories) or `Custom`. The individual "Custom" settings (levels, bonus type, bonus
  amount per category, plus cost base, growth and research time) only apply to `Custom`.
- **Category overrides**: move turrets between categories, e.g. `gun-turret=laser;
  some-modded-turret=ignored`. Categories: `bullet`, `shotgun`, `cannon`, `railgun`, `grenade`, `missile`, `flame`, `laser`,
  `electric`, `cold`, `acid`, `other`, `ignored`. Artillery turrets cannot be reassigned.

Factorio cannot build a per-turret settings list (the settings stage runs before any turret
exists), so overrides are one text setting. To see turret names and categories use the
`/rangetech` command in game, or search `factorio-current.log` for `[range-tech]`.

## Quality

Quality is a property of the placed turret, not of the prototype. When research changes a
turret, the replacement keeps its quality, ammo, fluids, health, kill counter and target
priorities. The quality range bonus (+10% per quality level in the base game) applies on top of
the researched range.

## Blueprints, ghosts and construction bots

The longer-range copies are an internal detail. Everything you carry around is the normal turret:

- Items, mining and pipette always give the normal turret item.
- **Blueprints** (copy, cut, new blueprints, re-selected contents, library records) are rewritten
  to the normal turret names when they are made. They work with or without this mod, and
  removing the mod never breaks a blueprint.
- **Ghosts** from a blueprint are the normal turret, so construction bots build the normal turret
  item. The moment it is built it is swapped for the copy that matches your research.
- A turret that is destroyed leaves a ghost of its copy. It looks identical, bots build it from
  the normal item, and it is rewritten to the normal name as soon as you blueprint it.

Only a turret that is standing in the world is a copy (it has to be: the range is part of the
prototype). Mods and tools that look for turrets by name will see the copy's name.

## Removing the mod

Copies that are standing in a save disappear when the mod is removed. Before removing it, run
`/range-tech-prep-uninstall` (admins only). It turns every turret back into its normal version and
pauses range upgrades, also after saving and loading (players who join get a reminder).
`/range-tech-resume` turns upgrades back on and upgrades every turret that is not at its research
level yet.

## Commands

- `/range-tech` (or `/rangetech`): shows your research level per category and writes the full
  details to `script-output/range-tech-report.txt` in your Factorio user data folder: settings,
  every category with its turrets, base range and range per level, why each turret is in its
  category, why ignored turrets are ignored, the research plan (units, time, science packs per
  level) and warnings.
- `/range-tech-prep-uninstall`: see above (admins only).
- `/range-tech-resume`: see above (admins only).

## Turrets placed by scripts

Turrets built normally or by bots are upgraded instantly. A script that creates a turret without
raising a build event (for example `surface.create_entity` without `raise_built = true`) cannot be
hooked, so a periodic sweep upgrades the normal turrets of researched categories. The interval is
the runtime setting "Upgrade sweep interval" (default 10 seconds, 0 = off). Scripts that pass
`raise_built = true` are upgraded immediately.

## How it works / limitations

Factorio has no research effect for turret range (only for artillery), no aura that affects
range, and scripts cannot make a turret shoot beyond its prototype range. So this mod creates
hidden copies of each turret with a longer range (one per level) and swaps turrets for the right
copy when research completes or a turret is built.

- Copies are made in `data-final-fixes`. A mod that changes turrets *after* this mod in the same
  stage will not be reflected in the copies. If that happens, adjust load order.
- Changing the settings or the turret mods in an existing save replaces or removes the copies;
  turrets are re-checked on configuration change.
- Rewriting a blueprint rebuilds it. Wires to entities *outside* a cut selection are not kept for
  the turrets in it, and other mods that read the blueprint mapping after this mod may find it
  empty.
- Technology icons are reused from the technologies that unlock the turrets.

## Technology icons

Every range research shows the icon of the technology that unlocks its turrets, with the small
"range" symbol that vanilla puts on the artillery range research.

**Validation.** Lua cannot open image files during loading, so the real pixel size of a mod's
PNG cannot be checked, and the game only notices a size mismatch after all mods have loaded.
What the mod does instead:

- It only reuses another mod's icon when every layer looks sound (a `.png` path, a sensible
  `icon_size` that is copied onto each layer, a valid scale), and it reuses it exactly as that
  mod defines it for its own technology. Anything doubtful falls back to a vanilla icon.
- The startup setting **Technology icons** can be switched from `Auto` to `Built-in`, which only
  ever uses vanilla icons. Use that if a mod pack reports a sprite or icon error that mentions
  `rangetech` technologies.
- Images that belong to this mod are checked at build time (CI runs `scripts/validate_assets.sh`),
  where the real file can be inspected.

**Range symbol.** The symbol is read from vanilla itself (the technology with the
`artillery-range` effect), so no path is hardcoded. If it is not found, researches simply have no
symbol. To use your own image:

1. Draw a PNG named `graphics/range-overlay.png`: 128 x 128 pixels, 32-bit RGBA, transparent
   background. A simple range glyph (for example a ring or crosshair with arrows pointing outwards)
   in light colours with a thin dark outline so it stays readable at small size, with a few pixels
   of margin. No text.
2. In `lib/icons.lua` set `M.CUSTOM_OVERLAY = "__range-tech__/graphics/range-overlay.png"`.
3. Position and size are taken from the vanilla symbol layer (bottom-right corner), so the image
   only needs the right canvas size. CI fails if the file is missing, not 128 x 128 or has no alpha
   channel.

## Requirements

- Factorio 2.0+
- Space Age (optional)

## Installation

Download the latest release zip from the
[Releases page](../../releases) and place it in your Factorio `mods`
directory, then enable it in the mod list. Alternatively, once published,
install it directly through the in-game mod portal.

---

## Repo setup (one time)

1. Run `scripts/configure_repo.sh` once (needs the GitHub CLI, logged in
   with admin rights). It makes squash merge the only merge method, uses
   the PR title as the commit message and deletes merged branches.
2. Add a `FACTORIO_API_KEY` secret in the repo's
   Settings -> Secrets and variables -> Actions (create the key at
   factorio.com/profile).
3. Add `thumbnail.png` (144x144) to the repo root.
4. The `FACTORIO_API_KEY` needs the "ModPortal: Upload Mods" usage and, so the
   very first release can create the mod listing, also "ModPortal: Publish
   Mods" (both are chosen when creating the key on factorio.com/profile).
5. Every PR needs a `Changelog:` section in its description (see "PR
   Changelog" below).

---

## Development / release process

Trunk-based: there is only `master`. Work happens on short-lived branches
that are squash-merged into `master` through a PR. There is no `dev` or
`staging`; to test a change, download the zip artifact that CI attaches to
the PR and load it in Factorio. `master` is always the latest work. A
release is a tag you create deliberately with the **Release** button.

### CI (PRs into `master`, pushes to `master`)

Validates `info.json`, `changelog.txt` (against the
[official changelog format](https://lua-api.factorio.com/latest/auxiliary/changelog-format.html))
and the mod's own images, and does a dry-run package build. Does not publish
anything. The built zip is attached as a workflow artifact for inspection.

### PR reminders (PRs into `master`) -- non-blocking

The **PR Reminders** workflow posts a single comment on every PR (and keeps
updating it on new pushes) listing optional files that are still missing,
with links to the relevant docs. Currently checked:

- `thumbnail.png` (144x144)
- `locale/en/locale.cfg`
- leftover template placeholders in `info.json`
- the template's "Using this template" section still in `README.md`
- the optional `portal-description.md`
- the optional `graphics/range-overlay.png` range symbol

It never fails the build. If everything is in place and no comment exists
yet, it stays quiet. PRs from forks cannot receive comments; the same
reminder is then shown in the run's summary instead.

To change what is checked, edit `scripts/check_optional_files.sh` (the
workflow itself is `.github/workflows/pr-reminders.yml`).

### PR Changelog (PRs into `master`) -- required

Every pull request description must contain a line that reads `Changelog:`,
followed by the changes of that PR. The **PR Changelog** workflow fails when
the section is missing or invalid, keeps one comment on the PR up to date
(with a preview of the exact lines that will end up in `changelog.txt`), and
re-runs when the description is edited. A PR template pre-fills the section.
To make the check required, add it to the branch protection / ruleset of
`master`.

```
Changelog:
Features:
- A single line entry.
- A multi-line entry continues on the next line
  without a new dash.
Bugfixes:
- Fixed something that was broken.
```

- Categories are the ones the game recognises: Major Features, Features,
  Minor Features, Graphics, Sounds, Optimizations, Balancing, Combat
  Balancing, Circuit Network, Changes, Bugfixes, Modding, Scripting, Gui,
  Control, Translation, Debug, Ease of use, Info, Locale, Compatibility.
  Matching ignores case. Use as many as the change needs.
- Every entry sits under a category. Use a multi-line entry when one line
  does not explain the change.
- Write `Changelog: none` for changes players do not care about (CI, docs,
  refactoring). It is a deliberate choice, so a PR cannot forget it.
- Markdown decoration (`## Changelog:`, `**Features:**`, `*` bullets) is
  accepted, and HTML comments are ignored.

The parser writes the entries in the exact format of the game: 99 dashes, the
version, the date, categories with 2 spaces, entries with 4 spaces and `- `,
continuation lines with 6 spaces, no duplicates, no tabs or trailing
whitespace. You never format that yourself.

### Changelog (built from the pull requests)

When you run the Release workflow, `scripts/changelog.py` collects the
`Changelog:` sections of all PRs merged since the last `v*` tag (read through
the GitHub API, falling back to the commit message, which holds the PR
description for squash merges) and writes the new version section at the top
of `changelog.txt`. Identical entries from different PRs are merged. The
**date is filled in automatically**, in the style of the official example
(`DD. MM. YYYY`). The same entries become the notes of the GitHub release.

The release **fails before anything is committed or tagged** if no entries
were found or the result would not follow the format. PRs that were merged
without a `Changelog:` section are listed as warnings.

**Manual override:** add a section at the top of `changelog.txt` for the
version the release will become (you choose the bump when you click Release,
so it is only known then). If the top entry already has that version, the
generator leaves it untouched. If your top entry is a *different, newer*
version than the release (e.g. you wrote `0.1.0` but the bump produced
`0.0.5`), generation is refused so the file stays in order. Every version
needs a `Date:` line and at least one entry.

**Internal versions:** every version gets its own changelog entry, whether or
not it ever reaches the mod portal. Entries and published versions don't
have to line up 1:1. When you publish a later version, the portal simply
shows the entries of the internal versions in between as well.

`python3 scripts/changelog.py` has four commands: `check-pr`, `validate`,
`release` and `notes` (see `--help`); it needs nothing but Python 3.

The template starts at `0.0.0` in `info.json` with a manual `0.0.1` entry, so
the first release (bump `release`) lands on `0.0.1` and keeps that entry.

### Release -- manual button

A release only ever happens when you trigger the **Release** workflow
yourself: Actions tab -> Release -> **Run workflow**, from `master`. Inputs:

- **bump**: `release` (default), `minor` or `major`. Resets the numbers to
  the right of it to 0.
- **internal**: tick this for a version you keep to yourself. The GitHub
  Release is marked as a pre-release, and "Publish to Mod Portal" skips
  pre-releases when it picks the latest release.

The workflow then:

1. Stops if there are no commits since the last tag (guards against a double
   click).
2. Bumps the version in `info.json`.
3. Generates the changelog entry from the PR changelog sections (unless a
   manual entry exists), commits `info.json` and `changelog.txt` back to
   `master` and tags it `vX.Y.Z`. It stops before this step if the changelog
   cannot be generated.
4. Packages the mod into `<mod-name>_X.Y.Z.zip` with the correct
   mod-portal folder structure.
5. Creates a GitHub Release with that zip attached and the changelog entry
   as the release notes.

The workflow pushes the version-bump commit directly to `master`. If you add
branch protection that requires pull requests on `master`, that push will be
blocked unless you give it a bypass.

This does **not** touch the live mod portal listing -- it only prepares
a GitHub Release you can inspect first.

### Publish to Mod Portal -- manual button

A separate workflow, **"Publish to Mod Portal"**, only ever runs when you
trigger it yourself: go to the repo's **Actions** tab, select it in the
left sidebar, and click **Run workflow**. You can optionally type a
specific tag (e.g. `v0.1.4`) to publish; leave it blank to publish
the latest GitHub Release that is not marked as a pre-release (so internal
versions are skipped).

That workflow downloads the chosen release's zip and publishes it to the
Factorio Mod Portal. Nothing ever reaches the live mod portal without this
manual step.

It works in two steps:

1. **The easy way:** add a release to the existing mod through the
   [Mod upload API](https://wiki.factorio.com/Mod_upload_API).
2. **If the mod does not exist on the portal yet** (the portal answers
   `UnknownMod`), publish it as a **new mod** through the
   [Mod publish API](https://wiki.factorio.com/Mod_publish_API). Only that
   one specific answer triggers this, so a bad key or a version that already
   exists never creates a listing by accident. The checkbox
   `new_mod_fallback` in the Run workflow form (on by default) turns this step
   off. A workflow cannot ask a question halfway through, so that form is the
   prompt: the click on **Run workflow** is the confirmation.

For a new mod the form also takes an optional `category`, `license` and
`source_url` (default: this repository). The portal description is the
contents of `portal-description.md` in the repo root if that file exists (it
is not packaged into the mod), otherwise the `description` from `info.json`.
Title, tags, FAQ and images can be finished on the mod's portal page
afterwards.
