# cliproxy-api и 9router — известные проблемы

## cliproxy-api (router-for-me/CLIProxyAPI)

### Порт 8317, панель /management.html

- Панель — SPA 2.3 МБ, бинарь тянет её с GitHub при старте (`panel-github-repository` в config.yaml), кладёт в `/opt/cliproxy-api/static/management.html`
- Бинарь автохешит `secret-key` в bcrypt при старте (это норма)
- Auto-update: `cliproxy-api-updater.timer` ежедневно 05:00, rollback-скрипт откатывает только на свежий (<15 мин) .bak

### Баг: `/management.html` висит, 0 байт ответа

- **Симптом**: сервер пишет весь файл в socket (`Send-Q ≈ 2.3 МБ`), но клиент не получает HTTP-заголовков. Таймаут curl/browser.
- **Не связано с версией**: 6.9.26 / 6.9.28 / 6.9.29 — одинаково
- **Не связано со статикой**: даже после удаления файла бинарь перекачивает его и воспроизводит тот же симптом
- API-роуты (`/v1/*`, `/v0/*`, `/`) отвечают нормально
- **Подтверждение, что баг именно в HTTP-хендлере бинаря**: если открыть `/opt/cliproxy-api/static/management.html` через `file://` (хоть на рабочей машине, хоть **в том же контейнере в браузере**) — панель подключается к `http://127.0.0.1:8317` и все API-запросы идут нормально. То есть HTTP-стек бинаря исправен для `/v0/*`, `/v1/*` и т.п., проблема **строго в хендлере роута `/management.html`** (видимо, какая-то проверка/миддлвар перед отдачей статика).
- **Рабочий обход**: скопировать `management.html` на рабочую машину, открыть в браузере, в поле URL указать `http://<container>:8317` + secret-key. `disable-control-panel: true` в config.yaml можно оставить (чтобы роут 404'ил, а не висел).
- Панель отдельно на GitHub Pages не хостится (404 на router-for-me.github.io/Cli-Proxy-API-Management-Center)

## 9router (decolua/9router, npm)

### Порт 20128, Next.js 16.2.1

- Unit запускает `/bin/9router` (Node.js), тот спавнит `next-server`
- Data dir: `/root/.9router/db.json` (состояние, настройки)
- Без `--tray` бинарь в stdout рисует TUI-меню «Choose Interface» (и при systemd без TTY — не блокирует, но мусорит в журнал)
- Auto-update: `9router-updater.timer` ежедневно 05:00

### Баг: `/login`, `/dashboard`, `/api/auth/session` виснут в SSR

- **Симптом**: `/` мгновенно 307 → `/dashboard` → `/login`, но рендер `/login` висит 15s+ с 0 байт ответа. `/api/health` работает мгновенно.
- **Strace**: после `GET /login` next-server читает `db.json` дважды, затем только eventfd wakeups — **deadlock в промисе**, никаких fetch/openat/connect
- **Не помогает**: откат на v0.3.83, `--tray`, `--log`, `--host 127.0.0.1` (HOSTNAME), `requireLogin: false` в db.json
- В issues апстрима ровно такого симптома нет — надо будет репортить с strace-данными
- **Обход пока не найден** — UI недоступен, но API (`/api/*` кроме auth) работает

### Полезные заметки

- `--host 127.0.0.1` биндит listener и меняет Next.js `HOSTNAME` env на 127.0.0.1 (важно, т.к. SSR-fetch использует HOSTNAME)
- Видел при старте контейнера, что бинарь спавнил два процесса node на разных интерфейсах (см. апстрим issue #475) — у нас сейчас один next-server
