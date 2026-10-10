#!/bin/zsh
set -euo pipefail
project_root="${0:A:h}"
mkdir -p "$project_root/build"
swiftc -swift-version 5 "$project_root/Sources/Schedule.swift" "$project_root/Sources/Accent.swift" "$project_root/Sources/Localization.swift" "$project_root/Sources/PopoverLayout.swift" "$project_root/Sources/Termination.swift" "$project_root/Sources/Applications.swift" "$project_root/Tests/Tests.swift" -o "$project_root/build/schedule-tests"
"$project_root/build/schedule-tests"
