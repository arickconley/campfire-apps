#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
check_dir=$(mktemp -d "${TMPDIR:-/tmp}/campfire-ux-checks.XXXXXX")
trap 'rm -rf "$check_dir"' EXIT
xcrun swiftc "$@" -module-cache-path "$check_dir/modules" \
  Shared/CampfireAPI.swift Shared/PostsStore.swift Shared/Ink.swift Shared/RichNote.swift Shared/LegacyMarkdown.swift \
  Shared/RichInk.swift Shared/AppAppearance.swift Shared/BlogConnection.swift Shared/SetupCode.swift Shared/MetaDescriptionEditor.swift Mac/MacDrafts.swift Mac/MacEditor.swift \
  Checks/HTMLAPIProtocol.swift Checks/SharedChecks.swift Checks/MacUXChecks.swift -o "$check_dir/checks"
"$check_dir/checks"
