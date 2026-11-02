#!/bin/zsh
set -euo pipefail

project_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$project_root"

installed="/Applications/Forma.app"
staged="/Applications/.Forma-install-$$.app"
previous="$project_root/deploy/.Forma-previous-install-$$.app"
built="$project_root/deploy/build/Forma.app"
archive="$project_root/deploy/Forma.app.zip"
staged_archive="$project_root/deploy/.Forma-install-$$.zip"

if pgrep -f '^/Applications/Forma.app/Contents/MacOS/Forma$' >/dev/null; then
  print -u2 "请先退出正在运行的 Forma，再部署。"
  exit 1
fi
[[ ! -e "$staged" && ! -e "$previous" && ! -e "$staged_archive" ]] || {
  print -u2 "临时路径已被占用。"; exit 1
}

./scripts/build.sh Release
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$built/Contents/Info.plist")" == "com.forma.diagram.app" ]]

# 保留压缩交付包，避免第二个可启动的 .app 被 Launchpad 收录。
ditto -c -k --sequesterRsrc --keepParent "$built" "$staged_archive"
python3 - "$staged_archive" "$archive" <<'PY'
import os
import pathlib
import sys

source, target = map(pathlib.Path, sys.argv[1:])
if target.exists():
    assert target.is_file() and not target.is_symlink()
os.replace(source, target)
PY
ditto "$built" "$staged"
source_hash="$(shasum -a 256 "$built/Contents/MacOS/Forma" | awk '{print $1}')"
staged_hash="$(shasum -a 256 "$staged/Contents/MacOS/Forma" | awk '{print $1}')"
[[ "$source_hash" == "$staged_hash" ]]

if [[ -d "$installed" ]]; then
  [[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$installed/Contents/Info.plist")" == "com.forma.diagram.app" ]]
  mv "$installed" "$previous"
fi
if ! mv "$staged" "$installed"; then
  [[ ! -d "$previous" ]] || mv "$previous" "$installed"
  exit 1
fi
installed_hash="$(shasum -a 256 "$installed/Contents/MacOS/Forma" | awk '{print $1}')"
[[ "$source_hash" == "$installed_hash" ]]

python3 - "$project_root" "$previous" "$built" <<'PY'
import pathlib
import plistlib
import shutil
import sys

root, previous, built = map(pathlib.Path, sys.argv[1:])
allowed = {root / 'deploy' / 'build' / 'Forma.app', previous}
assert previous.parent == root / 'deploy' and previous.name.startswith('.Forma-previous-install-')
for bundle in (previous, built):
    assert bundle in allowed
    if bundle.exists():
        assert bundle.is_dir() and not bundle.is_symlink()
        with (bundle / 'Contents' / 'Info.plist').open('rb') as file:
            assert plistlib.load(file)['CFBundleIdentifier'] == 'com.forma.diagram.app'
        shutil.rmtree(bundle)
PY
open -a "$installed"
print "已部署：$installed（SHA-256: $installed_hash）"
print "交付包：$archive"
