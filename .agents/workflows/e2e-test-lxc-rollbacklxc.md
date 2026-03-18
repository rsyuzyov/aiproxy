---
description: E2E тест установки AIProxy в LXC контейнере на Proxmox
---

# E2E тест AIProxy (откат + установка)

Контейнер уже существует. Workflow откатывает его к ZFS-снимку, затем устанавливает компоненты и проверяет.

## Параметры (подставь перед запуском)

| Параметр     | Значение по умолчанию                              | Описание                  |
| ------------ | -------------------------------------------------- | ------------------------- |
| `PVE_HOST`   | `srv-hv1.ag.local`                                 | Proxmox-сервер (SSH)      |
| `CT_ID`      | `131`                                              | ID контейнера             |
| `ZFS_POOL`   | `pool2`                                            | ZFS-пул                   |
| `SNAPSHOT`   | `s20260318`                                        | Имя ZFS-снимка            |
| `BRANCH`     | `lxqt`                                             | Ветка git-репо            |
| `COMPONENTS` | `--lxqt --xrdp --proxybridge --cliproxy --firefox` | Компоненты для install.sh |

## Шаги

### 1. Подключиться к Proxmox

```bash
ssh root@<PVE_HOST>
```

### 2. Остановить контейнер и откатить ZFS-снимок

```bash
pct stop <CT_ID> || true
zfs rollback <ZFS_POOL>/subvol-<CT_ID>-disk-0@<SNAPSHOT> -R
pct start <CT_ID>
```

Подождать ~3 секунды пока контейнер загрузится.

### 3. Зайти в контейнер, клонировать репо

```bash
pct enter <CT_ID>
git clone https://github.com/rsyuzyov/aiproxy.git ~/aiproxy
cd ~/aiproxy
git checkout <BRANCH>
```

### 4. Запустить установку

```bash
bash install.sh <COMPONENTS> -y
```

Дождаться завершения. Следить за ошибками в выводе.

### 5. Проверки после установки

#### Проверка служб

```bash
systemctl status proxybridge
systemctl status cliproxy-api
systemctl status xrdp
```

#### Проверка ProxyBridge

```bash
# Должен показать config.ini
cat /etc/proxybridge/config.ini

# Проверить что gen-args.sh формирует правильные аргументы
source /usr/local/lib/proxybridge/gen-args.sh && echo "ARGS: $PROXYBRIDGE_ARGS"

# Проверить что трафик ходит (DIRECT режим)
curl -sI https://ya.ru | head -3
```

#### Проверка RDP

Подключиться по RDP к IP контейнера на порт 3389.
Убедиться что LXQt загружается, в меню есть "Proxy Bridge".

#### Проверка GUI-обёртки

```bash
ls -la /usr/local/lib/proxybridge/gui-wrapper.sh
ls -la /usr/share/applications/proxybridge-gui.desktop
```
