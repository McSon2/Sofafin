import JellyfinKit
import SwiftUI

struct SettingsView: View {
    @Environment(AppSession.self) private var session
    @State private var serverInfo: PublicSystemInfo?
    /// Stocké sous la même clé que celle lue par `Localization` et par
    /// `JellyfinKit` : les trois doivent voir le même choix.
    @AppStorage("appLanguage") private var language: AppLanguage = .system

    var body: some View {
        ZStack {
            Theme.Palette.background.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 34) {
                Text("Réglages")
                    .font(Theme.Font.heroTitle)
                    .foregroundStyle(Theme.Palette.primaryText)

                infoCard

                languageCard

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

    /// Choix de la langue de l'interface.
    ///
    /// tvOS n'expose aucun réglage de langue par application : le système impose
    /// la sienne à toutes. Une médiathèque se regarde pourtant à plusieurs, et
    /// l'anglais d'un invité n'oblige pas à basculer tout l'appareil.
    private var languageCard: some View {
        HStack(spacing: 24) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Langue")
                    .font(Theme.Font.cardTitle)
                    .foregroundStyle(Theme.Palette.primaryText)
                Text("La langue de l'interface change immédiatement.")
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Palette.tertiaryText)
            }

            Spacer(minLength: 20)

            GlassMenu(title: String(localized: "Langue"), value: language.label) {
                ForEach(AppLanguage.allCases) { option in
                    MenuCheckItem(title: option.label, isSelected: language == option) {
                        language = option
                    }
                }
            }
        }
        .padding(.horizontal, 34)
        .padding(.vertical, 26)
        .frame(maxWidth: 1100, alignment: .leading)
        .liquidGlass(cornerRadius: 24)
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
