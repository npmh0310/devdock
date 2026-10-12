import Defaults
import KeyboardShortcuts
import SwiftUI

/// An account that can be shown in the menu bar.
struct MenuBarAccountOption: Identifiable {
    let id: String
    let title: String
}

struct SettingsView: View {
    var menuBarAccounts: [MenuBarAccountOption] = []

    @Default(.menuBarStyle) private var menuBarStyle
    @Default(.menuBarHiddenAccounts) private var hiddenAccounts
    @Default(.aiUsageInterval) private var aiUsageInterval
    @Default(.usageWarnPercent) private var usageWarnPercent
    @Default(.usageNotifications) private var usageNotifications

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.m) {
            SectionHeader(title: "Settings", subtitle: "DevDock \(AppInfo.version)")

            LaunchAtLoginRow()

            SettingRow(title: "Toggle panel") {
                KeyboardShortcuts.Recorder(for: .togglePanel)
            }

            SettingRow(title: "Update AI usage every") {
                Picker("", selection: $aiUsageInterval) {
                    Text("1m").tag(1)
                    Text("5m").tag(5)
                    Text("15m").tag(15)
                    Text("30m").tag(30)
                }
                .labelsHidden()
                .clickableCursor()
                .fixedSize()
            }

            SettingRow(title: "Menu bar shows") {
                Picker("", selection: $menuBarStyle) {
                    ForEach(MenuBarStyle.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .labelsHidden()
                .clickableCursor()
                .fixedSize()
            }

            if menuBarStyle != .icon, !menuBarAccounts.isEmpty {
                VStack(alignment: .leading, spacing: DS.Space.xs) {
                    ForEach(menuBarAccounts) { account in
                        Toggle(account.title, isOn: shownBinding(account.id))
                            .toggleStyle(.checkbox)
                            .font(DS.Typography.body)
                            .clickableCursor()
                    }
                }
                .padding(.leading, DS.Space.m)
            }

            SettingRow(title: "Warn when quota reaches") {
                Picker("", selection: $usageWarnPercent) {
                    Text("70%").tag(70)
                    Text("80%").tag(80)
                    Text("90%").tag(90)
                }
                .labelsHidden()
                .clickableCursor()
                .fixedSize()
            }

            SettingRow(title: "Notify about AI quota") {
                Toggle("", isOn: $usageNotifications)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .clickableCursor()
                    .onChange(of: usageNotifications) { _, enabled in
                        if enabled { Notifier.requestPermission() }
                    }
            }

            Text("Ports update live while the panel is open. Press ↻ to update everything now.")
                .font(DS.Typography.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            AuthorLink()
        }
    }

    private func shownBinding(_ id: String) -> Binding<Bool> {
        Binding(
            get: { !hiddenAccounts.contains(id) },
            set: { shown in
                hiddenAccounts.removeAll { $0 == id }
                if !shown { hiddenAccounts.append(id) }
            }
        )
    }
}

private struct SettingRow<Control: View>: View {
    let title: String
    @ViewBuilder var control: Control

    var body: some View {
        HStack {
            Text(title).font(DS.Typography.body)
            Spacer()
            control
        }
    }
}

/// Reads the real state from macOS each time, since the user can change it in System Settings too.
private struct LaunchAtLoginRow: View {
    @State private var isEnabled = LoginItem.isEnabled
    @State private var needsApproval = LoginItem.needsApproval

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.xxs) {
            SettingRow(title: "Launch at login") {
                Toggle("", isOn: Binding(
                    get: { isEnabled },
                    set: { enable in
                        LoginItem.setEnabled(enable)
                        isEnabled = LoginItem.isEnabled
                        needsApproval = LoginItem.needsApproval
                    }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
                .clickableCursor()
            }
            if needsApproval {
                Button("Allow DevDock in System Settings › Login Items") { LoginItem.openSystemSettings() }
                    .buttonStyle(.link)
                    .font(DS.Typography.caption)
                    .clickableCursor()
            } else if !LoginItem.isInstalled {
                Text("Running from a build folder. Run `make install` so login starts the installed copy.")
                    .font(DS.Typography.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .onAppear {
            isEnabled = LoginItem.isEnabled
            needsApproval = LoginItem.needsApproval
        }
    }
}

/// "DevDock 0.1.0 · by npmh0310", linking to the author's GitHub.
private struct AuthorLink: View {
    var body: some View {
        Button {
            Launcher.openURL(AppInfo.authorURL)
        } label: {
            HStack(spacing: DS.Space.xs) {
                Text("DevDock \(AppInfo.version) · by")
                Text(AppInfo.author).fontWeight(.semibold)
                Image(systemName: "arrow.up.right").font(.system(size: 9, weight: .semibold))
            }
            .font(DS.Typography.caption)
            .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .clickableCursor()
        .help(AppInfo.authorURL.absoluteString)
    }
}
