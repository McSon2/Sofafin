import AVKit
import Combine
import SwiftUI
import UIKit

/// Panneau de fin d'épisode : ce qui vient ensuite, et combien de temps il reste
/// avant que le lecteur enchaîne tout seul.
///
/// AVKit fournit toute la mécanique — apparition au bon moment, compte à rebours,
/// acceptation automatique, retour au délégué. On n'écrit que l'apparence, et on
/// laisse le système décider *quand* présenter.
final class NextEpisodeProposalViewController: AVContentProposalViewController {

    /// Délai avant l'enchaînement, décompté **depuis l'apparition de la carte**.
    ///
    /// `automaticAcceptanceInterval` ne convient pas seul : AVKit ne le décompte
    /// qu'à partir de la fin réelle du média, alors que la carte s'affiche dès le
    /// début du générique. Sur un générique d'une minute et demie, l'attente
    /// perçue était donc la somme des deux — près de deux minutes.
    static let acceptanceDelay: TimeInterval = 15

    private var host: UIHostingController<NextEpisodeCard>?
    private var acceptanceTimer: Task<Void, Never>?
    /// Contraintes actives, gardées pour pouvoir passer du repli au guide d'AVKit.
    private var placement: [NSLayoutConstraint] = []
    private var isPinnedToPlayerGuide = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear

        let card = NextEpisodeCard(
            title: "",
            previewImage: nil,
            subtitle: nil,
            // Le VC ne connaît sa date d'acceptation qu'une fois présenté, et elle
            // peut être annulée en cours de route : la carte la relit à chaque
            // battement plutôt que d'en garder une copie périmée.
            deadline: { [weak self] in self?.dateOfAutomaticAcceptance },
            onAccept: { [weak self] in self?.finish(.accept) },
            onDefer: { [weak self] in self?.finish(.defer) },
            onReject: { [weak self] in self?.finish(.reject) }
        )

        let host = UIHostingController(rootView: card)
        host.view.backgroundColor = .clear
        addChild(host)
        view.addSubview(host.view)
        host.view.translatesAutoresizingMaskIntoConstraints = false

        host.didMove(toParent: self)
        self.host = host

        // Repli sur notre propre vue. `playerLayoutGuide` serait le bon repère —
        // il cale le panneau sur l'image plutôt que sur l'écran — mais il n'est
        // **rattaché à aucune vue** tant qu'AVKit n'a pas présenté ce contrôleur.
        // S'y contraindre ici lève « no common ancestor » et fait tomber
        // l'application, à la fin du premier épisode ayant une suite. On pose donc
        // d'abord des ancres toujours valides, puis on bascule sur le guide dès
        // qu'il rejoint la hiérarchie — voir `pinToPlayerGuideIfPossible`.
        pin(host.view, to: view)
    }

    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        pinToPlayerGuideIfPossible()
    }

    /// Bascule le panneau sur le repère d'AVKit, une fois et seulement s'il est
    /// réellement utilisable.
    private func pinToPlayerGuideIfPossible() {
        guard !isPinnedToPlayerGuide, let hostView = host?.view else { return }
        // Deux ancres ne peuvent être liées que si leurs vues partagent une racine.
        // AVKit ne promet nulle part quand il rattache ce guide : on vérifie plutôt
        // que de supposer.
        guard let owner = playerLayoutGuide.owningView,
              owner.rootAncestor === hostView.rootAncestor
        else { return }

        isPinnedToPlayerGuide = true
        NSLayoutConstraint.deactivate(placement)
        pin(hostView, toGuide: playerLayoutGuide)
    }

    private func pin(_ subject: UIView, to container: UIView) {
        placement = [
            subject.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            subject.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            subject.topAnchor.constraint(equalTo: container.topAnchor),
            subject.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ]
        NSLayoutConstraint.activate(placement)
    }

    private func pin(_ subject: UIView, toGuide guide: UILayoutGuide) {
        placement = [
            subject.leadingAnchor.constraint(equalTo: guide.leadingAnchor),
            subject.trailingAnchor.constraint(equalTo: guide.trailingAnchor),
            subject.topAnchor.constraint(equalTo: guide.topAnchor),
            subject.bottomAnchor.constraint(equalTo: guide.bottomAnchor)
        ]
        NSLayoutConstraint.activate(placement)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        guard let proposal = contentProposal else { return }
        host?.rootView.title = proposal.title
        host?.rootView.previewImage = proposal.previewImage
        // Le sous-titre arrive après coup : lire une métadonnée est asynchrone
        // depuis tvOS 16, une valeur pouvant en principe demander un accès au
        // média. Celle-ci est déjà en mémoire — c'est nous qui l'avons écrite dans
        // `PlaybackEngine.metadata(for:)` — donc la carte n'attend qu'un tour de
        // boucle, et son libellé principal est déjà posé.
        Task { [weak self] in
            self?.host?.rootView.subtitle = await Self.subtitle(from: proposal)
        }

        startAcceptanceCountdown()
    }

    /// Fixe l'échéance au moment où la carte se montre, et l'honore nous-mêmes.
    ///
    /// Poser `dateOfAutomaticAcceptance` suffit à ce que le décompte affiché soit
    /// juste — la carte relit cette date à chaque battement. Mais c'est AVKit qui
    /// déciderait d'accepter, et seulement une fois le média terminé : la minuterie
    /// ci-dessous garantit l'enchaînement au bout du délai, générique en cours ou
    /// non. Le premier des deux mécanismes qui aboutit l'emporte, et tous deux
    /// visent la même durée.
    private func startAcceptanceCountdown() {
        dateOfAutomaticAcceptance = Date().addingTimeInterval(Self.acceptanceDelay)

        acceptanceTimer?.cancel()
        acceptanceTimer = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.acceptanceDelay))
            guard !Task.isCancelled else { return }
            self?.finish(.accept)
        }
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        // La carte peut disparaître sans passer par `finish` — l'utilisateur quitte
        // le lecteur, par exemple. Une minuterie laissée armée enchaînerait alors
        // sur l'épisode suivant après coup.
        acceptanceTimer?.cancel()
        acceptanceTimer = nil
    }

    private func finish(_ action: AVContentProposalAction) {
        // Annuler l'acceptation automatique avant de sortir : sans cela le
        // compte à rebours resterait armé derrière une vue déjà partie.
        acceptanceTimer?.cancel()
        acceptanceTimer = nil
        dateOfAutomaticAcceptance = nil
        dismissContentProposal(for: action, animated: true, completion: nil)
    }

    /// La proposition transporte les métadonnées de l'épisode : on y récupère le
    /// « Série · S02E05 » sans avoir à repasser par le moteur.
    private static func subtitle(from proposal: AVContentProposal) async -> String? {
        guard let item = proposal.metadata.first(where: { $0.identifier == .iTunesMetadataTrackSubTitle })
        else { return nil }
        return try? await item.load(.stringValue)
    }
}

private extension UIView {
    /// Vue la plus haute de la hiérarchie. Deux vues ne peuvent être contraintes
    /// l'une à l'autre que si elles partagent cette racine.
    var rootAncestor: UIView {
        superview?.rootAncestor ?? self
    }
}

// MARK: - Apparence

private struct NextEpisodeCard: View {
    var title: String
    var previewImage: UIImage?
    var subtitle: String?

    let deadline: () -> Date?
    let onAccept: () -> Void
    let onDefer: () -> Void
    let onReject: () -> Void

    @State private var remaining: Int?
    @FocusState private var isPlayFocused: Bool

    /// Un battement par seconde suffit pour un décompte, et évite de réveiller
    /// SwiftUI en continu pendant que le générique défile.
    private let tick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading) {
            Spacer()
            HStack(alignment: .bottom, spacing: 40) {
                preview
                details
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Theme.Metrics.screenPadding)
            .padding(.bottom, 90)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        .background(LinearGradient.heroScrim.ignoresSafeArea())
        .onReceive(tick) { _ in updateRemaining() }
        .onAppear {
            updateRemaining()
            isPlayFocused = true
        }
    }

    @ViewBuilder
    private var preview: some View {
        if let previewImage {
            Image(uiImage: previewImage)
                .resizable()
                .aspectRatio(16 / 9, contentMode: .fill)
                .frame(width: 440, height: 248)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Metrics.cornerRadius, style: .continuous))
                .shadow(color: .black.opacity(0.55), radius: 24, y: 12)
        }
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(headline)
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.Palette.accentBright)

            Text(title)
                .font(Theme.Font.sectionTitle)
                .foregroundStyle(Theme.Palette.primaryText)
                .lineLimit(2)

            if let subtitle {
                Text(subtitle)
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Palette.secondaryText)
            }

            HStack(spacing: 18) {
                Button(action: onAccept) {
                    Label("Lire maintenant", systemImage: "play.fill")
                        .padding(.horizontal, 14)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.glassProminent)
                .focused($isPlayFocused)
                .accessibilityHint("Passe à \(title)")

                Button("Rester ici", action: onDefer)
                    .buttonStyle(.glass)
                    .accessibilityHint("Annule l'enchaînement automatique")

                Button("Quitter", action: onReject)
                    .buttonStyle(.glass)
                    .accessibilityHint("Ferme le lecteur")
            }
            .font(Theme.Font.button)
            .padding(.top, 6)
        }
        .frame(maxWidth: 900, alignment: .leading)
    }

    private var headline: String {
        guard let remaining, remaining > 0 else { return "À suivre" }
        return "Épisode suivant dans \(remaining) s"
    }

    private func updateRemaining() {
        guard let date = deadline() else {
            remaining = nil
            return
        }
        remaining = max(0, Int(date.timeIntervalSinceNow.rounded()))
    }
}
