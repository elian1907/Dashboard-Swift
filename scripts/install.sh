#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
./scripts/build.sh
mkdir -p "$HOME/Applications"
# ditto keeps the code signature and bundle resources intact.
ditto 'build/Build/Products/Release/Loslo Dashboard.app' "$HOME/Applications/Loslo Dashboard.app"
open "$HOME/Applications/Loslo Dashboard.app"
