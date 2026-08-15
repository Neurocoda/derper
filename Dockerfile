# Tailscale DERP server (derper) — 自建镜像
#
# 官方不发布 derper 容器镜像；官方文档要求自行构建
# tailscale.com/cmd/derper。见 README 的来源链接。
#
# 构建参数由 CI 根据所选 tailscale.com 版本的 go.mod 自动解析：
#   docker build --build-arg DERP_VERSION=v1.102.2 --build-arg GO_VERSION=1.26.5 .
# 默认值用于本地构建；上游要求变化时不需要修改 Dockerfile，CI 会传入匹配的 Go 版本。

ARG GO_VERSION=1.26.5
ARG ALPINE_VERSION=3.24

# ---- build stage ----
FROM golang:${GO_VERSION}-alpine AS build

# CGO 关闭：纯静态编译，运行时镜像无需 Go 或动态库
ENV CGO_ENABLED=0 GOOS=linux

ARG DERP_VERSION=v1.102.2
RUN go install tailscale.com/cmd/derper@${DERP_VERSION}

# ---- runtime stage ----
FROM alpine:${ALPINE_VERSION}

# derper 校验证书（Let's Encrypt / ACME 等）必需
RUN apk add --no-cache ca-certificates
COPY --from=build /go/bin/derper /usr/local/bin/derper
COPY --chmod=0755 docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh

# 80/tcp: HTTP（ACME HTTP-01 验证 / 跳转）
# 443/tcp: HTTPS/WSS（DERP 主流量）
# 3478/udp: STUN
EXPOSE 80 443 3478/udp

ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
