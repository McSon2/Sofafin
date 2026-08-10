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

    private var host: UIHostingController<NextEpisodeCard>?

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

        // Le panneau se cale sur la vue vidéo plutôt que sur l'écran : c'est ce
        // que garantit `playerLayoutGuide`, quelle que soit la place que le
        // système laisse à l'image.
        NSLayoutConstraint.activate([
            host.view.leadingAnchor.constraint(equalTo: playerLayoutGuide.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: playerLayoutGuide.trailingAnchor),
            host.view.topAnchor.constraint(equalTo: playerLayoutGuide.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: playerLayoutGuide.bottomAnchor)
        ])
        host.didMove(toParent: self)
        self.host = host
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        guard let proposal = contentProposal else { return }
        host?.rootView.title = proposal.title
        host?.rootView.previewImage = proposal.previewImage
        host?.rootView.subtitle = Self.subtitle(from: proposal)
    }

    private func finish(_ action: AVContentProposalAction) {
        // Annuler l'acceptation automatique avant de sortir : sans cela le
        // compte à rebours resterait armé derrière une vue déjà partie.
        dateOfAutomaticAcceptance = nil
        dismissContentProposal(for: action, animated: true, completion: nil)
    }

    /// La proposition transporte les métadonnées de l'épisode : on y récupère le
    /// « Série · S02E05 » sans avoir à repasser par le moteur.
    private static func subtitle(from proposal: AVContentProposal) -> String? {
        proposal.metadata
            .first { $0.identifier == .iTunesMetadataTrackSubTitle }?
            .stringValue
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

                Button("Rester ici", action: onDefer)
                    .buttonStyle(.glass)

                Button("Quitter", action: onReject)
                    .buttonStyle(.glass)
            }
            .font(Theme.Font.cardTitle)
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
