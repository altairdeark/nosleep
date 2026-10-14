# nosleep

[Русский](README.ru.md)

Keep a Mac awake with the lid closed while a command runs (a claude session, a long
build). Plus a menu bar icon: see at a glance whether the Mac can sleep, and toggle
it in one click.

Under the hood: `pmset -a disablesleep 1`. `caffeinate` does not help here: with the
lid closed the Mac sleeps anyway.

<p>
  <img src="docs/menu-off.png" width="360" alt="Menu: Mac sleeps as usual">
  <img src="docs/menu-on.png" width="360" alt="Menu: Mac stays awake, a timer is running">
</p>

The menu bar UI is in Russian.

## Commands

```
nosleep claude          # stay awake while claude runs
nosleep for 1h          # stay awake for an hour (90m; bare 30 = minutes)
nosleep on | off        # manual mode
nosleep off --force     # clear everything
nosleep status
```

Several `nosleep <command>` at once are fine: the Mac may sleep again once the last
one exits.

## Install

Requires macOS 13+ and Xcode Command Line Tools (`xcode-select --install`, for `swiftc`).

```
git clone https://github.com/altairdeark/nosleep.git
cd nosleep
./install.sh             # asks for the admin password once
./install.sh uninstall   # remove everything and restore normal sleep
```

What it installs:
- `/etc/sudoers.d/nosleep` - passwordless sudo for `pmset -a disablesleep 0|1` only
  (template: `install/sudoers-nosleep`). The script checks that any other sudo still
  asks for a password.
- `~/.local/bin/nosleep` - symlink to `bin/nosleep`. `~/.local/bin` must be on `PATH`.
- `~/Applications/NosleepBar.app` menu bar icon (built from `menubar/NosleepBar.swift`
  with `swiftc`) and its login item `~/Library/LaunchAgents/local.nosleep.bar.plist`.

Keep the cloned folder in place after install: the command is a symlink into it.

## Menu bar icon

- empty cup - normal sleep
- full cup - sleep disabled
- orange full cup - sleep disabled but nothing holds it (crash, reboot), or running
  on battery (works, but drains and heats up)

The menu shows what keeps the Mac awake and offers "stay awake 1 hour / 2 hours /
until I turn it off" and "let the Mac sleep".

## Caveats

- A closed Mac in a bag gets hot. On battery the icon turns orange.
- If the process is killed with `kill -9` or the Mac crashes, the flag stays on (and
  survives a reboot). The icon turns orange; clear it with `nosleep off --force` or
  from the menu.

## License

MIT
