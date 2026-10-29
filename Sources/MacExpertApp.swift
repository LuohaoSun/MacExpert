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
            MenuBarMenu()
        } label: {
            MenuBarLabel()
        }
        .menuBarExtraStyle(.menu)

        Window("MacExpert", id: "main") {
            MainWindowView()
        }
        .defaultSize(width: 880, height: 720)
        .windowResizability(.contentMinSize)
        .defaultLaunchBehavior(.suppressed)
        .restorationBehavior(.disabled)
    }
}

/// 菜单栏图标：空闲时是 ⌘，敲入中换成键盘活动图标。
struct MenuBarLabel: View {
    @ObservedObject private var clip = TypeClipFeature.shared
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Image(systemName: clip.isActive ? "keyboard.badge.ellipsis" : "command")
            .accessibilityLabel(clip.isActive ? "MacExpert，正在敲入" : "MacExpert")
            .help(clip.isActive ? "MacExpert：正在敲入" : "MacExpert")
            .onAppear { MainWindowController.shared.register(openWindow) }
    }
}

// MARK: - App 生命周期

final class AppDelegate: NSObject, NSApplicationDelegate {

    private var installedMenu: NSMenu?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 菜单栏应用默认没有 App 菜单；先装好，主窗口打开时就能直接用。
        MainActor.assumeIsolated {
            MainMenu.install(target: self)
            installedMenu = NSApp.mainMenu
        }

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

        // 各功能模块自己安装热键、订阅等资源。
        FeatureRegistry.installAll()
        MainActor.assumeIsolated {
            TranslationPanelController.install()
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

    func applicationDidBecomeActive(_ notification: Notification) {
        // SwiftUI 的 MenuBarExtra 场景可能在激活时重设主菜单；发现被换掉就装回来。
        MainActor.assumeIsolated {
            if let installedMenu, NSApp.mainMenu === installedMenu { return }
            MainMenu.install(target: self)
            self.installedMenu = NSApp.mainMenu
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationWillTerminate(_ notification: Notification) {
        FeatureRegistry.prepareForTermination()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        MainActor.assumeIsolated {
            MainWindowController.shared.show()
        }
        return true
    }

    @objc func openSettings(_ sender: Any?) {
        MainActor.assumeIsolated {
            AppState.shared.openSettings()
            MainWindowController.shared.show()
        }
    }

    @objc func showMainWindow(_ sender: Any?) {
        MainActor.assumeIsolated {
            MainWindowController.shared.show()
        }
    }

    @objc func checkForUpdates(_ sender: Any?) {
        MainActor.assumeIsolated {
            UpdateChecker.shared.checkInteractively()
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

        if args.contains("--open-window") {
            MainActor.assumeIsolated {
                MainWindowController.shared.show()
            }
            return true
        }

        if args.contains("--open-window-inactive") {
            RuntimeFlags.suppressWindowActivation = true
            MainActor.assumeIsolated {
                MainWindowController.shared.show(activate: false)
            }
            return true
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

        if args.contains("--show-monitor-popover") || args.contains("--show-monitor-popover-network") {
            let kind: MonitorStatusKind =
                args.contains("--show-monitor-popover-network") ? .network : .processor
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                MainActor.assumeIsolated {
                    if !MonitorFeature.shared.enabled {
                        MonitorFeature.shared.enabled = true
                    }
                    MonitorFeature.shared.showPopoverForTesting(kind: kind)
                }
            }
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
