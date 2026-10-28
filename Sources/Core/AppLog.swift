import AppKit
import Foundation

/// 应用日志的落盘位置与权限。
///
/// 日志可能包含被敲入的字符（仅在打开诊断日志时），属于用户剪贴板内容的衍生数据。
/// 因此放在 `~/Library/Logs` 下并强制 0600：只有当前用户能读，位置也符合 macOS 惯例。
enum AppLog {

    private static let logsDirectory = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs", isDirectory: true)

    /// 主日志: ~/Library/Logs/MacExpert.log
    static let path = logsDirectory.appendingPathComponent("MacExpert.log").path

    /// 旧 TypeClip 的日志位置，仅用于提示迁移。
    static let legacyPath = logsDirectory.appendingPathComponent("TypeClip.log").path

    /// 覆盖写，并强制 0600。
    @discardableResult
    static func write(_ body: String) -> Bool {
        guard let data = body.data(using: .utf8) else { return false }
        let url = URL(fileURLWithPath: path)
        do {
            try FileManager.default.createDirectory(at: logsDirectory, withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
            // atomic 写入会按 umask 生成一个新文件（通常 0644），所以写完再收紧。
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path)
            return true
        } catch {
            return false
        }
    }

    /// 在 Finder 中选中日志文件；文件还不存在时打开日志目录。
    static func revealFile() {
        let url = URL(fileURLWithPath: path)
        if FileManager.default.fileExists(atPath: path) {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } else {
            revealFolder()
        }
    }

    static func revealFolder() {
        try? FileManager.default.createDirectory(at: logsDirectory, withIntermediateDirectories: true)
        NSWorkspace.shared.open(logsDirectory)
    }
}
