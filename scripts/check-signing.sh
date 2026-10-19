#!/bin/bash
# These checks sign temporary apps but never launch them or change permissions.
set -euo pipefail
cd "$(dirname "$0")/.."
/usr/bin/python3 Tests/test_signing.py
/usr/bin/python3 Tests/check_signing_identity.py
