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
# One-time setup for the default (Developer ID) mode: in Xcode > Settings >
# Accounts, sign in with an Apple ID on team T79C3JU3NR that has access to the
# team's cloud-managed Developer ID certificate. Signing and notarization both
# use that Xcode account, as Xcode's Organizer does; nothing else is needed.
# Set NOTARIZE_TIMEOUT (seconds, default 1800) to wait longer for Apple.
set -euo pipefail

here="$(cd "$(dirname "$0")/.." && pwd)"
project="$here/App/Speedway.xcodeproj"
scheme="Speedway"
team_id="T79C3JU3NR"
notarize_timeout="${NOTARIZE_TIMEOUT:-1800}"
poll_interval=30
out="$here/build"
archive="$out/Speedway.xcarchive"
upload_dir="$out/upload"
export_dir="$out/export"
app="$export_dir/Speedway.app"

notarize=1
ad_hoc=0
for arg in "$@"; do
    case "$arg" in
        --skip-notarize) notarize=0 ;;
        --ad-hoc) ad_hoc=1; notarize=0 ;;
        -h|--help) sed -n '2,20p' "$0"; exit 0 ;;
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

rm -rf "$archive" "$upload_dir" "$export_dir"
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

    # destination "upload" re-signs with Developer ID and sends the app to
    # Apple's notary service using the Xcode account, as the Organizer's Direct
    # Distribution does. "export" only re-signs and writes the app locally.
    if (( notarize )); then
        destination="upload"
        log "signing with Developer ID and uploading for notarization"
    else
        destination="export"
        log "signing with Developer ID (not notarizing)"
    fi
    export_options="$out/ExportOptions.plist"
    cat > "$export_options" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>developer-id</string>
    <key>destination</key>
    <string>$destination</string>
    <key>signingStyle</key>
    <string>automatic</string>
    <key>teamID</key>
    <string>$team_id</string>
</dict>
</plist>
EOF
    # With "upload", the export path only receives xcodebuild's summary and
    # logs; the signed app is fetched after notarization below.
    if (( notarize )); then
        export_path="$upload_dir"
    else
        export_path="$export_dir"
    fi
    xcodebuild -exportArchive \
        -archivePath "$archive" \
        -exportOptionsPlist "$export_options" \
        -exportPath "$export_path" \
        -allowProvisioningUpdates \
        -quiet

    if (( notarize )); then
        # -exportNotarizedApp fails until Apple has accepted the upload, then
        # writes the notarized app with its ticket already stapled. It has no
        # wait option, so poll it.
        log "waiting for Apple to notarize (usually a few minutes; timeout ${notarize_timeout}s)"
        attempt_log="$out/notarized-export.log"
        deadline=$(( SECONDS + notarize_timeout ))
        until xcodebuild -exportNotarizedApp \
                -archivePath "$archive" \
                -exportPath "$export_dir" > "$attempt_log" 2>&1; do
            if (( SECONDS >= deadline )); then
                echo "package-app.sh: notarization not finished after ${notarize_timeout}s; last attempt:" >&2
                tail -20 "$attempt_log" >&2
                echo "package-app.sh: details are in Xcode's distribution logs, or Window > Organizer in Xcode." >&2
                exit 1
            fi
            log "not notarized yet; checking again in ${poll_interval}s"
            sleep "$poll_interval"
        done
    fi
fi

[[ -d "$app" ]] || die "build produced no $app"
codesign --verify --deep --strict --verbose=2 "$app"
if (( ad_hoc )); then
    log "signed: ad hoc ($(codesign -dvv "$app" 2>&1 | grep -m1 '^Signature='))"
else
    log "signed: $(codesign -dvv "$app" 2>&1 | grep -m1 '^Authority=')"
fi

if (( notarize )); then
    # Confirm the ticket is stapled (so Gatekeeper can verify it offline on
    # first launch) and that Gatekeeper accepts the app.
    xcrun stapler validate "$app"
    spctl --assess --type execute --verbose=2 "$app"
else
    log "not notarized; recipients must use Open Anyway once per build"
fi

version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist")"
if (( ad_hoc )); then
    zip="$out/Speedway-$version-adhoc.zip"
else
    zip="$out/Speedway-$version.zip"
fi
rm -f "$zip"
# ditto keeps the bundle's symlinks, extended attributes, signature and
# stapled ticket intact; plain zip does not.
ditto -c -k --keepParent "$app" "$zip"
log "done: $zip"
