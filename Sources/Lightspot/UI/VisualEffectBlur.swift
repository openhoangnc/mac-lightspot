import SwiftUI
import AppKit

struct VisualEffectBlur: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .hudWindow
    var blendingMode: NSVisualEffectView.BlendingMode = .behindWindow
    var state: NSVisualEffectView.State = .active
    var isEmphasized: Bool = true
    var cornerRadius: CGFloat = 0

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = state
        view.isEmphasized = isEmphasized
        view.appearance = NSAppearance(named: .darkAqua)
        view.wantsLayer = true
        if cornerRadius > 0 {
            view.layer?.cornerRadius = cornerRadius
            view.layer?.cornerCurve = .continuous
            view.layer?.masksToBounds = true
        }
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
        nsView.state = state
        nsView.isEmphasized = isEmphasized
        nsView.appearance = NSAppearance(named: .darkAqua)
        nsView.wantsLayer = true
        if cornerRadius > 0 {
            nsView.layer?.cornerRadius = cornerRadius
            nsView.layer?.cornerCurve = .continuous
            nsView.layer?.masksToBounds = true
        } else {
            nsView.layer?.cornerRadius = 0
            nsView.layer?.masksToBounds = false
        }
    }
}
