#!/bin/sh
# Report whether a tag exists in a repository.
#
# Exit 0 if it does, 1 if GitHub confirms it does not, and 2 if the answer
# could not be determined. The third case is the reason this is not an inline
# `gh api ... 2>/dev/null`: gh exits non-zero for a missing tag, an expired
# token and a rate limit alike, and reading all of those as "absent" lets the
# pull request check approve a version that is already released.
#
# A wrong repository name also answers 404, but both callers pass
# github.repository, which the runner fills in.
#
# Usage: tag-exists.sh <owner/repo> <tag>
set -eu

repo="$1"
tag="$2"
err="$(mktemp)"

if gh api "repos/${repo}/git/ref/tags/${tag}" >/dev/null 2>"$err"; then
    rm -f "$err"
    exit 0
fi

if grep -q '(HTTP 404)' "$err"; then
    rm -f "$err"
    exit 1
fi

echo "Could not determine whether ${tag} exists in ${repo}:" >&2
sed 's/^/  /' "$err" >&2
rm -f "$err"
exit 2
