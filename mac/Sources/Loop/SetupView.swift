import AppKit
import SwiftUI

/// The history home, behind the setup page until the CLI and skill are installed.
struct HomeGate: View {
    @StateObject private var setup = SetupModel()

    var body: some View {
        ZStack {
            if setup.finished {
                HistoryHomeView().transition(.opacity)
            } else {
                SetupView(model: setup).transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: setup.finished)
        .background(WindowChrome())
        .toolbarBackground(.hidden, for: .windowToolbar)
    }
}

/// Lets the page run under the title bar, so the window is one surface with the traffic lights resting on it.
private struct WindowChrome: NSViewRepresentable {
    final class Probe: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else { return }
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.titlebarSeparatorStyle = .none
            window.styleMask.insert(.fullSizeContentView)
        }
    }

    func makeNSView(context: Context) -> Probe { Probe() }
    func updateNSView(_ view: Probe, context: Context) {}
}

private struct SetupView: View {
    @ObservedObject var model: SetupModel
    @State private var drawn = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            LoopMark()
                .trim(from: 0, to: drawn ? 1 : 0)
                .stroke(Color(Theme.vermilion), style: StrokeStyle(lineWidth: 3.5, lineCap: .round, lineJoin: .round))
                .frame(width: 88, height: 88)
                .accessibilityHidden(true)

            Text("安装命令行工具和 Skill")
                .font(Font(Theme.serif(30)))
                .foregroundStyle(Color(Theme.heading))
                .multilineTextAlignment(.center)
                .padding(.top, 40)

            Button(action: model.install) {
                ZStack {
                    Text(model.error == nil ? "安装" : "重试").opacity(model.installing || model.done ? 0 : 1)
                    if model.installing && !model.done {
                        ProgressView().controlSize(.small).tint(Color(Theme.onPrimary))
                    }
                    TickShape()
                        .trim(from: 0, to: model.done ? 1 : 0)
                        .stroke(Color(Theme.onPrimary), style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
                        .frame(width: 17, height: 14)
                        .animation(reduceMotion ? nil : .easeOut(duration: 0.3), value: model.done)
                }
                .frame(width: 148)
            }
            .buttonStyle(InkButtonStyle(height: 44, fontSize: 14.5, radius: 10))
            .keyboardShortcut(.defaultAction)
            .allowsHitTesting(!model.installing && !model.done)
            .accessibilityLabel(model.error == nil ? "安装" : "重试")
            .padding(.top, 44)

            Text(model.error ?? " ")
                .font(.system(size: 13))
                .foregroundStyle(Color(Theme.vermilion))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
                .padding(.top, 18)
                .opacity(model.error == nil ? 0 : 1)
        }
        .padding(.bottom, 24)
        .frame(minWidth: 720, maxWidth: .infinity, minHeight: 480, maxHeight: .infinity)
        .background(Color(Theme.sheet).ignoresSafeArea())
        .onAppear {
            if reduceMotion { drawn = true } else { withAnimation(.easeInOut(duration: 1.1).delay(0.15)) { drawn = true } }
        }
    }
}

/// One stroke of the red pen: a cursive l that doubles back through itself.
struct LoopMark: Shape {
    func path(in rect: CGRect) -> Path {
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: rect.minX + x * rect.width, y: rect.minY + y * rect.height) }
        var path = Path()
        path.move(to: point(0.02, 0.70))
        path.addCurve(to: point(0.66, 0.22), control1: point(0.30, 0.72), control2: point(0.62, 0.52))
        path.addCurve(to: point(0.46, 0.02), control1: point(0.69, 0.10), control2: point(0.58, 0.02))
        path.addCurve(to: point(0.30, 0.46), control1: point(0.33, 0.02), control2: point(0.27, 0.24))
        path.addCurve(to: point(0.58, 0.92), control1: point(0.33, 0.70), control2: point(0.42, 0.92))
        path.addCurve(to: point(0.98, 0.58), control1: point(0.76, 0.92), control2: point(0.90, 0.74))
        return path
    }
}

/// A teacher's tick.
struct TickShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + 1, y: rect.midY + 1))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.36, y: rect.maxY - 1.5))
        path.addLine(to: CGPoint(x: rect.maxX - 0.5, y: rect.minY + 1))
        return path
    }
}
