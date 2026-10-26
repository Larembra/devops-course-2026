#!/usr/bin/env bash
# Доставка статического ресурса на devops-vm
# Использование: scripts/deploy.sh [--dry-run]
set -euo pipefail

REMOTE="devops"
REMOTE_DIR="/var/www/devops-site"
SITE_URL="https://devops.local"
CA_CERT="${HOME}/devops.crt"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && git rev-parse --show-toplevel)"
LOCAL_DIR="${REPO_ROOT}/site/"

# 1. Разбор аргумента --dry-run
DRY_RUN=0
case "${1:-}" in
  "")        ;;
  --dry-run) DRY_RUN=1 ;;
  *) echo "Использование: $0 [--dry-run]" >&2; exit 2 ;;
esac

# 2. Проверки по требованиям 4 и 5
if [[ ! -f "${LOCAL_DIR}index.html" ]]; then
  echo "Ошибка: файл site/index.html отсутствует, доставка отменена" >&2
  exit 1
fi
if [[ -n "$(git -C "${REPO_ROOT}" status --porcelain)" ]]; then
  echo "Ошибка: есть незафиксированные изменения, доставка отменена" >&2
  exit 1
fi

# 3. Синхронизация (одно SSH-соединение за запуск)
RSYNC_OPTS=(-az --no-owner --no-group --delete --chmod=D755,F644 -v
            -e "ssh -o BatchMode=yes -o ConnectTimeout=5")
if [[ ${DRY_RUN} -eq 1 ]]; then
  RSYNC_OPTS+=(--dry-run)
fi
rsync "${RSYNC_OPTS[@]}" "${LOCAL_DIR}" "${REMOTE}:${REMOTE_DIR}/"

# 4. При --dry-run: завершение без проверки доступности
if [[ ${DRY_RUN} -eq 1 ]]; then
  echo "dry-run: план выведен, состояние сервера не изменено"
  exit 0
fi

# 5. Проверка доступности с проверкой сертификата (без -k)
if ! curl -fsS --max-time 10 --cacert "${CA_CERT}" -o /dev/null "${SITE_URL}/"; then
  echo "Ошибка: ${SITE_URL} недоступен после доставки" >&2
  exit 1
fi
echo "Доставлен коммит $(git -C "${REPO_ROOT}" rev-parse --short HEAD)"
