#!/bin/bash
# SPDX-License-Identifier: MIT
# Copyright (C) 2018 Pawel Krupa (@paulfantom) - All Rights Reserved
# Permission to copy and modify is granted under the MIT license
#
# Original script is available at https://github.com/paulfantom/travis-helper/blob/master/releasing/releaser.sh
#
# Script to automatically do a couple of things:
#   - generate a new tag according to semver (https://semver.org/)
#   - generate CHANGELOG.md by using https://github.com/skywinder/github-changelog-generator
#   - create draft of GitHub releases by using https://github.com/github/hub
#
# Tags are generated by searching for a keyword in last commit message. Keywords are:
#  - [patch] or [fix] to bump patch number
#  - [minor], [feature] or [feat] to bump minor number
#  - [major] or [breaking change] to bump major number
# All keywords MUST be surrounded with square braces.
#
# Script uses git mechanisms for locking, so it can be used in parallel builds
#
# Requirements:
#   - GITHUB_TOKEN variable set with GitHub token. Access level: repo.public_repo
#   - docker

set -e

if [ ! -f .gitignore ]; then
	echo "Run as ./travis/$(basename "$0") from top level directory of git repository"
	exit 1
fi

export GIT_MAIL="pawel+bot@netdata.cloud"
export GIT_USER="netdatabot"
echo "--- Initialize git configuration ---"
git config user.email "${GIT_MAIL}"
git config user.name "${GIT_USER}"
git checkout master
git pull

echo "---- FIGURING OUT TAGS ----"
# tagger.sh is sourced since we need environment variables it sets
#shellcheck source=/dev/null
source .travis/tagger.sh || exit 0

echo "---- UPDATE VERSION FILE ----"
echo "$GIT_TAG" >packaging/version
git add packaging/version

echo "---- GENERATE CHANGELOG -----"
./.travis/generate_changelog.sh
git add CHANGELOG.md

echo "---- COMMIT AND PUSH CHANGES ----"
git commit -m "[ci skip] release $GIT_TAG"
git tag "$GIT_TAG" -a -m "Automatic tag generation for travis build no. $TRAVIS_BUILD_NUMBER"
git push "https://${GITHUB_TOKEN}:@$(git config --get remote.origin.url | sed -e 's/^https:\/\///')"
git push "https://${GITHUB_TOKEN}:@$(git config --get remote.origin.url | sed -e 's/^https:\/\///')" --tags

echo "---- CREATING TAGGED DOCKER CONTAINERS ----"
export REPOSITORY="netdata/netdata"
./packaging/docker/build.sh

echo "---- CREATING RELEASE ARTIFACTS -----"
./.travis/create_artifacts.sh

echo "---- CREATING RELEASE DRAFT WITH ASSETS -----"
# Download hub
HUB_VERSION=${HUB_VERSION:-"2.5.1"}
wget "https://github.com/github/hub/releases/download/v${HUB_VERSION}/hub-linux-amd64-${HUB_VERSION}.tgz" -O "/tmp/hub-linux-amd64-${HUB_VERSION}.tgz"
tar -C /tmp -xvf "/tmp/hub-linux-amd64-${HUB_VERSION}.tgz"
export PATH=$PATH:"/tmp/hub-linux-amd64-${HUB_VERSION}/bin"

# Create a release draft
if [ -z ${GIT_TAG+x} ]; then
	echo "Variable GIT_TAG is not set. Something went terribly wrong! Exiting."
	exit 1
fi
if [ "${GIT_TAG}" != "$(git tag --points-at)" ]; then
	echo "ERROR! Current commit is not tagged. Stopping release creation."
	exit 1
fi
if [ ! -z ${RC+x} ]; then
	hub release create --draft -a "netdata-${GIT_TAG}.tar.gz" -a "netdata-${GIT_TAG}.gz.run" -a "sha256sums.txt" -m "${GIT_TAG}" "${GIT_TAG}"
fi
