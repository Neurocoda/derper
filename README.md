# derper — Tailscale DERP Server 容器镜像

这是一个**从 Tailscale 官方源码构建**的 `derper` 容器镜像。Tailscale 官方不发布 `derper` 容器镜像；官方要求自行构建、部署并定期更新 `tailscale.com/cmd/derper`。

- [官方 DERP 服务器说明](https://tailscale.com/docs/reference/derp-servers)
- [官方自定义 DERP 部署文档](https://tailscale.com/docs/reference/derp-servers/custom-derp-servers)
- [官方 `cmd/derper` README](https://github.com/tailscale/tailscale/tree/main/cmd/derper)
- [GHCR 镜像](https://github.com/Neurocoda/derper/pkgs/container/derper)

> **先判断是否真的需要自建 DERP。** DERP 通常只是建立直连时的辅助通道，直连失败时才中继流量。Tailscale 官方建议优先排查直连问题或使用 peer relay。自定义 DERP 目前仍标记为 **alpha**，并且不支持设备共享等跨 Tailnet 功能。

## 镜像

```bash
docker pull ghcr.io/neurocoda/derper:latest
```

目前发布以下平台：

- `linux/amd64`
- `linux/arm64`
- `linux/arm/v7`

镜像标签：

- `latest`：`main` 分支构建的最新镜像
- `tailscale-vX.Y.Z`：对应 `tailscale.com/cmd/derper@vX.Y.Z`
- `sha-<commit>`：对应本仓库提交
- `vX.Y.Z`：本仓库发布标签（如果通过 `git tag vX.Y.Z` 触发）

## 推荐的生产部署方式

### 1. 确认服务器网络条件

自定义 DERP 必须直接接入公网：

- 不要放在 NAT、反向代理、HTTP 代理或负载均衡器后面。
- DERP 会观察入站连接的源地址；NAT/LB 会改变源地址。
- DERP 在 TLS 内进行 HTTP protocol upgrade，再切换到双向二进制协议；很多 HTTP 代理/LB 不兼容。
- 不要让多个 DERP 服务器共享同一个公网 IP。
- 最好拥有静态 IPv4 和 IPv6，并把它们都写进 DERP map。

这里的“直接接入公网”不等于完全不能有主机防火墙：宿主机防火墙和云安全组可以存在，但必须允许所需流量，不能充当 NAT、反向代理或会改写/吞掉连接的中间层。

### 2. 放行端口和 ICMP

| 端口 | 协议 | 用途 |
|---:|---|---|
| 80 | TCP | HTTP、ACME HTTP-01 验证和跳转；端口不能自定义 |
| 443 | TCP | HTTPS、WebSocket 和 DERP 主流量 |
| 3478 | UDP | STUN |

还必须允许**双向 ICMP**。不要对 UDP STUN 包限速，也不要限速出站 TCP；不要配置会抑制发往死连接/未知连接的 TCP `RST` 的防火墙规则。

### 3. 宿主机运行与 derper 同版本的 tailscaled

如果启用 `--verify-clients`，官方要求：

1. `tailscaled` 和 `derper` 在同一台机器上运行；
2. 所有允许使用 DERP 的客户端都能被这台机器上的 `tailscaled` 在 ACL 中看到；
3. `derper` 和 `tailscaled` 最好从**同一个 Tailscale git revision**构建。官方源码 README 明确说两者只在同 revision 下共同测试。

先检查宿主机版本：

```bash
tailscale version
tailscale status
ls -l /var/run/tailscale/tailscaled.sock
```

本项目 CI 会把实际构建的上游版本写入镜像标签和 OCI label，例如：

```bash
docker image inspect ghcr.io/neurocoda/derper:tailscale-v1.102.2 \
  --format '{{ index .Config.Labels "io.github.neurocoda.derper.tailscale-version" }}'
```

生产环境应让宿主机 `tailscaled` 与这个版本保持一致；不要把“镜像能启动”误认为“`--verify-clients` 已经可用”。

### 4. 配置域名并自动签发证书

镜像使用 `derper` 内置的 ACME 客户端，不需要 Certbot、Nginx 或额外定时任务。复制环境变量模板：

```bash
cp .env.example .env
```

编辑 `.env`：

```dotenv
# A/AAAA 必须直接指向当前 DERP 主机公网地址
DERP_HOSTNAME=derp.example.com

# 可选但建议填写，用作 Let's Encrypt 账户联系邮箱
DERP_ACME_EMAIL=admin@example.com

# 推荐固定为与宿主机 tailscaled 对应的上游版本
DERPER_IMAGE=ghcr.io/neurocoda/derper:tailscale-v1.102.2
```

然后部署：

```bash
docker compose pull
docker compose up -d
docker compose logs -f derper
```

启动日志应包含：

```text
证书将由 derper 通过 Let's Encrypt 自动申请并续期，缓存目录: /certs
```

当客户端首次通过域名访问 443 时，`derper` 会完成 ACME 签发；HTTP-01 验证由同一进程监听的 80 端口处理。证书与 ACME 账户数据保存在 `./certs`，容器重建后会复用，并由 `derper` 自动续期。

容器入口脚本支持以下主要环境变量：

| 变量 | 默认值 | 说明 |
|---|---|---|
| `DERP_HOSTNAME` | 无，必填 | 证书域名，不能包含协议、端口、路径或通配符 |
| `DERP_ACME_EMAIL` | 空 | Let's Encrypt 联系邮箱 |
| `DERP_ACME_EAB_KID` | 空 | `gcp` 模式的 ACME EAB Key ID |
| `DERP_ACME_EAB_KEY` | 空 | `gcp` 模式的 ACME EAB HMAC key |
| `DERP_CERTMODE` | `letsencrypt` | `letsencrypt`、`manual` 或 `gcp` |
| `DERP_CERTDIR` | `/certs` | ACME 账户与证书缓存目录 |
| `DERP_ADDR` | `:443` | DERP HTTPS 监听地址 |
| `DERP_HTTP_PORT` | `80` | HTTP-01 监听端口 |
| `DERP_STUN_PORT` | `3478` | STUN UDP 端口 |
| `DERP_VERIFY_CLIENTS` | `false` | 是否通过本机 `tailscaled` 校验客户端 |
| `DERP_SOCKET` | `/var/run/tailscale/tailscaled.sock` | LocalAPI socket |

Compose 会把 `DERP_VERIFY_CLIENTS` 设为 `true` 并挂载宿主机 socket；如果 socket 不存在，入口脚本会直接退出，而不是让容器看似正常、实际拒绝所有客户端。

如果只是本地开发或检查 Dockerfile，也可以运行：

```bash
docker build \
  --build-arg DERP_VERSION=v1.102.2 \
  --build-arg GO_VERSION=1.26.5 \
  -t derper:local .
```

仓库里的 Compose 使用 `network_mode: host`，这是有意的生产部署选择：

- 避免 Docker bridge/端口转发成为额外网络中间层；
- 让 `derper` 直接监听宿主机的 80/443/3478；
- 挂载宿主机的 `/var/run/tailscale/tailscaled.sock` 给 `--verify-clients` 使用。

Compose 同时持久化两类状态：

- `./certs`：Let's Encrypt 证书；
- `./derper-data`：DERP 节点私钥 `/var/lib/derper/derper.key`。

**不要删除或随意复制 `derper-data`。** DERP 私钥变化会改变该 DERP 节点身份，重建容器不应导致它生成新身份。

> 这个 Compose 是面向 Linux 公网服务器的生产配置。OrbStack/macOS 可以用来构建和做本地 smoke test，但不能据此证明 Mac 主机具备可被公网访问的 DERP 网络条件。

### 5. 证书

默认使用 `--certmode=letsencrypt`：

- A/AAAA 必须直接指向这台服务器；如果配置 AAAA，IPv6 的 80/443 也必须真实可达；
- 443 必须从公网可达；
- 80 必须从公网可达，以完成 HTTP-01 验证；
- `/certs` 必须持久化；
- 只有 Let's Encrypt 证书会自动轮换，手工证书更新后需要重启 `derper`；
- 如果域名托管在 Cloudflare，必须使用 **DNS only（灰云）**，不能使用橙云代理。

签发后验证：

```bash
curl -I https://derp.example.com/
openssl s_client -connect derp.example.com:443 -servername derp.example.com </dev/null 2>/dev/null \
  | openssl x509 -noout -subject -issuer -dates
```

如果签发失败，首先检查：

```bash
dig +short A derp.example.com
dig +short AAAA derp.example.com
docker compose logs derper
```

本地或 CI 只能验证入口脚本、ACME HTTP-01 路径和证书缓存目录；真正的公开证书签发必须在 DNS 已生效且公网 80/443 可达的服务器上完成。

不要在生产环境使用 `--dev`；`--dev` 仅用于本地 smoke test，监听 HTTP `:3340`，不提供生产 TLS 配置。

## 添加到 Tailnet

在 Tailscale 的 tailnet policy file 中，把下面内容合并到已有 JSON，而不是覆盖整个策略文件：

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

注意：

- `RegionID` **900–999** 保留给自定义 DERP；
- 每个 region 原则上只有一个 DERP 节点；需要冗余时使用多个 region；
- `IPv4`/`IPv6` 可选但强烈推荐，必须是公网可路由地址；
- 如果要只使用自己的 DERP，可在 `derpMap` 中设置 `"OmitDefaultRegions": true`；
- 自定义 DERP 不用于 regional routing；
- `tailscale netcheck` 和 `tailscale debug derp` 可用于客户端侧确认。

## 监控和诊断

官方提供 `derpprobe`：

```bash
go install tailscale.com/cmd/derpprobe@v1.102.2
derpprobe --derp-map=file:///path/to/derpmap.json
```

若 `derper` 启用了 `--verify-clients`，监控端的 `derpprobe` 也需要与一个 `tailscaled` 同机运行，并使用：

```bash
derpprobe --derp-map=local
```

其他有用检查：

```bash
tailscale netcheck
tailscale debug derp
curl -k https://derp.example.com/
curl -k -o /dev/null -w '%{http_code}\n' https://derp.example.com/derp/probe
```

## CI/CD

`.github/workflows/docker-build.yml` 会：

1. 从 `proxy.golang.org` 解析 `tailscale.com` 最新稳定版本、上游 Git revision 和对应 `go.mod`；
2. 自动选择该版本所需的 Go toolchain；
3. 先构建仅存在于 runner 本地的 `linux/amd64` 验证镜像；
4. 在发布前验证：必填域名校验、Let's Encrypt 启动、HTTP-01 路径、STUN 监听、DERP key 跨重建持久化，以及 `/derp`、`/derp/probe`；
5. 只有全部验证成功才构建并推送 `amd64`、`arm64`、`arm/v7`；
6. 发布后检查 OCI manifest 必须包含三个目标平台；
7. 每天定时重新检查上游版本，也会吸收 Alpine 基础镜像安全更新；
8. 把真实的 Tailscale version/revision 和 Go version 写入 OCI labels。

触发方式：

| 触发 | 行为 |
|---|---|
| push `main` | 推送 `latest`、`tailscale-vX.Y.Z`、`sha-*` |
| push `v*` tag | 把该 tag 作为实际 Tailscale module 版本构建，推送同名 tag、`tailscale-vX.Y.Z`、`sha-*`；不覆盖 `latest` |
| Pull Request | 构建并完成发布前验证，不推送 |
| 每日 schedule | 重新解析上游并验证后发布 `latest` |
| 手动触发 | 可用 `derp_version` 固定上游版本；不覆盖 `latest` 和 `sha-*` |

本地固定版本构建：

```bash
docker build \
  --build-arg DERP_VERSION=v1.102.2 \
  --build-arg GO_VERSION=1.26.5 \
  -t derper:test .
```

## 官方限制摘要

自定义 DERP 目前是 alpha 功能。它：

- 不能支持设备共享和其他跨 Tailnet 功能；
- 不能获得 Tailscale 控制面的部分地理调度和优化；
- 不能放在 HTTP 代理、NAT 或全局负载均衡器后面；
- 不适合作为网络级明文调试工具，DERP 只能看到加密的 WireGuard 数据；
- 与 Mullvad exit node 存在官方文档所述限制。

## License

MIT
