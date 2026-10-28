// 冒烟测试用的接收端：打开一个纯文本窗口并抢焦点，等待 MacExpert 敲入，
// 到点后把 NSTextView 里的内容写到指定文件。
//
//   swiftc -sdk "$(xcrun --sdk macosx --show-sdk-path)" Tests/TypeTarget.swift -o build/tests/TypeTarget
//   build/tests/TypeTarget /tmp/typed.txt 12
import AppKit

final class TestTargetApp: NSObject, NSApplicationDelegate {
    private let outputPath: String
    private let duration: Double
    private var window: NSWindow!
    private var textView: NSTextView!

    init(outputPath: String, duration: Double) {
        self.outputPath = outputPath
        self.duration = duration
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let frame = NSRect(x: 0, y: 0, width: 680, height: 440)
        window = NSWindow(
            contentRect: frame,
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "MacExpert Type Target"
        window.center()

        let scroll = NSScrollView(frame: frame)
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.borderType = .noBorder

        let contentSize = scroll.contentSize
        let textView = NSTextView(frame: NSRect(origin: .zero, size: contentSize))
        textView.minSize = NSSize(width: 0, height: contentSize.height)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.containerSize = NSSize(
            width: contentSize.width,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.textContainer?.widthTracksTextView = true
        textView.font = NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)
        textView.isRichText = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.allowsUndo = false
        self.textView = textView

        scroll.documentView = textView
        window.contentView = scroll
        window.makeFirstResponder(textView)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        print("target ready, will write to \(outputPath) in \(duration)s")
        fflush(stdout)

        DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak self] in
            guard let self else { return }
            let text = self.textView.string
            try? text.write(toFile: self.outputPath, atomically: true, encoding: .utf8)
            print("target captured \(text.count) chars")
            fflush(stdout)
            NSApp.terminate(nil)
        }
    }
}

let arguments = CommandLine.arguments
let outputPath = arguments.count > 1 ? arguments[1] : "/tmp/macexpert-type-target.txt"
let duration = arguments.count > 2 ? (Double(arguments[2]) ?? 12) : 12

let application = NSApplication.shared
application.setActivationPolicy(.regular)
let delegate = TestTargetApp(outputPath: outputPath, duration: duration)
application.delegate = delegate
application.run()
