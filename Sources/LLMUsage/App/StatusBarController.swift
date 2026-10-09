import AppKit
import Combine
import SwiftUI
import UsageCore

@MainActor
final class StatusBarController: NSObject, NSApplicationDelegate {
    private let model = AppModel()
    private let popover = NSPopover()
    private var statusItem: NSStatusItem?
    private var contentController: PopoverContentController<UsagePanel>?
    private var subscriptions = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        configureStatusItem()
        bindStatusSummary()

        if let screenshotURL = screenshotURL() {
            do {
                try PreviewCapture.writePanelPNG(to: screenshotURL)
            } catch {
                print(error.localizedDescription)
            }
            NSApplication.shared.terminate(nil)
        } else {
            model.startRefreshLoop()
            if CommandLine.arguments.contains("--preview-popover") {
                DispatchQueue.main.async { [weak self] in
                    self?.togglePopover(nil)
                }
            }
        }
    }

    @objc private func togglePopover(_ sender: Any?) {
        guard let button = statusItem?.button else { return }
        popover.animates = !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        if popover.isShown {
            popover.performClose(sender)
            return
        }

        let controller = PopoverContentController(
            rootView: UsagePanel(model: model),
            maximumHeight: availablePanelHeight(for: button),
            onPreferredContentSizeChanged: { [weak self] size in
                self?.popover.contentSize = size
            },
            onCancel: { [weak self] in
                self?.popover.performClose(nil)
            }
        )
        contentController = controller
        popover.contentViewController = controller
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    }

    private func configureStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        guard let button = item.button else { return }

        button.target = self
        button.action = #selector(togglePopover(_:))
        button.font = .monospacedDigitSystemFont(ofSize: 13, weight: .regular)
        button.sendAction(on: [.leftMouseUp])
        statusItem = item

        popover.behavior = .transient
        popover.animates = !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        updateStatusSummary()
    }

    private func bindStatusSummary() {
        Publishers.CombineLatest3(model.$quotas, model.$isRefreshingQuota, model.$isScanningLogs)
            .receive(on: RunLoop.main)
            .sink { [weak self] _, _, _ in
                self?.updateStatusSummary()
            }
            .store(in: &subscriptions)

        model.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                DispatchQueue.main.async {
                    self?.contentController?.refreshContentSize()
                }
            }
            .store(in: &subscriptions)
    }

    private func updateStatusSummary() {
        let summary = model.menuSummary(.codex) + " · " + model.menuSummary(.claude)
        statusItem?.button?.title = summary
        statusItem?.button?.toolTip = "LLM Usage\n\(summary)"
        statusItem?.button?.setAccessibilityLabel("LLM Usage, \(summary)")
    }

    private func availablePanelHeight(for button: NSStatusBarButton) -> CGFloat {
        let visibleHeight = button.window?.screen?.visibleFrame.height
            ?? NSScreen.main?.visibleFrame.height
            ?? 800
        return max(240, visibleHeight - 64)
    }

    private func screenshotURL() -> URL? {
        let arguments = CommandLine.arguments
        guard let index = arguments.firstIndex(of: "--screenshot"), arguments.indices.contains(index + 1) else {
            return nil
        }
        return URL(fileURLWithPath: arguments[index + 1])
    }
}

@MainActor
private final class PopoverContentController<Content: View>: NSViewController {
    private let hostingController: NSHostingController<Content>
    private let maximumHeight: CGFloat
    private let onPreferredContentSizeChanged: (NSSize) -> Void
    private let onCancel: () -> Void
    private var scrollView: NSScrollView?

    init(
        rootView: Content,
        maximumHeight: CGFloat,
        onPreferredContentSizeChanged: @escaping (NSSize) -> Void,
        onCancel: @escaping () -> Void
    ) {
        hostingController = NSHostingController(rootView: rootView)
        self.maximumHeight = maximumHeight
        self.onPreferredContentSizeChanged = onPreferredContentSizeChanged
        self.onCancel = onCancel
        super.init(nibName: nil, bundle: nil)
        addChild(hostingController)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        let contentView = hostingController.view
        contentView.frame = NSRect(x: 0, y: 0, width: 380, height: 1)
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.autohidesScrollers = true
        scrollView.verticalScrollElasticity = .automatic
        scrollView.documentView = contentView
        self.scrollView = scrollView

        view = scrollView
        refreshContentSize()
    }

    override func cancelOperation(_ sender: Any?) {
        onCancel()
    }

    func refreshContentSize() {
        guard let scrollView else { return }
        let contentView = hostingController.view
        contentView.frame.size.width = 380
        contentView.layoutSubtreeIfNeeded()

        let naturalHeight = ceil(max(contentView.fittingSize.height, 1))
        let viewportHeight = min(naturalHeight, maximumHeight)
        contentView.frame.size = NSSize(width: 380, height: naturalHeight)
        scrollView.frame.size = NSSize(width: 380, height: viewportHeight)
        scrollView.hasVerticalScroller = naturalHeight > viewportHeight

        let size = NSSize(width: 380, height: viewportHeight)
        guard preferredContentSize != size else { return }
        preferredContentSize = size
        onPreferredContentSizeChanged(size)
    }
}
