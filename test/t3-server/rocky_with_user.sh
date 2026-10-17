#!/bin/bash
# Same checks as the default test, on a dnf-based image with a user that
# common-utils creates.
set -e
exec bash "$(dirname "$0")/test.sh"
