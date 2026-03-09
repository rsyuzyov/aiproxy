# AIProxy — Онбординг

> Этот файл — точка входа для разработчика и AI-агента. Читай его первым при начале работы с репозиторием.

## Что это

**AIProxy** — набор bash-скриптов для автоматического развёртывания AI-инфраструктуры на Debian.
Цель: поднять OpenAI-совместимые прокси + трафик через внешний SOCKS5/HTTP прокси + опционально GUI-доступ по RDP.

Типичный сценарий использования: VPS или LXC-контейнер в Proxmox, к которому AI-агенты и IDE обращаются как к локальному OpenAI-endpoint.

---

## Стек

| Слой                      | Компонент                                                        | Зачем                                                                                           |
| ------------------------- | ---------------------------------------------------------------- | ----------------------------------------------------------------------------------------------- |
| AI-прокси                 | **cliproxy-api**                                                 | Основной сервис. OpenAI-совместимый API, мультипровайдер (Gemini, Claude, OpenAI). Порт `8317`. |
| AI-прокси (альт.)         | **9router**                                                      | Второй прокси на Node.js. Порт `20128`.                                                         |
| Системный прокси          | **ProxyBridge**                                                  | Перехватывает трафик на уровне ядра (Netfilter NFQUEUE). TCP+UDP. GUI. Рекомендован.            |
| Системный прокси (устар.) | **redsocks**                                                     | Только TCP, iptables. Не совместим с ProxyBridge одновременно.                                  |
| VPN                       | **AmneziaWG**                                                    | WireGuard-совместимый VPN с обфускацией. Альтернатива прокси.                                   |
| GUI / RDP                 | **xrdp + openbox**                                               | RDP-доступ к Debian-десктопу. Нужен для OAuth, визуальной работы с IDE.                         |
| Браузеры                  | Firefox ESR, Brave                                               | Работают через xrdp-сессию.                                                                     |
| AI IDE                    | Antigravity, Claude Code, Claude Desktop, Cockpit Tools, VS Code | Опциональные инструменты разработки.                                                            |

---

## Структура репозитория

```
aiproxy/
├── install.sh                        # Мастер-установщик (точка входа)
├── README.md                         # Пользовательская документация
├── onboarding.md                     # Этот файл
├── scripts/
│   ├── install-cliproxy-api.sh       # Установка + автообновление cliproxy-api
│   ├── install-proxybridge.sh        # Установка ProxyBridge
│   ├── install-9router.sh            # Установка 9router (Node.js)
│   ├── install-firefox.sh
│   ├── install-brave.sh
│   ├── install-amnezia.sh            # Установка AmneziaWG
│   ├── install-antigravity.sh        # Google Antigravity IDE
│   ├── install-claude-code.sh        # Claude Code CLI
│   ├── install-claude-desktop.sh     # Claude Desktop (неофициальный Linux-порт)
│   ├── install-cockpit-tools.sh      # Cockpit Tools (менеджер аккаунтов AI IDE)
│   ├── install-vscode.sh             # VS Code
│   ├── setup-xrdp.sh                 # xrdp + openbox + раскладка US
│   ├── setup-redsocks.sh             # redsocks + iptables
│   ├── setup-amnezia-connection.sh   # Подключение VPN-конфига AmneziaWG
│   ├── proxy-toggle.sh               # Управление redsocks (on/off/status)
│   ├── cliproxy-api-update.sh        # Обновление cliproxy-api (запускается таймером)
│   └── 9router-update.sh             # Обновление 9router (запускается таймером)
├── configs/
│   ├── systemd/                      # Unit-файлы для всех сервисов
│   │   ├── cliproxy-api.service
│   │   ├── cliproxy-api-updater.{service,timer}
│   │   ├── cliproxy-api-rollback.service
│   │   ├── 9router.service
│   │   ├── 9router-updater.{service,timer}
│   │   └── proxybridge.service
│   └── proxybridge/                  # Конфиги ProxyBridge
│       └── tint2rc                   # Конфиг панели задач openbox
└── docs/
    ├── tasks/                        # Задачи для AI-агентов
    │   ├── _task-template.md         # Шаблон задачи
    │   ├── backlog.md                # Задачи в очереди
    │   ├── in-progress.md            # В работе
    │   └── done.md                   # Выполненные
    └── ai/
        └── prompts/                  # Промпты для тестирования и сценариев
```

---

## Требования к среде

- **ОС**: Debian 13 (тестируется на ней; Debian 12 — ограниченно)
- **Права**: root (`sudo` не поддерживается, только `su -` или прямой root)
- **Интернет**: нужен для скачивания релизов с GitHub
- **ProxyBridge**: требует нативный Linux и `glibc >= 2.38`; не работает в WSL

---

## Быстрый старт (для человека)

```bash
# Поднять всё (cliproxy-api + ProxyBridge + xrdp + Firefox)
wget -O- https://raw.githubusercontent.com/rsyuzyov/aiproxy/master/install.sh | bash -s -- --all -y

# Или клонировать и запустить интерактивно
git clone https://github.com/rsyuzyov/aiproxy.git ~/aiproxy
cd ~/aiproxy && bash install.sh
```

---

## Быстрый старт (для AI-агента)

Перед выполнением любой задачи агент должен:

1. **Прочитать этот файл** (`onboarding.md`) — уже делаешь.
2. **Прочитать `docs/tasks/backlog.md`** — там активные задачи.
3. **Прочитать файлы из `docs/tasks/in-progress.md`** — что сейчас в работе.
4. Прочитать конкретный файл задачи, если он указан.
5. Изучить релевантные скрипты в `scripts/` по задаче.

### Соглашения для агентов

- Все изменения — через отдельные ветки git. Ветка указана в задаче (поле `branch:`).
- Для тестирования используется **LXC-контейнер 131 на hv1** (Proxmox).
- Команда отката контейнера: `pct stop 131 ; zfs rollback -R pool2/subvol-131-disk-0@<снапшот> && pct start 131`
- Доступ к контейнеру: `ssh hv1` → `pct enter 131` или `ssh root@<IP контейнера>`
- Все скрипты должны работать в **неинтерактивном режиме** (`-y`).
- После изменения скрипта — обязательно протестировать полный запуск.

---

## Ключевые точки в коде

### `install.sh`

Единственная точка входа. Логика:

1. `require_root` — проверка прав
2. `ensure_locales` — настройка `en_US.UTF-8` + `ru_RU.UTF-8`
3. `ensure_repo` — клонирует репо в `~/aiproxy` если не существует
4. `parse_args` — парсит CLI-флаги в переменные `DO_*`
5. `interactive_menu` — интерактивный выбор (если не `-y`)
6. `run_installations` — запускает скрипты последовательно; при `exit 137` (SIGKILL) — retry
7. `show_summary` — итоговый отчёт

**Флаг `--all` разворачивается в**: `cliproxy + proxybridge + xrdp + firefox`

### `install-cliproxy-api.sh`

Самый сложный скрипт:

- Скачивает последний релиз с GitHub API
- Устанавливает в `/opt/cliproxy-api/`
- Регистрирует `systemd`-сервис
- Настраивает **автообновление** (`cliproxy-api-updater.timer`) и **rollback** при неудачном старте

### `install-proxybridge.sh`

- Использует официальный `deploy.sh` от [InterceptSuite/ProxyBridge](https://github.com/InterceptSuite/ProxyBridge)
- Зависимости: `libnetfilter-queue1`, `libnfnetlink0`, `iptables`, `libgtk-3-0`
- Проверяет совместимость glibc — при несовместимости сообщает, но не падает
- Настраивает автозапуск через systemd-сервис при наличии сохранённого конфига

---

## Адреса сервисов после установки

| Сервис                  | Адрес                                   |
| ----------------------- | --------------------------------------- |
| cliproxy-api            | `http://localhost:8317`                 |
| cliproxy-api management | `http://localhost:8317/management.html` |
| 9router                 | `http://localhost:20128`                |
| RDP                     | `<IP сервера>:3389`                     |

---

## Управление сервисами

```bash
# cliproxy-api
systemctl status cliproxy-api
systemctl restart cliproxy-api
journalctl -u cliproxy-api -f

# Автообновление
systemctl list-timers --all | grep updater

# ProxyBridge — ручной запуск (перехват всего TCP через SOCKS5)
ProxyBridge --proxy socks5://1.2.3.4:1080 --rule "*:*:*:TCP:PROXY"
ProxyBridge --cleanup        # очистка iptables после сбоя
ProxyBridgeGUI               # графический интерфейс

# redsocks (устаревший)
proxy-toggle.sh on           # включить
proxy-toggle.sh off          # выключить
proxy-toggle.sh status       # статус

# AmneziaWG VPN
systemctl start  awg-quick@amnezia0
systemctl stop   awg-quick@amnezia0
awg show
```

---

## Известные ограничения и нюансы

| Проблема                                                | Решение                                                                                                                                            |
| ------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------- |
| ProxyBridge не совместим с glibc < 2.38                 | Используй Debian 13 (glibc 2.40). На Debian 12 установится, но не запустится.                                                                      |
| redsocks и ProxyBridge нельзя использовать одновременно | Оба управляют iptables. Выбирай один. Рекомендуется ProxyBridge.                                                                                   |
| ProxyBridge не работает в WSL                           | Требует нативный Linux с поддержкой Netfilter NFQUEUE.                                                                                             |
| xrdp: раскладка клавиатуры                              | При входе по RDP принудительно устанавливается US. Переключение языка внутри сессии работает через xrdp-конфиг.                                    |
| Claude Desktop                                          | Официальной Linux-версии нет. Используется неофициальный порт [aaddrick/claude-desktop-debian](https://github.com/aaddrick/claude-desktop-debian). |

---

## Рабочий процесс разработки

```bash
# 1. Посмотреть задачи
cat docs/tasks/backlog.md

# 2. Создать ветку по задаче
git checkout -b <branch-из-задачи>

# 3. Внести изменения

# 4. Откатить тестовый контейнер и протестировать
ssh hv1 "pct stop 131 && zfs rollback -R pool2/subvol-131-disk-0@<снапшот> && pct start 131"
ssh root@<IP> "wget -O- .../install.sh | bash -s -- --all -y"

# 5. Закоммитить
git add -A && git commit -m "feat: <описание>"
```

---

## Структура задач для AI-агентов (`docs/tasks/`)

Каждая задача находится в `backlog.md`, `in-progress.md` или `done.md` в формате:

```markdown
## ID-001 — Короткий заголовок

- status: backlog | in-progress | done
- owner: ai | human
- priority: high | medium | low
- updated_at: YYYY-MM-DD
- branch: имя-ветки

**Контекст**
...

**Definition of Done**

- [ ] критерий
```

Шаблон новой задачи: `docs/tasks/_task-template.md`
