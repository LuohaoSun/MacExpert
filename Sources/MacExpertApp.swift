import AppKit
import ApplicationServices
import Carbon
import Carbon.HIToolbox
import SwiftUI

// MARK: - 应用入口

@main
struct MacExpertApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        MenuBarExtra {
            RootPanel()
        } label: {
            MenuBarLabel()
        }
        .menuBarExtraStyle(.window)
    }
}

/// 菜单栏图标：空闲时是 ⌘，敲入中换成键盘活动图标。
struct MenuBarLabel: View {
    @ObservedObject private var clip = TypeClipFeature.shared

    var body: some View {
        Image(systemName: clip.isActive ? "keyboard.badge.ellipsis" : "command")
    }
}

// MARK: - App 生命周期

final class AppDelegate: NSObject, NSApplicationDelegate {

    func applicationDidFinishLaunching(_ notification: Notification) {
        #if MACEXPERT_DEV_HOOKS
        if handleDevHook(ProcessInfo.processInfo.arguments) { return }
        #endif

        // 已在运行则不再起第二份。
        let others = NSRunningApplication
            .runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "")
            .filter { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
        if !others.isEmpty {
            NSApp.terminate(nil)
            return
        }

        HotkeyCenter.shared.register(
            keyCode: UInt32(kVK_ANSI_V),
            carbonModifiers: UInt32(cmdKey | controlKey),
            id: 1
        ) {
            TypeClipFeature.shared.handleHotkey(enter: false)
        }

        HotkeyCenter.shared.register(
            keyCode: UInt32(kVK_Return),
            carbonModifiers: UInt32(cmdKey | controlKey),
            id: 2
        ) {
            TypeClipFeature.shared.handleHotkey(enter: true)
        }

        #if MACEXPERT_DEV_HOOKS
        // 分布式通知驱动入口（自动化测试用，等价于按热键）。
        // 没有来源校验，任何本机进程都能借这个实例的 TCC 授权敲键盘，
        // 所以整块只在带 -D MACEXPERT_DEV_HOOKS 的构建里存在。
        DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("com.slh.macexpert.drive"),
            object: nil,
            queue: .main
        ) { note in
            let enter = (note.userInfo?["enter"] as? String) == "1"
            TypeClipFeature.shared.handleHotkey(enter: enter)
        }
        #endif

        if !AXIsProcessTrusted() {
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(options)
        }
    }

    #if MACEXPERT_DEV_HOOKS
    /// 处理开发/诊断钩子。返回 true = 已处理，不要继续走正常 GUI 启动。
    private func handleDevHook(_ args: [String]) -> Bool {
        if args.contains("--selfcheck") {
            print("trusted:\(AXIsProcessTrusted())")
            print("keymap:\(Keymap.build().count)")
            print("clean:\(TyperEngine.clean("a\r\nb\tc").debugDescription)")
            fflush(stdout)
            exit(0)
        }

        if let index = args.firstIndex(of: "--preview"), args.indices.contains(index + 1) {
            // applicationDidFinishLaunching 本来就在主线程，这里只是把这一事实告诉编译器。
            MainActor.assumeIsolated {
                PreviewRenderer.renderAll(to: args[index + 1])
            }
            exit(0)
        }

        if args.contains("--notify-drive") || args.contains("--notify-drive-enter") {
            DistributedNotificationCenter.default().postNotificationName(
                Notification.Name("com.slh.macexpert.drive"),
                object: nil,
                userInfo: ["enter": args.contains("--notify-drive-enter") ? "1" : "0"],
                deliverImmediately: true
            )
            exit(0)
        }

        if args.contains("--drive-once") || args.contains("--drive-once-enter") {
            driveOnce(enter: args.contains("--drive-once-enter"))
            return true
        }

        return false
    }

    /// 自动化测试入口：直接驱动一次引擎后退出（不抢焦点，不注册热键）。
    private func driveOnce(enter: Bool) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            guard AXIsProcessTrusted() else {
                print("drive-once: not-trusted")
                exit(3)
            }
            guard let raw = NSPasteboard.general.string(forType: .string) else {
                print("drive-once: clipboard-not-text")
                exit(2)
            }
            let text = TyperEngine.clean(raw)
            guard !text.isEmpty else {
                print("drive-once: clipboard-empty")
                exit(2)
            }
            let duration = TypeClipFeature.shared.engine.start(
                text: text,
                pressEnter: enter,
                cfg: TypeClipFeature.shared.engineConfig
            )
            print("drive-once: started \(text.count) chars, ~\(Int(duration))s")
            DispatchQueue.main.asyncAfter(deadline: .now() + duration + 1.0) {
                exit(0)
            }
        }
    }
    #endif
}
