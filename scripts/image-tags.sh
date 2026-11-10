#!/bin/sh
# The tags CI pushes ghcr.io/magmalake/orca under (.github/workflows/ci.yml),
# one a line, from GitHub's environment: <short sha>, then the tag without its
# v for a tag push, else dev. The image job pushes each as <tag>-<arch>, and
# the manifest job joins the architectures under <tag>.
set -eu
echo "${GITHUB_SHA%"${GITHUB_SHA#???????}"}"
if [ "$GITHUB_REF_TYPE" = tag ]; then
    echo "${GITHUB_REF_NAME#v}"
else
    echo dev
fi
