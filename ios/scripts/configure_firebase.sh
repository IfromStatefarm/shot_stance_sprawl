#!/bin/sh

set -eu

case "${FIREBASE_ENVIRONMENT:-}" in
  dev)
    expected_project_id="snap-and-go-dev"
    ;;
  prod)
    expected_project_id="snap-and-go-prod"
    ;;
  *)
    echo "error: FIREBASE_ENVIRONMENT must be dev or prod; got '${FIREBASE_ENVIRONMENT:-unset}'." >&2
    exit 1
    ;;
esac

source_plist="${SRCROOT}/../firebase/environments/${FIREBASE_ENVIRONMENT}/GoogleService-Info.plist"
destination_dir="${TARGET_BUILD_DIR}/${UNLOCALIZED_RESOURCES_FOLDER_PATH}"
destination_plist="${destination_dir}/GoogleService-Info.plist"
built_info_plist="${TARGET_BUILD_DIR}/${INFOPLIST_PATH}"
plist_buddy="/usr/libexec/PlistBuddy"

if [ ! -f "${source_plist}" ]; then
  echo "error: Missing ${source_plist}." >&2
  echo "error: Download the iOS Firebase configuration for ${expected_project_id}; see docs/ios_release.md." >&2
  exit 1
fi

actual_project_id="$(${plist_buddy} -c 'Print :PROJECT_ID' "${source_plist}" 2>/dev/null || true)"
actual_bundle_id="$(${plist_buddy} -c 'Print :BUNDLE_ID' "${source_plist}" 2>/dev/null || true)"
google_client_id="$(${plist_buddy} -c 'Print :CLIENT_ID' "${source_plist}" 2>/dev/null || true)"
reversed_client_id="$(${plist_buddy} -c 'Print :REVERSED_CLIENT_ID' "${source_plist}" 2>/dev/null || true)"

if [ "${actual_project_id}" != "${expected_project_id}" ]; then
  echo "error: ${source_plist} targets '${actual_project_id:-unknown}', expected '${expected_project_id}'." >&2
  exit 1
fi

if [ "${actual_bundle_id}" != "${PRODUCT_BUNDLE_IDENTIFIER}" ]; then
  echo "error: ${source_plist} targets bundle '${actual_bundle_id:-unknown}', expected '${PRODUCT_BUNDLE_IDENTIFIER}'." >&2
  exit 1
fi

if [ -z "${google_client_id}" ] || [ -z "${reversed_client_id}" ]; then
  echo "error: ${source_plist} has no Google CLIENT_ID/REVERSED_CLIENT_ID. Enable Google authentication and download it again." >&2
  exit 1
fi

mkdir -p "${destination_dir}"
cp "${source_plist}" "${destination_plist}"

# google_sign_in_ios needs both the client ID and its reversed URL scheme. Add
# them to the built Info.plist so dev and prod can use distinct Firebase apps.
${plist_buddy} -c "Set :GIDClientID ${google_client_id}" "${built_info_plist}" 2>/dev/null || \
  ${plist_buddy} -c "Add :GIDClientID string ${google_client_id}" "${built_info_plist}"

url_type_index="$(${plist_buddy} -c 'Print :CFBundleURLTypes' "${built_info_plist}" | grep -c 'Dict {' | tr -d ' ')"
${plist_buddy} -c "Add :CFBundleURLTypes:${url_type_index} dict" "${built_info_plist}"
${plist_buddy} -c "Add :CFBundleURLTypes:${url_type_index}:CFBundleTypeRole string Editor" "${built_info_plist}"
${plist_buddy} -c "Add :CFBundleURLTypes:${url_type_index}:CFBundleURLSchemes array" "${built_info_plist}"
${plist_buddy} -c "Add :CFBundleURLTypes:${url_type_index}:CFBundleURLSchemes:0 string ${reversed_client_id}" "${built_info_plist}"

echo "Configured Firebase project ${actual_project_id} for ${PRODUCT_BUNDLE_IDENTIFIER}."
