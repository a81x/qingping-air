import Foundation
import CoreGraphics

public enum PanelBehavior {
    /// Screen coordinates: AppKit's Y axis points upward; place below the menu bar anchor.
    public static func frame(anchor: CGRect, visible: CGRect, desiredHeight: CGFloat) -> CGRect {
        let margin: CGFloat = 6
        let width = min(350, max(0, visible.width - margin * 2))
        let height = min(desiredHeight, max(0, visible.height - margin * 2))
        let x = max(visible.minX + margin, min(anchor.midX - width / 2, visible.maxX - margin - width))
        let y = max(visible.minY + margin, min(anchor.minY - height - margin, visible.maxY - margin - height))
        return CGRect(x: x, y: y, width: width, height: height)
    }

    /// The click that toggles the status item must never also count as an outside click.
    public static func shouldDismissForClick(point: CGPoint, panel: CGRect, anchor: CGRect, isPresented: Bool) -> Bool {
        isPresented && !panel.contains(point) && !anchor.contains(point)
    }
}
