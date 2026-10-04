#!/bin/bash
# Same checks as the default test; test.sh adapts to the installed options.
set -e
exec bash "$(dirname "$0")/test.sh"
