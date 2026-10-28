import Foundation

// MARK: - 请求配置

struct TranslationConfig: Equatable {
    var baseURL: String
    var apiKey: String
    var model: String

    var isConfigured: Bool {
        !baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

// MARK: - 普通配置

/// Base URL / Model / 开关 / 目标语言落 UserDefaults；API Key 不走这里。
final class TranslationStore {

    enum Key {
        static let enabled = "translation.enabled"
        static let baseURL = "translation.baseURL"
        static let model = "translation.model"
        static let longTextTarget = "translation.longTextTarget"
        static let streamOutput = "translation.streamOutput"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var enabled: Bool {
        get { defaults.object(forKey: Key.enabled) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.enabled) }
    }

    var baseURL: String {
        get { defaults.string(forKey: Key.baseURL) ?? "https://api.openai.com/v1" }
        set { defaults.set(newValue, forKey: Key.baseURL) }
    }

    var model: String {
        get { defaults.string(forKey: Key.model) ?? "gpt-4o-mini" }
        set { defaults.set(newValue, forKey: Key.model) }
    }

    var longTextTarget: LongTextTarget {
        get {
            guard let raw = defaults.string(forKey: Key.longTextTarget),
                  let value = LongTextTarget(rawValue: raw) else {
                return .auto
            }
            return value
        }
        set { defaults.set(newValue.rawValue, forKey: Key.longTextTarget) }
    }

    var streamOutput: Bool {
        get { defaults.object(forKey: Key.streamOutput) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.streamOutput) }
    }
}

// MARK: - 密钥文件

/// API Key 存本机文件，而不是系统钥匙串。
/// 自签应用每次重编都会改变 cdhash，钥匙串 ACL 的 partition list 会失效，
/// 每次读取都弹登录密码框；文件用 0600 权限，重编不影响。
/// 这里刻意不写任何日志：Key 和用户输入都不该出现在日志里。
struct TranslationSecretStore {

    static let defaultFileURL: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support", isDirectory: true)
        return base
            .appendingPathComponent("MacExpert", isDirectory: true)
            .appendingPathComponent("translation.key", isDirectory: false)
    }()

    let fileURL: URL

    init(fileURL: URL = TranslationSecretStore.defaultFileURL) {
        self.fileURL = fileURL
    }

    func load() -> String {
        guard let data = try? Data(contentsOf: fileURL),
              let key = String(data: data, encoding: .utf8) else {
            return ""
        }
        return key.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    @discardableResult
    func save(_ key: String) -> Bool {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            delete()
            return true
        }
        guard let data = trimmed.data(using: .utf8) else { return false }

        let directory = fileURL.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o700],
                ofItemAtPath: directory.path
            )
            try data.write(to: fileURL, options: [.atomic])
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: fileURL.path
            )
            return true
        } catch {
            return false
        }
    }

    func delete() {
        try? FileManager.default.removeItem(at: fileURL)
    }
}
