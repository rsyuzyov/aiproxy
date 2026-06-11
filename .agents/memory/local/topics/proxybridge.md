# ProxyBridge — проектные решения и устройство

[InterceptSuite/ProxyBridge](https://github.com/InterceptSuite/ProxyBridge) — per-process прокси,
перехват трафика на уровне ядра через **Netfilter NFQUEUE**, TCP+UDP. В aiproxy — рекомендованный
системный прокси (вместо устаревшего redsocks; одновременно с redsocks работать НЕ может — оба рулят iptables).

## Проектные решения (НЕ баги — by design)

- ⚠️ **GUI и systemd-сервис взаимоисключающие, но ProxyBridge должен работать ВСЕГДА.**
  Механизм в [scripts/proxybridge-gui-wrapper.sh](../../../scripts/proxybridge-gui-wrapper.sh):
  при старте GUI → `systemctl stop proxybridge`; по выходу из GUI → `systemctl start proxybridge`.
  Поэтому нормально видеть `proxybridge.service` = inactive, пока в RDP-сессии открыт ProxyBridgeGUI —
  это НЕ конфликт и НЕ дубль. Оба пишут/читают единый конфиг `/etc/proxybridge/config.ini`.

- ⚠️ **NFQUEUE на `OUTPUT` без `--queue-bypass` — намеренно (fail-closed).**
  Если ProxyBridge упал — исходящий трафик должен ВСТАТЬ, а НЕ пойти напрямую в обход прокси
  (защита от утечки). Не предлагать добавить `--queue-bypass`.
  Нюанс: на этапе УСТАНОВКИ деплой оставляет NFQUEUE-правила без демона → install-proxybridge.sh
  делает `ProxyBridge --cleanup` сразу после установки, чтобы трафик не завис до первого старта.

## Конфиг `/etc/proxybridge/config.ini`

Единый формат для GUI и systemd. `[SETTINGS]` ip/port/type(0=HTTP,1=SOCKS5)/user/pass/logging/dns.
`[RULES]` строка: `id|protocol|action|enabled|process|hosts|ports`
- protocol: 0=TCP, 1=UDP, 2=BOTH
- action: **0=PROXY, 1=DIRECT, 2=BLOCK**
- enabled: 0/1
Правила матчатся по порядку; типовой набор: loopback/LAN/спец-хосты → DIRECT, `*` → PROXY (последним).

[gen-args.sh](../../../scripts/proxybridge-gen-args.sh) парсит config.ini → `PROXYBRIDGE_ARGS`,
`proxybridge.service` ExecStart его source'ит и `eval exec ProxyBridge $PROXYBRIDGE_ARGS`.
`--proxy` добавляется только если есть хоть одно правило action=PROXY.

## Безопасность

- ⚠️ В `[SETTINGS]` config.ini лежат **живые креды внешнего прокси** (ip/port/user/pass).
  В память (и тем более shared) НЕ записывать.

## Диагностика

- Кто реально обрабатывает очередь: `cat /proc/net/netfilter/nfnetlink_queue`
  (колонки: queue# peer_portid queued copy_mode copy_range q_dropped user_dropped id_seq 1).
  `peer_portid` ≠ 0 → процесс привязан; рост `q_dropped`/`user_dropped` → очередь насыщается.
- Какой процесс держит очередь: `pgrep -af 'ProxyBridge'` (может быть ProxyBridgeGUI из LXQt, не сервис).
- NFQUEUE-правила: `iptables-save | grep -i NFQUEUE` (обычно `-A OUTPUT -p tcp/udp -j NFQUEUE --queue-num 0`).

## ПОДТВЕРЖДЕНО: ProxyBridge ломает все локальные панели (A/B 2026-06-11, ct 107)

Зависание панелей cliproxy-api (8317), 9router (20128), OmniRoute (20129) — **не баги бинарей**,
а перехват ProxyBridge. Доказано A/B через curl из контейнера:
- ProxyBridge вкл → внешка 200 (через прокси), все 3 панели timeout 12с;
- `ProxyBridge --cleanup` (перехват снят) → все 3 панели **200 за 0.002–0.027с**.

Механизм точно не добит (две версии): (1) ломается userspace-реинъекция loopback-пакетов через
NFQUEUE даже при правиле `127.0.0.1:DIRECT`; (2) серверный рендер панелей делает исходящий self-fetch
по hostname/реальному IP, который ловит `*:PROXY` → внешний SOCKS5 → виснет. Пинить: `ss -tnp`/`strace`
на процессе панели во время висяка (смотреть, есть ли исходящее соединение и куда).

Фикс (не сделан): ProxyBridge V4.0-Beta не имеет флага «не трогать loopback». Варианты —
DIRECT-правила для self/private адресов, либо iptables-исключение `-A OUTPUT -o lo -j ACCEPT`
перед NFQUEUE (но ProxyBridge пересоздаёт правила на старте → нужен хук/обёртка). См.
[cliproxy-9router.md](cliproxy-9router.md).

## Механизм зависания панелей (разобрано 2026-06-11)

Что ПРОВЕРЕНО и отброшено:
- **Не матчинг адреса.** На том же порту мелкие роуты (`8317/`, `/v1/models`, `20128/api/health`,
  `20129/`) отвечают за 0.02–0.06с, а тяжёлые (`/management.html`, `/dashboard`, `/login`) висят.
  Если бы dual-stack `::ffff:127.0.0.1` не матчил DIRECT — висело бы ВСЁ на порту.
- **Не DNS-via-proxy.** При `dns=0` + рестарт панели всё равно висят.
- **Широкое `iptables -o lo -j ACCEPT` «чинит» панели ОБМАНОМ** — оно ломает ProxyBridge, тот
  снимает NFQUEUE → проксирование выключается целиком → рендер идёт напрямую. Точечное
  `-o lo -m multiport --ports 8317,20128,20129` ProxyBridge терпит (NFQUEUE цел), но панели НЕ чинит.
- Панели работают ТОЛЬКО когда проксирование полностью выключено (`--cleanup`).

Что наблюдается: при активном `*:*:*:BOTH:PROXY` curl→`127.0.0.1:<порт панели>` может застрять в
**SYN-SENT** (loopback-хендшейк не завершается), хотя есть правило `127.0.0.1:DIRECT`; ProxyBridge при
этом плодит десятки соединений к внешнему прокси. Похоже на **баг ProxyBridge V4.0-Beta**: DIRECT-loopback
всё равно гоняется через userspace-очередь и срывается для нетривиальных flow. **Конфигом надёжно не
обходится.** Рекомендации: upstream-репорт с репро; либо отказ от catch-all `*:PROXY` в пользу
PROXY только нужных провайдер-хостов (конфликтует с fail-closed/«проксировать всё»); либо новый релиз PB.

⚠️ **ProxyBridge не терпит ручной правки OUTPUT-цепочки** широкими правилами — снимает свой NFQUEUE
→ внешка уходит напрямую (утечка!). Полную команду с правилами видно в `pgrep -af ProxyBridge`
(там креды прокси — в память НЕ копировать). Exit IP: прокси=72.56.181.101 (entry=exit),
прямой=реальный IP контейнера (195.178.4.x); LAN-адрес контейнера 192.168.88.5. strace в LXC не
цепляется (ptrace закрыт) — диагностика через `ss -tanp`.

## Грабли (операционные)

- ⚠️ **Не убивать ProxyBridge через `pkill -f <pattern>` по ssh** — паттерн совпадает с
  собственной командной строкой ssh/pct и убивает шелл (exit 137). Только `kill <PID>`.
- ⚠️ Убийство ProxyBridgeGUI триггерит `gui-wrapper.sh` → `systemctl start proxybridge`.
  Чтобы снять перехват полностью: убить и wrapper, и GUI (по PID), затем `ProxyBridge --cleanup`.
- Вернуть перехват после теста: `systemctl start proxybridge` (демон) либо запустить GUI.
