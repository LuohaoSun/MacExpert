import SwiftUI

/// 主窗口：EZS 同款 SwiftUI Window scene + 原生全高侧栏。
struct MainWindowView: View {
    @ObservedObject private var app = AppState.shared

    var body: some View {
        split
            .ignoresSafeArea(.container, edges: .top)
            .navigationTitle(app.section.title)
            .toolbar { sidebarToolbar }
            .background {
                if RuntimeFlags.suppressWindowActivation {
                    EmptyView()
                } else {
                    WindowActivator().frame(width: 0, height: 0)
                }
            }
            .frame(minWidth: 820, minHeight: 640)
            .onAppear { app.refreshOnActivation() }
    }

    private var split: some View {
        NativeSidebarSplit(
            isSidebarVisible: $app.sidebarVisible,
            sidebar: sidebar,
            detail: detail
        )
    }

    @ToolbarContentBuilder
    private var sidebarToolbar: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            Button {
                app.sidebarVisible.toggle()
            } label: {
                Label(app.sidebarVisible ? "隐藏侧栏" : "显示侧栏", systemImage: "sidebar.left")
            }
            .help(app.sidebarVisible ? "隐藏侧栏" : "显示侧栏")
            .accessibilityLabel(app.sidebarVisible ? "隐藏侧栏" : "显示侧栏")
            .keyboardShortcut("s", modifiers: [.command, .control])
        }
    }

    private var selection: Binding<MainSection?> {
        Binding(
            get: { app.section },
            set: { newValue in
                if let newValue { app.open(newValue) }
            }
        )
    }

    private var sidebar: some View {
        List(selection: selection) {
            ForEach(Feature.allCases) { feature in
                let section = MainSection.feature(feature)
                HStack(spacing: 8) {
                    Label(feature.title, systemImage: feature.icon)
                    if let badge = section.badge {
                        Spacer(minLength: 6)
                        Badge(text: badge, color: .secondary)
                    }
                }
                .tag(section)
            }
            Label("设置", systemImage: "gearshape")
                .tag(MainSection.settings)
        }
        .listStyle(.sidebar)
    }

    private var detail: some View {
        detailContent
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var detailContent: some View {
        switch app.section {
        case .feature(.typeClip):
            TypeClipView()
        case .feature(.keyMapping):
            KeyMappingView()
        case .feature(.smoothScroll):
            SmoothScrollView()
        case .feature(.translate):
            TranslationView()
        case .feature(.monitor):
            MonitorView()
        case .settings:
            SettingsView()
        }
    }
}
