#!/bin/zsh
set -euo pipefail
project_root="$(cd "$(dirname "$0")/.." && pwd)"
"$project_root/scripts/build.sh" Debug
open "$project_root/deploy/build/Forma.app"
