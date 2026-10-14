#!/bin/zsh -f
# Установка nosleep. Повторный запуск безопасен.
#   ./install.sh             поставить (команда и значок NosleepBar.app)
#   ./install.sh uninstall   убрать всё и вернуть обычный сон

emulate zsh
setopt err_return
path+=(/usr/bin /bin /usr/sbin /sbin)

REPO=${0:A:h}
SUDOERS=/etc/sudoers.d/nosleep
BIN_DIR=$HOME/.local/bin
LINK=$BIN_DIR/nosleep
APP=$HOME/Applications/NosleepBar.app
AGENT_LABEL=local.nosleep.bar
AGENT=$HOME/Library/LaunchAgents/$AGENT_LABEL.plist

step() { print -P -- "%B==> $*%b" }
ok()   { print -P -- "    %F{green}ok%f $*" }
warn() { print -P -- "    %F{yellow}!%f $*" }
fail() { print -P -- "    %F{red}x%f $*" >&2; exit 1 }

# sudo с паролем. Без терминала (например, `!` в Claude Code) пароль
# спрашивается системным окном.
asudo() {
  if [[ -t 0 ]]; then
    sudo "$@"
  else
    SUDO_ASKPASS=$REPO/install/askpass sudo -A "$@"
  fi
}

# Правило работает: реальный вызов без пароля, но с текущим значением,
# поэтому ничего не меняет. `sudo -n -l` для такой проверки не годится: при
# любом NOPASSWD-правиле он отвечает "разрешено" на всё из (ALL) ALL.
pmset_ok() {
  local cur=0
  pmset -g | grep -q 'SleepDisabled[[:space:]]*1' && cur=1
  sudo -n /usr/bin/pmset -a disablesleep $cur >/dev/null 2>&1
}
# Правило не шире нужного: безобидная команда должна просить пароль.
too_broad() { sudo -n /usr/bin/true >/dev/null 2>&1 }

install_sudoers() {
  step "sudoers: pmset disablesleep без пароля"
  # Без кэша пароля: иначе и запрещённая команда выглядит разрешённой.
  sudo -k
  if pmset_ok; then
    ok "уже стоит"
  else
    local tmp=$(mktemp -t nosleep.sudoers)
    sed "s/^USER /$(id -un) /" $REPO/install/sudoers-nosleep > $tmp
    visudo -cf $tmp >/dev/null || { rm -f $tmp; fail "правило не прошло visudo -c" }
    print "    нужен пароль администратора"
    asudo install -m 0440 -o root -g wheel $tmp $SUDOERS
    rm -f $tmp
    sudo -k
    pmset_ok || fail "pmset disablesleep всё ещё просит пароль"
    ok "$SUDOERS"
  fi
  too_broad && fail "sudo без пароля разрешён шире, чем pmset disablesleep (проверь /etc/sudoers.d)"
  ok "без пароля только pmset disablesleep, остальное просит пароль"
}

install_bin() {
  step "команда nosleep"
  mkdir -p $BIN_DIR
  ln -sfn $REPO/bin/nosleep $LINK
  ok "$LINK -> $REPO/bin/nosleep"
  [[ ":$PATH:" == *":$BIN_DIR:"* ]] || warn "$BIN_DIR нет в PATH, добавь в ~/.zshrc"
  $LINK status | sed 's/^/    /'
}

# bootout возвращается раньше, чем сервис выгружен: bootstrap сразу после
# него падает с ошибкой 5. Ждём до 5 с.
stop_agent() {
  launchctl bootout gui/$UID/$AGENT_LABEL 2>/dev/null || return 0
  local i
  for i in {1..50}; do
    launchctl print gui/$UID/$AGENT_LABEL >/dev/null 2>&1 || return 0
    sleep 0.1
  done
}

install_app() {
  step "значок в панели меню (NosleepBar.app)"
  whence -p swiftc >/dev/null || fail "нет swiftc: xcode-select --install"

  local tmp=$(mktemp -d -t nosleepbar)
  swiftc -O -swift-version 5 -o $tmp/NosleepBar $REPO/menubar/NosleepBar.swift \
    || { rm -rf $tmp; fail "сборка не прошла" }
  rm -rf $APP
  mkdir -p $APP/Contents/MacOS
  mv $tmp/NosleepBar $APP/Contents/MacOS/
  rm -rf $tmp
  cat > $APP/Contents/Info.plist <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key><string>$AGENT_LABEL</string>
  <key>CFBundleName</key><string>NosleepBar</string>
  <key>CFBundleExecutable</key><string>NosleepBar</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>LSUIElement</key><true/>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
</dict>
</plist>
PLIST
  codesign --force --sign - $APP 2>/dev/null || warn "codesign не прошёл, запустится и так"
  ok "$APP"

  # Автозапуск при входе. KeepAlive только после сбоя: "Закрыть значок" не перезапускает.
  mkdir -p ${AGENT:h}
  cat > $AGENT <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$AGENT_LABEL</string>
  <key>ProgramArguments</key><array><string>$APP/Contents/MacOS/NosleepBar</string></array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><dict><key>SuccessfulExit</key><false/></dict>
  <key>ProcessType</key><string>Interactive</string>
</dict>
</plist>
PLIST
  plutil -lint -s $AGENT || fail "LaunchAgent не прошёл plutil -lint"
  stop_agent
  launchctl bootstrap gui/$UID $AGENT || fail "launchctl bootstrap не прошёл"
  ok "автозапуск: $AGENT"
}

uninstall() {
  step "снять флаг"
  if [[ -x $LINK || -x $REPO/bin/nosleep ]]; then
    $REPO/bin/nosleep off --force | sed 's/^/    /' || warn "не снялся, сниму через sudo"
  fi
  step "удалить"
  rm -f $LINK && ok "$LINK"
  stop_agent
  rm -f $AGENT && ok "$AGENT"
  rm -rf $APP && ok "$APP"
  print "    нужен пароль администратора"
  asudo /usr/bin/pmset -a disablesleep 0
  asudo rm -f $SUDOERS && ok "$SUDOERS"
  rm -rf $HOME/.nosleep && ok "~/.nosleep"
}

case "$1" in
  "")        install_sudoers; install_bin; install_app; step "готово" ;;
  uninstall) uninstall; step "готово" ;;
  *)         print -u2 "usage: ./install.sh [uninstall]"; exit 2 ;;
esac
