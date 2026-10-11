#!/bin/sh
set -eu

app_path=$1
bundle_id=$2

if ! xcrun simctl list devices booted | grep -q 'Booted'; then
    device_id=$(xcrun simctl list devices available | while IFS= read -r line; do
        case "$line" in
            *iPhone*)
                printf '%s\n' "$line" | cut -d '(' -f 2 | cut -d ')' -f 1
                break
                ;;
        esac
    done)
    if [ -z "$device_id" ]; then
        echo "no available iPhone simulator devices found" >&2
        exit 1
    fi
    xcrun simctl boot "$device_id"
    xcrun simctl bootstatus "$device_id" -b
fi

open -a Simulator
xcrun simctl install booted "$app_path"
xcrun simctl launch --console-pty booted "$bundle_id"
