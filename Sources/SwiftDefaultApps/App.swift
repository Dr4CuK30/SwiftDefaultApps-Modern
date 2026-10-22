// SwiftDefaultApps — app independiente (reemplazo del antiguo .prefPane) para ver y cambiar
// las aplicaciones por defecto de esquemas de URL y tipos de archivo.

import AppKit
import DefaultAppsCore
import SwiftUI
import UniformTypeIdentifiers

@main
struct SwiftDefaultAppsApp: App {
    @StateObject private var model = Model()

    var body: some Scene {
        WindowGroup("SwiftDefaultApps") {
            ContentView()
                .environmentObject(model)
                .frame(minWidth: 960, minHeight: 560)
                .task { await model.load() }
        }
    }
}

// MARK: - Modelo

enum Pane: String, CaseIterable, Identifiable {
    case schemes = "Esquemas de URL"
    case types = "Tipos de archivo"
    case apps = "Aplicaciones"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .schemes: return "link"
        case .types: return "doc"
        case .apps: return "square.grid.2x2"
        }
    }
}

struct Entry: Identifiable, Hashable {
    let id: String
    let detail: String
    var defaultApp: URL?
}

@MainActor
final class Model: ObservableObject {
    @Published var schemes: [Entry] = []
    @Published var types: [Entry] = []
    @Published var apps: [URL] = []
    @Published var isLoading = false
    @Published var loadError: String?

    func load() async {
        isLoading = true
        loadError = nil
        do {
            let (schemes, types, apps) = try await Task.detached(priority: .userInitiated) {
                let catalog = try LaunchServices.catalog()
                let schemes = catalog.schemes.map {
                    Entry(id: $0, detail: "", defaultApp: LaunchServices.defaultApp(forScheme: $0))
                }
                let types = catalog.utis.map {
                    Entry(id: $0, detail: LaunchServices.describe(uti: $0), defaultApp: LaunchServices.defaultApp(forUTI: $0))
                }
                return (schemes, types, catalog.apps)
            }.value
            self.schemes = schemes
            self.types = types
            self.apps = apps
        } catch {
            loadError = error.localizedDescription
        }
        isLoading = false
    }

    func refresh(_ kind: HandlerKind) {
        switch kind {
        case .scheme(let scheme):
            if let i = schemes.firstIndex(where: { $0.id == scheme }) {
                schemes[i].defaultApp = LaunchServices.defaultApp(forScheme: scheme)
            }
        case .uti(let uti):
            if let i = types.firstIndex(where: { $0.id == uti }) {
                types[i].defaultApp = LaunchServices.defaultApp(forUTI: uti)
            }
        }
    }
}

enum HandlerKind: Hashable {
    case scheme(String)
    case uti(String)

    var name: String {
        switch self {
        case .scheme(let scheme): return scheme
        case .uti(let uti): return uti
        }
    }

    var detail: String {
        switch self {
        case .scheme: return ""
        case .uti(let uti): return LaunchServices.describe(uti: uti)
        }
    }

    func defaultApp(role: Role = .all) -> URL? {
        switch self {
        case .scheme(let scheme): return LaunchServices.defaultApp(forScheme: scheme)
        case .uti(let uti): return LaunchServices.defaultApp(forUTI: uti, role: role)
        }
    }

    func candidates(role: Role = .all) -> [URL] {
        switch self {
        case .scheme(let scheme): return LaunchServices.candidates(forScheme: scheme)
        case .uti(let uti): return LaunchServices.candidates(forUTI: uti, role: role)
        }
    }

    func setDefault(_ app: URL, role: Role = .all) async throws {
        switch self {
        case .scheme(let scheme): try await LaunchServices.setDefault(app: app, forScheme: scheme)
        case .uti(let uti): try await LaunchServices.setDefault(app: app, forUTI: uti, role: role)
        }
    }
}

func roleName(_ role: Role) -> String {
    switch role {
    case .all: return "Todos"
    case .viewer: return "Visor"
    case .editor: return "Editor"
    case .shell: return "Shell"
    }
}

// MARK: - Vistas

struct ContentView: View {
    @EnvironmentObject private var model: Model
    @State private var pane: Pane? = .schemes
    @State private var selection: String?
    @State private var search = ""

    var body: some View {
        NavigationSplitView {
            List(Pane.allCases, selection: $pane) { pane in
                Label(pane.rawValue, systemImage: pane.symbol).tag(pane)
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200)
        } content: {
            Group {
                if model.isLoading {
                    ProgressView("Leyendo LaunchServices…")
                } else if let error = model.loadError {
                    Text(error).foregroundStyle(.red).padding()
                } else {
                    itemList
                }
            }
            .navigationSplitViewColumnWidth(min: 320, ideal: 400)
            .searchable(text: $search, prompt: "Buscar")
        } detail: {
            detail
        }
        .onChange(of: pane) { _ in
            selection = nil
            search = ""
        }
        .toolbar {
            Button {
                Task { await model.load() }
            } label: {
                Label("Recargar", systemImage: "arrow.clockwise")
            }
            .disabled(model.isLoading)
        }
    }

    @ViewBuilder private var itemList: some View {
        switch pane ?? .schemes {
        case .schemes: EntryList(entries: filter(model.schemes), selection: $selection)
        case .types: EntryList(entries: filter(model.types), selection: $selection)
        case .apps:
            List(filteredApps, id: \.path, selection: $selection) { url in
                HStack {
                    AppIcon(url: url, size: 24)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(LaunchServices.appName(url)).lineLimit(1)
                        Text(LaunchServices.bundleID(url) ?? "").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
            }
        }
    }

    @ViewBuilder private var detail: some View {
        if let selection {
            switch pane ?? .schemes {
            case .schemes: HandlerDetail(kind: .scheme(selection)).id(selection)
            case .types: HandlerDetail(kind: .uti(selection)).id(selection)
            case .apps: AppDetail(appURL: URL(fileURLWithPath: selection)).id(selection)
            }
        } else {
            Text("Selecciona un elemento de la lista").foregroundStyle(.secondary)
        }
    }

    private func filter(_ entries: [Entry]) -> [Entry] {
        guard !search.isEmpty else { return entries }
        return entries.filter {
            $0.id.localizedCaseInsensitiveContains(search)
                || $0.detail.localizedCaseInsensitiveContains(search)
                || ($0.defaultApp.map { LaunchServices.appName($0).localizedCaseInsensitiveContains(search) } ?? false)
        }
    }

    private var filteredApps: [URL] {
        guard !search.isEmpty else { return model.apps }
        return model.apps.filter {
            LaunchServices.appName($0).localizedCaseInsensitiveContains(search)
                || (LaunchServices.bundleID($0)?.localizedCaseInsensitiveContains(search) ?? false)
        }
    }
}

struct EntryList: View {
    let entries: [Entry]
    @Binding var selection: String?

    var body: some View {
        List(entries, selection: $selection) { entry in
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.id).font(.body.monospaced()).lineLimit(1)
                    if !entry.detail.isEmpty {
                        Text(entry.detail).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                Spacer()
                if let app = entry.defaultApp {
                    AppIcon(url: app, size: 16)
                    Text(LaunchServices.appName(app)).foregroundStyle(.secondary).lineLimit(1)
                } else {
                    Text("Sin app").foregroundStyle(.tertiary)
                }
            }
        }
    }
}

struct AppIcon: View {
    let url: URL
    let size: CGFloat

    var body: some View {
        Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
            .resizable()
            .frame(width: size, height: size)
    }
}

struct StatusMessage {
    let ok: Bool
    let text: String
}

struct StatusRow: View {
    let status: StatusMessage

    var body: some View {
        Label(status.text, systemImage: status.ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
            .foregroundStyle(status.ok ? .green : .red)
    }
}

/// Detalle de un esquema de URL o un UTI: permite elegir su app por defecto.
struct HandlerDetail: View {
    let kind: HandlerKind
    @EnvironmentObject private var model: Model
    @State private var role: Role = .all
    @State private var candidates: [String] = []
    @State private var current: String?
    @State private var selected: String?
    @State private var status: StatusMessage?
    @State private var busy = false

    private var isUTI: Bool {
        if case .uti = kind { return true }
        return false
    }

    /// Las rutas se usan como identidad para evitar diferencias de "/" final entre URLs.
    private var options: [String] {
        var list = candidates
        for path in [current, selected].compactMap({ $0 }) where !list.contains(path) {
            list.append(path)
        }
        return list
    }

    var body: some View {
        Form {
            Section {
                LabeledContent(isUTI ? "UTI" : "Esquema", value: kind.name)
                if !kind.detail.isEmpty {
                    LabeledContent("Descripción", value: kind.detail)
                }
            }
            Section("Aplicación por defecto") {
                if isUTI {
                    Picker("Rol", selection: $role) {
                        ForEach(Role.allCases) { Text(roleName($0)).tag($0) }
                    }
                }
                Picker("Abrir con", selection: $selected) {
                    if current == nil {
                        Text("Ninguna").tag(String?.none)
                    }
                    ForEach(options, id: \.self) { path in
                        Label {
                            Text(LaunchServices.appName(URL(fileURLWithPath: path)))
                        } icon: {
                            AppIcon(url: URL(fileURLWithPath: path), size: 16)
                        }
                        .tag(Optional(path))
                    }
                }
                .disabled(busy)
                HStack {
                    if busy { ProgressView().controlSize(.small) }
                    Spacer()
                    Button("Otra aplicación…", action: chooseOther).disabled(busy)
                }
            }
            if let status {
                Section { StatusRow(status: status) }
            }
            if case .scheme(let scheme) = kind, ["http", "https"].contains(scheme) {
                Section {
                    Text("Al cambiar el navegador, macOS te pedirá confirmar el cambio en un diálogo del sistema.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .task(id: role) { reload() }
        .onChange(of: selected) { newValue in
            guard let newValue, newValue != current else { return }
            apply(URL(fileURLWithPath: newValue))
        }
    }

    private func reload() {
        current = kind.defaultApp(role: role)?.path
        candidates = kind.candidates(role: role).map(\.path)
        selected = current
    }

    private func apply(_ app: URL) {
        busy = true
        status = nil
        Task {
            do {
                try await kind.setDefault(app, role: role)
                reload()
                model.refresh(kind)
                let name = LaunchServices.appName(app)
                status = current == app.path
                    ? StatusMessage(ok: true, text: "\(name) es ahora la app por defecto.")
                    : StatusMessage(ok: false, text: "macOS no aceptó el cambio: puede que \(name) no declare soporte para este tipo, o que se cancelara la confirmación.")
            } catch {
                reload()
                status = StatusMessage(ok: false, text: error.localizedDescription)
            }
            busy = false
        }
    }

    private func chooseOther() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.applicationBundle]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.prompt = "Elegir"
        if panel.runModal() == .OK, let url = panel.url {
            selected = url.path
        }
    }
}

/// Detalle de una aplicación: qué esquemas y tipos declara, y cuáles abre por defecto.
struct AppDetail: View {
    let appURL: URL
    @EnvironmentObject private var model: Model
    @State private var schemes: [HandlerKind] = []
    @State private var types: [HandlerKind] = []
    @State private var defaults: [HandlerKind: String] = [:]
    @State private var status: StatusMessage?
    @State private var busy = false

    var body: some View {
        Form {
            Section {
                HStack(spacing: 12) {
                    AppIcon(url: appURL, size: 48)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(LaunchServices.appName(appURL)).font(.title2.bold())
                        Text(LaunchServices.bundleID(appURL) ?? "Sin bundle identifier").foregroundStyle(.secondary)
                        Text(appURL.path).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                    }
                }
            }
            if let status {
                Section { StatusRow(status: status) }
            }
            Section("Esquemas de URL (\(schemes.count))") {
                if schemes.isEmpty { Text("Ninguno").foregroundStyle(.secondary) }
                ForEach(schemes, id: \.self, content: row)
            }
            Section("Tipos de archivo (\(types.count))") {
                if types.isEmpty { Text("Ninguno").foregroundStyle(.secondary) }
                ForEach(types, id: \.self, content: row)
            }
        }
        .formStyle(.grouped)
        .disabled(busy)
        .task { load() }
    }

    private func row(_ kind: HandlerKind) -> some View {
        let current = defaults[kind]
        return HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(kind.name).font(.body.monospaced()).lineLimit(1)
                if !kind.detail.isEmpty {
                    Text(kind.detail).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer()
            if current == appURL.path {
                Label("Por defecto", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
            } else {
                Text(current.map { LaunchServices.appName(URL(fileURLWithPath: $0)) } ?? "Sin app")
                    .foregroundStyle(.secondary).lineLimit(1)
                Button("Usar esta app") { apply(kind) }
            }
        }
    }

    private func load() {
        let claims = LaunchServices.claims(of: appURL)
        schemes = claims.schemes.map(HandlerKind.scheme)
        types = claims.utis.map(HandlerKind.uti)
        for kind in schemes + types {
            defaults[kind] = kind.defaultApp()?.path
        }
    }

    private func apply(_ kind: HandlerKind) {
        busy = true
        status = nil
        Task {
            do {
                try await kind.setDefault(appURL)
                defaults[kind] = kind.defaultApp()?.path
                model.refresh(kind)
                status = defaults[kind] == appURL.path
                    ? StatusMessage(ok: true, text: "\(LaunchServices.appName(appURL)) abre ahora \(kind.name).")
                    : StatusMessage(ok: false, text: "macOS no aceptó el cambio para \(kind.name).")
            } catch {
                status = StatusMessage(ok: false, text: error.localizedDescription)
            }
            busy = false
        }
    }
}
