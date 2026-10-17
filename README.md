# My Mod Title

Short description of what this mod does.

## Requirements

- Factorio 2.0+
- Space Age (optional, remove or change if your mod needs it as a hard dependency)

## Installation

Download the latest release zip from the
[Releases page](../../releases) and place it in your Factorio `mods`
directory, then enable it in the mod list. Alternatively, once published,
install it directly through the in-game mod portal.

---

## Using this template

1. Create a new repo from this template.
2. In `info.json`, set `name` (lowercase, dashes, no spaces), `title`,
   `description`, `author` and `dependencies`.
3. Add your Lua code. Common entry points:
   - `settings.lua` / `settings-updates.lua` / `settings-final-fixes.lua`
   - `data.lua` / `data-updates.lua` / `data-final-fixes.lua`
   - `control.lua` (runtime scripting)
4. Name PRs `type: description` for players (see "Changelog" below);
   `changelog.txt` is generated from the merge message on release. Edit it
   by hand only when you want to override that.
5. Replace this README.
6. Optionally add `thumbnail.png` (144x144) for the mod portal and
   `locale/en/locale.cfg` for localised strings.
7. Run `scripts/configure_repo.sh` once (needs the GitHub CLI, logged in
   with admin rights). It makes squash merge the only merge method, uses
   the PR title as the commit message and deletes merged branches. These
   settings are not copied from a template, so do this for every new repo.
8. Add a `FACTORIO_API_KEY` secret in the repo's
   Settings -> Secrets and variables -> Actions (create the key at
   factorio.com/profile).
9. Submit the very first release to the mod portal manually; the Upload API
   cannot create a new mod listing.

### Dependencies cheat sheet

| Syntax            | Meaning                                  |
| ----------------- | ---------------------------------------- |
| `"some-mod"`      | Hard dependency                          |
| `"? some-mod"`    | Optional dependency (loads after it)     |
| `"(?) some-mod"`  | Hidden optional dependency               |
| `"! some-mod"`    | Incompatible                             |
| `"~ some-mod"`    | Dependency without affecting load order  |

---

## Development / release process

Trunk-based: there is only `master`. Work happens on short-lived branches
that are squash-merged into `master` through a PR. There is no `dev` or
`staging`; to test a change, download the zip artifact that CI attaches to
the PR and load it in Factorio. `master` is always the latest work. A
release is a tag you create deliberately with the **Release** button.

### CI (PRs into `master`, pushes to `master`)

Validates `info.json` and does a dry-run package build. Does not publish
anything. The built zip is attached as a workflow artifact for inspection.

### PR reminders (PRs into `master`) -- non-blocking

The **PR Reminders** workflow posts a single comment on every PR (and keeps
updating it on new pushes) listing optional files that are still missing,
with links to the relevant docs. Currently checked:

- `thumbnail.png` (144x144)
- `locale/en/locale.cfg`
- leftover template placeholders in `info.json`
- the template's "Using this template" section still in `README.md`
- the PR title: a changelog preview, or a warning if it has no `type:` prefix
  (see "Changelog" below), or confirmation of a manual changelog entry

It never fails the build. If everything is in place and no comment exists
yet, it stays quiet. PRs from forks cannot receive comments; the same
reminder is then shown in the run's summary instead.

To change what is checked, edit `scripts/check_optional_files.sh` (the
workflow itself is `.github/workflows/pr-reminders.yml`).

### Changelog (auto-generated, manual override possible)

When you run the Release workflow, `changelog.txt` is generated from the
commit messages since the last `v*` tag, unless you already wrote an entry
yourself.

**The merge message is what counts.** The pipeline reads the commit subjects
on `master`. Merging is squash-only (set up by `scripts/configure_repo.sh`),
and the squash commit subject is the **PR title**, so name PRs
`type: description`, written for players. The commits inside the PR are not
used.

**Prefixes** (optional scope, e.g. `fix(gui): ...`):

| Prefix                                                       | Changelog category        |
| ------------------------------------------------------------ | ------------------------- |
| `feat:`                                                      | Features                  |
| `fix:`                                                       | Bugfixes                  |
| `perf:`                                                      | Optimizations             |
| `balance:`                                                   | Balancing                 |
| `info:`                                                      | Info                      |
| `chore:` `ci:` `docs:` `test:` `build:` `style:` `refactor:` | kept out of the changelog |
| no prefix / unknown prefix                                   | kept out of the changelog |

Also skipped: merge commits, the pipeline's own version-bump commits, and
any commit with `[skip changelog]` in the subject. A trailing `(#123)` PR
reference is stripped from the text.

**Manual override:** add an entry at the top of `changelog.txt` for the
version the release will become (you choose the bump when you click Release,
so it is only known then). If the top entry already has that version, the
generator leaves it untouched. If your top entry is a *different, newer*
version than the release (e.g. you wrote `0.1.0` but the bump produced
`0.0.5`), generation is refused with a warning so the file stays in order.

**Internal versions:** every version gets its own changelog entry, whether or
not it ever reaches the mod portal. Entries and published versions don't
have to line up 1:1. When you publish a later version, the portal simply
shows the entries of the internal versions in between as well.

**Feedback:** the PR reminder comment checks the PR title (it re-runs when
you rename the PR). It shows a collapsed preview of the changelog line the
title will generate, or a non-blocking warning when the title has no
prefix, so a player-relevant change doesn't silently miss the changelog.
Internal prefixes (`chore:` etc.) only get a neutral note. On release, a
warning annotation appears if there is still no entry with changes for the
new version, e.g. when every commit was internal. Nothing here blocks a
merge or a release.

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
3. Generates the changelog entry from commit messages (unless a manual
   entry exists), commits `info.json` and `changelog.txt` back to `master`
   and tags it `vX.Y.Z`.
4. Packages the mod into `<mod-name>_X.Y.Z.zip` with the correct
   mod-portal folder structure.
5. Creates a GitHub Release with that zip attached.

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
Factorio Mod Portal via the official
[Mod Upload API](https://wiki.factorio.com/Mod_upload_API). Nothing ever
reaches the live mod portal without this manual step.
