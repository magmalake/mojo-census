#!/bin/sh
# Writes the fragments in changes/ (changes/README.md) into CHANGELOG.md as
# the section "## <version> - <today>", ordered by PR number, and deletes them.
#
#   sh scripts/changelog.sh 0.2.0
set -eu
cd "$(dirname "$0")/.."

version=${1:?usage: scripts/changelog.sh <version>}
version=${version#v}
if grep -q "^## $version " CHANGELOG.md; then
    echo "CHANGELOG.md has $version already" >&2
    exit 1
fi
frags=$(find changes -name '*.md' ! -name README.md | sort -t/ -k2 -n)
if [ -z "$frags" ]; then
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

section=$(mktemp)
{
    printf '## %s - %s\n' "$version" "$(date -u +%Y-%m-%d)"
    for f in $frags; do
        printf '\n'
        cat "$f"
    done
    printf '\n'
} > "$section"

# The section goes after the title, before the newest version.
out=$(mktemp)
awk -v section="$section" '
    !done && /^## / { while ((getline l < section) > 0) print l; done = 1 }
    { print }
    END { if (!done) while ((getline l < section) > 0) print l }
' CHANGELOG.md > "$out"
mv "$out" CHANGELOG.md
rm -f "$section" $frags
echo "CHANGELOG.md: $version, $(echo "$frags" | wc -l | tr -d ' ') fragments, highest level $level"
