Проведи end-to-end тест установочного однострочника wget -qO- https://raw.githubusercontent.com/rsyuzyov/aiproxy/main/install.sh | bash -s -- --all -y на Proxmox/LXC.

Требования и порядок:

- Запусти субагента с заданием:

```
- Подключись к hv1.
- Создай новый LXC aiproxy-test (если не создан, Debian 12, 2 vCPU, 4GB RAM, диск 4GB, DHCP, сделай snapshot sYYYYMMDD_HHMMSS через zfs snapshot).
- Если контейнер есуществует, но не запущен - запусти
- В контейнере запусти установку строго однострочником из README.md (wget -qO- https://raw.githubusercontent.com/rsyuzyov/aiproxy/main/install.sh | bash -s -- --all -y), без локального копирования файлов.
- Для redsocks передай тестовые переменные окружения (PROXY_IP/PROXY_PORT/PROXY_LOGIN/PROXY_PASS), чтобы не ломался non-interactive путь в install.sh.
- На каждом шаге логируй полную команду и её stdout/stderr.

Если любая команда завершилась неуспешно — немедленно остановись и выдай:

- точную упавшую команду,
- exit code/сигнал,
- последние 100 строк лога,
- предварительную причину.

Отдельно проверь и зафиксируй:

- статус сервисов cliproxy-api, 9router, xrdp, xrdp-sesman, redsocks;
- наличие firefox-esr;
- прослушивание портов 8317/20128/3389;
- состояние dpkg/apt lock;
- режим прокси после установки (ожидаемо OFF/BYPASS через логику proxy-toggle.sh off).
- При проблемах с rollback через Proxmox используй fallback через zfs rollback -R на dataset контейнера и зафиксируй это в отчёте.
- В конце дай краткий verdict: PASS/FAIL + список найденных дефектов + минимальные предложения по фиксу.

Формат ответа:

- Шаг → Команда → Результат
- Ошибки (если есть)
- Итог
```

Далее предложи исправление. При согласии пользователя:

- внеси исправления
- сделай commit & syn
- останови контейнер, откати (zfs rollback pool2/subvol-131-disk-0@s202060303_145100), снова
- запусти субагента для повторного тестирования

Если что-то непонятно или выывает соменения - спрашивай
