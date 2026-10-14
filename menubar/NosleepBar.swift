// NosleepBar: значок nosleep в панели меню. Вся логика в bin/nosleep,
// приложение только читает `nosleep state` и вызывает on/off/for.
// Сборка: install.sh (swiftc, без Xcode-проекта).

import AppKit

// Язык меню: русский при регионе RU или русском языке системы, иначе английский.
let isRu = Locale.current.region?.identifier == "RU"
    || (Locale.preferredLanguages.first?.hasPrefix("ru") ?? false)
func L(_ ru: String, _ en: String) -> String { isRu ? ru : en }

// Метку таймера пишет bin/nosleep (TIMER_LABEL), всегда по-русски.
let timerLabel = "таймер до "

struct State {
    var flag = false
    var manual = false
    var battery = false
    var timers: [String] = []    // время конца таймера, "15:40"
    var sessions: [String] = []  // команды обычных сессий
    var error: String?

    var holding: Bool { manual || !timers.isEmpty }
    // Флаг включён, но держать его некому: краш, kill -9 или перезагрузка.
    var orphan: Bool { flag && !holding && sessions.isEmpty }
}

final class App: NSObject, NSApplicationDelegate, NSMenuDelegate {
    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    let menu = NSMenu()
    let bin: String
    var state = State()

    override init() {
        let env = ProcessInfo.processInfo.environment
        bin = env["NOSLEEP_BIN"] ?? NSHomeDirectory() + "/.local/bin/nosleep"
        super.init()
    }

    func applicationDidFinishLaunching(_ note: Notification) {
        menu.delegate = self
        item.menu = menu
        refresh()
        Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in self?.refresh() }
        // После сна обновить сразу, не ждать таймера.
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.refresh() }
    }

    // MARK: состояние

    func run(_ args: [String]) -> (out: String, ok: Bool) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: bin)
        p.arguments = args
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = Pipe()
        do { try p.run() } catch { return ("", false) }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return (String(decoding: data, as: UTF8.self), p.terminationStatus == 0)
    }

    func refresh() {
        var s = State()
        let (out, ok) = run(["state"])
        if !ok {
            s.error = L("не найден или упал: ", "not found or failed: ") + bin
        }
        for line in out.split(separator: "\n") {
            guard let eq = line.firstIndex(of: "=") else { continue }
            let key = line[..<eq], val = String(line[line.index(after: eq)...])
            switch key {
            case "flag": s.flag = val == "1"
            case "manual": s.manual = val == "1"
            case "power": s.battery = val == "battery"
            case "session":
                let cmd = val.split(separator: " ", maxSplits: 1).dropFirst().first.map(String.init) ?? ""
                if cmd.hasPrefix(timerLabel) { s.timers.append(String(cmd.dropFirst(timerLabel.count))) } else { s.sessions.append(cmd) }
            default: break
            }
        }
        state = s
        updateIcon()
    }

    func updateIcon() {
        guard let button = item.button else { return }
        let name: String
        if state.error != nil { name = "exclamationmark.triangle" }
        else { name = state.flag ? "cup.and.saucer.fill" : "cup.and.saucer" }
        var image = NSImage(systemSymbolName: name, accessibilityDescription: "nosleep")
        // Панель меню красит шаблонные иконки сама и contentTintColor игнорирует:
        // цветная иконка - только не шаблонная, с цветом в самом символе.
        if warnTint {
            image = image?.withSymbolConfiguration(.init(paletteColors: [.systemOrange]))
            image?.isTemplate = false
        } else {
            image?.isTemplate = true
        }
        button.image = image
    }

    var warnTint: Bool { state.error == nil && state.flag && (state.orphan || state.battery) }

    // MARK: меню

    func menuNeedsUpdate(_ menu: NSMenu) {
        refresh()
        menu.removeAllItems()
        let s = state

        if let error = s.error {
            menu.addItem(info(error, symbol: "exclamationmark.triangle"))
            menu.addItem(.separator())
            menu.addItem(quitItem())
            return
        }

        menu.addItem(info(s.flag ? L("Мак не спит, крышку можно закрывать", "Mac stays awake, you can close the lid")
                                  : L("Мак засыпает как обычно", "Mac sleeps as usual"),
                          symbol: s.flag ? "cup.and.saucer.fill" : "cup.and.saucer"))
        if s.orphan { menu.addItem(info(L("Ничего не запущено: забыли выключить?", "Nothing is running: forgot to turn it off?"), symbol: "exclamationmark.triangle", warn: true)) }
        if s.flag && s.battery { menu.addItem(info(L("Работает от батареи: разрядится и нагреется в сумке", "On battery: will drain and heat up in a bag"), symbol: "battery.25", warn: true)) }

        let holders = s.timers.map { L(timerLabel, "timer until ") + $0 } + s.sessions
        if !holders.isEmpty {
            menu.addItem(.separator())
            menu.addItem(info(L("Не дают спать:", "Keeping awake:"), symbol: nil))
            for h in holders {
                menu.addItem(info(h.count > 50 ? String(h.prefix(49)) + "…" : h, symbol: nil, mono: true))
            }
        }

        menu.addItem(.separator())
        // Кнопки по состоянию: каждая говорит, что станет с маком.
        if !s.flag {
            menu.addItem(action(L("Не давать спать 1 час", "Stay awake for 1 hour"), ["for", "1h"], symbol: "clock"))
            menu.addItem(action(L("Не давать спать 2 часа", "Stay awake for 2 hours"), ["for", "2h"], symbol: "clock"))
            menu.addItem(action(L("Не давать спать, пока не выключу", "Stay awake until I turn it off"), ["on"], symbol: "infinity"))
        } else if s.orphan {
            menu.addItem(action(L("Разрешить маку спать", "Let the Mac sleep"), ["off", "--force"]))
        } else if s.holding && s.sessions.isEmpty {
            menu.addItem(action(L("Разрешить маку спать", "Let the Mac sleep"), ["off"]))
        } else {
            if s.holding {
                menu.addItem(action(L("Разрешить спать, когда закончатся сессии", "Let it sleep when sessions end"), ["off"]))
            } else {
                menu.addItem(action(L("Не давать спать и после сессий", "Stay awake after sessions too"), ["on"]))
            }
            menu.addItem(action(L("Разрешить спать сейчас (не ждать сессий)", "Let it sleep now (don't wait for sessions)"), ["off", "--force"]))
        }

        menu.addItem(.separator())
        menu.addItem(quitItem())
    }

    func info(_ title: String, symbol: String?, warn: Bool = false, mono: Bool = false) -> NSMenuItem {
        let mi = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        mi.isEnabled = false
        if let symbol { mi.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) }
        if warn || mono {
            var attrs: [NSAttributedString.Key: Any] = [:]
            if warn { attrs[.foregroundColor] = NSColor.systemOrange }
            if mono { attrs[.font] = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular) }
            mi.attributedTitle = NSAttributedString(string: title, attributes: attrs)
        }
        return mi
    }

    func action(_ title: String, _ args: [String], symbol: String? = nil) -> NSMenuItem {
        let mi = NSMenuItem(title: title, action: #selector(runAction(_:)), keyEquivalent: "")
        mi.target = self
        mi.representedObject = args
        if let symbol { mi.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) }
        return mi
    }

    func quitItem() -> NSMenuItem {
        NSMenuItem(title: L("Закрыть значок", "Quit nosleep icon"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    }

    @objc func runAction(_ sender: NSMenuItem) {
        guard let args = sender.representedObject as? [String] else { return }
        // `nosleep for` ждёт до 2 с, пока таймер поставит флаг: не в главном потоке.
        DispatchQueue.global().async {
            let (_, ok) = self.run(args)
            DispatchQueue.main.async {
                self.refresh()
                if !ok { self.flashError() }
            }
        }
    }

    func flashError() {
        let alert = NSAlert()
        alert.messageText = L("nosleep: команда не выполнилась", "nosleep: command failed")
        alert.informativeText = L("Проверь в терминале: nosleep status. Возможно, не настроен sudo (./install.sh).",
                                  "Check in Terminal: nosleep status. sudo may not be set up (./install.sh).")
        alert.runModal()
    }
}

// --dump: напечатать иконку и меню и выйти (для проверки без экрана).
if CommandLine.arguments.contains("--dump") {
    let d = App()
    d.refresh()
    let tint = d.warnTint && d.item.button?.image?.isTemplate == false ? " orange" : ""
    print("icon: \(d.state.error != nil ? "exclamationmark.triangle" : d.state.flag ? "cup.and.saucer.fill" : "cup.and.saucer")\(tint)")
    d.menuNeedsUpdate(d.menu)
    for mi in d.menu.items {
        if mi.isSeparatorItem { print("---"); continue }
        let args = (mi.representedObject as? [String]).map { "  -> nosleep " + $0.joined(separator: " ") } ?? ""
        print(mi.title + args)
    }
    exit(0)
}

let app = NSApplication.shared
let delegate = App()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
