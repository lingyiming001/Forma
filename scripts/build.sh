#!/bin/zsh
set -euo pipefail
project_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$project_root"
configuration="${1:-Debug}"
case "$configuration" in
  Debug|Release) ;;
  *) print -u2 "配置仅支持 Debug 或 Release"; exit 2 ;;
esac
mkdir -p .agents deploy/build
xcodebuild -project Forma.xcodeproj -scheme Forma -configuration "$configuration" \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath .agents/DerivedData \
  CODE_SIGNING_ALLOWED=NO build > .agents/build.log 2>&1 || { tail -70 .agents/build.log; exit 1; }
# 只清理本脚本生成的 bundle，避免 Debug / Release 或旧资源混入新包。
python3 - <<'CLEAN'
from pathlib import Path
import shutil
bundle=Path('deploy/build/Forma.app')
if bundle.is_symlink():
    raise RuntimeError('Refusing to replace a symbolic-link application bundle')
if bundle.exists():
    shutil.rmtree(bundle)
CLEAN
ditto ".agents/DerivedData/Build/Products/$configuration/Forma.app" deploy/build/Forma.app
print "已构建：$project_root/deploy/build/Forma.app"
