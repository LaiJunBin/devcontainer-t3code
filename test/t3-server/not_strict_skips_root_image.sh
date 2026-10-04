#!/bin/bash
# A root-only image cannot use the ssh option. With "strict": false the feature
# must step aside and leave a container that starts normally.
set -e

# shellcheck source=/dev/null
source dev-container-features-test-lib

check "nothing was installed" bash -c "! command -v t3 && ! command -v t3-server"
check "the pass-through entrypoint is in place" test -x /usr/local/share/t3-server/entrypoint.sh
check "the entrypoint hands over to the container command" bash -c "[ \"\$(/usr/local/share/t3-server/entrypoint.sh echo ok)\" = ok ]"

reportResults
