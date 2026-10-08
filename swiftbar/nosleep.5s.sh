#!/bin/zsh -f
# <swiftbar.title>nosleep</swiftbar.title>
# <swiftbar.desc>Мак не спит при закрытой крышке, пока идут сессии nosleep</swiftbar.desc>
# <swiftbar.hideAbout>true</swiftbar.hideAbout>
# <swiftbar.hideRunInTerminal>true</swiftbar.hideRunInTerminal>
# <swiftbar.hideLastUpdated>true</swiftbar.hideLastUpdated>
# <swiftbar.hideDisablePlugin>true</swiftbar.hideDisablePlugin>
#
# Плагин SwiftBar: иконка ON/OFF, сессии, вкл/выкл. Вся логика в bin/nosleep,
# плагин только читает `nosleep state`. В папке SwiftBar лежит симлинк, `:A`
# разворачивает его до репо.

NOSLEEP=${NOSLEEP_BIN:-${0:A:h:h}/bin/nosleep}

if [[ ! -x $NOSLEEP ]]; then
  print "| sfimage=exclamationmark.triangle"
  print -- "---"
  print -r -- "не найден $NOSLEEP"
  exit 0
fi

typeset -A st
sessions=()
while IFS= read -r line; do
  case $line in
    session=*) sessions+=${line#session=} ;;
    *=*)       st[${line%%=*}]=${line#*=} ;;
  esac
done < <($NOSLEEP state)

# Таймеры (`nosleep for`) - тоже сессии, но для меню это "держу вручную".
timers=() real=()
for s in $sessions; do
  [[ ${s#* } == "таймер до "* ]] && timers+=$s || real+=$s
done

on=$(( ${st[flag]:-0} == 1 ))
battery=$([[ ${st[power]} == battery ]] && print 1 || print 0)
# Флаг включён, но держать его некому: краш, kill -9 или перезагрузка.
orphan=$(( on && ${st[sessions]:-0} == 0 && ${st[manual]:-0} == 0 ))

# Пункт меню: текст без "|", иначе SwiftBar примет его за параметры.
item() { print -r -- "${1//|/¦} | $2" }
action() { item "$1" "bash=$NOSLEEP $2 terminal=false refresh=true" }

if (( on )); then
  if (( orphan || battery )); then
    print "| sfimage=cup.and.saucer.fill sfcolor=orange"
  else
    print "| sfimage=cup.and.saucer.fill"
  fi
else
  print "| sfimage=cup.and.saucer"
fi

print -- "---"
if (( on )); then
  item "Мак не спит, крышку можно закрывать" "sfimage=cup.and.saucer.fill"
else
  item "Мак засыпает как обычно" "sfimage=cup.and.saucer"
fi
(( orphan ))         && item "Ничего не запущено: забыли выключить?" "color=orange sfimage=exclamationmark.triangle"
(( on && battery ))  && item "На батарее: разряд и нагрев в сумке" "color=orange sfimage=battery.25"

if (( $#sessions )); then
  print -- "---"
  item "Не дают спать:" "size=12"
  for s in $sessions; do
    cmd=${s#* }
    (( $#cmd > 50 )) && cmd="${cmd[1,49]}…"
    item "$cmd" "font=Menlo size=12"
  done
fi

print -- "---"
# Кнопки по состоянию: каждая говорит, что станет с маком.
manual=$(( ${st[manual]:-0} || $#timers ))
if (( ! on )); then
  action "Не давать спать 1 час" "param0=for param1=1h sfimage=clock"
  action "Не давать спать 2 часа" "param0=for param1=2h sfimage=clock"
  action "Не давать спать, пока не выключу" "param0=on sfimage=infinity"
elif (( orphan )); then
  action "Разрешить маку спать" "param0=off param1=--force"
elif (( manual && ! $#real )); then
  action "Разрешить маку спать" "param0=off"
else
  if (( manual )); then
    action "Разрешить спать, когда закончатся сессии" "param0=off"
  else
    action "Не давать спать и после сессий" "param0=on"
  fi
  action "Разрешить спать сейчас (не ждать сессий)" "param0=off param1=--force"
fi
exit 0
