// swda — reimplementación moderna (macOS 13+, Apple Silicon e Intel) del CLI de SwiftDefaultApps.
// Comandos compatibles con el original: getSchemes, getUTIs, getApps, getHandler, setHandler.

import DefaultAppsCore
import Foundation
import UniformTypeIdentifiers

let version = "3.0.0"

// MARK: - Salida y errores

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("swda ERROR: \(message)\n".utf8))
    exit(1)
}

func attempt<T>(_ body: () throws -> T) -> T {
    do { return try body() } catch { fail(error.localizedDescription) }
}

func printUsage() {
    print("""
    swda \(version) — Utilidad para consultar y cambiar las aplicaciones por defecto en macOS.

    Uso:
      swda getSchemes                       Lista los esquemas de URL conocidos y su app por defecto.
      swda getUTIs                          Lista los UTIs conocidos y su app por defecto.
      swda getApps                          Lista las aplicaciones registradas en LaunchServices.
      swda getHandler <tipo> [--role R] [--all]
                                            Muestra la app por defecto (o todas las posibles con --all).
      swda setHandler <tipo> --app <app> [--role R]
                                            Establece <app> como app por defecto.

    <tipo> es uno de:
      --URL <esquema>        p. ej. --URL mailto
      --UTI <uti>            p. ej. --UTI public.plain-text
      --ext <extensión>      p. ej. --ext md (se convierte al UTI correspondiente)
      --browser | --internet | --web   (http y https)
      --mail | --email | --e-mail      (mailto)
      --ftp | --rss | --news

    <app> puede ser un nombre ("Visual Studio Code"), un bundle id (com.microsoft.VSCode)
    o una ruta a un .app.

    --role <Viewer|Editor|Shell|All>   Solo para UTIs. Por defecto: All.
    """)
}

// MARK: - Argumentos

struct Args {
    var command: String
    var schemes: [String] = []
    var uti: String?
    var app: String?
    var role: Role = .all
    var all = false
}

func parseArgs(_ argv: [String]) -> Args {
    guard let command = argv.first else { printUsage(); exit(0) }
    if ["-h", "--help", "help"].contains(command) { printUsage(); exit(0) }
    if ["-v", "--version", "version"].contains(command) { print(version); exit(0) }

    var args = Args(command: command)
    var i = 1
    func value(_ flag: String) -> String {
        i += 1
        guard i < argv.count else { fail("\(flag) requiere un valor.") }
        return argv[i]
    }
    while i < argv.count {
        let flag = argv[i]
        switch flag.lowercased() {
        case "--url": args.schemes = [value(flag).trimmingCharacters(in: CharacterSet(charactersIn: ":/"))]
        case "--uti": args.uti = value(flag)
        case "--ext":
            let ext = value(flag).trimmingCharacters(in: CharacterSet(charactersIn: "."))
            guard let type = UTType(filenameExtension: ext) else { fail("No se encontró un UTI para la extensión .\(ext)") }
            args.uti = type.identifier
        case "--browser", "--internet", "--web": args.schemes = ["http", "https"]
        case "--mail", "--email", "--e-mail": args.schemes = ["mailto"]
        case "--ftp": args.schemes = ["ftp"]
        case "--rss": args.schemes = ["feed"]
        case "--news": args.schemes = ["news"]
        case "--app", "--application": args.app = value(flag)
        case "--role":
            let name = value(flag)
            guard let role = Role(name: name) else { fail("Rol inválido: \(name). Usa Viewer, Editor, Shell o All.") }
            args.role = role
        case "--all": args.all = true
        case "-h", "--help": printUsage(); exit(0)
        default: fail("Opción desconocida: \(flag). Usa `swda --help`.")
        }
        i += 1
    }
    return args
}

/// Ejecuta una operación asíncrona de LaunchServices y espera su resultado.
func waitFor(_ body: (@escaping (Error?) -> Void) -> Void) -> Error? {
    var result: Error?
    var done = false
    body { error in result = error; done = true }
    while !done { RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.05)) }
    return result
}

// MARK: - Comandos

func getHandler(_ args: Args) {
    if let uti = args.uti {
        if args.all {
            LaunchServices.candidates(forUTI: uti, role: args.role).forEach { print(LaunchServices.display($0)) }
        } else {
            print(LaunchServices.display(LaunchServices.defaultApp(forUTI: uti, role: args.role)))
        }
        return
    }
    guard !args.schemes.isEmpty else { fail("getHandler necesita --URL, --UTI, --ext o un atajo como --browser.") }
    for scheme in args.schemes {
        if args.all {
            print("\(scheme):")
            LaunchServices.candidates(forScheme: scheme).forEach { print("  \(LaunchServices.display($0))") }
        } else {
            let app = LaunchServices.display(LaunchServices.defaultApp(forScheme: scheme))
            print(args.schemes.count > 1 ? "\(scheme)\t\(app)" : app)
        }
    }
}

func setHandler(_ args: Args) {
    guard let query = args.app else { fail("setHandler necesita --app <aplicación>.") }
    if query.caseInsensitiveCompare("None") == .orderedSame {
        fail("\"None\" ya no está soportado: macOS moderno no permite dejar un tipo sin aplicación.")
    }
    let appURL = attempt { try LaunchServices.resolveApp(query) }

    if let uti = args.uti {
        if let error = waitFor({ LaunchServices.setDefault(app: appURL, forUTI: uti, role: args.role, completion: $0) }) {
            fail("No se pudo cambiar el handler de \(uti): \(error.localizedDescription)")
        }
        print("El handler por defecto de \(uti) ahora es \(LaunchServices.display(LaunchServices.defaultApp(forUTI: uti, role: args.role))).")
        return
    }

    guard !args.schemes.isEmpty else { fail("setHandler necesita --URL, --UTI, --ext o un atajo como --browser.") }
    for scheme in args.schemes {
        if let error = waitFor({ LaunchServices.setDefault(app: appURL, forScheme: scheme, completion: $0) }) {
            fail("No se pudo cambiar el handler de \(scheme): \(error.localizedDescription)")
        }
        print("El handler por defecto de \(scheme) ahora es \(LaunchServices.display(LaunchServices.defaultApp(forScheme: scheme))).")
    }
}

// MARK: - Main

let args = parseArgs(Array(CommandLine.arguments.dropFirst()))
switch args.command.lowercased() {
case "getschemes":
    for scheme in attempt({ try LaunchServices.catalog() }).schemes {
        print("\(scheme)\t\(LaunchServices.display(LaunchServices.defaultApp(forScheme: scheme)))")
    }
case "getutis":
    for uti in attempt({ try LaunchServices.catalog() }).utis {
        print("\(uti)\t\(LaunchServices.display(LaunchServices.defaultApp(forUTI: uti)))")
    }
case "getapps":
    for url in attempt({ try LaunchServices.catalog() }).apps {
        print("\(LaunchServices.display(url))\t\(url.path)")
    }
case "gethandler": getHandler(args)
case "sethandler": setHandler(args)
default: fail("Comando desconocido: \(args.command). Usa `swda --help`.")
}
