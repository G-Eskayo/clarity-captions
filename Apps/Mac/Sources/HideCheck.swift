import AppKit
import CoreGraphics

/// ⌘H must hide the always-on-top pop-up (#172, owner 2026-10-28). Launched with `-MarvinHideCheck`, the app finds the
/// app menu's ⌘H item, fires it the way the key does, checks with the window server that no Seal Speak window is left
/// on screen, brings the app back (as the Dock does) and checks the window returned. Prints the result, exits 0 or 1.
enum HideCheck {
    static func runIfRequested() {
        guard UserDefaults.standard.bool(forKey: "MarvinHideCheck") else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) { run() }
    }

    private static func log(_ line: String) { FileHandle.standardOutput.write((line + "\n").data(using: .utf8)!) }

    /// Seal Speak's own windows the window server is drawing right now (menu bar extras excluded).
    private static func onScreen() -> Int {
        let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
        return list.filter {
            ($0[kCGWindowOwnerPID as String] as? Int32) == getpid() && ($0[kCGWindowLayer as String] as? Int ?? 99) < 20
        }.count
    }

    private static func run() {
        let items = NSApp.mainMenu?.items.first?.submenu?.items ?? []
        guard let menu = NSApp.mainMenu?.items.first?.submenu,
              let index = items.firstIndex(where: { $0.keyEquivalent == "h" && $0.keyEquivalentModifierMask == .command }) else {
            log("FAILED: no ⌘H item in the app menu: \(items.map(\.title))"); exit(1)
        }
        let before = onScreen()
        log("app menu ⌘H item: \"\(items[index].title)\"; windows on screen before: \(before)")
        menu.performActionForItem(at: index)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            let hidden = onScreen()
            log("after ⌘H: app hidden \(NSApp.isHidden), windows on screen \(hidden)")
            NSApp.unhide(nil)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                let back = onScreen()
                log("after coming back: windows on screen \(back)")
                exit(before > 0 && hidden == 0 && back == before ? 0 : 1)
            }
        }
    }
}
