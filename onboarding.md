# AIProxy — Онбординг

> Точка входа для разработчика и AI-агента. Читай первым при начале работы с репозиторием.

## Что это

**AIProxy** — набор bash-скриптов для автоматического развёртывания AI-инфраструктуры на Debian 13.
Цель: поднять OpenAI-совместимые прокси + завернуть трафик через внешний SOCKS5/HTTP-прокси или VPN +
опционально GUI-доступ по RDP для OAuth и работы с AI IDE.

Типичный сценарий: VPS или LXC-контейнер в Proxmox, к которому AI-агенты и IDE обращаются как к
локальному OpenAI-endpoint, а исходящий трафик идёт через арендованный прокси.

---

## Стек

| Слой                        | Компонент          | Зачем                                                                            |
| --------------------------- | ------------------ | -------------------------------------------------------------------------------- |
| AI-прокси (основной)        | **cliproxy-api**   | OpenAI-совместимый API, мультипровайдер (Gemini/Claude/OpenAI). Порт `8317`.     |
| AI-прокси (альт.)           | **9router**        | Роутер на Node.js. Порт `20128`.                                                 |
| AI-прокси (альт.)           | **OmniRoute**      | AI gateway, 160+ провайдеров. Порт `20129` (не 20128 — чтобы не клешиться).      |
| Системный прокси            | **ProxyBridge**    | Per-process перехват на уровне ядра (NFQUEUE), TCP+UDP, GUI. Рекомендован.       |
| Системный прокси            | **gost**           | SOCKS5-сервер для всей LAN (без пароля → upstream с паролем). Замена redsocks.   |
| Системный прокси (классика) | **redsocks**       | Прозрачный TCP-редирект через iptables. Несовместим с ProxyBridge одновременно.  |
| Прокси-клиент / шлюз        | **sing-box**       | В режиме `--gate`: SOCKS5 `:1080` + TUN-шлюз для LAN.                            |
| Прокси-клиент / шлюз        | **Xray**           | В режиме `--gate`: SOCKS5 `:8080`, outbound=direct. Панель — 3x-ui.              |
| VPN                         | **AmneziaWG**      | WireGuard с обфускацией (обход DPI).                                              |
| GUI / RDP                   | **xrdp + LXQt/Openbox** | RDP-доступ к десктопу. Нужен для OAuth, визуальной работы с IDE.            |
| Браузеры                    | Firefox ESR, Brave | Работают через xrdp-сессию.                                                       |
| AI IDE / инструменты        | Antigravity, Claude Code, OpenCode, Cockpit Tools, VS Code | Опциональные.                              |

---

## Мета-наборы

| Набор         | Разворачивает                                                                  | Назначение         |
| ------------- | ------------------------------------------------------------------------------ | ------------------ |
| **`--aiproxy`** | xrdp + LXQt + cliproxy-api + 9router + Firefox + Cockpit Tools + ProxyBridge | Клиентская машина  |
| **`--gate`**    | sing-box (SOCKS5 `:1080` + TUN) + Xray (SOCKS5 `:8080`, outbound=direct)     | Прокси-шлюз для LAN |

---

## Структура репозитория

```
aiproxy/
├── install.sh                   # Мастер-установщик (единственная точка входа)
├── README.md                    # Пользовательская документация
├── onboarding.md                # Этот файл
├── scripts/                     # По одному install-/setup- скрипту на компонент
│   ├── install-cliproxy-api.sh  # + cliproxy-api-update.sh (автообновление по таймеру)
│   ├── install-9router.sh       # + 9router-update.sh / 9router-selfupdate.sh
│   ├── install-omniroute.sh
│   ├── install-proxybridge.sh   # + proxybridge-gen-args.sh, proxybridge-gui-wrapper.sh
│   ├── setup-gost.sh            # + gost-toggle.sh (set/on/off/status)
│   ├── setup-redsocks.sh        # + proxy-toggle.sh
│   ├── install-singbox.sh / install-xray.sh / install-3xui.sh
│   ├── install-amnezia.sh / setup-amnezia-connection.sh
│   ├── setup-xrdp.sh            # xrdp + раскладка + reconnectwm.sh workaround
│   ├── setup-openbox.sh / setup-lxqt.sh
│   ├── install-firefox.sh / install-brave.sh
│   └── install-{antigravity,claude-code,opencode,cockpit-tools,vscode}.sh
├── configs/
│   ├── systemd/                 # Unit-файлы + .timer для всех сервисов
│   ├── proxybridge/             # config.ini (единый для GUI и systemd), gui.desktop
│   ├── gost/                    # config-direct.yaml
│   ├── singbox/  xray/          # config.json + gate.json (+ chain-*.json для Xray)
│   └── desktop/                 # .desktop + LXQt-меню AIProxy (aiproxy-menu.menu, *.directory)
├── docs/ai/prompts/             # Промпты для тестовых сценариев
└── .agents/memory/local/        # yamem-память проекта (см. ниже)
```

---

## Требования к среде

- **ОС**: Debian 13 (основная цель; Debian 12 — ограниченно, ProxyBridge не запустится).
- **Права**: root (`sudo` не поддерживается, только прямой root / `su -`).
- **Интернет**: нужен для скачивания релизов с GitHub.
- **ProxyBridge**: нативный Linux + `glibc >= 2.38` (Debian 13 = 2.40). Не работает в WSL.

---

## Быстрый старт (для человека)

```bash
# Клиентская машина одной командой:
wget -O- https://raw.githubusercontent.com/rsyuzyov/aiproxy/master/install.sh | bash -s -- --aiproxy -y

# Прокси-шлюз:
wget -O- .../install.sh | bash -s -- --gate -y

# Интерактивный мастер (whiptail-меню с чекбоксами):
git clone https://github.com/rsyuzyov/aiproxy.git ~/aiproxy && cd ~/aiproxy && bash install.sh
```

---

## Онбординг для AI-агента

1. **Прочитать этот файл** (`onboarding.md`).
2. **Память проекта — в yamem** (`.agents/memory/local/`), не в `docs/`:
   - `MEMORY.md` — устойчивые факты, инфраструктура, грабли;
   - `backlog.md` / `archive.md` — задачи;
   - `diary/YYYY-MM-DD.md` — журнал работы и решений;
   - `topics/` — накопленные знания (`xrdp.md`, `cliproxy-9router.md`, `proxybridge.md`).
   - Перед действием сверяйся с памятью (инфраструктура, ID контейнеров, грабли).
3. Все изменения скриптов проверять полным прогоном на тестовом контейнере (ID/хост — см.
   `MEMORY.md`, раздел «Инфраструктура»), все скрипты обязаны работать в `-y` режиме.

---

## Ключевые точки в коде

### `install.sh` — единственная точка входа

Поток: `require_root` → `ensure_locales` (en_US + ru_RU UTF-8) → при запуске через `wget|bash`
без аргументов клонирует репо в `~/aiproxy` и `exec`'ает себя → `parse_args` (флаги → `DO_*`
переменные; мета-наборы раскрываются в набор `DO_*`) → `ensure_repo` → если не `-y`:
`interactive_menu` (whiptail `--checklist`) → `run_installations` → `show_summary`.

- `run_installations` запускает скрипты компонентов по порядку; при `exit 137` (SIGKILL,
  обычно OOM в LXC) — один retry через 5с.
- `--gate` прокидывает `GATE_MODE=1` в install-singbox.sh / install-xray.sh.

### `install-cliproxy-api.sh`

Самый сложный: качает релиз с GitHub API → `/opt/cliproxy-api/` → systemd-сервис +
**автообновление** (`cliproxy-api-updater.timer`, 05:00) + **rollback** при неудачном старте.
Порт `8317`, панель `/management.html`.

### `install-proxybridge.sh` + ProxyBridge

Ставит через официальный `deploy.sh` от InterceptSuite. Ключевые **проектные решения** (см.
`topics/proxybridge.md`):
- GUI и systemd-сервис **взаимоисключающие**; `gui-wrapper.sh` стопает сервис на старте GUI и
  возвращает на выходе. ProxyBridge должен работать всегда.
- NFQUEUE на `OUTPUT` **без `--queue-bypass`** — fail-closed: упал ProxyBridge → трафик встаёт,
  а не утекает мимо прокси.
- Единый конфиг `/etc/proxybridge/config.ini` (формат RULES `id|proto|action|enabled|process|hosts|ports`,
  action 0=PROXY/1=DIRECT/2=BLOCK); `gen-args.sh` парсит его в аргументы сервиса.

### `setup-xrdp.sh`

xrdp + раскладка US/RU + `reconnectwm.sh` (always-restart chansrv на reconnect — лечит
буфер обмена и чёрный экран; см. `topics/xrdp.md`). DE отдельно: `setup-lxqt.sh` или `setup-openbox.sh`.

---

## Адреса сервисов

| Сервис                  | Адрес                                     |
| ----------------------- | ----------------------------------------- |
| cliproxy-api            | `http://localhost:8317` (`/management.html`) |
| 9router                 | `http://localhost:20128`                  |
| OmniRoute               | `http://localhost:20129`                  |
| gost                    | SOCKS5 `0.0.0.0:1080`                     |
| sing-box (`--gate`)     | SOCKS5 `:1080` + TUN-шлюз                 |
| Xray (`--gate`)         | SOCKS5 `:8080` (outbound=direct)          |
| 3x-ui                   | web-панель (команда `x-ui`)               |
| RDP                     | `<IP сервера>:3389`                       |

---

## Управление сервисами

```bash
systemctl status|restart cliproxy-api ; journalctl -u cliproxy-api -f
systemctl list-timers --all | grep updater          # автообновления

# gost
scripts/gost-toggle.sh set IP PORT USER PASS ; scripts/gost-toggle.sh on|off|status

# ProxyBridge
ProxyBridgeGUI                 # GUI (стопает сервис, возвращает по выходу)
ProxyBridge --cleanup          # снять NFQUEUE-правила из iptables
cat /proc/net/netfilter/nfnetlink_queue   # кто держит очередь, дропы

# AmneziaWG
systemctl start|stop awg-quick@amnezia0 ; awg show
```

---

## Известные ограничения и нюансы

| Тема                              | Суть / решение                                                                                       |
| --------------------------------- | ---------------------------------------------------------------------------------------------------- |
| ProxyBridge ↔ glibc               | Требует glibc ≥ 2.38 → только Debian 13+. На Debian 12 установится, но не запустится.                |
| redsocks ↔ ProxyBridge            | Оба рулят iptables — одновременно нельзя. Выбирать один (рекоменд. ProxyBridge).                     |
| ProxyBridge fail-closed           | Без `--queue-bypass` — by design. Упал → трафик встаёт (защита от утечки). НЕ «чинить».              |
| xrdp буфер/чёрный экран           | chansrv не переживает нештатный обрыв TCP; `reconnectwm.sh` рестартует chansrv на reconnect.          |
| cliproxy-api `/management.html`   | Виснет при доступе не с loopback/LAN при активном ProxyBridge-правиле `*:PROXY`. См. `topics/`.       |
| 9router `/login`,`/dashboard`     | SSR-deadlock в next-server после чтения db.json (не зависит от версии). Обхода нет, API работает.    |

---

## Память и задачи (yamem)

Трекинг задач и накопленные знания — в `.agents/memory/local/` (навык `yamem`). `docs/tasks/`
больше не используется. Перед содержательной работой агент обязан выполнить блок «При старте»
навыка yamem (чтение MEMORY.md, backlog, diary, topics).
