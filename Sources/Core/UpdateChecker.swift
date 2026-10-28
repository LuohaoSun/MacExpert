import AppKit
import Foundation

// MARK: - 结果

enum UpdateCheckOutcome {
    case upToDate(current: String, latest: String)
    case available(current: String, latest: String, releaseURL: URL)
    case failed(String)
}

// MARK: - GitHub 响应

private struct GitHubRelease: Decodable {
    let tagName: String
    let htmlURL: String

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlURL = "html_url"
    }
}

// MARK: - 检查更新

/// 只查询 GitHub 的 latest release，不下载、不安装、不写任何配置。
/// 网络请求在后台完成，结果用系统 Alert 展示；用户确认后才打开发布页。
@MainActor
final class UpdateChecker {

    static let shared = UpdateChecker()

    private let repository = "LuohaoSun/MacExpert"
    private let session: URLSession
    private var isChecking = false

    private init(session: URLSession = .shared) {
        self.session = session
    }

    var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "未知"
    }

    private var currentBuild: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? ""
    }

    private var currentLabel: String {
        currentBuild.isEmpty ? currentVersion : "\(currentVersion)（Build \(currentBuild)）"
    }

    /// 菜单栏/设置页的入口：立即返回，检查完成后弹 Alert。
    func checkInteractively() {
        guard !isChecking else { return }
        isChecking = true

        Task { @MainActor in
            let outcome = await check()
            self.isChecking = false
            self.present(outcome)
        }
    }

    func check() async -> UpdateCheckOutcome {
        guard let current = AppVersion(currentVersion) else {
            return .failed("无法读取当前版本号。")
        }
        guard let url = URL(string: "https://api.github.com/repos/\(repository)/releases/latest") else {
            return .failed("更新地址无效。")
        }

        var request = URLRequest(url: url, timeoutInterval: 15)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("MacExpert/\(currentVersion) (macOS)", forHTTPHeaderField: "User-Agent")

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                return .failed("GitHub 没有返回有效的响应。")
            }

            switch http.statusCode {
            case 200..<300:
                break
            case 403:
                return .failed("GitHub 请求被限流，请稍后再试。")
            case 404:
                return .failed("GitHub 上还没有正式发布版本。")
            default:
                return .failed("GitHub 返回 HTTP \(http.statusCode)。")
            }

            let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
            guard let latest = AppVersion(release.tagName) else {
                return .failed("无法解析最新版本号：\(release.tagName)。")
            }

            guard latest > current else {
                return .upToDate(current: currentLabel, latest: release.tagName)
            }

            guard let releaseURL = URL(string: release.htmlURL) else {
                return .failed("发布页地址无效。")
            }
            return .available(
                current: currentLabel,
                latest: release.tagName,
                releaseURL: releaseURL
            )
        } catch let error as URLError {
            return .failed("网络请求失败：\(error.localizedDescription)")
        } catch {
            return .failed("检查更新失败：\(error.localizedDescription)")
        }
    }

    // MARK: 展示

    private func present(_ outcome: UpdateCheckOutcome) {
        let alert = NSAlert()
        alert.icon = NSApp.applicationIconImage

        switch outcome {
        case .upToDate(let current, let latest):
            if let currentVersion = AppVersion(current),
               let latestVersion = AppVersion(latest),
               currentVersion > latestVersion {
                alert.messageText = "当前版本较新"
                alert.informativeText = "当前版本 \(current)，GitHub 最新正式版是 \(latest)。本地版本更新，无需更新。"
            } else {
                alert.messageText = "已是最新版本"
                alert.informativeText = "当前版本 \(current) 已是 GitHub 上最新的正式版。"
            }
            alert.addButton(withTitle: "好")

        case .available(let current, let latest, let releaseURL):
            alert.messageText = "发现新版本 \(latest)"
            alert.informativeText = "当前版本 \(current)，最新版本 \(latest)。\n\n是否打开 GitHub 发布页查看更新说明并下载？"
            alert.addButton(withTitle: "打开发布页")
            alert.addButton(withTitle: "以后再说")
            NSApp.activate(ignoringOtherApps: true)
            if alert.runModal() == .alertFirstButtonReturn {
                NSWorkspace.shared.open(releaseURL)
            }
            return

        case .failed(let message):
            alert.alertStyle = .warning
            alert.messageText = "检查更新失败"
            alert.informativeText = message
            alert.addButton(withTitle: "好")
        }

        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
}
