import AppKit
import Combine
import SwiftUI

private final class StatusItemContentView: NSView {
    var items: [MenuBarSummaryItem] = [] {
        didSet {
            invalidateIntrinsicContentSize()
            needsDisplay = true
        }
    }

    private let font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
    private let iconSize = NSSize(width: 16, height: 16)
    private let horizontalPadding: CGFloat = 0
    private let itemSpacing: CGFloat = 10
    private let iconTextSpacing: CGFloat = 6

    override var allowsVibrancy: Bool {
        true
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    override var intrinsicContentSize: NSSize {
        let width = measuredContentWidth()
        return NSSize(width: width, height: NSStatusBar.system.thickness)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let appearance = effectiveAppearance
        appearance.performAsCurrentDrawingAppearance {
            let color = NSColor.labelColor
            let attributes: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: color,
            ]

            var x = horizontalPadding

            for (index, item) in items.enumerated() {
                if index > 0 {
                    x += itemSpacing
                }

                if let icon = ProviderIconAsset.image(for: item.provider) {
                    let iconRect = NSRect(
                        x: x,
                        y: floor((bounds.height - iconSize.height) / 2),
                        width: iconSize.width,
                        height: iconSize.height
                    )
                    drawIcon(icon, color: color, in: iconRect)
                    x += iconSize.width + iconTextSpacing
                }

                let text = percentageText(for: item.remainingFraction)
                let textSize = text.size(withAttributes: attributes)
                let textRect = NSRect(
                    x: x,
                    y: floor((bounds.height - textSize.height) / 2),
                    width: textSize.width,
                    height: textSize.height
                )
                text.draw(in: textRect, withAttributes: attributes)
                x += textSize.width
            }
        }
    }

    private func measuredContentWidth() -> CGFloat {
        let attributes: [NSAttributedString.Key: Any] = [.font: font]
        var width = horizontalPadding * 2

        for (index, item) in items.enumerated() {
            if index > 0 {
                width += itemSpacing
            }

            if ProviderIconAsset.image(for: item.provider) != nil {
                width += iconSize.width + iconTextSpacing
            }

            width += percentageText(for: item.remainingFraction).size(withAttributes: attributes).width
        }

        return ceil(width)
    }

    private func drawIcon(_ image: NSImage, color: NSColor, in rect: NSRect) {
        let sourceSize = image.size
        guard sourceSize.width > 0, sourceSize.height > 0 else {
            return
        }

        let scale = min(rect.width / sourceSize.width, rect.height / sourceSize.height)
        let fittedSize = NSSize(width: sourceSize.width * scale, height: sourceSize.height * scale)
        let fittedRect = NSRect(
            x: rect.midX - (fittedSize.width / 2),
            y: rect.midY - (fittedSize.height / 2),
            width: fittedSize.width,
            height: fittedSize.height
        )

        tintedImage(from: image, color: color).draw(
            in: fittedRect,
            from: .zero,
            operation: .sourceOver,
            fraction: 1,
            respectFlipped: true,
            hints: [.interpolation: NSImageInterpolation.high]
        )
    }

    private func tintedImage(from image: NSImage, color: NSColor) -> NSImage {
        let tintedImage = NSImage(size: image.size)
        tintedImage.lockFocus()

        let imageRect = NSRect(origin: .zero, size: image.size)
        image.draw(in: imageRect)
        color.set()
        imageRect.fill(using: .sourceAtop)

        tintedImage.unlockFocus()
        tintedImage.isTemplate = false
        return tintedImage
    }

    private func percentageText(for fraction: Double?) -> String {
        guard let fraction else {
            return "-%"
        }

        return "\(Int((fraction * 100).rounded()))%"
    }
}

enum AppMetadata {
    static let version = "0.1.0"
}

@MainActor
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    private let environment: AppEnvironment

    init(environment: AppEnvironment) {
        self.environment = environment

        let hostingController = NSHostingController(rootView: SettingsView(environment: environment))
        let window = NSWindow(contentViewController: hostingController)
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.title = environment.localizer.text(.settingsTitle)
        window.identifier = NSUserInterfaceItemIdentifier("settings")
        window.setContentSize(NSSize(width: 760, height: 580))
        window.minSize = NSSize(width: 640, height: 500)
        window.center()
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    func show() {
        guard let window else {
            return
        }

        window.title = environment.localizer.text(.settingsTitle)
        (window.contentViewController as? NSHostingController<SettingsView>)?.rootView = SettingsView(environment: environment)
        showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}

@MainActor
final class StatusItemController: NSObject {
    private let environment: AppEnvironment
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let popover = NSPopover()
    private var popoverController: NSHostingController<UsagePanelView>?
    private var contentView: StatusItemContentView?
    private var cancellables = Set<AnyCancellable>()

    init(environment: AppEnvironment) {
        self.environment = environment
        super.init()
        configureStatusItem()
        configurePopover()
        observeEnvironment()
        observeAppearanceChanges()
        refreshStatusView()
    }

    deinit {
        DistributedNotificationCenter.default().removeObserver(self)
    }

    func closePopover() {
        popover.performClose(nil)
        refreshStatusView()
    }

    @objc
    private func handleStatusItemClick(_ sender: Any?) {
        guard let event = NSApp.currentEvent else {
            togglePopover(nil)
            return
        }

        if event.type == .rightMouseUp || event.modifierFlags.contains(.control) {
            closePopover()
            if let button = statusItem.button {
                NSMenu.popUpContextMenu(contextMenu(), with: event, for: button)
            }
        } else {
            togglePopover(nil)
        }
    }

    @objc
    private func refreshAction(_ sender: Any?) {
        Task {
            await environment.refreshNow()
        }
    }

    @objc
    private func settingsAction(_ sender: Any?) {
        environment.showSettings()
    }

    @objc
    private func quitAction(_ sender: Any?) {
        environment.quitApplication()
    }

    @objc
    private func handleAppearanceChange(_ notification: Notification) {
        refreshStatusView()
        DispatchQueue.main.async { [weak self] in
            self?.refreshStatusView()
        }
    }

    private func configureStatusItem() {
        guard let button = statusItem.button else {
            return
        }

        button.title = ""
        button.image = nil
        button.attributedTitle = NSAttributedString(string: "")
        button.target = self
        button.action = #selector(handleStatusItemClick(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        button.setAccessibilityLabel(environment.localizer.text(.usagePanelTitle))

        let contentView = StatusItemContentView(frame: button.bounds)
        contentView.translatesAutoresizingMaskIntoConstraints = false
        button.addSubview(contentView)
        NSLayoutConstraint.activate([
            contentView.leadingAnchor.constraint(equalTo: button.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: button.trailingAnchor),
            contentView.topAnchor.constraint(equalTo: button.topAnchor),
            contentView.bottomAnchor.constraint(equalTo: button.bottomAnchor),
        ])
        self.contentView = contentView
    }

    private func configurePopover() {
        let controller = NSHostingController(rootView: UsagePanelView(environment: environment))
        popover.contentViewController = controller
        popover.behavior = .transient
        popover.animates = true
        self.popoverController = controller
    }

    private func observeEnvironment() {
        environment.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else {
                    return
                }

                self.refreshStatusView()
                self.popoverController?.rootView = UsagePanelView(environment: self.environment)
            }
            .store(in: &cancellables)
    }

    private func observeAppearanceChanges() {
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(handleAppearanceChange(_:)),
            name: NSNotification.Name("AppleInterfaceThemeChangedNotification"),
            object: nil,
            suspensionBehavior: .deliverImmediately
        )
    }

    private func refreshStatusView() {
        guard let button = statusItem.button else {
            return
        }

        contentView?.items = environment.visibleMenuBarItems
        contentView?.needsDisplay = true
        button.highlight(popover.isShown)
        button.needsDisplay = true

        let width = max(28, (contentView?.intrinsicContentSize.width ?? 20) + 4)
        statusItem.length = width
    }

    private func togglePopover(_ sender: Any?) {
        guard let button = statusItem.button else {
            return
        }

        if popover.isShown {
            closePopover()
        } else {
            popover.contentViewController = popoverController
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            repositionPopoverIfNeeded(relativeTo: button)
            NSApp.activate(ignoringOtherApps: true)
            refreshStatusView()
        }
    }

    private func repositionPopoverIfNeeded(relativeTo button: NSStatusBarButton) {
        guard let popoverWindow = popover.contentViewController?.view.window,
              let statusWindow = button.window,
              let screen = statusWindow.screen else {
            return
        }

        let visibleFrame = screen.visibleFrame.insetBy(dx: 8, dy: 4)
        var frame = popoverWindow.frame

        if frame.maxY > visibleFrame.maxY {
            frame.origin.y -= frame.maxY - visibleFrame.maxY
        }

        if frame.minY < visibleFrame.minY {
            frame.origin.y = visibleFrame.minY
        }

        if frame.maxX > visibleFrame.maxX {
            frame.origin.x -= frame.maxX - visibleFrame.maxX
        }

        if frame.minX < visibleFrame.minX {
            frame.origin.x = visibleFrame.minX
        }

        guard frame.equalTo(popoverWindow.frame) == false else {
            return
        }

        popoverWindow.setFrame(frame, display: false)
    }

    private func contextMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: environment.localizer.text(.menuActionRefresh), action: #selector(refreshAction(_:)), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: environment.localizer.text(.menuActionSettings), action: #selector(settingsAction(_:)), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: environment.localizer.text(.quitApp), action: #selector(quitAction(_:)), keyEquivalent: ""))
        menu.items.forEach { $0.target = self }
        return menu
    }

}
