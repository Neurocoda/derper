#!/bin/sh
set -eu

# 显式传入命令/参数时保持 derper 原生 CLI 行为：
#   docker run IMAGE --dev
#   docker run IMAGE derper --help
#   docker run IMAGE sh
if [ "$#" -gt 0 ]; then
    case "$1" in
        derper)
            shift
            exec /usr/local/bin/derper "$@"
            ;;
        -*)
            exec /usr/local/bin/derper "$@"
            ;;
        *)
            exec "$@"
            ;;
    esac
fi

DERP_ADDR=${DERP_ADDR:-:443}
DERP_HTTP_PORT=${DERP_HTTP_PORT:-80}
DERP_STUN_PORT=${DERP_STUN_PORT:-3478}
DERP_CERTMODE=${DERP_CERTMODE:-letsencrypt}
DERP_CERTDIR=${DERP_CERTDIR:-/certs}
DERP_CONFIG=${DERP_CONFIG:-/var/lib/derper/derper.key}
DERP_VERIFY_CLIENTS=${DERP_VERIFY_CLIENTS:-false}
DERP_SOCKET=${DERP_SOCKET:-/var/run/tailscale/tailscaled.sock}
DERP_STUN=${DERP_STUN:-true}
DERP_ACME_EMAIL=${DERP_ACME_EMAIL:-}
DERP_ACME_EAB_KID=${DERP_ACME_EAB_KID:-}
DERP_ACME_EAB_KEY=${DERP_ACME_EAB_KEY:-}
DERP_HOSTNAME=${DERP_HOSTNAME:-}

case "$DERP_CERTMODE" in
    letsencrypt|manual|gcp) ;;
    *)
        echo "错误: DERP_CERTMODE 必须是 letsencrypt、manual 或 gcp" >&2
        exit 64
        ;;
esac

if [ "$DERP_CERTMODE" = "letsencrypt" ]; then
    if [ -z "$DERP_HOSTNAME" ]; then
        echo "错误: 自动签发证书需要设置 DERP_HOSTNAME（例如 derp.example.com）" >&2
        exit 64
    fi
    case "$DERP_HOSTNAME" in
        *://*|*/*|*:*|\*.*|*[!A-Za-z0-9.-]*|.*|*.|*..*)
            echo "错误: DERP_HOSTNAME 必须是普通域名，不要包含协议、端口、路径、通配符或非法字符" >&2
            exit 64
            ;;
    esac
fi

if [ -z "$DERP_HOSTNAME" ]; then
    echo "错误: 必须设置 DERP_HOSTNAME" >&2
    exit 64
fi

if [ "$DERP_CERTMODE" = "gcp" ]; then
    if [ -z "$DERP_ACME_EMAIL" ] || [ -z "$DERP_ACME_EAB_KID" ] || [ -z "$DERP_ACME_EAB_KEY" ]; then
        echo "错误: DERP_CERTMODE=gcp 需要 DERP_ACME_EMAIL、DERP_ACME_EAB_KID 和 DERP_ACME_EAB_KEY" >&2
        exit 64
    fi
fi

mkdir -p "$DERP_CERTDIR" "$(dirname "$DERP_CONFIG")"
chmod 700 "$DERP_CERTDIR" "$(dirname "$DERP_CONFIG")" 2>/dev/null || true

set -- \
    -a "$DERP_ADDR" \
    --http-port "$DERP_HTTP_PORT" \
    --stun-port "$DERP_STUN_PORT" \
    --hostname "$DERP_HOSTNAME" \
    --certmode "$DERP_CERTMODE" \
    --certdir "$DERP_CERTDIR" \
    -c "$DERP_CONFIG" \
    --stun="$DERP_STUN"

if [ -n "$DERP_ACME_EMAIL" ]; then
    set -- "$@" --acme-email "$DERP_ACME_EMAIL"
fi
if [ "$DERP_CERTMODE" = "gcp" ]; then
    set -- "$@" --acme-eab-kid "$DERP_ACME_EAB_KID" --acme-eab-key "$DERP_ACME_EAB_KEY"
fi

case "$DERP_VERIFY_CLIENTS" in
    true|1|yes)
        if [ ! -S "$DERP_SOCKET" ]; then
            echo "错误: DERP_VERIFY_CLIENTS=true，但找不到 tailscaled socket: $DERP_SOCKET" >&2
            exit 66
        fi
        set -- "$@" --verify-clients --socket "$DERP_SOCKET"
        ;;
    false|0|no) ;;
    *)
        echo "错误: DERP_VERIFY_CLIENTS 必须是 true 或 false" >&2
        exit 64
        ;;
esac

echo "启动 derper: hostname=$DERP_HOSTNAME certmode=$DERP_CERTMODE http=$DERP_HTTP_PORT https=$DERP_ADDR stun=$DERP_STUN_PORT verify-clients=$DERP_VERIFY_CLIENTS"
if [ "$DERP_CERTMODE" = "letsencrypt" ]; then
    echo "证书将由 derper 通过 Let's Encrypt 自动申请并续期，缓存目录: $DERP_CERTDIR"
fi

exec /usr/local/bin/derper "$@"
