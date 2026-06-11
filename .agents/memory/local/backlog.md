# Бэклог

## Активные

- [ ] Мигрировать aiproxy с ProxyBridge на sing-box TUN (отказ от ProxyBridge)
  created: 2026-06-11
  updated: 2026-06-11
  notes: РЕШЕНИЕ принято 2026-06-11. Причина: ProxyBridge V4.0-Beta рвёт loopback-трафик локальных панелей (баг в NFQUEUE-перехвате, конфигом не обходится, апстрим мёртв ~4 мес). Реальный кейс юзера — `*:PROXY` (проксировать всё кроме локалки), per-process не используется → это классическая задача прозрачного проксирования. sing-box TUN решает её нативно (loopback в TUN не попадает → панели работают), TCP+UDP, fail-closed (sing-box down → TUN down). sing-box в проекте уже есть (для --gate). Объём: TUN-режим как клиент (не gate), SOCKS5-outbound на внешний прокси, исключения для локалки/LAN, замена пунктов меню/мета-набора --aiproxy, депрекейт proxybridge-скриптов. Per-process проксирование нужно юзеру, но в ДРУГОМ проекте.

- [ ] Забрать скрипт `C:\Users\rsyuzyov\repo\it\admin1\ops\scripts\proxy\redsocks-tune` и заменить им текущие скрипты настройки redsocks в aiproxy
  created: 2026-06-11
  updated: 2026-06-11
  notes: Источник — отдельный репо admin1. Заменить setup-redsocks.sh / proxy-toggle.sh (или их логику) на готовый redsocks-tune. Свериться с текущим поведением (set/on/off/status) перед заменой.

## Ожидает

## Идеи

- [ ] Вернуть LogLevel=INFO в контейнере 107 после накопления статистики (2-4 недели) или после нахождения причины падения chansrv
  created: 2026-04-17
  updated: 2026-04-17
  notes: DEBUG не критичен (7.5MB/день при 10 юзерах с новым logrotate), но в штатном режиме держать INFO

- [ ] Добавить vscode в мета-набор --aiproxy (или отдельную опцию в дефолтный набор)
  created: 2026-06-11
  updated: 2026-06-11
  notes: Сейчас vscode только отдельным флагом --vscode, в --aiproxy не входит. Юзер ставит дефолтный набор + vscode вручную. Рассмотреть включение в мета-набор.

Завершённые задачи: см. `archive.md`
