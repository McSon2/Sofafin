import JellyfinKit
import SwiftUI

struct SettingsView: View {
    @Environment(AppSession.self) private var session
    @State private var serverInfo: PublicSystemInfo?

    var body: some View {
        ZStack {
            Theme.Palette.background.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 34) {
                Text("Réglages")
                    .font(Theme.Font.heroTitle)
                    .foregroundStyle(Theme.Palette.primaryText)

                infoCard

                HStack(spacing: 20) {
                    Button("Changer d'utilisateur") {
                        Task { await session.switchUser() }
                    }
                    .buttonStyle(.glass)

                    Button("Se déconnecter") {
                        Task { await session.signOut() }
                    }
                    .buttonStyle(.glassProminent)
                }

                Spacer()

                Text("Jellyflix \(appVersion) — lecteur natif pour Jellyfin")
                    .font(Theme.Font.badge)
                    .foregroundStyle(Theme.Palette.tertiaryText)
            }
            .padding(Theme.Metrics.screenPadding)
        }
        .task { serverInfo = try? await session.api.publicSystemInfo() }
    }

    private var infoCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            row("Utilisateur", session.user?.name ?? "—")
            Divider().overlay(Theme.Palette.separator)
            row("Serveur", serverInfo?.serverName ?? session.serverName ?? "—")
            Divider().overlay(Theme.Palette.separator)
            row("Adresse", session.serverURL?.absoluteString ?? "—")
            Divider().overlay(Theme.Palette.separator)
            row("Version Jellyfin", serverInfo?.version ?? "—")
        }
        .padding(34)
        .frame(maxWidth: 1100, alignment: .leading)
        .liquidGlass(cornerRadius: 24)
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.Palette.tertiaryText)
            Spacer()
            Text(value)
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.Palette.primaryText)
        }
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1"
    }
}
