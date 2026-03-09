# Backlog

## DE-001 — Поддержка LXQt и разделение опций Desktop Environment

- status: backlog
- owner: ai
- priority: medium
- updated_at: 2026-03-09
- branch: lxqt

**Контекст**
Сейчас `--xrdp` устанавливает сразу xrdp + openbox + tint2 как единый блок.
Нужно разделить опции: xrdp отдельно, DE отдельно. Добавить LXQt как альтернативу openbox.

**Ограничения**

- ОС: только **Debian 13** (на Debian 12 часть пакетов LXQt не ставится)
- Файловый менеджер: **ставим pcmanfm-qt** (~3 MB — приемлемо)
- Конфиги openbox (меню, tint2, autostart) в LXQt пока не переносить — сначала тест голой установки

**Решения**

- Разделить флаги на три независимых:
  - `--xrdp` — только xrdp + xorgxrdp (без DE)
  - `--openbox` — openbox + tint2 (текущий `setup-xrdp.sh` де-факто)
  - `--lxqt` — LXQt (новый скрипт `setup-lxqt.sh`)
- `--all` включает: cliproxy + proxybridge + xrdp + openbox + firefox (без lxqt)
- `lxqt-session` в `startwm.sh` вместо `openbox-session` (запускаем напрямую, без обёртки startlxqt)
- Два DE одновременно: технически можно, но смысла мало

**Definition of Done**

- [ ] `setup-xrdp.sh` разделён: отдельный скрипт для xrdp, отдельный для openbox
- [ ] Создан `scripts/setup-lxqt.sh` для Debian 13
- [ ] `install.sh`: добавлены флаги `--openbox`, `--lxqt`; `--xrdp` только xrdp-сервер
- [ ] Интерактивное меню обновлено
- [ ] Протестировано на Debian 13 (LXC/Proxmox)

## AI-001 — Оформить каталог AI-артефактов

- status: backlog
- owner: human
- priority: high
- updated_at: 2026-03-03

**Контекст**
Нужно централизованно хранить задачи и промпты для Claude и Kilo.

**Definition of Done**

- [ ] Создана структура `docs/ai/`
- [ ] Добавлены шаблоны задач и промптов
- [ ] Добавлены стартовые промпты по ключевым сценариям
