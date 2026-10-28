import Combine
import Foundation

// MARK: - 面板状态

enum TranslationPanelState: Equatable {
    case idle
    case loading
    case streaming(String)
    case translated(String)
    case dictionary(DictionaryEntry)
    case plain(String)
    case failed(String)
    case notConfigured
}

enum TranslationSaveState: Equatable {
    case idle
    case saved
    case failed(String)
}

// MARK: - 热键翻译

/// 功能状态、配置和请求生命周期。UI 只订阅这里的 @Published。
/// 面板控制器和设置页通过三个闭包接进来，避免 feature 依赖 AppKit / SwiftUI。
final class TranslationFeature: ObservableObject {

    static let shared = TranslationFeature()

    private let store: TranslationStore
    private let secrets: TranslationSecretStore
    private let client: TranslationClient
    private var activeTask: Task<Void, Never>?
    private var keyLoaded = false
    /// 每次提交/取消都递增；旧请求回来时据此丢弃结果，避免覆盖新状态。
    private var requestID = 0

    /// UI 注入：显示/隐藏面板、从面板跳设置。
    var presentPanel: (() -> Void)?
    var dismissPanel: (() -> Void)?
    var openSettingsHandler: (() -> Void)?

    @Published var enabled: Bool {
        didSet {
            guard !RuntimeFlags.isRenderingPreview else { return }
            store.enabled = enabled
            syncHotkey()
            if !enabled {
                cancel()
                dismissPanel?()
            }
        }
    }

    @Published private(set) var baseURL: String
    @Published private(set) var model: String
    @Published private(set) var apiKey: String = ""

    @Published var longTextTarget: LongTextTarget {
        didSet {
            guard !RuntimeFlags.isRenderingPreview else { return }
            store.longTextTarget = longTextTarget
        }
    }

    @Published var streamOutput: Bool {
        didSet {
            guard !RuntimeFlags.isRenderingPreview else { return }
            store.streamOutput = streamOutput
        }
    }

    /// 输入、模式、结果都是面板的临时状态，不落盘。
    @Published var input: String = ""
    @Published var mode: TranslationMode = .auto
    @Published var state: TranslationPanelState = .idle
    /// 每次呼出面板加一，输入框据此重新抢焦点。
    @Published var focusRequest = 0

    @Published private(set) var models: [String] = []
    @Published private(set) var isFetchingModels = false
    @Published private(set) var submittedText = ""
    @Published private(set) var lastDecision: TranslationDecision?

    /// 设置页的草稿和反馈。放在 feature 上而不是 @State，
    /// 是因为仓库用 swiftc 直接编译，没有 SwiftUI 宏插件。
    @Published var draftBaseURL = ""
    @Published var draftModel = ""
    @Published var draftKey = ""
    @Published var saveState: TranslationSaveState = .idle
    @Published var connectionMessage: String?
    @Published var connectionIsError = false

    init(
        store: TranslationStore = TranslationStore(),
        secrets: TranslationSecretStore = TranslationSecretStore(),
        client: TranslationClient = .shared
    ) {
        self.store = store
        self.secrets = secrets
        self.client = client
        enabled = store.enabled
        baseURL = store.baseURL
        model = store.model
        longTextTarget = store.longTextTarget
        streamOutput = store.streamOutput
        draftBaseURL = store.baseURL
        draftModel = store.model
    }

    // MARK: 配置

    var config: TranslationConfig {
        TranslationConfig(baseURL: baseURL, apiKey: apiKey, model: model)
    }

    var isConfigured: Bool {
        !baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// 只在真正要用 Key 的时候读密钥文件：单测构造 feature 时不应该碰用户数据。
    func loadKeyIfNeeded() {
        guard !keyLoaded, !RuntimeFlags.isRenderingPreview else { return }
        keyLoaded = true
        apiKey = secrets.load()
        draftKey = apiKey
    }

    @discardableResult
    func saveProvider(baseURL rawBase: String, model rawModel: String, apiKey rawKey: String) -> TranslationError? {
        let base = rawBase.trimmingCharacters(in: .whitespacesAndNewlines)
        let model = rawModel.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = rawKey.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !base.isEmpty, TranslationEndpoint.normalizedBase(base) != nil else {
            return .invalidURL
        }
        if TranslationEndpoint.insecureReason(base) != nil {
            return .insecureURL
        }
        guard !model.isEmpty else { return .missingModel }
        guard secrets.save(key) else { return .secretStore }

        let previousBase = self.baseURL
        self.baseURL = base
        self.model = model
        self.apiKey = key
        keyLoaded = true
        draftBaseURL = base
        draftModel = model
        draftKey = key
        store.baseURL = base
        store.model = model
        if base != previousBase { models = [] }

        return nil
    }

    @MainActor
    func fetchModels(baseURL rawBase: String, apiKey rawKey: String) async -> TranslationError? {
        isFetchingModels = true
        defer { isFetchingModels = false }

        let base = rawBase.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = rawKey.trimmingCharacters(in: .whitespacesAndNewlines)

        do {
            let ids = try await client.fetchModels(baseURL: base, apiKey: key)
            models = ids
            return nil
        } catch let error as TranslationError {
            return error
        } catch {
            return .network(error.localizedDescription)
        }
    }

    // MARK: 面板

    func openPanel() {
        loadKeyIfNeeded()
        focusRequest &+= 1
        presentPanel?()
    }

    func openSettings() {
        openSettingsHandler?()
    }

    var directionLabel: String {
        TranslationClassifier.decide(
            input,
            mode: mode,
            longTextTarget: longTextTarget
        )?.label ?? ""
    }

    @MainActor
    func setMode(_ newMode: TranslationMode) {
        mode = newMode
        guard !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            state = .idle
            return
        }
        // 手动切换后如果已有内容，立即按新模式重查一次。
        submit()
    }

    @MainActor
    func submit() {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            state = .idle
            return
        }

        loadKeyIfNeeded()
        guard isConfigured else {
            state = .notConfigured
            return
        }
        guard let decision = TranslationClassifier.decide(
            text,
            mode: mode,
            longTextTarget: longTextTarget
        ) else {
            state = .idle
            return
        }

        cancel()
        requestID &+= 1
        let currentID = requestID
        submittedText = text
        lastDecision = decision
        state = .loading

        let config = self.config
        let shouldStream = streamOutput
        activeTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                if decision.isDictionary {
                    let lookup = try await self.client.lookupDictionary(
                        text: text,
                        decision: decision,
                        config: config
                    )
                    guard !Task.isCancelled, self.requestID == currentID else { return }
                    switch lookup {
                    case .entry(let entry):
                        self.state = .dictionary(entry)
                    case .raw(let raw):
                        self.state = .plain(raw)
                    }
                } else if shouldStream {
                    var result = ""
                    for try await delta in self.client.streamText(
                        text: text,
                        decision: decision,
                        config: config
                    ) {
                        if Task.isCancelled || self.requestID != currentID { break }
                        result += delta
                        self.state = .streaming(result)
                    }
                    guard !Task.isCancelled, self.requestID == currentID else { return }
                    if result.isEmpty { throw TranslationError.badResponse }
                    self.state = .translated(result)
                } else {
                    let result = try await self.client.translateText(
                        text: text,
                        decision: decision,
                        config: config
                    )
                    guard !Task.isCancelled, self.requestID == currentID else { return }
                    if result.isEmpty { throw TranslationError.badResponse }
                    self.state = .translated(result)
                }
            } catch is CancellationError {
                if self.requestID == currentID { self.state = .idle }
            } catch let error as TranslationError {
                guard self.requestID == currentID else { return }
                self.state = error == .cancelled ? .idle : .failed(error.localizedDescription)
            } catch {
                guard self.requestID == currentID else { return }
                self.state = .failed(
                    TranslationError.network(error.localizedDescription).localizedDescription
                )
            }
            if self.requestID == currentID {
                self.activeTask = nil
            }
        }
    }

    func cancel() {
        requestID &+= 1
        activeTask?.cancel()
        activeTask = nil
    }

    @MainActor
    func cancelTranslation() {
        cancel()
        switch state {
        case .loading, .streaming:
            state = .idle
        default:
            break
        }
    }
}
