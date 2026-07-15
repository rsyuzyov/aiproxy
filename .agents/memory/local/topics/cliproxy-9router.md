# cliproxy-api и 9router — известные проблемы

> **РЕШЕНО (2026-07-16).** Зависание панелей `/management.html`, `/dashboard`, `/login`
> у ВСЕХ трёх локальных сервисов (cliproxy 8317, 9router 20128, OmniRoute 20129) — это
> **НЕ баги бинарей**, а перехват ProxyBridge (NFQUEUE рвал loopback-flow даже при правиле
> `127.0.0.1:DIRECT`). Доказано A/B-тестом 2026-06-11. Первопричина устранена в форке
> **[rsyuzyov/ProxyBridge v3.2.0-loopfix](https://github.com/rsyuzyov/ProxyBridge/releases/tag/v3.2.0-loopfix)**
> (PR апстриму + неофиц. Linux-сборка). Детали механизма: [proxybridge.md](proxybridge.md).
>
> Старый детальный per-binary разбор (по версиям бинарей, strace, «eventfd deadlock 9router»,
> «баг в хендлере /management.html») описывал СИМПТОМЫ и оказался **ложным следом** — удалён,
> чтобы не путать. Если панель снова виснет — искать перехват loopback, а не баг бинаря.

## Как отличить перехват loopback от реального бага бинаря

- **Тест:** снять перехват (`ProxyBridge --cleanup`, либо загрузить форк с loopfix, либо
  sing-box TUN — там loopback идёт мимо TUN). Панели открываются за 0.002–0.027с → был перехват.
- При активном «плохом» перехвате: `ss -tnp` показывает curl→`127.0.0.1:<порт>` застрявшим
  в **SYN-SENT**, ответ 0 байт (`Send-Q` растёт, заголовки не уходят).

## Полезные операционные заметки (актуальны)

- **cliproxy-api (8317):** панель — SPA ~2.3 МБ, бинарь тянет её с GitHub при старте
  (`panel-github-repository` в config.yaml) → `/opt/cliproxy-api/static/management.html`.
  Обход при недоступной панели: открыть этот файл локально через `file://`, в поле URL указать
  `http://<container>:8317` + secret-key. Auto-update: `cliproxy-api-updater.timer` (05:00).
- **9router (20128, Next.js):** `--host 127.0.0.1` биндит listener И меняет Next.js `HOSTNAME`
  env на 127.0.0.1 — важно, т.к. SSR-fetch использует HOSTNAME. Data dir: `/root/.9router/db.json`.
  Auto-update: `9router-updater.timer` (05:00). Может спавнить два node на разных интерфейсах
  (апстрим issue #475).
- **OmniRoute (20129):** порт сдвинут с дефолтного 20128 (чтобы не клешиться с 9router).
  CLI: `omniroute --port <p> --no-open`.
