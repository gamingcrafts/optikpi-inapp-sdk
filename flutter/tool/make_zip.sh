#!/usr/bin/env bash
# Builds optikpi_inapp-<version>.zip from this folder alone: the package source and its docs.
# Tests stay out, because they read the shared fixtures in ../contract, which the zip doesn't carry.
#   tool/make_zip.sh [output-dir]
set -euo pipefail

pkg_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
out_dir="${1:-$pkg_dir/dist}"
version="$(sed -n 's/^version:[[:space:]]*\([^[:space:]]*\).*/\1/p' "$pkg_dir/pubspec.yaml")"
[ -n "$version" ] || { echo "no version in pubspec.yaml" >&2; exit 1; }

mkdir -p "$out_dir"
out_dir="$(cd "$out_dir" && pwd)"
zip_path="$out_dir/optikpi_inapp-$version.zip"
stage="$(mktemp -d)"
trap 'rm -rf "$stage"' EXIT

mkdir "$stage/optikpi_inapp"
# Copy an allow-list, so nothing the developer has lying around ends up in the client's repo.
for entry in lib tool CHANGELOG.md README.md LICENSE pubspec.yaml analysis_options.yaml; do
  if [ -e "$pkg_dir/$entry" ]; then cp -R "$pkg_dir/$entry" "$stage/optikpi_inapp/"; fi
done
find "$stage/optikpi_inapp" \( -name build -o -name .dart_tool -o -name failures \) -prune -exec rm -rf {} +
find "$stage/optikpi_inapp" \( -name '.DS_Store' -o -name '*.iml' \) -delete

rm -f "$zip_path"
(cd "$stage" && zip -qr "$zip_path" optikpi_inapp)
echo "$zip_path"
