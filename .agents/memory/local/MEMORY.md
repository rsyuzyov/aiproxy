# Memory Index

Последняя оптимизация: 2026-04-21

## Проект

- **aiproxy** — набор скриптов для развёртывания прокси/RDP-контейнеров (Proxmox LXC) с desktop-окружением, xrdp и набором AI-инструментов.
- Основные каталоги:
  - [scripts/](../../../scripts/) — установочные скрипты (setup-xrdp, setup-lxqt, install-*)
  - [install.sh](../../../install.sh) — главная точка входа
  - [.claude/](../../../.claude/) — настройки Claude Code для проекта

## Инфраструктура

- Контейнеры проекта крутятся на Proxmox-хосте **srv-hv1.ag.local**
- Доступ внутрь контейнера: `ssh srv-hv1.ag.local` → `pct exec <ID> -- bash`
- Контейнер 107 — основной рабочий (aiproxy1)
- RDP-настройка: `Policy=U` в sesman.ini, persistent-сессии, multi-user, root разрешён

## Ограничения

- Не запускать watchdog-скрипты инлайн в интерактивной RDP-сессии (см. topics/xrdp.md)
- Все фиксы поведения xrdp — только через `/etc/xrdp/*.ini`, `/etc/X11/xrdp/xorg.conf.d/*`, `/etc/xdg/autostart/*.desktop` или systemd unit
- На прод-контейнерах `LogLevel=INFO` в xrdp; `DEBUG` включать только временно для диагностики

## Факты

- xrdp 0.10.x **не рестартует умерший `xrdp-chansrv`** при reconnect в существующую сессию — by design
- Клиент RDP сообщает свою текущую активную раскладку (keylayout, напр. 0x00000419=ru) — xrdp ставит в Xorg только её без переключателя; `us,ru + alt_shift_toggle` возвращается через XDG autostart из setup-xrdp.sh

## Грабли и уроки

- ⚠️ **Зомби-watchdog в RDP-сессии (2026-04-17, контейнер 107):** предыдущая итерация AI-агента запустила `while true; do setxkbmap; sleep 5; done &` инлайн в интерактивной сессии с `DISPLAY=:11`. После гибели сессии :11 процесс (pid 85627) висел 21ч на несуществующем дисплее, не помогал никому, нигде не зафиксирован (cron/systemd/autostart чисты). Правило: inline-watchdog'и в сессию не запускать, см. [topics/xrdp.md](topics/xrdp.md).
- ⚠️ **Policy=Default в sesman.ini плодит отдельные сессии на каждый IP** — плохо для сценария «подключился с работы → из дома». Правильно: `Policy=U`.
- ⚠️ **chansrv exit(0) на нештатный TCP-обрыв + sesman 0.10.x не перезапускает chansrv при reconnect** (by design, upstream fix — PR #3567 в 0.11+). Симптом: после sleep ноута → reconnect → чёрный экран 10с + сломанный clipboard. Фикс в [scripts/setup-xrdp.sh](../../../scripts/setup-xrdp.sh) `configure_reconnect_script()`: патч `/etc/xrdp/reconnectwm.sh` который сам перезапускает chansrv. Детали: diary 2026-04-21.

## Ссылки

- [topics/xrdp.md](topics/xrdp.md) — полная инфа по настройке xrdp
- [topics/cliproxy-9router.md](topics/cliproxy-9router.md) — баги панелей cliproxy-api/9router, обходы
