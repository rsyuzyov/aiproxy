# Архив

## 2026-06

- [x] Расследовать зависание локальных панелей при ProxyBridge + подготовить handoff
  created: 2026-04-19
  completed: 2026-06-11
  result: первопричина доказана (перехват ProxyBridge, NFQUEUE рвёт loopback; НЕ баги бинарей). Фикс/форк вынесен юзером в ОТДЕЛЬНЫЙ репо/сессию. Артефакт-handoff: `tasks/2026-06-11-proxybridge-loopback-bug/report.md`. В aiproxy остаётся миграция на sing-box TUN (см. backlog).

- [x] Починить буфер обмена VM→host, отваливающийся после reconnect (ct 107)
  created: 2026-04-21
  completed: 2026-06-11
  result: корень — старый chansrv, переживший reconnect, не делает чистый re-handshake cliprdr; VM→host буфер мёртв. Фикс: `reconnectwm.sh` переведён на always-restart on reconnect (kill живого chansrv + respawn на каждый reconnect). Залит на ct 107 + в [scripts/setup-xrdp.sh](../../../scripts/setup-xrdp.sh). Заодно закрыта задача слежения за chansrv exit (wrapper-лог чист с 2026-06-03, always-restart перекрывает). Детали: diary 2026-06-11, topics/xrdp.md.

## 2026-04

- [x] Починить clipboard/раскладку RDP в контейнере 107
  created: 2026-04-17
  completed: 2026-04-17
  result: Policy=U, убита призрачная сессия :11 и мёртвая :10, LogLevel=DEBUG временно, добавлен кастомный logrotate. Зомби-watchdog (pid 85627) прибит. Clipboard работает. См. `topics/xrdp.md` и diary/2026-04-17.md.

- [x] Зафиксировать полученный опыт в установочных скриптах
  created: 2026-04-17
  completed: 2026-04-17
  result: в `scripts/setup-xrdp.sh` добавлены функции `configure_sesman_ini` (Policy=U) и `configure_logrotate` (daily/7/100M).

- [x] Выяснить root cause падения xrdp-chansrv и устранить в контейнере 107
  created: 2026-04-17
  completed: 2026-04-21
  result: root cause — chansrv делает exit(0) при нештатном обрыве TCP (sleep клиента). Плюс sesman 0.10.x не перезапускает chansrv при реконнекте в persistent-сессию (by design, upstream fix PR #3567 merged в devel → 0.11+, в Debian 13/0.10.1 нет). Фикс: патчим `/etc/xrdp/reconnectwm.sh` — при реконнекте проверяет живой chansrv, если нет — чистит сокеты и стартует новый через systemd-run. Артефакты в [scripts/setup-xrdp.sh](../../../scripts/setup-xrdp.sh) (функция `configure_reconnect_script` + `EnableFuseMount=false`). Диагностика: diary 2026-04-17, 2026-04-19, 2026-04-20, 2026-04-21. Технические детали: topics/xrdp.md.
