#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
# A stable developer signature preserves Keychain trust across local rebuilds.
# Without a certificate, Xcode falls back to the project's ad-hoc signature.
signing_args=()
identity=$(security find-identity -v -p codesigning | sed -n 's/.*) \([A-F0-9]\{40\}\) "Apple Development:.*/\1/p' | head -1)
if [[ -n "$identity" ]]; then
  signing_args=("CODE_SIGN_IDENTITY=$identity")
fi
xcodebuild -project LosloDashboard.xcodeproj -scheme LosloDashboard -configuration Release -derivedDataPath build "${signing_args[@]}" build
print 'App créée : build/Build/Products/Release/Loslo Dashboard.app'
