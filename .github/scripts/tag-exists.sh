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

# Redirection order is load-bearing: 2>&1 aims stderr at the capture, then
# >/dev/null drops the response body. Reversed, both go to /dev/null and the
# diagnostic below prints nothing. gh puts the 404 body on stdout and the
# "(HTTP 404)" line on stderr, so stderr is the half worth keeping.
#
# Captured rather than written to a temp file so that no failure of mktemp can
# exit 1 here, which would read as a confirmed absence.
rc=0
err="$(gh api "repos/${repo}/git/ref/tags/${tag}" 2>&1 >/dev/null)" || rc=$?

if [ "$rc" -eq 0 ]; then
    exit 0
fi

case "$err" in
    *'(HTTP 404)'*) exit 1 ;;
esac

echo "Could not determine whether ${tag} exists in ${repo}:" >&2
printf '%s\n' "$err" | sed 's/^/  /' >&2
exit 2
