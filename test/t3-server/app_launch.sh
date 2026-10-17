#!/bin/bash
# Installs and starts the T3 Code server over the SSH entry point the way the
# T3 Code app does, then checks it (see app_style_launch in test.sh).
set -e
export T3_TEST_SCENARIO=app_launch
exec bash "$(dirname "$0")/test.sh"
