# AIProxy Setup

Набор скриптов для развертывания OpenAI-совместимых прокси. Создавались и проверялись на Debian 13.

## Что включает

| Компонент           | Описание                                                             |
| ------------------- | -------------------------------------------------------------------- |
| **cliproxy-api**    | AI-прокси сервер с поддержкой OpenAI/Gemini/Claude                   |
| **9router**         | Ещё один AI-прокси сервер                                            |
| **Cockpit Tools**   | Менеджер аккаунтов AI IDE: Antigravity, Copilot, Windsurf, Cursor... |
| **gost**            | SOCKS5 прокси для всей сети (замена redsocks)                        |
| **ProxyBridge**     | Перенаправление TCP/UDP трафика per-process через SOCKS5/HTTP прокси |
| **AmneziaWG**       | Альтернатива прокси для доступа к зарубежным провайдерам             |
| **xrdp + openbox**  | RDP-доступ к рабочему столу                                          |
| **Firefox ESR**     | Браузер                                                              |
| **Brave Browser**   | Альтернативный браузер                                               |
| **Claude Code**     | CLI-агент от Anthropic для работы с кодом в терминале                |
| **Claude Desktop**  | Десктопное приложение Claude для Linux — неофициальный порт          |
| **VS Code**         | Visual Studio Code — универсальный редактор от Microsoft             |
| **Antigravity IDE** | Google AI IDE на базе VS Code с Gemini                               |

- Минимальный набор для установки — `cliproxy-api`.
- Для работы с claude, openai и другими провайдерами можно установить **gost** (прокси для всей сети) и/или **ProxyBridge** (per-process прокси) и арендовать прокси на https://px6.me (https://proxy6.net)
- Для активации учётных записей (google, aws) и прохождения OAuth через прокси или туннель можно поставить браузер+xrdp и заходить по RDP на рабочий стол.

## Требования

- Debian 13
- Доступ root
- Интернет-соединение

**Ресурсы:**

- Режим без GUI и браузера: 1 CPU / 512 MB ОЗУ / 2 GB диск
- Режим с GUI и браузером: минимум 2 CPU / 4 GB / 4 GB, для комфортной работы 4 CPU / 8 GB / 4 GB

## Быстрый старт

### Однострочная команда (основной набор)

```bash
wget -O- https://raw.githubusercontent.com/rsyuzyov/aiproxy/master/install.sh | bash -s -- --all -y
```

`--all` устанавливает: **cliproxy-api + 9router + gost + ProxyBridge + xrdp + openbox + Firefox ESR**

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
# Установить основной набор: cliproxy-api + 9router + gost + ProxyBridge + xrdp + Firefox
bash install.sh --all -y

# Только gost + ProxyBridge (прокси для сети + per-process правила)
bash install.sh --gost --proxybridge -y

# Только cliproxy-api и xrdp
bash install.sh --cliproxy --xrdp -y

# AI-инструменты: Antigravity IDE + Claude Code + Cockpit Tools
bash install.sh --antigravity --claude-code --cockpit-tools -y
```

### Параметры командной строки

| Параметр                   | Описание                                                                       |
| -------------------------- | ------------------------------------------------------------------------------ |
| `--all`                    | Основной набор: cliproxy + 9router + gost + ProxyBridge + xrdp + Firefox       |
| `--cliproxy`               | Установить cliproxy-api                                                        |
| `--gost`                   | Установить gost (SOCKS5 прокси для всей сети)                                  |
| `--proxybridge`            | Установить ProxyBridge (per-process TCP+UDP прокси)                            |
| `--9router`                | Установить 9router                                                             |
| `--xrdp`                   | Настроить xrdp + openbox                                                       |
| `--openbox`                | Настроить Openbox + tint2 как DE                                               |
| `--lxqt`                   | Настроить LXQt как DE (Debian 13)                                              |
| `--firefox`                | Установить Firefox ESR                                                         |
| `--brave`                  | Установить Brave Browser                                                       |
| `--amnezia`                | Установить AmneziaWG VPN-клиент                                                |
| `--antigravity`            | Установить Google Antigravity IDE                                              |
| `--claude-code`            | Установить Claude Code CLI                                                     |
| `--claude-desktop`         | Установить Claude Desktop (неофициальный Linux-порт)                           |
| `--cockpit-tools`          | Установить Cockpit Tools (менеджер аккаунтов AI IDE)                           |
| `--vscode`                 | Установить Visual Studio Code                                                  |
| `-y` / `--non-interactive` | Неинтерактивный режим                                                          |
| `--help`                   | Показать справку                                                               |

> 💡 **gost + ProxyBridge** — рекомендуемая связка. Gost обслуживает всю сеть (SOCKS5 без пароля → upstream с паролем), ProxyBridge выбирает приложения для проксирования.

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

### Настройка xrdp + openbox

```bash
bash ~/aiproxy/scripts/setup-xrdp.sh
```

- Устанавливает xrdp, xorgxrdp, openbox
- Настраивает сессию через `dbus-launch openbox-session`
- Принудительно устанавливает **английскую раскладку (US)** при RDP-входе
- Порт RDP: `3389`

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

### Установка Claude Desktop

```bash
bash ~/aiproxy/scripts/install-claude-desktop.sh
```

> ⚠ Официальный Claude Desktop поддерживается только на macOS и Windows. Скрипт устанавливает **неофициальный Debian-порт** ([aaddrick/claude-desktop-debian](https://github.com/aaddrick/claude-desktop-debian)) — перепаковку Windows-версии.

- Пробует установить через APT-репозиторий, при неудаче — скачивает `.deb` с GitHub Releases
- Поддерживает MCP (Model Context Protocol), системный трей, глобальные горячие клавиши
- Запуск: `claude-desktop`

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
    ├── install-cliproxy-api.sh        # Установка cliproxy-api
    ├── install-proxybridge.sh         # Установка ProxyBridge
    ├── install-9router.sh             # Установка 9router
    ├── install-firefox.sh             # Установка Firefox ESR
    ├── install-brave.sh               # Установка Brave Browser
    ├── install-amnezia.sh             # Установка AmneziaWG VPN-клиента
    ├── install-antigravity.sh         # Установка Google Antigravity IDE
    ├── install-claude-code.sh         # Установка Claude Code CLI
    ├── install-claude-desktop.sh      # Установка Claude Desktop (Linux-порт)
    ├── install-cockpit-tools.sh       # Установка Cockpit Tools
    ├── install-vscode.sh              # Установка Visual Studio Code
    ├── setup-gost.sh                  # Установка gost
    ├── gost-toggle.sh                 # Управление gost прокси
    ├── setup-xrdp.sh                  # Настройка RDP + openbox
    └── setup-amnezia-connection.sh    # Настройка VPN-подключения Amnezia
```

## После установки

### Адреса сервисов

| Сервис       | Адрес                  |
| ------------ | ---------------------- |
| cliproxy-api | http://localhost:8317  |
| 9router      | http://localhost:20128 |
| RDP          | `<IP сервера>:3389`    |

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

# xrdp
systemctl status xrdp

# AmneziaWG VPN (замените amnezia0 на имя вашего интерфейса)
systemctl start   awg-quick@amnezia0
systemctl stop    awg-quick@amnezia0
awg show
```

## Лицензия

MIT
