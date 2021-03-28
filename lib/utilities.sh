#! /usr/bin/env bash

set -o nounset
set -o errexit
set -o pipefail
IFS=$'\n\t'

# Label: Image
# Description: Answer image name.
# Parameters: None.
image() {
  printf "%s" "$USER/$(project)"
}

# Label: Project
# Description: Answer project name.
# Parameters: None.
project() {
  printf "%s" "${PWD##*/docker-}"
}

# Label: Tag
# Description: Answer image tag.
# Parameters: $1 (optional) - Version, Default: "latest".
tag() {
  local version="${1:-latest}"

  printf "%s" "$USER/$(project):$version"
}
