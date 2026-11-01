#!/bin/sh
# Installs (or updates) soundya over SSH — for speakers with dropbear/openssh
# set up (e.g. via tailscale), where adb is not needed:
#   sh scripts/deploy-ssh.sh root@192.168.1.228 2222
#   sh scripts/deploy-ssh.sh soundya.local
# Port is optional (default 22). Keys must already allow a non-interactive login.
set -u
cd "$(dirname "$0")/.."
TARGET=${1:?usage: scripts/deploy-ssh.sh <user@host> [port]}
PORT=${2:-22}
TAR=dist/soundya-armv7.tar
[ -f "$TAR" ] || { echo "no $TAR: build it first (see scripts/build-mac.sh)" >&2; exit 1; }
SIZE=$(wc -c < "$TAR" | tr -d ' ')
SSH="ssh -p $PORT -o ConnectTimeout=5 -o BatchMode=yes"

retry() {
    i=1
    while [ "$i" -le 4 ]; do
        "$@" && return 0
        echo "  не вышло, попытка $((i + 1)) из 4…" >&2
        i=$((i + 1))
        sleep 3
    done
    return 1
}

upload() {
    cat "$TAR" | $SSH "$TARGET" "cat > /tmp/soundya-armv7.tar" &&
        [ "$($SSH "$TARGET" "wc -c < /tmp/soundya-armv7.tar" | tr -d ' \r')" = "$SIZE" ]
}

start_install() {
    # The same way the init script starts soundya (nohup + setsid): a dropped
    # connection cannot leave it half-done.
    $SSH "$TARGET" "cd /tmp && rm -rf soundya /tmp/soundya-install.done /tmp/soundya-install.log && \
        tar -xf soundya-armv7.tar && \
        nohup setsid sh -c 'sh /tmp/soundya/install.sh > /tmp/soundya-install.log 2>&1; touch /tmp/soundya-install.done' \
        </dev/null >/dev/null 2>&1 & sleep 1; [ -f /tmp/soundya-install.log ]" &&
        { sleep 2; $SSH "$TARGET" "[ -f /tmp/soundya-install.log ]"; }
}

installed() {
    LOGTEXT=$($SSH "$TARGET" "[ -f /tmp/soundya-install.done ] && cat /tmp/soundya-install.log" 2>/dev/null)
    printf '%s' "$LOGTEXT" | grep -q "Installed"
}

echo "Загружаю на колонку $TARGET (порт $PORT)…"
retry upload || { echo "Не удалось загрузить: колонка недоступна по ssh." >&2; exit 1; }
echo "Устанавливаю…"
retry start_install || { echo "Не удалось запустить установку." >&2; exit 1; }
for _ in $(seq 20); do
    sleep 2
    if installed; then
        printf '%s\n' "$LOGTEXT"
        exit 0
    fi
done
echo "Не дождался конца установки. Посмотрите: ssh -p $PORT $TARGET cat /tmp/soundya-install.log" >&2
exit 1
