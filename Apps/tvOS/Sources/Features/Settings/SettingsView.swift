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

                Text("Sofafin \(appVersion) — lecteur natif pour Jellyfin")
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
            separator
            row("Serveur", serverInfo?.serverName ?? session.serverName ?? "—")
            separator
            row("Adresse", session.serverURL?.absoluteString ?? "—")
            separator
            row("Version Jellyfin", serverInfo?.version ?? "—")
        }
        .padding(34)
        .frame(maxWidth: 1100, alignment: .leading)
        .liquidGlass(cornerRadius: 24)
    }

    /// `Divider` trace une ligne d'un point, invisible sur un téléviseur : on la
    /// remplace par un rectangle à l'épaisseur plancher du thème.
    private var separator: some View {
        Rectangle()
            .fill(Theme.Palette.separator)
            .frame(height: Theme.Metrics.hairline)
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
        // Deux textes séparés par un ressort seraient annoncés comme deux
        // éléments sans lien : « Serveur » d'un côté, un nom de l'autre.
        .accessibilityElement(children: .combine)
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1"
    }
}
