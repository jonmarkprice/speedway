#!/usr/bin/env bash
# Builds a Developer ID-signed, notarized, stapled Speedway.app from the command
# line, zipped for sharing. Recipients can open it with no Gatekeeper warning.
#
#   scripts/package-app.sh                  # web build, archive, sign, notarize, zip
#   scripts/package-app.sh --skip-notarize  # stop after signing (faster, for testing)
#   scripts/package-app.sh --ad-hoc         # no Apple account needed; see below
#
# Output: build/Speedway-<version>.zip, or build/Speedway-<version>-adhoc.zip
# with --ad-hoc (and build/export/Speedway.app either way).
#
# --ad-hoc signs with no certificate, so it needs no Apple account, team
# membership or provisioning profile. Recipients must allow the app once per
# build: open it, then System Settings > Privacy & Security > Open Anyway.
#
# One-time setup per developer for the default (Developer ID) mode
# (see README "Distributing Speedway.app"):
#   1. Xcode > Settings > Accounts: sign in with an Apple ID on team T79C3JU3NR
#      whose role can use a Developer ID Application certificate.
#   2. Store notarization credentials in the keychain under a profile name:
#        xcrun notarytool store-credentials speedway-notary \
#          --apple-id <you@khanacademy.org> --team-id T79C3JU3NR
#      (it prompts for an app-specific password from account.apple.com).
#      Set NOTARY_PROFILE to use a different profile name.
set -euo pipefail

here="$(cd "$(dirname "$0")/.." && pwd)"
project="$here/App/Speedway.xcodeproj"
scheme="Speedway"
team_id="T79C3JU3NR"
notary_profile="${NOTARY_PROFILE:-speedway-notary}"
out="$here/build"
archive="$out/Speedway.xcarchive"
export_dir="$out/export"
app="$export_dir/Speedway.app"

notarize=1
ad_hoc=0
for arg in "$@"; do
    case "$arg" in
        --skip-notarize) notarize=0 ;;
        --ad-hoc) ad_hoc=1; notarize=0 ;;
        -h|--help) sed -n '2,24p' "$0"; exit 0 ;;
        *) echo "package-app.sh: unknown argument: $arg" >&2; exit 2 ;;
    esac
done

log() { echo "package-app.sh: $*"; }
die() { echo "package-app.sh: $*" >&2; exit 1; }

# xcodebuild needs the full Xcode, not the command line tools. DEVELOPER_DIR,
# if set, wins over xcode-select.
developer_dir="${DEVELOPER_DIR:-$(xcode-select -p)}"
if [[ "$developer_dir" != *.app/Contents/Developer ]]; then
    die "xcodebuild needs Xcode, but the developer dir is $developer_dir.
  Run: sudo xcode-select -s /Applications/Xcode.app (or set DEVELOPER_DIR)."
fi

# Always package a fresh web build, so the app never ships stale web assets.
"$here/scripts/build-web.sh"

rm -rf "$archive" "$export_dir"
mkdir -p "$out"

archive_args=(
    -project "$project"
    -scheme "$scheme"
    -configuration Release
    -destination "generic/platform=macOS"
    -archivePath "$archive"
    -quiet
)

if (( ad_hoc )); then
    log "archiving $scheme (Release), signing ad hoc"
    # Identity "-" is an ad-hoc signature: no certificate, so no team and no
    # profile. Xcode still applies the entitlements and Hardened Runtime.
    xcodebuild archive "${archive_args[@]}" \
        CODE_SIGN_STYLE=Manual \
        CODE_SIGN_IDENTITY=- \
        DEVELOPMENT_TEAM= \
        PROVISIONING_PROFILE_SPECIFIER=
    # An ad-hoc build is not exported (export re-signs with a certificate), so
    # take the app straight from the archive.
    mkdir -p "$export_dir"
    ditto "$archive/Products/Applications/Speedway.app" "$app"
else
    log "archiving $scheme (Release)"
    # -allowProvisioningUpdates lets xcodebuild use the Xcode account to create
    # or download certificates and profiles, which is what automatic signing
    # does in the IDE.
    xcodebuild archive "${archive_args[@]}" -allowProvisioningUpdates
fi

if (( ! ad_hoc )); then
log "exporting with Developer ID signing"
export_options="$out/ExportOptions.plist"
cat > "$export_options" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>developer-id</string>
    <key>destination</key>
    <string>export</string>
    <key>signingStyle</key>
    <string>automatic</string>
    <key>teamID</key>
    <string>$team_id</string>
</dict>
</plist>
EOF
xcodebuild -exportArchive \
    -archivePath "$archive" \
    -exportOptionsPlist "$export_options" \
    -exportPath "$export_dir" \
    -allowProvisioningUpdates \
    -quiet
fi

[[ -d "$app" ]] || die "build produced no $app"
codesign --verify --deep --strict --verbose=2 "$app"
if (( ad_hoc )); then
    log "signed: ad hoc ($(codesign -dvv "$app" 2>&1 | grep -m1 '^Signature='))"
else
    log "signed: $(codesign -dvv "$app" 2>&1 | grep -m1 '^Authority=')"
fi

version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist")"
if (( ad_hoc )); then
    zip="$out/Speedway-$version-adhoc.zip"
else
    zip="$out/Speedway-$version.zip"
fi
rm -f "$zip"

if (( notarize )); then
    # notarytool takes a zip, not a bare .app. ditto keeps the bundle's
    # symlinks, extended attributes and signature intact; plain zip does not.
    submission="$out/Speedway-notarize.zip"
    ditto -c -k --keepParent "$app" "$submission"

    log "submitting to the notary service (usually a few minutes)"
    result="$out/notarize-result.json"
    xcrun notarytool submit "$submission" \
        --keychain-profile "$notary_profile" \
        --wait \
        --output-format json > "$result"
    status="$(plutil -extract status raw -o - "$result")"
    id="$(plutil -extract id raw -o - "$result")"
    if [[ "$status" != "Accepted" ]]; then
        echo "package-app.sh: notarization $status; log follows" >&2
        xcrun notarytool log "$id" --keychain-profile "$notary_profile" >&2 || true
        exit 1
    fi
    rm -f "$submission"

    # Stapling attaches the notarization ticket to the app, so Gatekeeper can
    # verify it offline on first launch.
    xcrun stapler staple "$app"
    xcrun stapler validate "$app"
    spctl --assess --type execute --verbose=2 "$app"
else
    log "not notarized; recipients must use Open Anyway once per build"
fi

# Re-zip after stapling, so the shared zip carries the ticket.
ditto -c -k --keepParent "$app" "$zip"
log "done: $zip"
