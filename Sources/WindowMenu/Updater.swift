import AppKit
import Security

/// Actualizaciones desde las releases de GitHub: busca la última, descarga el zip, comprueba que
/// está firmada con el mismo certificado que la app actual y la sustituye.
@MainActor
final class Updater {

    struct Release {
        let version: String
        let zipURL: URL
    }

    enum UpdateError: LocalizedError {
        case badResponse
        case missingAsset
        case badSignature
        case unzipFailed

        var errorDescription: String? {
            switch self {
            case .badResponse: return "GitHub no ha devuelto la última versión."
            case .missingAsset: return "La última versión no incluye \(Updater.assetName)."
            case .badSignature: return "La nueva versión no está firmada con el mismo certificado que la actual."
            case .unzipFailed: return "No se ha podido descomprimir la nueva versión."
            }
        }
    }

    nonisolated static let assetName = "WindowMenu.zip"
    private let latestURL = URL(string: "https://api.github.com/repos/escorponox/WindowMenu/releases/latest")!

    /// Versión más nueva encontrada en la última comprobación.
    private(set) var available: Release?

    var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    /// Consulta la última release y guarda en `available` si es más nueva que la actual.
    func check() async throws -> Release? {
        var request = URLRequest(url: latestURL)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw UpdateError.badResponse }

        let latest = try JSONDecoder().decode(GitHubRelease.self, from: data)
        let version = latest.tag_name.hasPrefix("v") ? String(latest.tag_name.dropFirst()) : latest.tag_name
        guard Self.isVersion(version, newerThan: currentVersion) else { available = nil; return nil }
        guard let asset = latest.assets.first(where: { $0.name == Self.assetName }) else { throw UpdateError.missingAsset }

        available = Release(version: version, zipURL: asset.browser_download_url)
        return available
    }

    /// Descarga la release, sustituye la app actual por la nueva y la reinicia.
    func install(_ release: Release) async throws {
        let (zip, _) = try await URLSession.shared.download(from: release.zipURL)
        defer { try? FileManager.default.removeItem(at: zip) }

        let current = Bundle.main.bundleURL
        // Carpeta temporal en el mismo volumen que la app, para que la sustitución sea atómica.
        let staging = try FileManager.default.url(for: .itemReplacementDirectory, in: .userDomainMask,
                                                  appropriateFor: current, create: true)
        defer { try? FileManager.default.removeItem(at: staging) }

        let unzip = try Process.run(URL(fileURLWithPath: "/usr/bin/ditto"), arguments: ["-x", "-k", zip.path, staging.path])
        unzip.waitUntilExit()
        let newApp = staging.appendingPathComponent(current.lastPathComponent)
        guard unzip.terminationStatus == 0, FileManager.default.fileExists(atPath: newApp.path) else {
            throw UpdateError.unzipFailed
        }

        try verifySignature(of: newApp)
        _ = try FileManager.default.replaceItemAt(current, withItemAt: newApp)

        // Abre la nueva versión cuando esta ya se haya cerrado.
        try Process.run(URL(fileURLWithPath: "/bin/sh"), arguments: ["-c", "sleep 1; open \"$0\"", current.path])
        NSApp.terminate(nil)
    }

    /// La nueva app debe cumplir el designated requirement de la actual (mismo identificador y certificado).
    /// Así no se instala nada firmado por otro, y macOS conserva el permiso de Accesibilidad.
    private func verifySignature(of app: URL) throws {
        var me: SecCode?
        var meStatic: SecStaticCode?
        var requirement: SecRequirement?
        var newCode: SecStaticCode?
        guard SecCodeCopySelf([], &me) == errSecSuccess, let me,
              SecCodeCopyStaticCode(me, [], &meStatic) == errSecSuccess, let meStatic,
              SecCodeCopyDesignatedRequirement(meStatic, [], &requirement) == errSecSuccess, let requirement,
              SecStaticCodeCreateWithPath(app as CFURL, [], &newCode) == errSecSuccess, let newCode,
              SecStaticCodeCheckValidity(newCode, SecCSFlags(rawValue: kSecCSStrictValidate), requirement) == errSecSuccess
        else { throw UpdateError.badSignature }
    }

    /// Compara versiones tipo "1.10.2" número a número.
    static func isVersion(_ a: String, newerThan b: String) -> Bool {
        let pa = a.split(separator: ".").map { Int($0) ?? 0 }
        let pb = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(pa.count, pb.count) {
            let x = i < pa.count ? pa[i] : 0
            let y = i < pb.count ? pb[i] : 0
            if x != y { return x > y }
        }
        return false
    }

    private struct GitHubRelease: Decodable {
        struct Asset: Decodable {
            let name: String
            let browser_download_url: URL
        }
        let tag_name: String
        let assets: [Asset]
    }
}
