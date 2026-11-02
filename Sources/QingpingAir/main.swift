import AppKit
import SwiftUI
import AirCore

@MainActor
final class AirPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override func cancelOperation(_ sender: Any?) { orderOut(nil) }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let monitor = Monitor()
    var item: NSStatusItem!
    let panel = AirPanel(contentRect: NSRect(x: 0, y: 0, width: 350, height: 420),
                        styleMask: [.borderless], backing: .buffered, defer: false)
    private var outsideClickMonitor: Any?
    private var localEventMonitor: Any?
    private var panelHeight: CGFloat = 420

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        item = NSStatusBar.system.statusItem(withLength: 28)
        item.button?.target = self
        item.button?.action = #selector(toggle)
        panel.level = .popUpMenu
        panel.hasShadow = true
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.transient, .moveToActiveSpace, .fullScreenAuxiliary]
        panel.backgroundColor = .windowBackgroundColor
        panel.contentViewController = NSHostingController(rootView:
            ScrollView { Panel(monitor: monitor, onSettingsChange: { [weak self] settings in
                self?.panelHeight = settings ? 570 : 420
                self?.positionPanel()
            }) }.frame(width: 350)
        )
        panel.contentView?.wantsLayer = true
        panel.contentView?.layer?.cornerRadius = 12
        panel.contentView?.layer?.masksToBounds = true
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in self?.panel.orderOut(nil) }
        }
        localEventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .keyDown]) { [weak self] event in
            let consumed = MainActor.assumeIsolated {
                guard let self, self.panel.isVisible else { return false }
                if event.type == .keyDown {
                    if event.keyCode == 53 { self.panel.orderOut(nil); return true }
                } else if event.window !== self.panel, event.window !== self.item.button?.window {
                    self.panel.orderOut(nil)
                }
                return false
            }
            return consumed ? nil : event
        }
        monitor.onChange = { [weak self] in self?.refresh() }
        refresh()
    }
    func applicationDidResignActive(_ notification: Notification) { panel.orderOut(nil) }
    func positionPanel() {
        guard let button = item.button, let window = button.window else { return }
        let anchor = window.convertToScreen(button.convert(button.bounds, to: nil))
        let screen = window.screen ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return }
        let height = min(panelHeight, visible.height - 12)
        let x = max(visible.minX + 6, min(anchor.midX - 175, visible.maxX - 356))
        let y = max(visible.minY + 6, min(anchor.minY - height - 5, visible.maxY - height - 5))
        panel.setFrame(NSRect(x: x, y: y, width: 350, height: height), display: true)
    }
    @objc func toggle() {
        if panel.isVisible { panel.orderOut(nil) }
        else {
            positionPanel()
            NSApp.activate(ignoringOtherApps: true)
            panel.makeKeyAndOrderFront(nil)
        }
    }
    func refresh() {
        guard let button = item?.button else { return }
        let metric = monitor.displayed
        let sample = monitor.fresh(metric)
        let value = sample.map { metric.format($0.value) } ?? "—"
        let red = !monitor.alerts.isEmpty
        button.image = CloudIcon.image(value: value, label: metric.shortLabel, red: red, available: sample != nil, appearance: button.effectiveAppearance)
        button.toolTip = "\(metric.label): \(value) \(metric.unit)\n\(monitor.connectionText)"
        button.setAccessibilityLabel("Qingping Air. \(metric.label): \(value) \(metric.unit). \(red ? "Красная зона." : "") \(monitor.connectionText)")
    }
}

@MainActor
enum CloudIcon {
    static func image(value: String, label: String, red: Bool, available: Bool, appearance: NSAppearance) -> NSImage {
        let image = NSImage(size: NSSize(width: 24, height: 24))
        appearance.performAsCurrentDrawingAppearance {
            image.lockFocus()
            let dark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            let fill: NSColor = red ? .systemRed : (dark ? .white : NSColor(calibratedWhite: 0.17, alpha: 1))
            fill.withAlphaComponent(available ? 1 : 0.45).setFill()
            // Six overlapping rounded lobes keep a compact, nearly circular cloud silhouette.
            let cloud = NSBezierPath(ovalIn: NSRect(x: 4, y: 4, width: 16, height: 16))
            for lobe in 0..<6 {
                let angle = Double(lobe) * .pi / 3 + .pi / 6
                let x = 12 + 6 * cos(angle)
                let y = 12 + 6 * sin(angle)
                cloud.appendOval(in: NSRect(x: x - 4.5, y: y - 4.5, width: 9, height: 9))
            }
            cloud.fill()
            let ink: NSColor = red || !dark ? .white : .black
            let fontSize: CGFloat = value.count >= 4 ? 7.5 : 9
            let text = NSAttributedString(string: value, attributes: [
                .font: NSFont.monospacedDigitSystemFont(ofSize: fontSize, weight: .bold),
                .foregroundColor: ink
            ])
            text.draw(at: NSPoint(x: (24 - text.size().width) / 2, y: (24 - text.size().height) / 2))
            image.unlockFocus()
        }
        image.isTemplate = false
        return image
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
