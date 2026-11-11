#!/bin/sh
# Writes the fragments in changes/ (changes/README.md) into CHANGELOG.md as
# the section "## <version> - <today>", ordered by PR number, and deletes them.
# The steps files beside them (changes/<pr>-<slug>.after.toml and
# changes/release.after.toml) become the version's entry in upgrade.toml,
# which the image ships for deploy.sh to show and run (orca.mojo#323), and the
# section's "Before deploying" / "After deploying" lists; they are deleted too.
#
#   sh scripts/changelog.sh 0.2.0
#   sh scripts/changelog.sh --check   # only check changes/*.after.toml (CI)
set -eu
cd "$(dirname "$0")/.."

version=${1:?usage: scripts/changelog.sh <version> | --check}
version=${version#v}
check=
[ "$version" = --check ] && check=1
if [ -z "$check" ] && grep -q "^## $version " CHANGELOG.md; then
    echo "CHANGELOG.md has $version already" >&2
    exit 1
fi
frags=$(find changes -name '*.md' ! -name README.md | sort -t/ -k2 -n)
if [ -z "$frags" ] && [ -z "$check" ]; then
    echo "no fragments in changes/" >&2
    exit 1
fi

# The highest level among the fragments, to check the version against.
level=patch
for f in $frags; do
    case $f in
    *.breaking.md) level=breaking ;;
    *.minor.md) [ "$level" = breaking ] || level=minor ;;
    esac
done

# The steps: one line per step, id<TAB>when<TAB>run|manual<TAB>text, checked
# as the deploy will check them.
steps_files=$(find changes -name '*.after.toml' | sort -t/ -k2 -n)
steps=$(mktemp)
if [ -n "$steps_files" ]; then
    # shellcheck disable=SC2086
    awk '
        function flush() {
            if (!open) return
            if (id == "") { printf "%s: a step has no id\n", FILENAME > "/dev/stderr"; bad = 1 }
            if ((run == "") == (manual == "")) { printf "%s: step %s needs one of run or manual\n", FILENAME, id > "/dev/stderr"; bad = 1 }
            if (run != "" && run !~ /^orca /) { printf "%s: step %s: run must be an orca command\n", FILENAME, id > "/dev/stderr"; bad = 1 }
            if (when != "before" && when != "after") { printf "%s: step %s: when is before or after\n", FILENAME, id > "/dev/stderr"; bad = 1 }
            if (id in seen) { printf "%s: step id %s twice\n", FILENAME, id > "/dev/stderr"; bad = 1 }
            seen[id] = 1
            printf "%s\t%s\t%s\t%s\n", id, when, (run != "" ? "run" : "manual"), (run != "" ? run : manual)
            open = 0
        }
        FNR == 1 { flush() }
        /^[ \t]*(#|$)/ { next }
        /^\[\[step\]\][ \t]*$/ { flush(); open = 1; id = ""; when = "after"; run = ""; manual = ""; next }
        {
            if (!open || !match($0, /^[ \t]*[a-z]+[ \t]*=[ \t]*"/)) { printf "%s:%d: not a step line: %s\n", FILENAME, FNR, $0 > "/dev/stderr"; bad = 1; next }
            key = $0; sub(/[ \t]*=.*/, "", key); gsub(/[ \t]/, "", key)
            v = substr($0, RLENGTH + 1)
            if (v !~ /"[ \t]*$/) { printf "%s:%d: a value is one double-quoted line\n", FILENAME, FNR > "/dev/stderr"; bad = 1; next }
            sub(/"[ \t]*$/, "", v); gsub(/\\"/, "\"", v); gsub(/\t/, " ", v)
            if (key == "id") id = v; else if (key == "when") when = v
            else if (key == "run") run = v; else if (key == "manual") manual = v
            else { printf "%s:%d: unknown key %s\n", FILENAME, FNR, key > "/dev/stderr"; bad = 1 }
        }
        END { flush(); exit bad }
    ' $steps_files > "$steps"
fi

if [ -n "$check" ]; then
    # CI: the steps files parse and say what the deploy will accept.
    echo "changes/: $(wc -l < "$steps" | tr -d ' ') steps, all well-formed"
    rm -f "$steps"
    exit 0
fi

# A TOML basic string.
toml_string() {
    printf '"%s"' "$(printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g')"
}

section=$(mktemp)
{
    printf '## %s - %s\n' "$version" "$(date -u +%Y-%m-%d)"
    for f in $frags; do
        printf '\n'
        cat "$f"
    done
    for when in before after; do
        if awk -F '\t' -v w="$when" '$2 == w { found = 1 } END { exit !found }' "$steps"; then
            printf '\n**%s deploying** (deploy.sh shows these and runs the commands):\n\n' \
                "$([ "$when" = before ] && echo Before || echo After)"
            awk -F '\t' -v w="$when" '$2 == w {
                if ($3 == "run") printf "- Run `%s`.\n", $4; else printf "- %s\n", $4
            }' "$steps"
        fi
    done
    printf '\n'
} > "$section"

# upgrade.toml: this version's steps, newest version first.
if [ -s "$steps" ]; then
    block=$(mktemp)
    {
        printf '[[version]]\nversion = "%s"\n' "$version"
        while IFS="$(printf '\t')" read -r id when kind text; do
            printf '\n[[version.step]]\nid = %s\nwhen = "%s"\n%s = %s\n' \
                "$(toml_string "$id")" "$when" "$kind" "$(toml_string "$text")"
        done < "$steps"
        printf '\n'
    } > "$block"
    up=$(mktemp)
    awk -v block="$block" '
        !done && /^\[\[version\]\]/ { while ((getline l < block) > 0) print l; done = 1 }
        { print }
        END { if (!done) while ((getline l < block) > 0) print l }
    ' upgrade.toml > "$up"
    mv "$up" upgrade.toml
    rm -f "$block"
fi

# The section goes after the title, before the newest version.
out=$(mktemp)
awk -v section="$section" '
    !done && /^## / { while ((getline l < section) > 0) print l; done = 1 }
    { print }
    END { if (!done) while ((getline l < section) > 0) print l }
' CHANGELOG.md > "$out"
mv "$out" CHANGELOG.md
nsteps=$(wc -l < "$steps" | tr -d ' ')
# shellcheck disable=SC2086
rm -f "$section" "$steps" $frags $steps_files
echo "CHANGELOG.md: $version, $(echo "$frags" | wc -l | tr -d ' ') fragments, highest level $level; upgrade.toml: $nsteps steps"
