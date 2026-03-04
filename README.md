# AIProxy Setup

Набор скриптов для развертывания OpenAI-совместимых прокси. Создавались и проверялись на debain 12.

## Что включает

| Компонент          | Описание                                                 |
| ------------------ | -------------------------------------------------------- |
| **cliproxy-api**   | AI-прокси сервер с поддержкой OpenAI/Gemini/Claude       |
| **9router**        | Еще один AI-прокси сервер                                |
| **xrdp + openbox** | RDP-доступ к рабочему столу                              |
| **Firefox ESR**    | Браузер (опционально)                                    |
| **Brave Browser**  | Альтернативный браузер (опционально)                     |
| **redsocks**       | Перенаправление TCP-трафика через SOCKS5 прокси          |
| **AmneziaWG**      | Альтернатива прокси для доступа к зарубежным провайдерам |

- Минимальный набор для установки - cliproxy-api.
- Для работы с claude, openai и другими провайдерами можно установить redsocks и арендовать прокси на https://px6.me (https://proxy6.net)
- Для активации учетных записей (google, aws) и прохождения oauth через прокси или туннель можно поставить браузер+xrdp и заходить по rdp на рабочий стол

## Требования

- Режим без gui и браузера требует 1 CPU / 512 MB ОЗУ/ 2 GB Диск
- Режим с gui и браузером требует минимум 2CPU / 4GB / 4GB, для комфортной работы в браузере 4CPU / 8GB / 4GB

## Быстрый старт

### Однострочная команда установки

```bash
wget -O- https://raw.githubusercontent.com/rsyuzyov/aiproxy/master/install.sh | bash -s -- --all -y
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
| `--amnezia`                | Установить AmneziaWG VPN-клиент         |
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

### Установка и настройка AmneziaWG VPN

**Шаг 1. Установить AmneziaWG:**

```bash
sudo bash ~/aiproxy/scripts/install-amnezia.sh
```

- Устанавливает ядро AmneziaWG (PPA для Ubuntu, `.deb` с GitHub или сборка из исходников)
- Создаёт каталог конфигураций `/etc/amnezia/amneziawg/`
- Поддерживает архитектуры `amd64` и `arm64`

**Шаг 2. Подключить конфигурацию:**

```bash
sudo bash ~/aiproxy/scripts/setup-amnezia-connection.sh /path/to/amnezia.conf

# С явным именем интерфейса (по умолчанию amnezia0):
sudo bash ~/aiproxy/scripts/setup-amnezia-connection.sh /path/to/amnezia.conf office-vpn
```

- Принимает `.conf`-файл в формате WireGuard/AmneziaWG (с секцией `[Interface]`)
- Копирует конфиг в `/etc/amnezia/amneziawg/<имя>.conf`
- Включает автозапуск и поднимает туннель через `systemd`

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
├── install.sh                        # Мастер-установщик
├── README.md
└── scripts/
    ├── install-cliproxy-api.sh        # Установка cliproxy-api
    ├── install-9router.sh             # Установка 9router
    ├── install-firefox.sh             # Установка Firefox ESR
    ├── install-brave.sh               # Установка Brave Browser
    ├── install-amnezia.sh             # Установка AmneziaWG VPN-клиента
    ├── setup-xrdp.sh                  # Настройка RDP + openbox
    ├── setup-redsocks.sh              # Настройка redsocks
    ├── setup-amnezia-connection.sh    # Настройка VPN-подключения Amnezia
    └── proxy-toggle.sh                # Управление прокси
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

# AmneziaWG VPN (замените amnezia0 на имя вашего интерфейса)
systemctl start   awg-quick@amnezia0   # включить VPN
systemctl stop    awg-quick@amnezia0   # выключить VPN
systemctl status  awg-quick@amnezia0   # статус
awg show                               # показать активные туннели и трафик
```

## Управление AmneziaWG

После установки и первичной настройки (через `setup-amnezia-connection.sh`) туннель управляется через `systemd`:

```bash
# Включить VPN
systemctl start awg-quick@amnezia0

# Выключить VPN
systemctl stop awg-quick@amnezia0

# Включить/выключить автозапуск при загрузке
systemctl enable  awg-quick@amnezia0
systemctl disable awg-quick@amnezia0

# Обновить конфиг (при изменении .conf-файла)
sudo bash ~/aiproxy/scripts/setup-amnezia-connection.sh /path/to/new.conf amnezia0
```

Конфигурационные файлы хранятся в `/etc/amnezia/amneziawg/`.

## Требования

- Debian 11 (Bullseye) или Debian 12 (Bookworm)
- Доступ root
- Интернет-соединение

## Лицензия

MIT
