# AIProxy Setup

Набор скриптов для развертывания OpenAI-совместимых прокси. Создавались и проверялись на Debian 13.

## Что включает

### AI-прокси сервисы

| Компонент        | Описание                                                             |
| ---------------- | -------------------------------------------------------------------- |
| **cliproxy-api** | AI-прокси сервер с поддержкой OpenAI/Gemini/Claude (порт `8317`)     |
| **9router**      | Ещё один AI-прокси сервер (порт `20128`)                             |

### Сеть: прокси и VPN

| Компонент       | Описание                                                             |
| --------------- | -------------------------------------------------------------------- |
| **gost**        | SOCKS5 прокси для всей сети (замена redsocks)                        |
| **ProxyBridge** | Перенаправление TCP/UDP трафика per-process через SOCKS5/HTTP прокси |
| **sing-box**    | Мультипротокольный прокси-клиент; в режиме `--gate` — SOCKS5 `:1080` + TUN-шлюз |
| **Xray**        | Прокси-клиент; в режиме `--gate` — SOCKS5 `:8080`, outbound=direct   |
| **3x-ui**       | Web-панель управления Xray                                           |
| **AmneziaWG**   | VPN-клиент на базе WireGuard (обход DPI)                             |

### Рабочее окружение

| Компонент          | Описание                                       |
| ------------------ | ---------------------------------------------- |
| **xrdp**           | RDP-сервер (порт `3389`)                       |
| **Openbox + tint2** | Лёгкий рабочий стол для xrdp                  |
| **LXQt**           | Полноценный рабочий стол для xrdp (Debian 13)  |
| **Firefox ESR**    | Браузер                                        |
| **Brave Browser**  | Альтернативный браузер                         |

### AI IDE и инструменты

| Компонент           | Описание                                                             |
| ------------------- | -------------------------------------------------------------------- |
| **Antigravity IDE** | Google AI IDE на базе VS Code с Gemini                               |
| **Claude Code**     | CLI-агент от Anthropic для работы с кодом в терминале                |
| **OpenCode**        | Open-source AI-ассистент (CLI + Desktop)                             |
| **Cockpit Tools**   | Менеджер аккаунтов AI IDE: Antigravity, Copilot, Windsurf, Cursor... |
| **VS Code**         | Visual Studio Code — универсальный редактор от Microsoft             |

- Минимальный набор для AI-прокси — `cliproxy-api`.
- Для работы с claude, openai и другими провайдерами можно установить **gost** (прокси для всей сети) и/или **ProxyBridge** (per-process прокси) и арендовать прокси на https://px6.me (https://proxy6.net).
- Для активации учётных записей (google, aws) и прохождения OAuth через прокси или туннель можно поставить браузер+xrdp и заходить по RDP на рабочий стол.
- Мета-набор `--aiproxy` разворачивает стандартную конфигурацию клиентской машины, `--gate` — поднимает машину как прокси-шлюз для локальной сети.

## Требования

- Debian 13
- Доступ root
- Интернет-соединение

**Ресурсы:**

- Режим без GUI и браузера: 1 CPU / 512 MB ОЗУ / 2 GB диск
- Режим с GUI и браузером: минимум 2 CPU / 4 GB / 4 GB, для комфортной работы 4 CPU / 8 GB / 4 GB

## Быстрый старт

### Однострочная команда (мета-набор AIProxy)

```bash
wget -O- https://raw.githubusercontent.com/rsyuzyov/aiproxy/master/install.sh | bash -s -- --aiproxy -y
```

`--aiproxy` устанавливает: **cliproxy-api + 9router + ProxyBridge + xrdp + LXQt + Firefox ESR + Cockpit Tools**

Для поднятия прокси-шлюза:

```bash
wget -O- https://raw.githubusercontent.com/rsyuzyov/aiproxy/master/install.sh | bash -s -- --gate -y
```

`--gate` устанавливает: **sing-box (SOCKS5 `:1080` + TUN) + Xray (SOCKS5 `:8080`, outbound=direct)**

### Или: клонировать и запустить

```bash
git clone https://github.com/rsyuzyov/aiproxy.git ~/aiproxy
cd ~/aiproxy
bash install.sh
```

## Использование мастер-установщика

### Интерактивный режим (по умолчанию)

```bash
bash install.sh
```

Откроется меню, где можно выбрать нужные компоненты.

### Неинтерактивный режим (для автоматизации)

```bash
# Мета-набор AIProxy (клиентская машина)
bash install.sh --aiproxy -y

# Мета-набор GATE (прокси-шлюз)
bash install.sh --gate -y

# Только gost + ProxyBridge (прокси для сети + per-process правила)
bash install.sh --gost --proxybridge -y

# Только cliproxy-api и xrdp
bash install.sh --cliproxy --xrdp -y

# AI-инструменты: Antigravity + Claude Code + OpenCode + Cockpit Tools
bash install.sh --antigravity --claude-code --opencode --cockpit-tools -y
```

### Параметры командной строки

**Мета-наборы:**

| Параметр        | Описание                                                                                |
| --------------- | --------------------------------------------------------------------------------------- |
| `--aiproxy`     | cliproxy-api + 9router + ProxyBridge + xrdp + LXQt + Firefox + Cockpit Tools            |
| `--gate`        | sing-box (SOCKS5 `:1080` + TUN) + Xray (SOCKS5 `:8080`), outbound=direct                |

**Отдельные компоненты:**

| Параметр                   | Описание                                                             |
| -------------------------- | -------------------------------------------------------------------- |
| `--cliproxy`               | cliproxy-api                                                         |
| `--9router`                | 9router                                                              |
| `--gost`                   | gost (SOCKS5 прокси для всей сети)                                   |
| `--proxybridge`            | ProxyBridge (per-process TCP+UDP прокси)                             |
| `--sing-box`               | sing-box (нейтральный конфиг; для шлюза используй `--gate`)          |
| `--xray`                   | Xray (нейтральный конфиг; для шлюза используй `--gate`)              |
| `--3x-ui`                  | 3x-ui (web-панель для Xray)                                          |
| `--amnezia`                | AmneziaWG VPN-клиент                                                 |
| `--xrdp`                   | xrdp-сервер (без DE)                                                 |
| `--openbox`                | Openbox + tint2 как DE                                               |
| `--lxqt`                   | LXQt как DE (Debian 13)                                              |
| `--firefox`                | Firefox ESR                                                          |
| `--brave`                  | Brave Browser                                                        |
| `--antigravity`            | Google Antigravity IDE                                               |
| `--claude-code`            | Claude Code CLI                                                      |
| `--opencode`               | OpenCode (CLI + Desktop)                                             |
| `--cockpit-tools`          | Cockpit Tools (менеджер аккаунтов AI IDE)                            |
| `--vscode`                 | Visual Studio Code                                                   |
| `-y` / `--non-interactive` | Неинтерактивный режим                                                |
| `--help`                   | Показать справку                                                     |

> **gost + ProxyBridge** — рекомендуемая связка для клиентской машины. Gost обслуживает всю сеть (SOCKS5 без пароля → upstream с паролем), ProxyBridge выбирает приложения для проксирования.

## Отдельные скрипты

Все скрипты находятся в `~/aiproxy/scripts/` и могут запускаться самостоятельно.

### Установка cliproxy-api

```bash
bash ~/aiproxy/scripts/install-cliproxy-api.sh
```

- Скачивает последний релиз с GitHub
- Устанавливает в `/opt/cliproxy-api/`
- Настраивает автообновление при каждом старте
- Настраивает rollback при неудачном старте
- Порт: `8317`

### Установка ProxyBridge

```bash
bash ~/aiproxy/scripts/install-proxybridge.sh
```

- Устанавливает через официальный `deploy.sh` от [InterceptSuite/ProxyBridge](https://github.com/InterceptSuite/ProxyBridge)
- Зависимости: `libnetfilter-queue1`, `libnfnetlink0`, `iptables`, `libgtk-3-0`
- Поддерживает TCP и UDP
- Работает на уровне ядра (Netfilter NFQUEUE)
- **Не совместим с WSL1/WSL2** — только нативный Linux

После установки:

```bash
# Запустить с прокси и правилом (весь TCP через прокси)
ProxyBridge --proxy socks5://1.2.3.4:1080 --rule "*:*:*:TCP:PROXY"

# Очистка после сбоя
ProxyBridge --cleanup

# Графический интерфейс (если установлен GTK3)
ProxyBridgeGUI

# Справка
ProxyBridge --help
```

### Установка 9router

```bash
bash ~/aiproxy/scripts/install-9router.sh
```

- Устанавливает Node.js 20.x (LTS)
- Устанавливает 9router глобально через npm
- Порт: `20128`

### Настройка xrdp

```bash
bash ~/aiproxy/scripts/setup-xrdp.sh
```

- Устанавливает xrdp и xorgxrdp (без DE)
- Принудительно устанавливает **английскую раскладку (US)** при RDP-входе
- Порт RDP: `3389`
- После установки добавь DE отдельно: `setup-openbox.sh` или `setup-lxqt.sh`

### Настройка Openbox + tint2

```bash
bash ~/aiproxy/scripts/setup-openbox.sh
```

- Лёгкий оконный менеджер + панель tint2
- Сессия: `dbus-launch openbox-session`

### Настройка LXQt

```bash
bash ~/aiproxy/scripts/setup-lxqt.sh
```

- Полноценный рабочий стол (Debian 13)
- Добавляет подменю приложений AIProxy в LXQt

### Установка sing-box / Xray / 3x-ui

```bash
bash ~/aiproxy/scripts/install-singbox.sh   # sing-box
bash ~/aiproxy/scripts/install-xray.sh      # Xray
bash ~/aiproxy/scripts/install-3xui.sh      # 3x-ui (web-панель)
```

- `GATE_MODE=1` — конфигурируются как прокси-шлюз (SOCKS5 + TUN для sing-box; SOCKS5 direct для Xray)
- Без `GATE_MODE` — нейтральный шаблон конфига, редактируется под свои нужды
- Конфиги: `/etc/sing-box/config.json`, `/usr/local/etc/xray/config.json`
- 3x-ui управляется командой `x-ui`

### Установка браузеров

```bash
bash ~/aiproxy/scripts/install-firefox.sh
bash ~/aiproxy/scripts/install-brave.sh
```

### Настройка gost

```bash
bash ~/aiproxy/scripts/setup-gost.sh
```

- Устанавливает бинарник [gost](https://github.com/go-gost/gost) через официальный скрипт
- Запускает SOCKS5 прокси на `0.0.0.0:1080` без авторизации (direct-режим)
- Другие хосты в LAN могут использовать этот прокси
- Не требует зависимостей (статический бинарник Go)

Управление после установки:

```bash
gost-toggle.sh set 1.2.3.4 1080 myuser mypassword  # задать upstream прокси
gost-toggle.sh on       # включить upstream (трафик через внешний прокси)
gost-toggle.sh off      # отключить upstream (direct-режим)
gost-toggle.sh status   # текущий статус
```

| Режим    | Описание                                      |
| -------- | --------------------------------------------- |
| `DIRECT` | gost работает напрямую, без upstream          |
| `PROXY`  | трафик идёт через внешний SOCKS5 прокси       |

### Установка Google Antigravity IDE

```bash
bash ~/aiproxy/scripts/install-antigravity.sh
```

- Добавляет официальный APT-репозиторий `packages.antigravity.google`
- Устанавливает пакет `antigravity` через `apt`
- Запуск: `antigravity` или через меню приложений

> Antigravity — AI IDE от Google на базе VS Code с интегрированным Gemini. Требует GUI (установите `--xrdp` для RDP-доступа).

### Установка Claude Code CLI

```bash
bash ~/aiproxy/scripts/install-claude-code.sh
```

- Использует официальный нативный установщик: `curl -fsSL https://claude.ai/install.sh | bash`
- Устанавливается в `~/.claude/bin/`
- Требует аутентификации при первом запуске

```bash
claude          # запуск агента
claude --help   # справка
```

### Установка OpenCode

```bash
bash ~/aiproxy/scripts/install-opencode.sh
```

- Устанавливает CLI (`opencode`) и Desktop-приложение (`opencode-desktop`)
- Open-source AI-ассистент с поддержкой множества моделей

### Установка Cockpit Tools

```bash
bash ~/aiproxy/scripts/install-cockpit-tools.sh
```

- Скачивает последний `.deb` с [GitHub Releases](https://github.com/jlcodes99/cockpit-tools/releases)
- При отсутствии `.deb` — устанавливает `.AppImage`
- Поддерживаемые платформы: **Antigravity, Codex, GitHub Copilot, Windsurf, Kiro, Cursor**
- Возможности: мультиаккаунт, мониторинг квот, автопробуждение, множественные инстанции
- Запуск: `cockpit-tools`

### Установка Visual Studio Code

```bash
bash ~/aiproxy/scripts/install-vscode.sh
```

- Добавляет официальный APT-репозиторий Microsoft
- Устанавливает пакет `code` через `apt`
- Запуск: `code` или через меню приложений

> Для работы GUI требуется xrdp или другой способ доступа к рабочему столу. Установите `--xrdp` для RDP.

### Установка и настройка AmneziaWG VPN

**Шаг 1. Установить AmneziaWG:**

```bash
bash ~/aiproxy/scripts/install-amnezia.sh
```

- Устанавливает ядро AmneziaWG (PPA для Ubuntu, `.deb` с GitHub или сборка из исходников)
- Создаёт каталог конфигураций `/etc/amnezia/amneziawg/`
- Поддерживает архитектуры `amd64` и `arm64`

**Шаг 2. Подключить конфигурацию:**

```bash
bash ~/aiproxy/scripts/setup-amnezia-connection.sh /path/to/amnezia.conf

# С явным именем интерфейса (по умолчанию amnezia0):
bash ~/aiproxy/scripts/setup-amnezia-connection.sh /path/to/amnezia.conf office-vpn
```

- Принимает `.conf`-файл в формате WireGuard/AmneziaWG (с секцией `[Interface]`)
- Копирует конфиг в `/etc/amnezia/amneziawg/<имя>.conf`
- Включает автозапуск и поднимает туннель через `systemd`

Управление туннелем:

```bash
systemctl start   awg-quick@amnezia0   # включить VPN
systemctl stop    awg-quick@amnezia0   # выключить VPN
systemctl enable  awg-quick@amnezia0   # автозапуск
systemctl disable awg-quick@amnezia0   # отключить автозапуск
awg show                               # активные туннели и трафик
```

## Структура репозитория

```
aiproxy/
├── install.sh                        # Мастер-установщик
├── README.md
├── configs/
│   ├── gost/
│   │   └── config-direct.yaml        # Дефолтный конфиг gost (direct-режим)
│   ├── proxybridge/
│   │   └── config.ini                # Конфиг ProxyBridge
│   └── systemd/
│       ├── gost.service              # Systemd-юнит gost
│       └── proxybridge.service       # Systemd-юнит ProxyBridge
└── scripts/
    ├── install-cliproxy-api.sh       # Установка cliproxy-api
    ├── cliproxy-api-update.sh        # Автообновление cliproxy-api
    ├── install-9router.sh            # Установка 9router
    ├── 9router-update.sh             # Автообновление 9router
    ├── 9router-selfupdate.sh         # Самообновление 9router
    ├── install-proxybridge.sh        # Установка ProxyBridge
    ├── proxybridge-gen-args.sh       # Генератор аргументов ProxyBridge
    ├── proxybridge-gui-wrapper.sh    # GUI-обёртка ProxyBridge
    ├── install-singbox.sh            # Установка sing-box
    ├── install-xray.sh               # Установка Xray
    ├── install-3xui.sh               # Установка 3x-ui
    ├── setup-gost.sh                 # Установка gost
    ├── gost-toggle.sh                # Управление gost прокси
    ├── install-amnezia.sh            # Установка AmneziaWG VPN-клиента
    ├── setup-amnezia-connection.sh   # Настройка VPN-подключения Amnezia
    ├── setup-xrdp.sh                 # Настройка xrdp-сервера
    ├── setup-openbox.sh              # Настройка Openbox + tint2
    ├── setup-lxqt.sh                 # Настройка LXQt
    ├── install-firefox.sh            # Установка Firefox ESR
    ├── install-brave.sh              # Установка Brave Browser
    ├── install-antigravity.sh        # Установка Google Antigravity IDE
    ├── install-claude-code.sh        # Установка Claude Code CLI
    ├── install-opencode.sh           # Установка OpenCode (CLI + Desktop)
    ├── install-cockpit-tools.sh      # Установка Cockpit Tools
    └── install-vscode.sh             # Установка Visual Studio Code
```

## После установки

### Адреса сервисов

| Сервис            | Адрес                                    |
| ----------------- | ---------------------------------------- |
| cliproxy-api      | http://localhost:8317                    |
| 9router           | http://localhost:20128                   |
| gost              | SOCKS5 `0.0.0.0:1080`                    |
| sing-box (`--gate`) | SOCKS5 `:1080` + TUN-шлюз              |
| Xray (`--gate`)   | SOCKS5 `:8080` (outbound=direct)         |
| 3x-ui             | web-панель (команда `x-ui` для настройки) |
| RDP               | `<IP сервера>:3389`                      |

### Управление службами

```bash
# cliproxy-api
systemctl status cliproxy-api
systemctl restart cliproxy-api
journalctl -u cliproxy-api -f

# gost
systemctl status gost
systemctl restart gost
journalctl -u gost -f

# 9router
systemctl status 9router
systemctl restart 9router

# sing-box
systemctl status sing-box
journalctl -u sing-box -f

# Xray
systemctl status xray
journalctl -u xray -f

# xrdp
systemctl status xrdp

# AmneziaWG VPN (замените amnezia0 на имя вашего интерфейса)
systemctl start   awg-quick@amnezia0
systemctl stop    awg-quick@amnezia0
awg show
```

## Лицензия

MIT
