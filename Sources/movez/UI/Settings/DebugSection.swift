import SwiftUI

/// The debug tools, behind the settings footer's disclosure: a faster clock, the signals on a
/// switch, and a window into the scheduler.
struct DebugSection: View {
    var state: DebugState
    var actions = DebugActions()

    /// Tall enough to read a dozen transitions without swallowing the window.
    static let inspectorHeight: CGFloat = 260

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SettingsRow(label: "Time scale") {
                SegmentedControl(
                    options: DebugState.timeScaleOptions,
                    selection: Binding(get: { state.timeScale }, set: actions.setTimeScale)
                )
            }

            labelled("Signals") {
                InjectorGrid(injectors: DebugState.signalInjectors, fire: actions.fire)
            }

            labelled("Scheduler") {
                InjectorGrid(injectors: DebugState.schedulerActions, fire: actions.fire)
            }

            StateInspectorView(state: state)
        }
    }

    private func labelled<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            MovezText(label, MovezType.settingsRow)
            content()
        }
    }
}

/// The injector buttons, wrapped onto as many rows as they need.
struct InjectorGrid: View {
    var injectors: [SignalInjector]
    var fire: (SignalInjector) -> Void

    /// Wide enough for "Fire full break now" at 13 pt.
    private static let columns = [GridItem(.adaptive(minimum: 150, maximum: 220), spacing: 8, alignment: .leading)]

    var body: some View {
        LazyVGrid(columns: Self.columns, alignment: .leading, spacing: 8) {
            ForEach(injectors) { injector in
                Button(injector.label) { fire(injector) }
                    .buttonStyle(SecondaryButtonStyle())
            }
        }
    }
}

/// The scheduler, as it stands. A model-driven view, not a log: what it shows is the snapshot the
/// scheduler is actually holding.
struct StateInspectorView: View {
    var state: DebugState

    var body: some View {
        ScrollView {
            Text(state.inspectorText)
                .font(.system(size: 11, weight: .regular, design: .monospaced))
                .foregroundStyle(Tokens.text2.color)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
        }
        .frame(maxWidth: .infinity)
        .frame(height: DebugSection.inspectorHeight)
        .background(Tokens.ink.opacity(0.45).color)
        .overlay(
            RoundedRectangle(cornerRadius: Tokens.Radius.select, style: .continuous)
                .strokeBorder(Tokens.ruleSettings.color, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Tokens.Radius.select, style: .continuous))
    }
}
