#!/usr/bin/env bash
set -euo pipefail
test -f _site/index.html
test -f _site/docs/index.html
test -f _site/docs/commands/install.html
test -f _site/docs/getting-started/windows-powershell.html
test -f _site/docs/getting-started/linux-macos-bash.html
test -f _site/assets/search-index.json
test -f _site/assets/css/site.css
test -f _site/assets/js/site.js
test -f _site/install.ps1
test -f _site/install.sh
cmp install.ps1 _site/install.ps1
cmp install.sh _site/install.sh
python -m json.tool _site/assets/search-index.json >/dev/null
grep -q 'class="docs-nav"' _site/index.html
grep -q 'Search documentation' _site/index.html
grep -q 'Getting Started' _site/index.html
grep -q 'docs/commands/install.html' _site/index.html
grep -q 'aria-current="page"' _site/docs/commands/install.html
grep -q '"title": "Install"' _site/assets/search-index.json
for release_notes in .github/release-notes/v*.md; do
  [[ -e "$release_notes" ]] || continue
  tag="$(basename "$release_notes" .md)"
  history_source="docs/releases/history/$tag.md"
  history_link="history/$tag.md"
  history_page="_site/docs/releases/history/$tag.html"
  if [[ ! -f "$history_source" ]]; then
    printf 'Release history missing for %s: %s\n' "$tag" "$history_source" >&2
    exit 1
  fi
  if ! grep -Fq "$history_link" docs/releases/README.md; then
    printf 'Releases overview does not link %s\n' "$history_source" >&2
    exit 1
  fi
  if ! grep -Fq "path: $history_source" _data/navigation.yml; then
    printf 'Pages navigation does not include %s\n' "$history_source" >&2
    exit 1
  fi
  if [[ ! -f "$history_page" ]]; then
    printf 'Release history page did not generate: %s\n' "$history_page" >&2
    exit 1
  fi
  if ! grep -Fq "docs/releases/history/$tag.html" _site/assets/search-index.json; then
    printf 'Release history is missing from the Pages search index: %s\n' "$tag" >&2
    exit 1
  fi
done
while IFS= read -r path; do
  case "$path" in
    README.md) generated="_site/index.html" ;;
    */README.md) generated="_site/$(dirname "$path")/index.html" ;;
    *.md) generated="_site/$(dirname "$path")/$(basename "$path" .md).html" ;;
    *) generated="_site/$path" ;;
  esac
  if [[ ! -f "$generated" ]]; then
    printf 'Navigation target did not generate: %s -> %s\n' "$path" "$generated" >&2
    exit 1
  fi
done < <(awk '/^[[:space:]]+path:/ { print $2 }' _data/navigation.yml)
test ! -e _site/tests
test ! -e _site/scripts
test ! -e _site/isolated-dotnet-sdk.sh
test ! -e _site/isolated-dotnet-sdk.ps1
