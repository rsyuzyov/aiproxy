Проверь, сколько места, памяти и процессоров нужно выделять для контейнера в разных режимах установки.

# Вариант 1

- Подключись по ssh к hv1, там есть контейенр 131
- Откати контейнер (pct stop 131 ; zfs rollback -R pool2/subvol-131-disk-0@s202060303_145100 && pct start 131)
- В контейнере запусти команду

```bash
wget -O- https://raw.githubusercontent.com/rsyuzyov/aiproxy/master/install.sh | bash -s -- --all -y
```

Отследи, сколько места, памяти и cpu понадобится в процессе установки, запиши в readme

# Вариант 2

- Подключись по ssh к hv1, там есть контейенр 131
- Откати контейнер (pct stop 131 ; zfs rollback -R pool2/subvol-131-disk-0@s202060303_145100 && pct start 131)
- В контейнере запусти команду

```bash
wget -O- https://raw.githubusercontent.com/rsyuzyov/aiproxy/master/install.sh | bash -s -- --cliproxy --9router --gost -y
```

Отследи, сколько места, памяти и cpu понадобится в процессе установки, запиши в readme
