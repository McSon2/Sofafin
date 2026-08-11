import Foundation

/// Amorce le téléchargement d'une affiche avant que sa vignette n'entre à l'écran.
///
/// Une pile paresseuse construit ses vues **en avance** sur le défilement : c'est
/// sa fenêtre de préchargement, et c'est là que le travail asynchrone doit
/// démarrer. `AsyncImage`, lui, n'émet sa requête qu'une fois la vue réellement
/// apparue — la fenêtre est donc perdue, et chaque affiche arrive avec un
/// aller-retour réseau de retard. Sur une bibliothèque de trois cents titres
/// parcourue à vive allure, cela se voit.
///
/// On n'écrit pas pour autant un chargeur d'images maison : `RemoteImage` continue
/// de s'appuyer sur `AsyncImage`, qui sait décoder, animer et libérer sa mémoire
/// sous pression. Seule la **requête réseau** est avancée. Elle remplit
/// `URLCache.shared` — le cache d'un gigaoctet installé au lancement — dans lequel
/// `AsyncImage` puise ensuite sans repartir sur le réseau.
actor ImagePrefetcher {
    static let shared = ImagePrefetcher()

    /// Requêtes en vol, pour ne pas télécharger deux fois la même affiche quand
    /// plusieurs rangées l'affichent.
    private var inFlight: Set<URL> = []
    /// Déjà obtenues : évite de retourner interroger le cache disque à chaque
    /// réévaluation d'une vue, ce qui arrive des centaines de fois par défilement.
    private var completed: Set<URL> = []

    /// Au-delà, on repart de zéro : une session longue finirait sinon par retenir
    /// l'adresse de toute la médiathèque.
    private static let memoryLimit = 4000

    /// Plafond de requêtes simultanées.
    ///
    /// **Les affiches et la vidéo viennent du même serveur.** Sans plafond, parcourir
    /// une bibliothèque lance des dizaines de téléchargements qui restent en vol, et
    /// Jellyfin — occupé à remuxer un flux en parallèle — ne délivre plus les segments
    /// à temps : la lecture se fige sur son indicateur de chargement, avec le son qui
    /// continue puisqu'il est déjà tamponné. Un préchargement est un confort, jamais
    /// une raison d'affamer la lecture.
    private static let maxConcurrent = 3

    private var active = 0
    private var isSuspended = false

    /// Coupe le préchargement pendant une lecture : la bande passante appartient
    /// alors entièrement au flux vidéo.
    nonisolated func setSuspended(_ suspended: Bool) {
        Task { await apply(suspended: suspended) }
    }

    private func apply(suspended: Bool) {
        isSuspended = suspended
    }

    /// Appelable depuis n'importe où — typiquement l'`init` d'une vue, seul endroit
    /// exécuté pendant le préchargement d'une pile paresseuse.
    nonisolated func prefetch(_ url: URL?) {
        guard let url else { return }
        Task(priority: .utility) { await load(url) }
    }

    private func load(_ url: URL) async {
        // Rien n'est mis en file d'attente : une demande qui arrive alors que le
        // plafond est atteint est simplement abandonnée. Le préchargement est
        // opportuniste — `AsyncImage` chargera l'affiche à son apparition, comme
        // avant. Une file, elle, ne ferait que différer la saturation.
        guard !isSuspended, active < Self.maxConcurrent else { return }
        guard !completed.contains(url), !inFlight.contains(url) else { return }

        inFlight.insert(url)
        active += 1
        defer {
            inFlight.remove(url)
            active -= 1
        }

        let request = URLRequest(url: url)
        // Le cache disque a déjà la réponse : la requête n'apprendrait rien.
        if URLCache.shared.cachedResponse(for: request) == nil {
            guard (try? await URLSession.shared.data(for: request)) != nil else { return }
        }

        if completed.count >= Self.memoryLimit { completed.removeAll() }
        completed.insert(url)
    }
}
