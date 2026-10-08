#!/bin/zsh -f
# Установка nosleep. Повторный запуск безопасен.
#   ./install.sh             поставить
#   ./install.sh uninstall   убрать всё и вернуть обычный сон

emulate zsh
setopt err_return
path+=(/usr/bin /bin /usr/sbin /sbin)

REPO=${0:A:h}
SUDOERS=/etc/sudoers.d/nosleep
BIN_DIR=$HOME/.local/bin
LINK=$BIN_DIR/nosleep

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

uninstall() {
  step "снять флаг"
  if [[ -x $LINK || -x $REPO/bin/nosleep ]]; then
    $REPO/bin/nosleep off --force | sed 's/^/    /' || warn "не снялся, сниму через sudo"
  fi
  step "удалить"
  rm -f $LINK && ok "$LINK"
  print "    нужен пароль администратора"
  asudo /usr/bin/pmset -a disablesleep 0
  asudo rm -f $SUDOERS && ok "$SUDOERS"
  rm -rf $HOME/.nosleep && ok "~/.nosleep"
}

case "$1" in
  "")        install_sudoers; install_bin; step "готово" ;;
  uninstall) uninstall; step "готово" ;;
  *)         print -u2 "usage: ./install.sh [uninstall]"; exit 2 ;;
esac
