#!/usr/bin/env python3
"""Changelog tooling for Factorio mods.

Follows the official format:
https://lua-api.factorio.com/latest/auxiliary/changelog-format.html

Every pull request describes its own changelog entries in its description, after a line that
reads "Changelog:". When a release is made, the entries of all pull requests since the last
release are collected, merged and written to changelog.txt in the official format, with the
date filled in automatically.

Commands
  check-pr   Validate the "Changelog:" section of a PR description (used by the PR check).
  validate   Validate changelog.txt against the official format (used by CI and releases).
  release    Collect the entries of all PRs since the last tag and write the new version section.
  notes      Print one version section of changelog.txt as markdown (for the GitHub release).

Only the Python standard library is used.
"""

import argparse
import datetime
import difflib
import json
import os
import re
import shutil
import subprocess
import sys

DASHES = "-" * 99

# The categories the game recognises and sorts to the front (see the format documentation).
CATEGORIES = [
    "Major Features", "Features", "Minor Features", "Graphics", "Sounds", "Optimizations",
    "Balancing", "Combat Balancing", "Circuit Network", "Changes", "Bugfixes", "Modding",
    "Scripting", "Gui", "Control", "Translation", "Debug", "Ease of use", "Info", "Locale",
    "Compatibility",
]
CATEGORY_LOOKUP = {name.lower(): name for name in CATEGORIES}

CHANGELOG_FILE = "changelog.txt"
MARKER = "<!-- changelog-check -->"

MARKER_RE = re.compile(
    r"^[ \t]*(?:#{1,6}[ \t]*)?(?:\*\*|__)?Changelog:(?:\*\*|__)?[ \t]*(.*)$",
    re.IGNORECASE | re.MULTILINE,
)
NONE_RE = re.compile(r"^(none|skip|n/a)\b", re.IGNORECASE)
CATEGORY_RE = re.compile(r"^(?:\*\*|__)?([A-Za-z][A-Za-z ]*[A-Za-z])(?:\*\*|__)?:(?:\*\*|__)?$")
BULLET_RE = re.compile(r"^[-*]\s+(.*)$")
RULE_RE = re.compile(r"^(?:-{3,}|\*{3,}|_{3,})$")
HEADING_RE = re.compile(r"^#{1,6}\s")
VERSION_RE = re.compile(r"^Version: (\d+)\.(\d+)\.(\d+)$")


# ---------------------------------------------------------------------------
# Pull request descriptions
# ---------------------------------------------------------------------------

def parse_pr_body(body):
    """Parse the "Changelog:" section of a PR description.

    Returns a dict:
      status   "missing" (no section), "none" (explicitly no entry), "entries" or "invalid"
      entries  {category: [[line, ...], ...]} in order of appearance (an entry is a list of lines)
      errors   problems that make the section invalid
      hints    style suggestions, never blocking
    """
    result = {"status": "missing", "entries": {}, "errors": [], "hints": []}

    text = (body or "").replace("\r\n", "\n").replace("\r", "\n")
    text = re.sub(r"<!--.*?-->", "", text, flags=re.DOTALL)  # template guidance is not content
    text = text.replace("\t", "    ")

    marker = MARKER_RE.search(text)
    if not marker:
        return result

    first = marker.group(1).strip()
    if first and NONE_RE.match(first):
        result["status"] = "none"
        return result

    lines = ([first] if first else []) + text[marker.end():].split("\n")[1:]

    # "Changelog:" followed by a line that starts with none/skip/n/a.
    for line in lines:
        if line.strip():
            if NONE_RE.match(line.strip()) and not CATEGORY_RE.match(line.strip()):
                result["status"] = "none"
                return result
            break

    errors = result["errors"]
    entries = {}
    current_category = None
    current_entry = None
    blank_since_entry = False

    for raw in lines:
        stripped = raw.strip()

        if stripped and (RULE_RE.match(stripped) or HEADING_RE.match(stripped)):
            break  # the section ends at a horizontal rule or the next markdown heading

        if not stripped:
            blank_since_entry = True
            continue

        if stripped in ("-", "*"):
            errors.append("An entry is empty (a line with only a dash). Write the change after the dash, or remove the line.")
            current_entry = None
            continue

        bullet = BULLET_RE.match(stripped)
        if bullet:
            if current_category is None:
                errors.append("Entry \"%s\" is not under a category. Put a category line such as \"Features:\" before it." % bullet.group(1))
                current_entry = None
                continue
            current_entry = [bullet.group(1).strip()]
            entries[current_category].append(current_entry)
            blank_since_entry = False
            continue

        category = CATEGORY_RE.match(stripped)
        if category:
            key = category.group(1).strip().lower()
            if key in CATEGORY_LOOKUP:
                current_category = CATEGORY_LOOKUP[key]
                entries.setdefault(current_category, [])
                current_entry = None
                blank_since_entry = False
                continue
            if current_entry is None or blank_since_entry:
                guess = difflib.get_close_matches(category.group(1).strip().title(), CATEGORIES, n=1)
                hint = " Did you mean \"%s\"?" % guess[0] if guess else ""
                errors.append("\"%s:\" is not a category the game recognises.%s" % (category.group(1).strip(), hint))
                # Keep reading under that name so its entries are not reported a second time.
                current_category = category.group(1).strip()
                entries.setdefault(current_category, [])
                current_entry = None
                continue
            # directly after an entry line: it is just the next line of that entry

        if current_entry is not None and not blank_since_entry:
            current_entry.append(stripped)
            continue

        errors.append("Text \"%s\" is not part of an entry. Start entries with \"- \" under a category." % stripped)

    # Per category checks.
    for category, items in entries.items():
        if not items:
            errors.append("Category \"%s:\" has no entries." % category)
            continue
        seen_entries = set()
        seen_lines = {}
        for index, entry in enumerate(items):
            joined = "\n".join(entry)
            if joined in seen_entries:
                errors.append("Duplicate entry in \"%s\": %s" % (category, entry[0]))
            seen_entries.add(joined)
            if len(entry) > 1:
                for line in entry:
                    other = seen_lines.get(line)
                    if other is not None and other != index:
                        errors.append(
                            "In \"%s\" the line \"%s\" appears in two multi-line entries. The game treats "
                            "identical lines in one category as duplicates." % (category, line))
                    seen_lines.setdefault(line, index)

    if not entries and not errors:
        errors.append("The Changelog: section has no entries. Add entries under a category, or write \"Changelog: none\".")

    entry_lists = [entry for items in entries.values() for entry in items]
    if any(not entry[0][:1].isupper() or not entry[-1].rstrip().endswith((".", "!", "?")) for entry in entry_lists):
        result["hints"].append("Entries read best as full sentences: start with a capital letter and end with a period.")

    result["entries"] = entries
    result["status"] = "invalid" if errors else "entries"
    return result


def sort_categories(names):
    return sorted(names, key=lambda name: CATEGORIES.index(name) if name in CATEGORIES else len(CATEGORIES))


def render_section(version, date, entries):
    """The version section for changelog.txt, in the official format."""
    out = [DASHES, "Version: %s" % version, "Date: %s" % date]
    for category in sort_categories(entries):
        out.append("  %s:" % category)
        for entry in entries[category]:
            out.append("    - %s" % entry[0])
            for extra in entry[1:]:
                out.append("      %s" % extra)
    return "\n".join(out) + "\n"


def today():
    """The release date in the style of the official example (DD. MM. YYYY)."""
    return datetime.date.today().strftime("%d. %m. %Y")


TEMPLATE_HELP = """\
**How to write it.** Put this in the pull request description:

```
Changelog:
Features:
- A single line entry.
- A multi-line entry continues on the next line
  without a new dash.
Bugfixes:
- Fixed something that was broken.
```

- Write `Changelog: none` for changes players do not care about (CI, docs, refactoring).
- Use as many categories as the change needs. The categories the game recognises are:
  %s.
- Use a multi-line entry when one line is not enough to explain a change.
- The release date and the version are filled in automatically when a release is made.
""" % ", ".join(CATEGORIES)


def cmd_check_pr(args):
    if args.body_file:
        with open(args.body_file, encoding="utf-8") as handle:
            body = handle.read()
    else:
        body = os.environ.get("PR_BODY", "")

    result = parse_pr_body(body)
    out = [MARKER]

    if result["status"] == "none":
        out.append("### Changelog check: no entry")
        out.append("")
        out.append("This PR is marked `Changelog: none`, so it will not appear in the changelog.")
    elif result["status"] == "entries":
        out.append("### Changelog check: OK")
        out.append("")
        out.append("These entries will be added to the changelog when this PR is part of a release:")
        out.append("")
        out.append("```")
        out.append(render_section("X.Y.Z", "<release date>", result["entries"]).rstrip("\n"))
        out.append("```")
        if result["hints"]:
            out.append("")
            for hint in result["hints"]:
                out.append("Tip: " + hint)
    else:
        out.append("### Changelog check: action needed")
        out.append("")
        if result["status"] == "missing":
            out.append("The pull request description must contain a line that reads `Changelog:`, followed by the changes of this PR.")
        else:
            out.append("The `Changelog:` section of this PR has problems:")
            out.append("")
            for error in result["errors"]:
                out.append("- " + error)
        out.append("")
        out.append(TEMPLATE_HELP)

    sys.stdout.write("\n".join(out) + "\n")
    return 0 if result["status"] in ("entries", "none") else 1


# ---------------------------------------------------------------------------
# changelog.txt
# ---------------------------------------------------------------------------

def validate_text(text, path=CHANGELOG_FILE):
    """Validate changelog.txt content against the official format. Returns a list of problems."""
    problems = []

    def problem(number, message):
        problems.append("%s:%d: %s" % (path, number, message))

    lines = text.replace("\r\n", "\n").split("\n")
    if lines and lines[-1] == "":
        lines.pop()

    seen_versions = set()
    state = "start"  # start, after_dashes, in_section
    version = None
    version_line = 0
    has_date = False
    category = None
    entry_open = False
    entry_count = 0
    entries_in_category = {}
    lines_in_category = {}
    section_has_entries = False

    def close_section():
        if version is not None and not section_has_entries:
            problem(version_line, "Version %s has no entries. Every version needs at least one change." % version)
        if version is not None and not has_date:
            problem(version_line, "Version %s has no Date line." % version)

    for number, line in enumerate(lines, start=1):
        if "\t" in line:
            problem(number, "Tabs are not allowed.")
        if line != line.rstrip():
            problem(number, "Trailing whitespace is not allowed.")

        if state == "after_dashes":
            match = VERSION_RE.match(line)
            if not match:
                problem(number, "The line after the dashes must be \"Version: major.minor.sub\" (found: \"%s\")." % line)
                state = "in_section"
                version = None
                continue
            parts = [int(part) for part in match.groups()]
            if any(part > 65535 for part in parts) or parts == [0, 0, 0]:
                problem(number, "Invalid version \"%s\" (each number 0-65535, and not 0.0.0)." % line)
            version_text = "%d.%d.%d" % tuple(parts)
            if version_text in seen_versions:
                problem(number, "Version %s appears more than once." % version_text)
            seen_versions.add(version_text)
            version, version_line = version_text, number
            has_date = False
            category = None
            entry_open = False
            entries_in_category = {}
            lines_in_category = {}
            section_has_entries = False
            state = "in_section"
            continue

        if line == DASHES:
            close_section()
            version = None
            state = "after_dashes"
            continue

        if not line.strip():
            continue

        if state == "start":
            problem(number, "Content before the first version section (a line of exactly 99 dashes).")
            continue

        if line.startswith("-") and set(line) == {"-"}:
            problem(number, "A version section starts with exactly 99 dashes (found %d)." % len(line))
            continue

        if line.startswith("Version:"):
            problem(number, "\"Version:\" must directly follow the line of 99 dashes.")
            continue

        if line.startswith("Date:"):
            if line[5:6] != " " or not line[6:].strip():
                problem(number, "Write the date as \"Date: <text>\" (a space after the colon).")
            if has_date:
                problem(number, "A version section may only have one Date line.")
            has_date = True
            continue

        if line.startswith("  ") and not line.startswith("   ") and line.endswith(":"):
            name = line.strip()[:-1]
            if name.lower() not in CATEGORY_LOOKUP:
                guess = difflib.get_close_matches(name.title(), CATEGORIES, n=1)
                hint = " Did you mean \"%s\"?" % guess[0] if guess else ""
                problem(number, "\"%s\" is not a category the game recognises.%s" % (name, hint))
            elif CATEGORY_LOOKUP[name.lower()] != name:
                problem(number, "Write the category as \"%s\"." % CATEGORY_LOOKUP[name.lower()])
            category = name
            entry_open = False
            entries_in_category.setdefault(category, set())
            lines_in_category.setdefault(category, {})
            continue

        if line.startswith("    - ") and not line.startswith("     ") and line[6:].strip():
            if category is None:
                problem(number, "An entry must come after a category line.")
                continue
            entry_count += 1
            section_has_entries = True
            entry_open = True
            text_line = line[6:]
            if text_line in entries_in_category[category]:
                problem(number, "Duplicate entry in category \"%s\": %s" % (category, text_line))
            entries_in_category[category].add(text_line)
            lines_in_category[category][text_line] = lines_in_category[category].get(text_line, 0) + 1
            continue

        if line.startswith("      ") and not line.startswith("       ") and entry_open:
            continuation = line[6:]
            if lines_in_category[category].get(continuation):
                problem(number, "The line \"%s\" repeats a line of another entry in category \"%s\"." % (continuation, category))
            lines_in_category[category][continuation] = lines_in_category[category].get(continuation, 0) + 1
            continue

        problem(number, "Unexpected line. Categories start with exactly 2 spaces and end with a colon, "
                        "entries with exactly 4 spaces and \"- \", continuation lines with exactly 6 spaces.")

    if state == "after_dashes":
        problem(len(lines), "The file ends right after a line of dashes; a Version line must follow.")
    close_section()
    return problems


def top_version(text):
    match = re.search(r"^Version: (\S+)\s*$", text.replace("\r\n", "\n"), re.MULTILINE)
    return match.group(1) if match else None


def version_tuple(version):
    return tuple(int(part) for part in version.split("."))


def section_of(text, version):
    """The lines of one version section (without the dashes line)."""
    lines = text.replace("\r\n", "\n").split("\n")
    out, inside = [], False
    for index, line in enumerate(lines):
        if line == "Version: %s" % version:
            inside = True
            continue
        if inside and line == DASHES:
            break
        if inside:
            out.append(line)
    return out if inside else None


def cmd_validate(args):
    path = args.file
    if not os.path.exists(path):
        print("%s does not exist." % path)
        return 1
    with open(path, encoding="utf-8") as handle:
        text = handle.read()

    problems = validate_text(text, path)

    if args.expect_version:
        top = top_version(text)
        if top != args.expect_version:
            problems.append("%s: the top entry is %s but this release is %s." % (path, top, args.expect_version))

    for message in problems:
        print(message)
    if not problems:
        print("%s follows the changelog format." % path)
    return 1 if problems else 0


def cmd_notes(args):
    with open(args.file, encoding="utf-8") as handle:
        text = handle.read()
    section = section_of(text, args.version)
    if section is None:
        print("No section for version %s in %s." % (args.version, args.file), file=sys.stderr)
        return 1

    out = []
    for line in section:
        if not line.strip() or line.startswith("Date:"):
            continue
        if line.startswith("    - "):
            out.append("- " + line[6:])
        elif line.startswith("      "):
            out.append("  " + line[6:])
        elif line.startswith("  ") and line.endswith(":"):
            if out:
                out.append("")
            out.append("### " + line.strip()[:-1])
    sys.stdout.write("\n".join(out) + "\n")
    return 0


# ---------------------------------------------------------------------------
# Releases
# ---------------------------------------------------------------------------

def run(*command):
    return subprocess.run(command, capture_output=True, text=True, check=False)


def previous_tag():
    result = run("git", "describe", "--tags", "--abbrev=0", "--match", "v[0-9]*")
    return result.stdout.strip() or None


def commits_since(tag):
    revision = "%s..HEAD" % tag if tag else "HEAD"
    result = run("git", "log", "--no-merges", "--reverse", "--format=%H", revision)
    return [line for line in result.stdout.split("\n") if line.strip()]


def commit_subject(sha):
    return run("git", "show", "-s", "--format=%s", sha).stdout.strip()


def commit_message(sha):
    return run("git", "show", "-s", "--format=%B", sha).stdout


def pr_body_for(repo, sha):
    """The description of the merged pull request that contains this commit (needs gh and a token)."""
    if not repo or not shutil.which("gh"):
        return None
    result = run("gh", "api", "repos/%s/commits/%s/pulls" % (repo, sha),
                 "-H", "Accept: application/vnd.github+json")
    if result.returncode != 0:
        return None
    try:
        pulls = json.loads(result.stdout)
    except ValueError:
        return None
    merged = [pull for pull in pulls if pull.get("merged_at")]
    pull = (merged or pulls or [None])[0]
    return pull.get("body") if pull else None


def merge_entries(target, source, warnings, origin):
    """Add the entries of one PR to the release, skipping repeats the format would reject."""
    for category, items in source.items():
        existing = target.setdefault(category, [])
        for entry in items:
            joined = "\n".join(entry)
            if any("\n".join(other) == joined for other in existing):
                continue  # the exact same entry already exists
            if len(entry) > 1:
                used_lines = {line for other in existing if len(other) > 1 for line in other}
                clash = [line for line in entry if line in used_lines]
                if clash:
                    warnings.append("%s: a line of a multi-line entry repeats another entry in \"%s\" (%s); entry skipped."
                                    % (origin, category, clash[0]))
                    continue
            existing.append(entry)


def cmd_release(args):
    path = args.file
    exists = os.path.exists(path)
    text = ""
    if exists:
        with open(path, encoding="utf-8") as handle:
            text = handle.read()

    top = top_version(text) if text else None
    if top == args.version:
        print("%s already has an entry for %s; keeping the manual entry." % (path, args.version))
        return 0
    if top and version_tuple(top) > version_tuple(args.version):
        print("%s: the top entry is %s, which is newer than the release %s. Not generating an entry; "
              "fix the changelog by hand." % (path, top, args.version), file=sys.stderr)
        return 4

    tag = args.since or previous_tag()
    shas = commits_since(tag)
    print("Collecting changelog entries from %d commit(s) since %s." % (len(shas), tag or "the start"))

    collected, warnings = {}, []
    used = 0
    for sha in shas:
        subject = commit_subject(sha)
        if subject.startswith("chore: bump version"):
            continue
        origin = "%s (%s)" % (subject, sha[:7])

        parsed = None
        for body in (pr_body_for(args.repo, sha), commit_message(sha)):
            if body is None:
                continue
            candidate = parse_pr_body(body)
            if candidate["status"] != "missing":
                parsed = candidate
                break

        if parsed is None:
            warnings.append("%s has no \"Changelog:\" section; nothing was added for it." % origin)
        elif parsed["status"] == "invalid":
            warnings.append("%s has an invalid Changelog section and was skipped: %s" % (origin, "; ".join(parsed["errors"])))
        elif parsed["status"] == "entries":
            merge_entries(collected, parsed["entries"], warnings, origin)
            used += 1

    for warning in warnings:
        print("WARNING: " + warning)

    if not any(collected.values()):
        print("No changelog entries were found, so no entry was generated for %s." % args.version, file=sys.stderr)
        return 3

    section = render_section(args.version, today(), collected)
    if not args.write:
        sys.stdout.write(section)
        return 0

    new_text = section + (text.lstrip("\n") if text else "")
    with open(path, "w", encoding="utf-8", newline="\n") as handle:
        handle.write(new_text)
    print("Wrote the entry for %s from %d pull request(s)." % (args.version, used))

    problems = validate_text(new_text, path)
    for message in problems:
        print(message, file=sys.stderr)
    return 5 if problems else 0


# ---------------------------------------------------------------------------

def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest="command", required=True)

    check = sub.add_parser("check-pr", help="validate the Changelog section of a PR description")
    check.add_argument("--body-file", help="file with the PR description (default: environment variable PR_BODY)")
    check.set_defaults(func=cmd_check_pr)

    validate = sub.add_parser("validate", help="validate changelog.txt")
    validate.add_argument("--file", default=CHANGELOG_FILE)
    validate.add_argument("--expect-version", help="the top entry must be this version")
    validate.set_defaults(func=cmd_validate)

    release = sub.add_parser("release", help="build the version section from the PRs since the last tag")
    release.add_argument("--version", required=True)
    release.add_argument("--file", default=CHANGELOG_FILE)
    release.add_argument("--repo", help="owner/name, to read pull request descriptions through the GitHub API")
    release.add_argument("--since", help="tag to start from (default: the latest v* tag)")
    release.add_argument("--write", action="store_true", help="write changelog.txt (default: print the section)")
    release.set_defaults(func=cmd_release)

    notes = sub.add_parser("notes", help="print one version of changelog.txt as markdown")
    notes.add_argument("--version", required=True)
    notes.add_argument("--file", default=CHANGELOG_FILE)
    notes.set_defaults(func=cmd_notes)

    args = parser.parse_args()
    sys.exit(args.func(args))


if __name__ == "__main__":
    main()
