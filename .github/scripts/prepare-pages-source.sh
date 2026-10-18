#!/usr/bin/env bash
set -euo pipefail
rm -rf .pages-source _site
mkdir -p .pages-source/docs .pages-source/.config
stage_markdown() {
  local source="$1"
  local destination=".pages-source/$source"
  mkdir -p "$(dirname "$destination")"
  if head -n 1 "$source" | grep -qx -- '---'; then
    cp "$source" "$destination"
  else
    {
      printf '%s\n' '---' 'layout: default' '---' ''
      cat "$source"
    } > "$destination"
  fi
}
stage_markdown README.md
stage_markdown CHANGELOG.md
cp LICENSE .pages-source/
cp .config/test-frameworks.json .config/static-analysis.json .pages-source/.config/
cp _config.yml search-index.json .pages-source/
cp install.ps1 install.sh .pages-source/
cp -R _data _layouts assets .pages-source/
while IFS= read -r -d '' file; do
  stage_markdown "$file"
done < <(find docs -type f -name '*.md' -print0)
node --check .pages-source/assets/js/site.js
test -f .pages-source/install.ps1
test -f .pages-source/install.sh
test ! -e .pages-source/tests
test ! -e .pages-source/scripts
test ! -e .pages-source/dotnet-install.sh
test ! -e .pages-source/dotnet-install.ps1
test ! -e .pages-source/isolated-dotnet-sdk.sh
test ! -e .pages-source/isolated-dotnet-sdk.ps1
