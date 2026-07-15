# sing-box как TUN-клиент (замена ProxyBridge)

Прозрачное проксирование всего исходящего трафика контейнера через внешний SOCKS5,
кроме loopback/LAN. Заменяет ProxyBridge (у того loopback-баг, см. [proxybridge.md](proxybridge.md)).
**PoC подтверждён 2026-06-11 на ct 136 (dev-proxybridge), sing-box 1.13.12.**

## Почему работает (и чем лучше ProxyBridge)

TUN с `auto_route` перехватывает исходящий трафик, но **loopback (127.0.0.0/8) в TUN не попадает** →
локальные панели (cliproxy 8317 и т.п.) работают нативно. Никакого NFQUEUE-round-trip по loopback.

## Конфиг (configs/singbox/client.json)

- `inbound: tun`, `stack: gvisor` (userspace — надёжно в LXC), `interface_name: sing-tun`,
  `address: ["172.19.0.1/30"]` (только IPv4!), `mtu 1500`, `auto_route: true`, `strict_route: true`.
- `outbounds`: `proxy` (socks5 → внешний, плейсхолдер 127.0.0.1:1 в шаблоне) + `direct`.
- `route.rules`: `{action: sniff}`, `{protocol: dns, action: hijack-dns}`, `{ip_is_private → direct}`;
  `final: direct` в шаблоне (toggle переключает на `proxy`).
- `route.default_domain_resolver: {server: dns-direct}` — **обязательно** в sing-box 1.12+ (иначе FATAL).
- `dns`: `dns-proxy` (tls 1.1.1.1, detour proxy) + `dns-direct` (local); `ip_is_private → dns-direct`;
  `strategy: ipv4_only` — **обязательно**, иначе apps лезут в битый IPv6 → `TLS unexpected eof`.

## Управление (scripts/singbox-toggle.sh)

`set <ip> <port> [user] [pass]` (задаёт upstream + proxy on) / `on` / `off` (direct) / `status`.
Редактирует `/etc/sing-box/config.json` через jq, делает `sing-box check` перед применением,
рестартит службу. status использует `curl -4` (без -4 ловит IPv6-фейл).

## ⚠️ Требование к LXC: /dev/net/tun

В контейнере по умолчанию НЕТ `/dev/net/tun` → TUN не стартует (служба `activating`, нет интерфейса).
Host-side, в `/etc/pve/lxc/<id>.conf` (как `fuse=1` для RDP):
```
lxc.cgroup2.devices.allow: c 10:200 rwm
lxc.mount.entry: /dev/net/tun dev/net/tun none bind,create=file
```
Затем `pct stop <id> && pct start <id>` (raw lxc.* применяется только при полном рестарте, НЕ `pct reboot`;
команды `pct restart` нет). Работает и в **unprivileged** контейнере (ct136 unprivileged — TUN поднялся).

## Проверенное поведение

- Панель cliproxy 8317 при активном прокси — 200 за 0.002с (loopback не проксируется). ✅
- `curl https://ifconfig.me` → exit IP = адрес прокси. ✅
- Битый upstream → DNS через прокси не резолвит → трафик НЕ утекает напрямую (fail-closed по upstream). ✅

## Открытые вопросы

- **Fail-closed при ПАДЕНИИ sing-box**: при остановке процесса `auto_route` снимает маршруты →
  трафик пойдёт напрямую (утечка). ProxyBridge (NFQUEUE без bypass) в этом смысле был строже.
  Для строгого killswitch — добавить persistent nftables-правило (блок egress на eth0 кроме proxy/LAN),
  не зависящее от процесса. Рассмотреть при интеграции.
- 9router на ct136 крест-лупит (его баг next-server, не sing-box) — отдельно.
- Интеграция в установщик: режим PROXY_MODE в install-singbox.sh, замена ProxyBridge в `--aiproxy`,
  депрекейт `--proxybridge`, меню/desktop, hint про /dev/net/tun в выводе. НЕ сделано.
