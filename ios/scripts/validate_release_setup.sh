#!/bin/sh

set -eu

repo_root="$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)"
prod_plist="${repo_root}/firebase/environments/prod/GoogleService-Info.plist"
signing_config="${repo_root}/ios/Flutter/Signing.xcconfig"
plist_buddy="/usr/libexec/PlistBuddy"

if [ "$(uname -s)" != "Darwin" ]; then
  echo "error: iOS release validation must run on macOS." >&2
  exit 1
fi

for command_name in flutter pod xcodebuild codesign; do
  if ! command -v "${command_name}" >/dev/null 2>&1; then
    echo "error: Required command '${command_name}' was not found." >&2
    exit 1
  fi
done

if [ ! -f "${prod_plist}" ]; then
  echo "error: Missing ${prod_plist}." >&2
  exit 1
fi

project_id="$(${plist_buddy} -c 'Print :PROJECT_ID' "${prod_plist}")"
bundle_id="$(${plist_buddy} -c 'Print :BUNDLE_ID' "${prod_plist}")"
if [ "${project_id}" != "snap-and-go-prod" ] || [ "${bundle_id}" != "com.snapandgo.shadowwrestling" ]; then
  echo "error: Production Firebase plist has the wrong project or bundle ID." >&2
  exit 1
fi

if [ ! -f "${signing_config}" ] || ! grep -Eq '^APPLE_DEVELOPMENT_TEAM = [A-Z0-9]{10}$' "${signing_config}"; then
  echo "error: Copy ios/Flutter/Signing.xcconfig.example to Signing.xcconfig and set the Apple Team ID." >&2
  exit 1
fi

team_id="$(sed -n 's/^APPLE_DEVELOPMENT_TEAM = //p' "${signing_config}" | head -n 1)"
if [ "${team_id}" = "ABCDE12345" ]; then
  echo "error: Signing.xcconfig still contains the example Apple Team ID." >&2
  exit 1
fi

cd "${repo_root}"
flutter pub get
(
  cd ios
  pod install --repo-update
)
flutter analyze
flutter test
flutter build ipa --release --dart-define=FIREBASE_ENV=prod

archive_app="${repo_root}/build/ios/archive/Runner.xcarchive/Products/Applications/Runner.app"
bundled_plist="${archive_app}/GoogleService-Info.plist"
if [ ! -d "${archive_app}" ] || [ ! -f "${bundled_plist}" ]; then
  echo "error: The archive or its bundled Firebase configuration is missing." >&2
  exit 1
fi

codesign --verify --deep --strict --verbose=2 "${archive_app}"

bundled_project_id="$(${plist_buddy} -c 'Print :PROJECT_ID' "${bundled_plist}")"
if [ "${bundled_project_id}" != "snap-and-go-prod" ]; then
  echo "error: Archived app contains Firebase project '${bundled_project_id}', not production." >&2
  exit 1
fi

archive_info="${archive_app}/Info.plist"
google_client_id="$(${plist_buddy} -c 'Print :CLIENT_ID' "${bundled_plist}")"
reversed_client_id="$(${plist_buddy} -c 'Print :REVERSED_CLIENT_ID' "${bundled_plist}")"
archived_client_id="$(${plist_buddy} -c 'Print :GIDClientID' "${archive_info}")"
if [ "${archived_client_id}" != "${google_client_id}" ] || \
   ! ${plist_buddy} -c 'Print :CFBundleURLTypes' "${archive_info}" | grep -Fq "${reversed_client_id}"; then
  echo "error: Archived Google sign-in client ID or callback URL scheme is missing." >&2
  exit 1
fi

archive_entitlements="$(mktemp "${TMPDIR:-/tmp}/snap-and-go-entitlements.XXXXXX")"
trap 'rm -f "${archive_entitlements}"' EXIT
codesign -d --entitlements :- "${archive_app}" >"${archive_entitlements}"

aps_environment="$(${plist_buddy} -c 'Print :aps-environment' "${archive_entitlements}")"
app_attest_environment="$(${plist_buddy} -c 'Print :com.apple.developer.devicecheck.appattest-environment' "${archive_entitlements}")"
apple_sign_in="$(${plist_buddy} -c 'Print :com.apple.developer.applesignin:0' "${archive_entitlements}")"
if [ "${aps_environment}" != "production" ] || \
   [ "${app_attest_environment}" != "production" ] || \
   [ "${apple_sign_in}" != "Default" ]; then
  echo "error: Archived signing entitlements are incomplete or not production." >&2
  exit 1
fi

echo "Release archive, signature, production Firebase plist, and entitlements validated."
echo "Archive: build/ios/archive/Runner.xcarchive"
echo "IPA: build/ios/ipa"
echo "Upload it with Xcode Organizer or Transporter, then complete the TestFlight checks in docs/ios_release.md."
