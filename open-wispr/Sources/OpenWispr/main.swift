import AppKit
import Foundation
import OpenWisprLib

setvbuf(stdout, nil, _IOLBF, 0)
setvbuf(stderr, nil, _IOLBF, 0)

let version = OpenWispr.version

func printUsage() {
    print("""
    open-wispr v\(version) — Push-to-talk voice dictation for macOS

    USAGE:
        open-wispr start              Start the dictation daemon
        open-wispr set-hotkey <key>   Set the push-to-talk hotkey
        open-wispr get-hotkey         Show current hotkey
        open-wispr set-model <size>   Set the Whisper model
        open-wispr set-language <code>  Set the language (e.g. en, fr, auto)
        open-wispr download-model [size]  Download a Whisper model
        open-wispr status             Show configuration and status
        open-wispr --help             Show this help message

    HOTKEY EXAMPLES:
        open-wispr set-hotkey globe             Globe/fn key (default)
        open-wispr set-hotkey rightoption        Right Option key
        open-wispr set-hotkey f5                 F5 key
        open-wispr set-hotkey ctrl+space         Ctrl + Space

    AVAILABLE MODELS:
        \(Config.supportedModels.joined(separator: ", "))
    """)
}

/// Notification a second launch sends so the ALREADY-RUNNING copy surfaces its window.
let showWindowNotification = Notification.Name("com.salespilot.app.showWindow")

func cmdStart() {
    // Single instance. Two copies means two menu-bar items, two coaching engines, and — worst — a
    // STALE binary silently owning the menu bar after an update, so shipped fixes appear not to work.
    // launchd runs the bundle executable directly, which LaunchServices doesn't treat as "the app",
    // so `open -a SalesPilot` was starting a second copy. If one is already up, tell it to show its
    // window, then quit.
    let bid = Bundle.main.bundleIdentifier ?? "com.salespilot.app"
    let mePid = ProcessInfo.processInfo.processIdentifier
    let others = NSRunningApplication.runningApplications(withBundleIdentifier: bid)
        .filter { $0.processIdentifier != mePid && !$0.isTerminated }
    if let existing = others.first {
        DistributedNotificationCenter.default().postNotificationName(
            showWindowNotification, object: nil, userInfo: nil, deliverImmediately: true)
        existing.activate(options: [.activateIgnoringOtherApps])
        exit(0)
    }

    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)

    let delegate = AppDelegate()
    app.delegate = delegate

    signal(SIGINT) { _ in
        print("\nStopping open-wispr...")
        exit(0)
    }

    app.run()
}

func cmdSetHotkey(_ keyString: String) {
    guard let parsed = KeyCodes.parse(keyString) else {
        print("Error: Unknown key '\(keyString)'")
        print("Run 'open-wispr --help' for examples")
        exit(1)
    }

    var config = Config.load()
    config.hotkey = HotkeyConfig(keyCode: parsed.keyCode, modifiers: parsed.modifiers)

    do {
        try config.save()
        let desc = KeyCodes.describe(keyCode: parsed.keyCode, modifiers: parsed.modifiers)
        print("Hotkey set to: \(desc)")
    } catch {
        print("Error saving config: \(error.localizedDescription)")
        exit(1)
    }
}

func cmdSetModel(_ size: String) {
    guard Config.supportedModels.contains(size) else {
        print("Error: Unknown model '\(size)'")
        print("Available: \(Config.supportedModels.joined(separator: ", "))")
        exit(1)
    }

    var config = Config.load()
    config.modelSize = size

    do {
        try config.save()
        print("Model set to: \(size)")
        if !Transcriber.modelExists(modelSize: size) {
            print("Model will be downloaded on next start.")
        }
    } catch {
        print("Error saving config: \(error.localizedDescription)")
        exit(1)
    }
}

func cmdSetLanguage(_ lang: String) {
    let validCodes = Config.supportedLanguages.map { $0.code }
    guard validCodes.contains(lang) else {
        print("Error: Unknown language '\(lang)'")
        print("Available: auto, en, fr, de, es, zh, ja, ko, pt, it, nl, ru, ...")
        print("See full list: https://github.com/human37/open-wispr")
        exit(1)
    }

    var config = Config.load()
    config.language = lang

    do {
        try config.save()
        let name = Config.supportedLanguages.first(where: { $0.code == lang })?.name ?? lang
        print("Language set to: \(name) (\(lang))")
    } catch {
        print("Error saving config: \(error.localizedDescription)")
        exit(1)
    }
}

func cmdGetHotkey() {
    let config = Config.load()
    let desc = config.hotkeySummary()
    print("Current hotkey: \(desc)")
}

func cmdDownloadModel(_ size: String) {
    do {
        try ModelDownloader.download(modelSize: size)
    } catch {
        print("Error: \(error.localizedDescription)")
        exit(1)
    }
}

func cmdStatus() {
    let config = Config.load()
    let hotkeyDesc = config.hotkeySummary()

    print("open-wispr v\(version)")
    print("Config:      \(Config.configFile.path)")
    print("Hotkey:      \(hotkeyDesc)")
    print("Model:       \(config.modelSize)")
    print("Model ready: \(Transcriber.modelExists(modelSize: config.modelSize) ? "yes" : "no")")
    print("whisper-cpp: \(Transcriber.findWhisperBinary() != nil ? "yes" : "no")")
    let langName = Config.supportedLanguages.first(where: { $0.code == config.language })?.name ?? config.language
    print("Language:    \(langName) (\(config.language))")
    let toggleMode = config.toggleMode?.value ?? false
    print("Toggle:      \(toggleMode ? "on (press to start/stop)" : "off (hold to talk)")")
}

let args = CommandLine.arguments
let rawCommand = args.count > 1 ? args[1] : nil
let command: String? = {
    if let r = rawCommand, r.hasPrefix("-psn_") { return "start" }
    // Launched from the .app bundle (Finder/LaunchServices pass no args) → start the menu-bar app.
    if rawCommand == nil, AppBundleLaunch.isExecutableInsideAppBundle(args[0]) { return "start" }
    return rawCommand
}()

switch command {
case "provider-credentials":
    ProviderCredentials.writeToPrivatePipe()
case "start":
    if AppBundleLaunch.relaunchThroughAppBundleIfNeeded() {
        exit(0)
    }
    cmdStart()
case "set-hotkey":
    guard args.count > 2 else {
        print("Usage: open-wispr set-hotkey <key>")
        exit(1)
    }
    cmdSetHotkey(args[2])
case "set-model":
    guard args.count > 2 else {
        print("Usage: open-wispr set-model <size>")
        exit(1)
    }
    cmdSetModel(args[2])
case "set-language":
    guard args.count > 2 else {
        print("Usage: open-wispr set-language <code>")
        print("Examples: en, fr, auto")
        exit(1)
    }
    cmdSetLanguage(args[2])
case "get-hotkey":
    cmdGetHotkey()
case "download-model":
    let size = args.count > 2 ? args[2] : "base.en"
    cmdDownloadModel(size)
case "status":
    cmdStatus()
case "verify-audio-offline":
    guard args.count > 2 else { exit(1) }
    do { try WorkspacePreview.verifyAudio(path: args[2]) }
    catch { print("Audio verification failed: \(error)"); exit(1) }
case "verify-ui-offline":
    do { try WorkspacePreview.verifyOffline() }
    catch { print("UI verification failed: \(error)"); exit(1) }
case "preview":
    guard args.count > 2 else { exit(1) }
    do { try WorkspacePreview.render(path: args[2], compact: args.contains("--compact"), prep: args.contains("--prep"), notes: args.contains("--notes"), section: args.contains("--competition") ? "competition" : args.contains("--opportunities") ? "opportunities" : args.contains("--answers") ? "answers" : nil, knowledge: args.contains("--knowledge"), consent: args.contains("--consent"), privacy: args.contains("--privacy"), example: args.contains("--example")) }
    catch { print("Preview failed: \(error)"); exit(1) }
case "miccheck":
    let secs = args.count > 2 ? (Double(args[2]) ?? 20) : 20
    ReplayRunner.micCheck(seconds: secs)
case "replay":
    guard args.count > 2 else {
        print("Usage: SalesPilot replay <customer.wav> [--coach] [--you <mic.wav>]")
        exit(1)
    }
    var youArg: String? = nil
    if let i = args.firstIndex(of: "--you"), i + 1 < args.count { youArg = args[i + 1] }
    ReplayRunner.run(wavPath: args[2], coach: args.contains("--coach"), youPath: youArg)
case "dictate":
    guard args.count > 2 else {
        print("Usage: SalesPilot dictate <audio.wav> [repeats]   # exercise the dictation transcribe path")
        exit(1)
    }
    DictationCheck.run(wavPath: args[2], repeats: args.count > 3 ? (Int(args[3]) ?? 3) : 3)
case "--help", "-h", "help":
    printUsage()
case nil:
    printUsage()
default:
    print("Unknown command: \(command!)")
    printUsage()
    exit(1)
}
