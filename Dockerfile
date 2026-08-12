# Tailscale DERP server (derper) — 自建镜像
#
# 官方不发布 derper 容器镜像（ghcr.io/tailscale 下只有 tailscale/tailscale），
# 官方文档要求自行构建 cmd/derper：
#   https://tailscale.com/docs/reference/derp-servers/custom-derp-servers
# 源码: https://github.com/tailscale/tailscale/tree/main/cmd/derper
#
# 版本策略：
#   - DERP_VERSION 默认 latest（go install @latest 语义），
#     CI 里会自动查询 proxy.golang.org 上 tailscale.com 的最新版本号传入，
#     实现可复现构建 + 自动跟踪上游更新（官方建议周期性重建以兼容客户端更新）。
#   - GO_VERSION 默认 1.26：tailscale v1.102+ 要求 Go >= 1.26.5，
#     上游要求提高时通过构建参数覆盖即可。

# ---- build stage ----
ARG GO_VERSION=1.26
FROM golang:${GO_VERSION}-alpine AS build

# CGO 关闭：纯静态编译，运行时镜像无需任何动态库
ENV CGO_ENABLED=0 GOOS=linux

ARG DERP_VERSION=latest
RUN go install tailscale.com/cmd/derper@${DERP_VERSION}

# ---- runtime stage ----
FROM alpine:3.20
# ca-certificates: derper 校验证书（Let's Encrypt / ACME 等）必需
RUN apk add --no-cache ca-certificates
COPY --from=build /go/bin/derper /usr/local/bin/derper

# 443/tcp: HTTPS/WSS 主流量；3478/udp: STUN。
# 注意：官方文档要求 HTTP(80) 也开放，derper 默认同时监听 80
# （ACME http-01 验证 + 跳转）。见 README 部署说明。
EXPOSE 443 3478/udp

ENTRYPOINT ["derper"]
