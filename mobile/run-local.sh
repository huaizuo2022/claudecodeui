#!/bin/bash
# Runs or builds the personal build with the seed token from mobile/.env.local
# (gitignored). Everything lands in the binary; nothing is committed.
#
#   ./run-local.sh run -d <device>      # flutter run
#   ./run-local.sh build ios --simulator
#   ./run-local.sh test
set -euo pipefail
cd "$(dirname "$0")"

if [ ! -f .env.local ]; then
  echo "缺 mobile/.env.local。先生成并写入：" >&2
  echo "  ./scripts/mint-seed-token.sh" >&2
  echo "  echo \"CLOUDCLI_SERVER_URL=https://claude.huaizuo2029.cn\" > .env.local" >&2
  echo "  echo \"CLOUDCLI_TOKEN=<上面那条命令的输出>\" >> .env.local" >&2
  exit 1
fi

# shellcheck disable=SC1091
source .env.local

CMD="${1:-run}"
if [ $# -gt 0 ]; then shift; fi

exec flutter "$CMD" "$@" \
  --dart-define=CLOUDCLI_SERVER_URL="$CLOUDCLI_SERVER_URL" \
  --dart-define=CLOUDCLI_TOKEN="$CLOUDCLI_TOKEN"
