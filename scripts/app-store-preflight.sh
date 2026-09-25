#!/usr/bin/env bash

# Read-only App Store launch gate. Pass an .xcarchive path to include archive
# signing and payload checks:
#   ./scripts/app-store-preflight.sh /path/to/QuitNic.xcarchive

set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ARCHIVE="${1:-}"
FAILURES=0
WARNINGS=0

pass() { printf 'PASS  %s\n' "$1"; }
fail() { printf 'FAIL  %s\n' "$1"; FAILURES=$((FAILURES + 1)); }
warn() { printf 'WARN  %s\n' "$1"; WARNINGS=$((WARNINGS + 1)); }

version_at_least() {
  local actual="$1" required="$2"
  local actual_major actual_minor required_major required_minor
  IFS=. read -r actual_major actual_minor _ <<< "$actual"
  IFS=. read -r required_major required_minor _ <<< "$required"
  actual_minor="${actual_minor:-0}"
  required_minor="${required_minor:-0}"
  (( actual_major > required_major || (actual_major == required_major && actual_minor >= required_minor) ))
}

check_http_200() {
  local label="$1" url="$2" code
  code="$(curl -L --silent --show-error --max-time 15 --output /dev/null --write-out '%{http_code}' "$url" 2>/dev/null || true)"
  if [[ "$code" == "200" ]]; then
    pass "$label is publicly reachable ($url)"
  else
    fail "$label must return public HTTP 200; received ${code:-no response} ($url)"
  fi
}

printf 'QuitNic App Store preflight\n'
printf 'Workspace: %s\n\n' "$ROOT"

OS_VERSION="$(sw_vers -productVersion)"
if version_at_least "$OS_VERSION" "15.6"; then
  pass "macOS $OS_VERSION supports Xcode 26"
else
  fail "macOS $OS_VERSION is too old; Xcode 26 requires macOS 15.6 or later"
fi

XCODE_VERSION="$(xcodebuild -version 2>/dev/null | awk 'NR == 1 { print $2 }')"
if [[ -n "$XCODE_VERSION" ]] && version_at_least "$XCODE_VERSION" "26.0"; then
  pass "Xcode $XCODE_VERSION satisfies Apple's upload requirement"
else
  fail "Xcode ${XCODE_VERSION:-not found} is too old; uploads require Xcode 26 or later"
fi

INFO="$ROOT/ios/QuitNic/Info.plist"
PROJECT_YML="$ROOT/ios/project.yml"
MARKETING_VERSION="$(awk -F': ' '/^[[:space:]]*MARKETING_VERSION:/ {print $2; exit}' "$PROJECT_YML")"
BUILD_VERSION="$(awk -F': ' '/^[[:space:]]*CURRENT_PROJECT_VERSION:/ {print $2; exit}' "$PROJECT_YML")"
INFO_MARKETING="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$INFO" 2>/dev/null || true)"
INFO_BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$INFO" 2>/dev/null || true)"
if [[ "$INFO_MARKETING" == '$(MARKETING_VERSION)' && "$INFO_BUILD" == '$(CURRENT_PROJECT_VERSION)' ]]; then
  pass "Info.plist inherits version $MARKETING_VERSION ($BUILD_VERSION) from build settings"
else
  fail "Info.plist version fields do not inherit MARKETING_VERSION/CURRENT_PROJECT_VERSION"
fi

if rg -q 'PRODUCT_BUNDLE_IDENTIFIER: com\.ibraimabduramanov\.QuitNic' "$PROJECT_YML"; then
  pass "bundle identifier is com.ibraimabduramanov.QuitNic"
else
  fail "expected bundle identifier is missing from ios/project.yml"
fi

if rg -q 'TARGETED_DEVICE_FAMILY: 1' "$PROJECT_YML"; then
  pass "version 1.0 is scoped to iPhone"
else
  fail "version 1.0 must be iPhone-only until iPad layouts are release-tested"
fi

if rg -q 'Release:' "$PROJECT_YML" && rg -q 'QUITNIC_API_URL: https://' "$PROJECT_YML"; then
  pass "Release API URL uses HTTPS"
else
  fail "Release API URL is not HTTPS"
fi

PRIVACY="$ROOT/ios/QuitNic/PrivacyInfo.xcprivacy"
if [[ -f "$PRIVACY" ]] && plutil -lint "$PRIVACY" >/dev/null; then
  pass "PrivacyInfo.xcprivacy is present and valid"
else
  fail "PrivacyInfo.xcprivacy is missing or invalid"
fi

FONT="$ROOT/ios/QuitNic/Resources/Fonts/Satoshi-Variable.ttf"
LICENSE="$ROOT/ios/QuitNic/Resources/Fonts/Satoshi-FFL.txt"
if [[ -s "$FONT" && -s "$LICENSE" ]]; then
  pass "Satoshi font and licence are bundled"
else
  fail "Satoshi font or licence is missing"
fi

ICON="$ROOT/ios/QuitNic/Assets.xcassets/AppIcon.appiconset/AppIcon-Horizon-v2-1024.png"
if [[ -f "$ICON" ]]; then
  ICON_WIDTH="$(sips -g pixelWidth "$ICON" 2>/dev/null | awk '/pixelWidth/ {print $2}')"
  ICON_HEIGHT="$(sips -g pixelHeight "$ICON" 2>/dev/null | awk '/pixelHeight/ {print $2}')"
  ICON_ALPHA="$(sips -g hasAlpha "$ICON" 2>/dev/null | awk '/hasAlpha/ {print $2}')"
  if [[ "$ICON_WIDTH" == "1024" && "$ICON_HEIGHT" == "1024" && "$ICON_ALPHA" == "no" ]]; then
    pass "App Store icon is 1024x1024 with no alpha"
  else
    fail "App Store icon must be 1024x1024 with no alpha"
  fi
else
  fail "App Store icon file is missing"
fi

IDENTITIES="$(security find-identity -v -p codesigning 2>/dev/null | awk '/valid identities found/ {print $1}')"
if [[ "${IDENTITIES:-0}" -gt 0 ]]; then
  pass "$IDENTITIES valid code-signing identity/identities found"
else
  fail "no valid Apple code-signing identity is installed"
fi

check_http_200 "production API health" "https://3yhhdy4yvi.eu-west-1.awsapprunner.com/health"
check_http_200 "privacy policy" "https://quitnic-support.otheribrahim.chatgpt.site/privacy"
check_http_200 "support page" "https://quitnic-support.otheribrahim.chatgpt.site/support"

if rg -q '^Approved by:' "$ROOT/docs/medical-content-review.md"; then
  pass "qualified clinical approval is recorded"
else
  fail "qualified clinical approval is not recorded in docs/medical-content-review.md"
fi

SCREENSHOT_DIR="$ROOT/release/app-store/screenshots/en-US/6.9-inch"
SCREENSHOT_COUNT="$(find "$SCREENSHOT_DIR" -maxdepth 1 -type f -name '*.png' 2>/dev/null | wc -l | tr -d ' ')"
if [[ "$SCREENSHOT_COUNT" -ge 1 && "$SCREENSHOT_COUNT" -le 10 ]]; then
  pass "$SCREENSHOT_COUNT App Store screenshots are packaged"
else
  fail "expected 1-10 packaged App Store screenshots; found $SCREENSHOT_COUNT"
fi

if [[ -n "$ARCHIVE" ]]; then
  APP="$ARCHIVE/Products/Applications/QuitNic.app"
  if [[ ! -d "$APP" ]]; then
    fail "archive does not contain Products/Applications/QuitNic.app"
  else
    ARCHIVE_BUNDLE="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Info.plist" 2>/dev/null || true)"
    ARCHIVE_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Info.plist" 2>/dev/null || true)"
    ARCHIVE_BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP/Info.plist" 2>/dev/null || true)"
    ARCHIVE_FAMILY="$(/usr/libexec/PlistBuddy -c 'Print :UIDeviceFamily:0' "$APP/Info.plist" 2>/dev/null || true)"
    ARCHIVE_ENCRYPTION="$(/usr/libexec/PlistBuddy -c 'Print :ITSAppUsesNonExemptEncryption' "$APP/Info.plist" 2>/dev/null || true)"
    [[ "$ARCHIVE_BUNDLE" == "com.ibraimabduramanov.QuitNic" ]] && pass "archive bundle identifier is correct" || fail "archive bundle identifier is $ARCHIVE_BUNDLE"
    [[ "$ARCHIVE_VERSION" == "$MARKETING_VERSION" && "$ARCHIVE_BUILD" == "$BUILD_VERSION" ]] && pass "archive version is $ARCHIVE_VERSION ($ARCHIVE_BUILD)" || fail "archive version is $ARCHIVE_VERSION ($ARCHIVE_BUILD), expected $MARKETING_VERSION ($BUILD_VERSION)"
    [[ "$ARCHIVE_FAMILY" == "1" ]] && pass "archive targets iPhone" || fail "archive UIDeviceFamily is not iPhone-only"
    [[ "$ARCHIVE_ENCRYPTION" == "false" ]] && pass "archive declares no non-exempt encryption" || fail "archive export-compliance declaration is missing or unexpected"
    [[ -f "$APP/PrivacyInfo.xcprivacy" ]] && pass "archive contains the privacy manifest" || fail "archive is missing the privacy manifest"
    if codesign --verify --deep --strict "$APP" >/dev/null 2>&1; then
      pass "archive app has a valid signature"
    else
      fail "archive app is unsigned or its signature is invalid"
    fi
  fi
else
  warn "no .xcarchive supplied; archive payload and signature were not checked"
fi

printf '\nResult: %d failure(s), %d warning(s)\n' "$FAILURES" "$WARNINGS"
if (( FAILURES > 0 )); then
  exit 1
fi
