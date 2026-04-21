# Бэклог

## Активные

- [ ] Следить за chansrv exit в `/var/log/xrdp-chansrv-wrapper.log` на ct 107 после внедрения `reconnectwm.sh` workaround
  created: 2026-04-21
  updated: 2026-04-21
  notes: фикс "автостарт chansrv на reconnect" активен. Хотим убедиться что (а) wrapper продолжает ловить exit(0) на нештатных обрывах и (б) reconnectwm.sh всегда успешно стартует replacement. Через 1-2 недели можно закрыть как done или перевести в idea.

- [/] Разобраться с висящей панелью cliproxy-api `/management.html`
  created: 2026-04-19
  updated: 2026-04-19
  notes: не зависит от версии 6.9.26/28/29. Бинарь пишет 2.3 МБ в socket, клиент не получает HTTP-заголовков. Баг строго в HTTP-хендлере бинаря (подтверждено: SPA работает, если открыть management.html локально через file://). Рабочий обход: открывать панель локально на рабочей машине. В config.yaml стоит disable-control-panel: true. Апдейтер выключен. Детали: topics/cliproxy-9router.md.

- [/] Разобраться с deadlock'ом 9router `/login` /`/dashboard` (SSR висит)
  created: 2026-04-19
  updated: 2026-04-19
  notes: после чтения db.json next-server уходит в eventfd wait (strace). Не зависит от версии 0.3.83/0.3.96, флагов, hostname, requireLogin. Обхода нет, API (/api/health и пр.) работает. Апдейтер выключен. Юзер ковыряет сам, issue апстриму пока не открывали. Детали: topics/cliproxy-9router.md.

## Ожидает

## Идеи

- [ ] Вернуть LogLevel=INFO в контейнере 107 после накопления статистики (2-4 недели) или после нахождения причины падения chansrv
  created: 2026-04-17
  updated: 2026-04-17
  notes: DEBUG не критичен (7.5MB/день при 10 юзерах с новым logrotate), но в штатном режиме держать INFO

Завершённые задачи: см. `archive.md`
