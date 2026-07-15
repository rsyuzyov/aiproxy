# Бэклог

## Активные

- [/] Добавить sing-box TUN как вариант системного прокси в aiproxy
  created: 2026-06-11
  updated: 2026-07-16
  notes: PoC ПОДТВЕРЖДЁН на ct136 (детали: topics/singbox-client.md). Готовы и валидированы configs/singbox/client.json + scripts/singbox-toggle.sh: панели работают, внешка через прокси, fail-closed по upstream. Решения: DNS через прокси, gvisor, ipv4_only. ⚠️ ПЕРЕСМОТР ЦЕЛИ (2026-07-16): loopback-баг ProxyBridge РЕШЁН в форке v3.2.0-loopfix → отказ от PB БОЛЬШЕ НЕ ОБОСНОВАН. Не депрекейтить --proxybridge; sing-box добавлять как ВТОРОЙ вариант (выбор PB / sing-box), а не замену. ОСТАЛОСЬ: (1) режим PROXY_MODE/setup в install-singbox.sh (ставит client.json+toggle+юнит, hint про /dev/net/tun); (2) install.sh — добавить выбор singbox-client vs proxybridge в --aiproxy/parse_args/whiptail/summary; (3) desktop/LXQt-меню (singbox status/toggle); (4) опционально killswitch (nftables) на падение sing-box; (5) задокументировать /dev/net/tun в LXC (как fuse). НЕ забыть закоммитить client.json/toggle/topics.

- [ ] Добавить в реализацию спеку AI Routing (sing-box:1080 + xray:8080 на proxy1.ag.local)
  created: 2026-07-16
  updated: 2026-07-16
  notes: Готовая спека — tasks/airouting/spec.md. Две независимые системы маршрутизации (sing-box вход :1080, xray вход :8080), 5 логических маршрутов (us-direct, kz-us, nl-us, kz-direct, nl-direct) через промежуточные узлы kz/nl.vps.ontab.ru → us.prx.ontab.ru:8000. sing-box: manual selector + auto urltest; xray: ручной выбор. Перед реализацией закрыть 5 открытых вопросов из конца спеки (auto-port 1081? 5 юзеров = proxy1 или люди? транспорт xray на kz/nl? готов ли nl endpoint? единые учётки на оба узла?).

- [ ] Вернуть LogLevel=INFO (ChansrvLogging) в контейнере 107
  created: 2026-04-17
  updated: 2026-07-16
  notes: DEBUG включали временно для диагностики падения chansrv. Причина НАЙДЕНА и ИСПРАВЛЕНА ещё 2026-04-21 (chansrv exit(0) на обрыв TCP + always-restart reconnectwm.sh), стата за ~3 мес набрана → условие «после нахождения причины» выполнено, можно возвращать INFO. Правка: `[Chansrv] ChansrvLogging=INFO` в /etc/xrdp/sesman.ini на ct107 (в setup-xrdp.sh уже INFO).

- [ ] Забрать скрипт `C:\Users\rsyuzyov\repo\it\admin1\ops\scripts\proxy\redsocks-tune` и заменить им текущие скрипты настройки redsocks в aiproxy
  created: 2026-06-11
  updated: 2026-06-11
  notes: Источник — отдельный репо admin1. Заменить setup-redsocks.sh / proxy-toggle.sh (или их логику) на готовый redsocks-tune. Свериться с текущим поведением (set/on/off/status) перед заменой.

## Ожидает

## Идеи

- [ ] Добавить vscode в мета-набор --aiproxy (или отдельную опцию в дефолтный набор)
  created: 2026-06-11
  updated: 2026-06-11
  notes: Сейчас vscode только отдельным флагом --vscode, в --aiproxy не входит. Юзер ставит дефолтный набор + vscode вручную. Рассмотреть включение в мета-набор.

- [ ] install.sh: `INSTALL_DIR="${HOME:-/root}/aiproxy"` (устойчивость к пустому HOME)
  created: 2026-06-11
  updated: 2026-06-11
  notes: При запуске через systemd-run без HOME install.sh падает с `HOME: unbound variable` (set -u). Документированный путь wget|bash в обычном шелле — ок, но дефолт не помешает.

Завершённые задачи: см. `archive.md`
