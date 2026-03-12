#!/usr/bin/env bash
#
# sync-models.sh
#
# Downloads all SunSpec JSON model definitions from the official
# sunspec/models GitHub repository (master branch) into the local
# models/ directory. Useful for keeping a local copy of the SunSpec
# data models in sync with the upstream source of truth.
#
# https://github.com/sunspec/models/tree/master/json
#
# Usage: ./sync-models.sh
#

set -euo pipefail

REPO="sunspec/models"
BRANCH="master"
API_URL="https://api.github.com/repos/${REPO}/git/trees/${BRANCH}?recursive=1"
RAW_BASE="https://raw.githubusercontent.com/${REPO}/${BRANCH}"
DEST_DIR="$(cd "$(dirname "$0")" && pwd)/models"

mkdir -p "$DEST_DIR"

echo "Fetching file list from ${REPO}@${BRANCH} ..."
curl -sf "$API_URL" \
  | grep '"path"' \
  | sed 's/.*"path": "\(.*\)".*/\1/' \
  | grep '^json/.*\.json$' \
  | while read -r path; do
      filename="$(basename "$path")"
      echo "Downloading ${filename} ..."
      curl -sf "${RAW_BASE}/${path}" -o "${DEST_DIR}/${filename}"
    done

echo "Done. JSON models saved to ${DEST_DIR}"
