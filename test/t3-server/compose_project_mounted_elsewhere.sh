#!/bin/bash
# A Docker Compose project mounted outside /workspaces. test.sh adds the
# checks that only make sense here: the name has to come from the dev
# container tool, and the entrypoint has to have started the server.
set -e
export T3_TEST_SCENARIO=compose
exec bash "$(dirname "$0")/test.sh"
