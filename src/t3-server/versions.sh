#!/bin/sh
# SHA-256 of each release archive this feature will install, keyed by
# "<version>:<arch>". install.sh refuses anything that is not listed here.
#
# These are pinned in the feature instead of read from the release's own
# SHA256SUMS, so a release that is replaced after the fact fails the build.
# To add a version: download t3-<version>-linux-<arch>.tar.gz for both
# architectures from the official GitHub release, run sha256sum on each, and
# add the two lines below.
t3_server_archive_sha256() {
  case "$1:$2" in
    0.0.45:x64) echo "10505ae74bc6a43cfab0fde0bf06a0e0d6862f74030591be994a640d48a0d6bd" ;;
    0.0.45:arm64) echo "9133591017e7d477525fda661a46cc9528fd62a0c42268079e435ffb35b95ac9" ;;
    *) return 1 ;;
  esac
}
