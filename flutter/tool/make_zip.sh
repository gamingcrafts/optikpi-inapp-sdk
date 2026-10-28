#!/usr/bin/env bash
# Builds optikpi_popup-<version>.zip next to the package: the package source, docs and tests,
# without build output, tool caches or the lock file.
#   tool/make_zip.sh [output-dir]
set -euo pipefail

pkg_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
out_dir="${1:-$pkg_dir/dist}"
version="$(sed -n 's/^version:[[:space:]]*\([^[:space:]]*\).*/\1/p' "$pkg_dir/pubspec.yaml")"
[ -n "$version" ] || { echo "no version in pubspec.yaml" >&2; exit 1; }

mkdir -p "$out_dir"
out_dir="$(cd "$out_dir" && pwd)"
zip_path="$out_dir/optikpi_popup-$version.zip"
stage="$(mktemp -d)"
trap 'rm -rf "$stage"' EXIT

mkdir "$stage/optikpi_popup"
# Copy an allow-list, so nothing the developer has lying around ends up in the client's repo.
for entry in lib test tool API.md CHANGELOG.md README.md pubspec.yaml analysis_options.yaml dart_test.yaml; do
  if [ -e "$pkg_dir/$entry" ]; then cp -R "$pkg_dir/$entry" "$stage/optikpi_popup/"; fi
done
find "$stage/optikpi_popup" \( -name build -o -name .dart_tool -o -name failures \) -prune -exec rm -rf {} +
find "$stage/optikpi_popup" \( -name '.DS_Store' -o -name '*.iml' \) -delete

rm -f "$zip_path"
(cd "$stage" && zip -qr "$zip_path" optikpi_popup)
echo "$zip_path"
