// Shared logic for the CLI (swda) and the app (SwiftDefaultApps) to query
// and change default applications through LaunchServices.

import AppKit
import CoreServices
import Foundation
import UniformTypeIdentifiers

public struct DefaultAppsError: LocalizedError {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var errorDescription: String? { message }
}

public enum Role: String, CaseIterable, Identifiable {
    case all = "All", viewer = "Viewer", editor = "Editor", shell = "Shell"

    public var id: String { rawValue }

    public init?(name: String) {
        guard let role = Role.allCases.first(where: { $0.rawValue.caseInsensitiveCompare(name) == .orderedSame }) else { return nil }
        self = role
    }

    public var mask: LSRolesMask {
        switch self {
        case .all: return .all
        case .viewer: return .viewer
        case .editor: return .editor
        case .shell: return .shell
        }
    }
}

public enum LaunchServices {
    public static let lsregisterPath = "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

    // MARK: Names

    public static func appName(_ url: URL) -> String {
        url.deletingPathExtension().lastPathComponent
    }

    public static func bundleID(_ url: URL) -> String? {
        Bundle(url: url)?.bundleIdentifier
    }

    public static func display(_ url: URL?) -> String {
        guard let url else { return "No application set" }
        return "\(appName(url)) (\(bundleID(url) ?? "?"))"
    }

    /// Human-readable description of a UTI, e.g. "Markdown Document (.md)".
    public static func describe(uti: String) -> String {
        guard let type = UTType(uti) else { return "" }
        let description = type.localizedDescription ?? ""
        guard let ext = type.preferredFilenameExtension else { return description }
        return description.isEmpty ? ".\(ext)" : "\(description) (.\(ext))"
    }

    // MARK: Catalog (lsregister dump)

    public struct Catalog {
        public let schemes: [String]
        public let utis: [String]
        public let apps: [URL]
    }

    public static func catalog() throws -> Catalog {
        let dump = try lsregisterDump()
        return Catalog(schemes: schemes(in: dump), utis: utis(in: dump), apps: apps(in: dump))
    }

    static func lsregisterDump() throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: lsregisterPath)
        process.arguments = ["-dump"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch {
            throw DefaultAppsError("Could not run lsregister: \(error.localizedDescription)")
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(decoding: data, as: UTF8.self)
    }

    static func values(_ key: String, in dump: String) -> [String] {
        let prefix = key + ":"
        return dump.split(separator: "\n").compactMap { line in
            guard line.hasPrefix(prefix) else { return nil }
            return line.dropFirst(prefix.count).trimmingCharacters(in: .whitespaces)
        }
    }

    static func schemes(in dump: String) -> [String] {
        let schemes = values("claimed schemes", in: dump).flatMap { $0.split(separator: ",") }
            .map { $0.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: ":")) }
            .filter { $0.range(of: #"^[A-Za-z][A-Za-z0-9+.-]*$"#, options: .regularExpression) != nil }
        return Array(Set(schemes)).sorted()
    }

    static func utis(in dump: String) -> [String] {
        let declared = values("uti", in: dump)
        let claimed = values("bindings", in: dump).compactMap { $0.split(separator: ",").first.map(String.init) }
        let utis = (declared + claimed).map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix(".") && !$0.hasPrefix("'") && $0.contains(".") }
        return Array(Set(utis)).sorted()
    }

    static func apps(in dump: String) -> [URL] {
        let paths = values("path", in: dump)
            .map { $0.replacingOccurrences(of: #"\s+\(0x[0-9a-f]+\)$"#, with: "", options: .regularExpression) }
            .filter { $0.hasSuffix(".app") && FileManager.default.fileExists(atPath: $0) }
        return Array(Set(paths)).sorted().map { URL(fileURLWithPath: $0) }
    }

    // MARK: Queries

    public static func defaultApp(forScheme scheme: String) -> URL? {
        guard let url = URL(string: "\(scheme):") else { return nil }
        return NSWorkspace.shared.urlForApplication(toOpen: url)
    }

    public static func defaultApp(forUTI uti: String, role: Role = .all) -> URL? {
        if role == .all, let type = UTType(uti) {
            return NSWorkspace.shared.urlForApplication(toOpen: type)
        }
        // NSWorkspace doesn't expose roles; LaunchServices still resolves them.
        guard let id = LSCopyDefaultRoleHandlerForContentType(uti as CFString, role.mask)?.takeRetainedValue() as String? else { return nil }
        return NSWorkspace.shared.urlForApplication(withBundleIdentifier: id)
    }

    public static func candidates(forScheme scheme: String) -> [URL] {
        guard let url = URL(string: "\(scheme):") else { return [] }
        return NSWorkspace.shared.urlsForApplications(toOpen: url)
    }

    public static func candidates(forUTI uti: String, role: Role = .all) -> [URL] {
        if role == .all {
            guard let type = UTType(uti) else { return [] }
            return NSWorkspace.shared.urlsForApplications(toOpen: type)
        }
        let ids = LSCopyAllRoleHandlersForContentType(uti as CFString, role.mask)?.takeRetainedValue() as? [String] ?? []
        return ids.compactMap { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) }
    }

    /// Schemes and UTIs an app declares it can open in its Info.plist.
    public static func claims(of appURL: URL) -> (schemes: [String], utis: [String]) {
        guard let info = Bundle(url: appURL)?.infoDictionary else { return ([], []) }
        let urlTypes = info["CFBundleURLTypes"] as? [[String: Any]] ?? []
        let schemes = urlTypes.flatMap { $0["CFBundleURLSchemes"] as? [String] ?? [] }.map { $0.lowercased() }
        let docTypes = info["CFBundleDocumentTypes"] as? [[String: Any]] ?? []
        let byUTI = docTypes.flatMap { $0["LSItemContentTypes"] as? [String] ?? [] }
        let byExtension = docTypes.flatMap { $0["CFBundleTypeExtensions"] as? [String] ?? [] }
            .filter { $0 != "*" }
            .compactMap { UTType(filenameExtension: $0)?.identifier }
        let utis = (byUTI + byExtension).filter { !$0.hasPrefix("dyn.") }
        return (Array(Set(schemes)).sorted(), Array(Set(utis)).sorted())
    }

    /// Resolves a name, bundle ID, or path to the URL of a .app.
    public static func resolveApp(_ query: String) throws -> URL {
        let expanded = (query as NSString).expandingTildeInPath
        if expanded.hasSuffix(".app"), FileManager.default.fileExists(atPath: expanded) {
            return URL(fileURLWithPath: expanded)
        }
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: query) { return url }
        let name = query.hasSuffix(".app") ? String(query.dropLast(4)) : query
        let dirs = ["/Applications", "/System/Applications", "/System/Applications/Utilities",
                    "/Applications/Utilities", NSHomeDirectory() + "/Applications"]
        for dir in dirs {
            let path = "\(dir)/\(name).app"
            if FileManager.default.fileExists(atPath: path) { return URL(fileURLWithPath: path) }
        }
        if let match = try catalog().apps.first(where: { appName($0).caseInsensitiveCompare(name) == .orderedSame }) {
            return match
        }
        throw DefaultAppsError("Application \"\(query)\" not found.")
    }

    // MARK: Changes

    /// For http/https, macOS asks the user to confirm in a system dialog.
    public static func setDefault(app: URL, forScheme scheme: String, completion: @escaping (Error?) -> Void) {
        NSWorkspace.shared.setDefaultApplication(at: app, toOpenURLsWithScheme: scheme, completion: completion)
    }

    public static func setDefault(app: URL, forUTI uti: String, role: Role = .all, completion: @escaping (Error?) -> Void) {
        guard let type = UTType(uti) else { return completion(DefaultAppsError("\(uti) is not a valid UTI.")) }
        if role == .all {
            NSWorkspace.shared.setDefaultApplication(at: app, toOpen: type, completion: completion)
            return
        }
        guard let id = bundleID(app) else { return completion(DefaultAppsError("The app has no bundle identifier.")) }
        let status = LSSetDefaultRoleHandlerForContentType(uti as CFString, role.mask, id as CFString)
        completion(status == noErr ? nil : DefaultAppsError("LaunchServices returned error \(status) for \(uti)."))
    }

    public static func setDefault(app: URL, forScheme scheme: String) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            setDefault(app: app, forScheme: scheme) { error in
                if let error { continuation.resume(throwing: error) } else { continuation.resume() }
            }
        }
    }

    public static func setDefault(app: URL, forUTI uti: String, role: Role = .all) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            setDefault(app: app, forUTI: uti, role: role) { error in
                if let error { continuation.resume(throwing: error) } else { continuation.resume() }
            }
        }
    }
}
