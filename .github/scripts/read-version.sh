#!/bin/sh
# Print the module version held in VERSION, or fail if the file does not hold
# exactly one bare MAJOR.MINOR.PATCH semantic version.
#
# A `#` starts a comment anywhere on a line, and blank lines are dropped, so
# VERSION can carry the notes a maintainer wants in front of them at the moment
# of a bump. Pass a path to read a file other than ./VERSION, which is how the
# pull request check reads the base revision of the same file.
#
# The pull request check and the tag job both read the version through this, so
# neither can accept a version the other rejects.
set -eu

file="${1:-VERSION}"

version="$(sed 's/#.*//' "$file" | tr -d '[:blank:]' | grep -v '^$' || true)"

count="$(printf '%s\n' "$version" | grep -c . || true)"
if [ "$count" -ne 1 ]; then
    echo "${file} must hold one version outside its comments, found ${count}." >&2
    exit 1
fi

if ! printf '%s' "$version" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$'; then
    echo "${file} must hold a bare MAJOR.MINOR.PATCH version, found '${version}'." >&2
    exit 1
fi

printf '%s\n' "$version"
