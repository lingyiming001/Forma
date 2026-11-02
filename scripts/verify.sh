#!/bin/zsh
set -euo pipefail
project_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$project_root"
mkdir -p .agents/test
python3 scripts/check-architecture.py
python3 scripts/check-localizations.py
swift test --package-path Packages/FormaKit > .agents/test/unit-tests.log 2>&1 || { tail -70 .agents/test/unit-tests.log; exit 1; }
./scripts/build.sh Debug
rm -f .agents/test/integration-results.json
./deploy/build/Forma.app/Contents/MacOS/Forma --verify "$project_root/.agents/test" > .agents/test/app-verification.log 2>&1 || { cat .agents/test/app-verification.log; cat .agents/test/integration-results.json 2>/dev/null; exit 1; }
cat .agents/test/integration-results.json
print '\n验证通过；截图、文件和报告位于 .agents/test/'
