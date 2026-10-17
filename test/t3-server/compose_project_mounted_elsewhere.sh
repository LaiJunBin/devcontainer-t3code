#!/bin/bash
# A Docker Compose project mounted outside /workspaces. test.sh adds the
# checks that only make sense here: the feature has no name for it, and the
# entrypoint must still have prepared the data volume.
set -e
export T3_TEST_SCENARIO=compose
exec bash "$(dirname "$0")/test.sh"
