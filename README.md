# nosleep

Мак не засыпает при закрытой крышке, пока идёт команда (например, сессия claude).
Основа - `pmset -a disablesleep 1`.

```
nosleep claude          # флаг держится, пока идёт claude
nosleep on | off        # ручной режим
nosleep off --force     # снять всё
nosleep status
```

## Установка

```
./install.sh             # спросит пароль администратора один раз
./install.sh uninstall   # убрать всё и вернуть обычный сон
```

Что ставит:
- `/etc/sudoers.d/nosleep` - без пароля разрешены только `pmset -a disablesleep 0|1`
  (шаблон: `install/sudoers-nosleep`). Скрипт проверяет, что остальной sudo
  по-прежнему просит пароль.
- `~/.local/bin/nosleep` - симлинк на `bin/nosleep`.
