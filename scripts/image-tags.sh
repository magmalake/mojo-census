#!/bin/sh
# The tags CI pushes ghcr.io/morca-dev/census under (.github/workflows/ci.yml),
# one a line, from GitHub's environment: <short sha>, then the tag without its
# v for a tag push, lab for the lab branch (morca.lab.toml's stack), else dev. The image job pushes each as <tag>-<arch>, and
# the manifest job joins the architectures under <tag>.
set -eu
echo "${GITHUB_SHA%"${GITHUB_SHA#???????}"}"
if [ "$GITHUB_REF_TYPE" = tag ]; then
    echo "${GITHUB_REF_NAME#v}"
elif [ "$GITHUB_REF_NAME" = lab ]; then
    echo lab
else
    echo dev
fi
