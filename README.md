# AIProxy Setup

Репозиторий для автоматической установки и настройки AI-прокси окружения на чистом Debian.

## Что включает

| Компонент          | Описание                                           |
| ------------------ | -------------------------------------------------- |
| **cliproxy-api**   | AI-прокси сервер с поддержкой OpenAI/Gemini/Claude |
| **9router**        | Еще один AI-прокси сервер                          |
| **xrdp + openbox** | RDP-доступ к рабочему столу                        |
| **Firefox ESR**    | Браузер (опционально)                              |
| **Brave Browser**  | Альтернативный браузер (опционально)               |
| **redsocks**       | Перенаправление TCP-трафика через SOCKS5 прокси    |

## Быстрый старт

### Однострочная команда установки

```bash
wget -qO- https://raw.githubusercontent.com/rsyuzyov/aiproxy/main/install.sh | bash
```

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
# Установить всё (кроме Brave)
bash install.sh --all -y

# Только cliproxy-api и xrdp
bash install.sh --cliproxy --xrdp -y

# С настройкой redsocks
PROXY_IP=1.2.3.4 PROXY_PORT=1080 PROXY_LOGIN=user PROXY_PASS=pass \
  bash install.sh --all --redsocks -y
```

### Параметры командной строки

| Параметр                   | Описание                                |
| -------------------------- | --------------------------------------- |
| `--all`                    | Установить все компоненты (кроме Brave) |
| `--cliproxy`               | Установить cliproxy-api                 |
| `--9router`                | Установить 9router                      |
| `--xrdp`                   | Настроить xrdp + openbox                |
| `--firefox`                | Установить Firefox ESR                  |
| `--brave`                  | Установить Brave Browser                |
| `--redsocks`               | Настроить redsocks                      |
| `-y` / `--non-interactive` | Неинтерактивный режим                   |
| `--help`                   | Показать справку                        |

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

### Настройка redsocks

```bash
bash ~/aiproxy/scripts/setup-redsocks.sh <ip> <port> <login> <password> [local_port]

# Пример:
bash ~/aiproxy/scripts/setup-redsocks.sh 1.2.3.4 1080 myuser mypassword
```

## Управление прокси

После установки redsocks доступны команды (должны запускаться от root):

```bash
# Включить прокси (весь TCP через SOCKS5)
proxy-toggle.sh on

# Выключить прокси (прямое соединение)
proxy-toggle.sh off

# Проверить статус
proxy-toggle.sh status

# Обновить настройки прокси
update-redsocks.sh 1.2.3.4 1080 newuser newpassword
```

### Статусы прокси

| Статус   | Описание                                      |
| -------- | --------------------------------------------- |
| `ACTIVE` | redsocks запущен, трафик идёт через прокси    |
| `BYPASS` | redsocks остановлен, прямое соединение        |
| `BROKEN` | Несогласованное состояние (нужна диагностика) |

## Структура репозитория

```
aiproxy/
├── install.sh                    # Мастер-установщик
├── README.md
└── scripts/
    ├── install-cliproxy-api.sh   # Установка cliproxy-api
    ├── install-9router.sh        # Установка 9router
    ├── install-firefox.sh        # Установка Firefox ESR
    ├── install-brave.sh          # Установка Brave Browser
    ├── setup-xrdp.sh             # Настройка RDP + openbox
    ├── setup-redsocks.sh         # Настройка redsocks
    └── proxy-toggle.sh           # Управление прокси
```

## После установки

### Адреса сервисов

| Сервис                           | URL                    |
| -------------------------------- | ---------------------- |
| cliproxy-api                     | http://localhost:8317  |
| cliproxy-api (панель управления) | http://localhost:8317  |
| 9router                          | http://localhost:20128 |
| RDP                              | `<IP сервера>:3389`    |

### Управление службами

```bash
# cliproxy-api
systemctl status cliproxy-api
systemctl restart cliproxy-api
journalctl -u cliproxy-api -f

# 9router
systemctl status 9router
systemctl restart 9router

# xrdp
systemctl status xrdp
```

## Требования

- Debian 11 (Bullseye) или Debian 12 (Bookworm)
- Доступ root
- Интернет-соединение

## Лицензия

MIT
