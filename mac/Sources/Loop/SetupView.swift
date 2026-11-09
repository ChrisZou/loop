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
        .animation(.easeInOut(duration: 0.25), value: setup.finished)
    }
}

private struct SetupView: View {
    @ObservedObject var model: SetupModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("安装命令行工具和 Skill")
                .font(Font(Theme.serif(22)))
                .foregroundStyle(Color(Theme.heading))
                .padding(.bottom, 22)

            VStack(spacing: 0) {
                ForEach(Array(model.steps.enumerated()), id: \.element.id) { index, step in
                    if index > 0 { Rectangle().fill(Color(Theme.rule)).frame(height: 1) }
                    SetupRow(step: step)
                }
            }

            if let error = model.error {
                Text(error)
                    .font(.system(size: 12.5))
                    .foregroundStyle(Color(Theme.vermilion))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 14)
            }

            Button(action: model.install) {
                Text(buttonTitle).frame(maxWidth: .infinity)
            }
            .buttonStyle(InkButtonStyle())
            .keyboardShortcut(.defaultAction)
            .disabled(!model.ready || model.installing)
            .padding(.top, 26)
        }
        .frame(width: 400)
        .padding(.horizontal, 36)
        .padding(.top, 34)
        .padding(.bottom, 32)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(Theme.sheet))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color(Theme.rule), lineWidth: 1))
                .shadow(color: Color.black.opacity(0.05), radius: 14, x: 0, y: 4)
        )
        .frame(minWidth: 720, maxWidth: .infinity, minHeight: 480, maxHeight: .infinity)
        .background(Color(Theme.ground).ignoresSafeArea())
        .onAppear(perform: model.prepare)
    }

    private var buttonTitle: String {
        if model.installing { return "安装中…" }
        return model.error == nil ? "安装" : "重试"
    }
}

private struct SetupRow: View {
    let step: SetupStep

    var body: some View {
        HStack(spacing: 12) {
            Text(step.title)
                .font(.system(size: 13.5, weight: .semibold))
                .foregroundStyle(Color(Theme.ink))
                .fixedSize()
            Spacer(minLength: 8)
            Text(step.detail)
                .font(.system(size: 11.5, design: .monospaced))
                .foregroundStyle(Color(Theme.secondary))
                .lineLimit(1)
                .truncationMode(.head)
            RedTick(done: step.done)
        }
        .frame(height: 44)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(step.title)
        .accessibilityValue(step.done ? "已安装" : "未安装")
    }
}

/// A teacher's tick, drawn in red pen when its step completes.
private struct RedTick: View {
    let done: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color(Theme.rule), lineWidth: 1.5)
                .frame(width: 14, height: 14)
                .opacity(done ? 0 : 1)
            TickShape()
                .trim(from: 0, to: done ? 1 : 0)
                .stroke(Color(Theme.vermilion), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                .frame(width: 16, height: 14)
        }
        .frame(width: 18, height: 18)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.28), value: done)
    }
}

private struct TickShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + 1, y: rect.midY + 1))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.36, y: rect.maxY - 1.5))
        path.addLine(to: CGPoint(x: rect.maxX - 0.5, y: rect.minY + 1))
        return path
    }
}
