Проведи end-to-end тест установочного однострочника wget -qO- https://raw.githubusercontent.com/rsyuzyov/aiproxy/main/install.sh | bash -s -- --all -y на Proxmox/LXC.

Требования и порядок:

- Подключись к hv1.
- Создай новый LXC aiproxy-test (если не создан, Debian 12, 2 vCPU, 4GB RAM, диск 4GB, DHCP, ). Установи пароль 1234567890.
- Сразу после создания сделай snapshot before_install_YYYYMMDD_HHMMSS.
- Запусти установку строго однострочником из README.md, без локального копирования файлов.
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
- Формат ответа:

Шаг → Команда → Результат
Ошибки (если есть)
Итог
