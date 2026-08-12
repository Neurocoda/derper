# derper — Tailscale DERP Server 容器镜像

自建 [Tailscale](https://tailscale.com/) DERP 服务器的 Docker 镜像。

> **为什么需要自建？** Tailscale **官方不发布** derper 的容器镜像（`ghcr.io/tailscale` 下只有 `tailscale/tailscale`），官方文档要求自行构建 `cmd/derper`：[custom DERP servers](https://tailscale.com/docs/reference/derp-servers/custom-derp-servers)。

## 镜像特性

- **多架构**：`linux/amd64`、`linux/arm64`、`linux/arm/v7`
- **版本自动跟踪**：CI 自动查询上游最新版本构建，无需手动改版本号（可用 `workflow_dispatch` 固定版本）
- **可复现**：构建时显式传入 `DERP_VERSION`，避免 `go install @latest` 的不可复现性
- 运行时镜像基于 Alpine，约 **33MB**

## 快速开始

### 本地构建并运行

```bash
docker compose build
docker compose up -d
```

### 直接拉取 GHCR 镜像

```bash
docker pull ghcr.io/<你的用户名>/derper:latest
docker run -d --name derper \
  -p 443:443 -p 3478:3478/udp \
  -v derper-certs:/certs \
  ghcr.io/<你的用户名>/derper:latest \
  --hostname=derp.example.com --certdir=/certs --verify-clients
```

## ⚠️ 部署要求（官方文档确认）

运行自定义 DERP 服务器前，请务必满足以下条件（来源：[custom-derp-servers](https://tailscale.com/docs/reference/derp-servers/custom-derp-servers)）：

### 必须直连公网

- **不能放在 NAT、防火墙或负载均衡器后面**。DERP 通过**源 IP 地址**识别 tailnet 设备，NAT/LB 会改写源地址导致功能失效。
- Tailscale 客户端使用 **HTTP upgrade 协议**建立双向数据通道，大多数云负载均衡器不支持。

### 端口与网络

| 端口 | 协议 | 用途 |
|---|---|---|
| 80 | TCP | HTTP（ACME 验证 / 跳转，**不能自定义端口**） |
| 443 | TCP | HTTPS / WebSocket 主流量 |
| 3478 | UDP | STUN |

- **必须允许双向 ICMP 流量**
- 主机名必须指向该服务器公网 IP（DNS A/AAAA 记录）

### --verify-clients 需要 tailscaled 同机运行

官方要求：要使用 `--verify-clients` 防止 DERP 被他人滥用，**必须在同一台机器上运行 `tailscaled`**（并已加入你的 tailnet）：

```bash
# 宿主机上
tailscale up
# 容器内 derper 加 --verify-clients 参数
```

## 添加到你的 Tailnet

1. 在 Tailscale 管理后台编辑 **tailnet policy file**，加入 `derpMap`：

```json
{
  "derpMap": {
    "Regions": {
      "900": {
        "RegionID": 900,
        "RegionCode": "myderp",
        "RegionName": "My DERP",
        "Nodes": [
          {
            "Name": "1",
            "RegionID": 900,
            "HostName": "derp.example.com",
            "IPv4": "203.0.113.15",
            "IPv6": "2001:db8::1"
          }
        ]
      }
    }
  }
}
```

> - RegionID **900–999** 保留给自定义 DERP 使用
> - **每个 region 只能有一个 DERP server**；需要冗余就建多个 region
> - `IPv4`/`IPv6` 字段可选但**强烈推荐**填写（DNS 故障时的兜底），必须是公网可路由地址

2.（可选）只用自建 DERP：设置 `"OmitDefaultRegions": true` 移除 Tailscale 默认服务器。

3. 验证：`tailscale netcheck` 查看客户端选择的 DERP 服务器。

## 监控

官方提供 `derpprobe` 工具监控自建 DERP：

```bash
go install tailscale.com/cmd/derpprobe@latest
derpprobe --derp-map=file:///path/to/derpmap.json
```

## GitHub Actions 说明

`.github/workflows/docker-build.yml` 自动完成：

| 触发 | 行为 |
|---|---|
| push main | 构建并推送 `latest` + `sha-<7位>` 到 GHCR |
| tag `v*` | 构建并推送 `<tag>` 到 GHCR |
| PR | 仅构建 + 冒烟测试（HTTP 页面 / DERP 协议端点），不推送 |
| 手动触发 | 可指定 `derp_version` 固定版本号 |

**版本自动跟踪**：CI 从 Go module proxy 查询 `tailscale.com` 最新版本并作为 `DERP_VERSION` 构建参数传入。官方建议周期性重建 derper 以兼容 Tailscale 客户端更新，本镜像开箱即用。

## 版本固定与更新

- **跟随最新**：什么都不用做，每次构建自动用上游最新版
- **固定版本**：workflow_dispatch 填写版本号（如 `v1.102.2`）
- **本地固定**：`docker build --build-arg DERP_VERSION=v1.102.2 .`

## 项目结构

```
.
├── Dockerfile          # 多阶段构建（golang → alpine）
├── docker-compose.yml  # 本地/服务器一键部署
├── .github/workflows/  # 多架构 CI
└── certs/              # 证书目录（挂载卷，自动创建）
```

## License

MIT
