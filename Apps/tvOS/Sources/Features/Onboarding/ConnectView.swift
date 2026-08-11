import JellyfinKit
import SwiftUI

/// Écran d'accueil hors connexion : adresse du serveur, puis identification.
struct ConnectView: View {
    @Environment(AppSession.self) private var session

    var body: some View {
        ZStack {
            BackdropAtmosphere()

            switch session.phase {
            case .needsServer, .restoring:
                ServerStepView()
            case .needsSignIn(let serverName):
                SignInStepView(serverName: serverName)
            case .ready:
                EmptyView()
            }
        }
    }
}

/// Fond animé discret : deux halos colorés qui évitent l'écran noir vide,
/// et donnent au verre de quoi réfracter.
///
/// La dérive est purement décorative et tourne en boucle sans fin : c'est
/// exactement ce que « Réduire les animations » demande de couper. Les halos
/// restent, figés à leur position de départ.
struct BackdropAtmosphere: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var drift = false

    var body: some View {
        ZStack {
            Theme.Palette.background.ignoresSafeArea()

            Circle()
                .fill(Theme.Palette.accent.opacity(0.35))
                .frame(width: 900, height: 900)
                .blur(radius: 220)
                .offset(x: drift ? -260 : -160, y: drift ? -180 : -260)

            Circle()
                .fill(Color(red: 0.29, green: 0.30, blue: 0.85).opacity(0.32))
                .frame(width: 780, height: 780)
                .blur(radius: 220)
                .offset(x: drift ? 320 : 220, y: drift ? 220 : 300)
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 14).repeatForever(autoreverses: true)) {
                drift = true
            }
        }
    }
}

// MARK: - Étape 1 : le serveur

private struct ServerStepView: View {
    @Environment(AppSession.self) private var session
    /// Pré-remplissable au lancement (`-serverAddress <hôte>:<port>`), ce qui
    /// évite de saisir une adresse à la télécommande à chaque test. Voir la
    /// section `schemes` de `project.yml`.
    @State private var address = UserDefaults.standard.string(forKey: "serverAddress") ?? ""
    @State private var isChecking = false
    @FocusState private var focus: Field?

    private enum Field { case address, connect }

    var body: some View {
        VStack(spacing: 0) {
            Spacer().frame(height: 140)

            Text("Sofafin")
                .font(.system(size: 124, weight: .heavy))
                .foregroundStyle(
                    LinearGradient(
                        colors: [Theme.Palette.accentBright, Theme.Palette.accent],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .accessibilityAddTraits(.isHeader)

            Spacer()

            // Le champ de tvOS dessine déjà sa propre pilule et sa réaction au
            // focus : l'entourer d'une surface de verre produisait une boîte dans
            // une boîte. Sa police doit venir des styles système : avec une taille
            // absolue, le contrôle cale le texte vers le haut de la pilule.
            // Le texte est centré sur sa boîte de ligne, laquelle réserve la place
            // des jambages. Une adresse n'en a presque jamais, d'où un texte qui
            // paraît collé en haut : mesuré à 6 points, compensés ici. La ligne de
            // base est le seul levier — un décalage de la vue emporterait la pilule.
            TextField("192.168.1.10:8096", text: $address)
                .font(.headline)
                .baselineOffset(-6)
                .multilineTextAlignment(.center)
                .focused($focus, equals: .address)
                .frame(width: 520)
                .onSubmit(connect)

            // Hauteur réservée en permanence : sans elle, l'apparition d'une erreur
            // ferait sauter tout le bloc.
            Label(session.lastError ?? "", systemImage: "exclamationmark.triangle.fill")
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.Palette.accentBright)
                .opacity(session.lastError == nil ? 0 : 1)
                .frame(height: 40)
                .padding(.top, 28)

            Spacer()

            Button(action: connect) {
                HStack(spacing: 14) {
                    if isChecking {
                        ProgressView().tint(.white)
                    }
                    Text(isChecking ? "Vérification…" : "Se connecter")
                }
                .font(.headline)
                .frame(width: 340)
                .padding(.vertical, 8)
            }
            .buttonStyle(.glassProminent)
            .focused($focus, equals: .connect)
            .disabled(address.isEmpty || isChecking)
            .padding(.bottom, 120)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Une adresse déjà connue appelle une validation, pas une nouvelle saisie :
        // ouvrir le clavier plein écran serait un obstacle de plus.
        .onAppear { focus = address.isEmpty ? .address : .connect }
    }

    private func connect() {
        guard !address.isEmpty, !isChecking else { return }
        isChecking = true
        Task {
            _ = await session.connectToServer(address)
            isChecking = false
        }
    }
}

// MARK: - Étape 2 : l'identité

private struct SignInStepView: View {
    @Environment(AppSession.self) private var session
    let serverName: String?

    @State private var quickConnectCode: String?
    @State private var quickConnectSecret: String?
    @State private var quickConnectFailed = false
    @State private var username = ""
    @State private var password = ""
    @State private var isSigningIn = false
    @FocusState private var focusedField: Field?

    private enum Field { case username, password }

    var body: some View {
        HStack(spacing: 70) {
            quickConnectPanel
            Rectangle()
                .fill(Theme.Palette.separator)
                .frame(width: Theme.Metrics.hairline, height: 420)
            credentialsPanel
        }
        .padding(70)
        .task { await startQuickConnect() }
    }

    // Quick Connect : aucun mot de passe à saisir à la télécommande.
    private var quickConnectPanel: some View {
        VStack(spacing: 26) {
            Image(systemName: "bolt.horizontal.circle.fill")
                .font(.system(size: 60, weight: .medium))
                .foregroundStyle(Theme.Palette.accentBright)
                .accessibilityHidden(true)

            Text("Connexion rapide")
                .font(Theme.Font.sectionTitle)
                .foregroundStyle(Theme.Palette.primaryText)

            if let code = quickConnectCode {
                Text(code)
                    .font(.system(size: 76, weight: .bold, design: .monospaced))
                    .kerning(10)
                    .foregroundStyle(Theme.Palette.primaryText)
                    .padding(.horizontal, 40)
                    .padding(.vertical, 24)
                    .liquidGlass(cornerRadius: 20, isHighlighted: true)
                    // « 428913 » se lirait « quatre cent vingt-huit mille… » :
                    // inutilisable pour recopier un code sur un autre appareil.
                    // Séparé par des virgules, il est énoncé chiffre par chiffre.
                    .accessibilityLabel(
                        "Code de connexion rapide : "
                            + code.map(String.init).joined(separator: ", ")
                    )

                Text("Saisis ce code dans Jellyfin depuis un autre appareil :\nProfil → Connexion rapide.")
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Palette.secondaryText)
                    .multilineTextAlignment(.center)

                HStack(spacing: 10) {
                    ProgressView().tint(Theme.Palette.secondaryText)
                    Text("En attente de validation…")
                        .font(Theme.Font.badge)
                        .foregroundStyle(Theme.Palette.tertiaryText)
                }
            } else if quickConnectFailed {
                Text("La connexion rapide n'est pas disponible sur ce serveur.")
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Palette.tertiaryText)
                    .multilineTextAlignment(.center)
            } else {
                ProgressView().tint(.white)
            }
        }
        .frame(width: 560)
    }

    private var credentialsPanel: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text(serverName ?? "Serveur Jellyfin")
                .font(Theme.Font.sectionTitle)
                .foregroundStyle(Theme.Palette.primaryText)

            Text("Ou connecte-toi avec ton compte")
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.Palette.secondaryText)

            TextField("Nom d'utilisateur", text: $username)
                .font(Theme.Font.body)
                .focused($focusedField, equals: .username)

            SecureField("Mot de passe", text: $password)
                .font(Theme.Font.body)
                .focused($focusedField, equals: .password)

            Button(action: signIn) {
                Text(isSigningIn ? "Connexion…" : "Se connecter")
                    .font(Theme.Font.button)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glass)
            .disabled(username.isEmpty || isSigningIn)

            if let error = session.lastError {
                Text(error)
                    .font(Theme.Font.badge)
                    .foregroundStyle(Theme.Palette.accentBright)
            }

            Button("Changer de serveur") {
                Task { await session.signOut() }
            }
            .buttonStyle(.plain)
            .font(Theme.Font.badge)
            .foregroundStyle(Theme.Palette.tertiaryText)
            // Action secondaire : centrée et détachée, pour qu'au focus sa pilule
            // ne vienne pas mordre sur le bouton principal.
            .frame(maxWidth: .infinity)
            .padding(.top, 44)
        }
        .frame(width: 560)
    }

    private func signIn() {
        isSigningIn = true
        Task {
            _ = await session.signIn(username: username, password: password)
            isSigningIn = false
        }
    }

    /// Ouvre une session Quick Connect puis interroge le serveur jusqu'à validation.
    private func startQuickConnect() async {
        guard let client = session.anonymousClient else { return }
        guard (try? await client.quickConnectEnabled()) == true,
              let state = try? await client.quickConnectInitiate(),
              let secret = state.secret, let code = state.code else {
            quickConnectFailed = true
            return
        }
        quickConnectCode = code
        quickConnectSecret = secret

        // Le code Jellyfin expire après quelques minutes : on cesse d'interroger avant.
        for _ in 0..<100 {
            try? await Task.sleep(for: .seconds(3))
            if Task.isCancelled { return }
            guard let refreshed = try? await client.quickConnectState(secret: secret) else { continue }
            if refreshed.authenticated == true {
                _ = await session.completeQuickConnect(secret: secret)
                return
            }
        }
        quickConnectCode = nil
        quickConnectFailed = true
    }
}
