---
description: E2E тест установки AIProxy в LXC контейнере на Proxmox
---

# E2E тест AIProxy (откат + установка)

Контейнер уже существует. Workflow откатывает его к ZFS-снимку, затем устанавливает компоненты и проверяет.

## Параметры

Все параметры вынесены в [`.agents/workflows/.env`](.env) (файл игнорируется git).
Если .agents/workflows/.env не существует то скопируй шаблон, сообщи пользователю и прекрати выполнение:

```bash
cp .agents/workflows/.env.example .agents/workflows/.env
# подправь значения под свой стенд
```

Перед каждым шагом подгрузи переменные:

```bash
set -a; . .agents/workflows/.env; set +a
```

Ожидаемые переменные: `PVE_HOST`, `CT_ID`, `ZFS_POOL`, `SNAPSHOT`, `REPO_URL`, `BRANCH`, `COMPONENTS`, `TIMEOUT`.

## Шаги

### 1. Подключиться к Proxmox

```bash
ssh "root@${PVE_HOST}"
```

### 2. Остановить контейнер и откатить ZFS-снимок

```bash
pct stop "${CT_ID}" || true
zfs rollback "${ZFS_POOL}/subvol-${CT_ID}-disk-0@${SNAPSHOT}" -R
pct start "${CT_ID}"
```

Подождать ~3 секунды пока контейнер загрузится.

### 3. Зайти в контейнер, клонировать репо

Все последующие команды (шаги 3–5) выполняются **внутри контейнера** через `pct exec`, а **не** через `pct enter` (он создаёт интерактивную сессию и может зависнуть).

```bash
pct exec "${CT_ID}" -- bash -c "git clone ${REPO_URL} ~/aiproxy && cd ~/aiproxy && git checkout ${BRANCH}"
```

### 4. Запустить установку

Установка ограничена тайм-аутом (`${TIMEOUT}`). Если превышен — тест считается проваленным.

```bash
pct exec "${CT_ID}" -- bash -c "cd ~/aiproxy && timeout ${TIMEOUT} bash install.sh ${COMPONENTS} -y"
```

Дождаться завершения. Следить за ошибками в выводе. Если exit code = 124, значит тайм-аут сработал — установка зависла.

### 5. Проверки после установки

#### Проверка служб

```bash
pct exec "${CT_ID}" -- systemctl status gost
pct exec "${CT_ID}" -- systemctl status proxybridge
pct exec "${CT_ID}" -- systemctl status cliproxy-api
pct exec "${CT_ID}" -- systemctl status 9router
pct exec "${CT_ID}" -- systemctl status xrdp
```

#### Проверка ProxyBridge

```bash
# Должен показать config.ini
pct exec "${CT_ID}" -- cat /etc/proxybridge/config.ini

# Проверить что gen-args.sh формирует правильные аргументы
pct exec "${CT_ID}" -- bash -c "source /usr/local/lib/proxybridge/gen-args.sh && echo ARGS: \$PROXYBRIDGE_ARGS"

# Проверить что трафик ходит (DIRECT режим)
pct exec "${CT_ID}" -- curl -sI https://ya.ru | head -3
```

#### Проверка RDP

Подключиться по RDP к IP контейнера на порт 3389.
Убедиться что LXQt загружается, в меню есть "Proxy Bridge".

#### Проверка GUI-обёртки

```bash
pct exec "${CT_ID}" -- ls -la /usr/local/lib/proxybridge/gui-wrapper.sh
pct exec "${CT_ID}" -- ls -la /usr/share/applications/proxybridge-gui.desktop
```
