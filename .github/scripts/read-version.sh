#!/bin/sh
# Print the module version held in VERSION, or fail if the file does not hold
# exactly one bare MAJOR.MINOR.PATCH semantic version.
#
# A `#` starts a comment anywhere on a line, and blank lines are dropped, so
# VERSION can carry the notes a maintainer wants in front of them at the moment
# of a bump. Pass a path to read a file other than ./VERSION, which is how the
# pull request check reads the base revision of the same file.
#
# Padding around the version is trimmed, but whitespace inside it is not: `1.
# 0.0` is a typo rather than a version, and deleting every blank would turn it
# into a tag. The trim covers carriage returns, so a VERSION committed with CRLF
# endings parses rather than failing on an invisible character. Leading zeros are
# rejected because semantic versioning does not allow them.
#
# Both the pull request check and the release job parse through this, so they
# cannot disagree on whether a version is well formed. They do not otherwise
# agree: the pull request check adds rules of its own, the downgrade guard among
# them, that the release job does not repeat.
set -eu

file="${1:-VERSION}"

version="$(sed -e 's/#.*//' -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' "$file" | grep -v '^$' || true)"

count="$(printf '%s\n' "$version" | grep -c . || true)"
if [ "$count" -ne 1 ]; then
    echo "${file} must hold one version outside its comments, found ${count}." >&2
    exit 1
fi

if ! printf '%s' "$version" | grep -Eq '^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$'; then
    echo "${file} must hold a bare MAJOR.MINOR.PATCH version, found '${version}'." >&2
    exit 1
fi

printf '%s\n' "$version"
