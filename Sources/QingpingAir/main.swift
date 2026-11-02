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
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    private var outsideClickMonitor: Any?
    private var localEventMonitor: Any?
    private var panelHeight: CGFloat = 420

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.target = self
        item.button?.action = #selector(toggle)
        item.button?.sendAction(on: .leftMouseUp)
        panel.level = .popUpMenu
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.transient, .moveToActiveSpace, .fullScreenAuxiliary]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.appearance = NSAppearance(named: .darkAqua)
        panel.contentViewController = NSHostingController(rootView:
            ScrollView { Panel(monitor: monitor, onSettingsChange: { [weak self] settings in
                self?.panelHeight = settings ? 570 : 420
                self?.positionPanel()
            }) }
                .frame(width: 350)
                .frame(maxHeight: .infinity)
                .background(RoundedRectangle(cornerRadius: 18).fill(Color(red: 44 / 255, green: 44 / 255, blue: 44 / 255)))
                .clipShape(RoundedRectangle(cornerRadius: 18))
                .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Color.white.opacity(0.13), lineWidth: 1))
                .preferredColorScheme(.dark)
        )
        panel.contentView?.wantsLayer = true
        panel.contentView?.layer?.cornerRadius = 18
        panel.contentView?.layer?.masksToBounds = true
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            // AppKit invokes event monitors on the main thread. Handle this event now:
            // queuing it can close a panel opened by the same status-item click.
            MainActor.assumeIsolated { self?.dismissForOutsideClick(at: NSEvent.mouseLocation) }
        }
        localEventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .keyDown]) { [weak self] event in
            let consumed = MainActor.assumeIsolated {
                guard let self, self.panel.isVisible else { return false }
                if event.type == .keyDown {
                    if event.keyCode == 53 { self.panel.orderOut(nil); self.panelLog("closed: escape"); return true }
                } else if event.window !== self.panel, event.window !== self.item.button?.window {
                    let location = event.window.map { $0.convertPoint(toScreen: event.locationInWindow) } ?? NSEvent.mouseLocation
                    self.dismissForOutsideClick(at: location)
                }
                return false
            }
            return consumed ? nil : event
        }
        monitor.onChange = { [weak self] in self?.refresh() }
        refresh()
    }
    func applicationWillTerminate(_ notification: Notification) {
        if let outsideClickMonitor { NSEvent.removeMonitor(outsideClickMonitor) }
        if let localEventMonitor { NSEvent.removeMonitor(localEventMonitor) }
    }
    private var anchorRect: NSRect? {
        guard let button = item?.button, let window = button.window else { return nil }
        return window.convertToScreen(button.convert(button.bounds, to: nil))
    }
    private func dismissForOutsideClick(at point: NSPoint) {
        guard let anchor = anchorRect else { return }
        if PanelBehavior.shouldDismissForClick(point: point, panel: panel.frame, anchor: anchor, isPresented: panel.isVisible) {
            panel.orderOut(nil)
            panelLog("closed: outside click")
        }
    }
    private func panelLog(_ message: String) {
        guard CommandLine.arguments.contains("--diagnostics") else { return }
        print("Panel: \(message)")
        fflush(stdout)
    }
    func positionPanel() {
        guard let button = item.button, let window = button.window else { return }
        let anchor = window.convertToScreen(button.convert(button.bounds, to: nil))
        let screen = window.screen ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return }
        panel.setFrame(PanelBehavior.frame(anchor: anchor, visible: visible, desiredHeight: panelHeight), display: true)
    }
    @objc func toggle() {
        if panel.isVisible { panel.orderOut(nil); panelLog("closed: status item") }
        else {
            positionPanel()
            panel.makeKeyAndOrderFront(nil)
            panelLog("opened: visible=\(panel.isVisible), key=\(panel.isKeyWindow), frame=\(panel.frame)")
        }
    }
    func refresh() {
        guard let button = item?.button else { return }
        let metric = monitor.displayed
        let sample = monitor.fresh(metric)
        let value = sample.map { metric.format($0.value) } ?? "—"
        let red = !monitor.alerts.isEmpty
        button.image = nil
        let normalColor: NSColor = sample == nil ? .secondaryLabelColor : .white
        let color = red ? NSColor(calibratedRed: 0.78, green: 0.36, blue: 0.29, alpha: 1) : normalColor
        button.attributedTitle = NSAttributedString(string: value, attributes: [
            .font: NSFont.menuBarFont(ofSize: 0),
            .foregroundColor: color
        ])
        button.toolTip = "\(metric.label): \(value) \(metric.unit)\n\(monitor.connectionText)"
        button.setAccessibilityLabel("Qingping Air. \(metric.label): \(value) \(metric.unit). \(red ? "Красная зона." : "") \(monitor.connectionText)")
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
