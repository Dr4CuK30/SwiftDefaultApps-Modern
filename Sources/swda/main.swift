// swda — modern reimplementation (macOS 13+, Apple Silicon and Intel) of the SwiftDefaultApps CLI.
// Commands compatible with the original: getSchemes, getUTIs, getApps, getHandler, setHandler.

import DefaultAppsCore
import Foundation
import UniformTypeIdentifiers

let version = "3.0.1"

// MARK: - Output and errors

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("swda ERROR: \(message)\n".utf8))
    exit(1)
}

func attempt<T>(_ body: () throws -> T) -> T {
    do { return try body() } catch { fail(error.localizedDescription) }
}

func printUsage() {
    print("""
    swda \(version) — Utility to view and change default applications on macOS.

    Usage:
      swda getSchemes                       List known URL schemes and their default app.
      swda getUTIs                          List known UTIs and their default app.
      swda getApps                          List applications registered with LaunchServices.
      swda getHandler <type> [--role R] [--all]
                                            Show the default app (or every capable app with --all).
      swda setHandler <type> --app <app> [--role R]
                                            Set <app> as the default app.

    <type> is one of:
      --URL <scheme>         e.g. --URL mailto
      --UTI <uti>            e.g. --UTI public.plain-text
      --ext <extension>      e.g. --ext md (converted to the matching UTI)
      --browser | --internet | --web   (http and https)
      --mail | --email | --e-mail      (mailto)
      --ftp | --rss | --news

    <app> can be a name ("Visual Studio Code"), a bundle ID (com.microsoft.VSCode),
    or a path to a .app.

    --role <Viewer|Editor|Shell|All>   UTIs only. Default: All.
    """)
}

// MARK: - Arguments

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
        guard i < argv.count else { fail("\(flag) requires a value.") }
        return argv[i]
    }
    while i < argv.count {
        let flag = argv[i]
        switch flag.lowercased() {
        case "--url": args.schemes = [value(flag).trimmingCharacters(in: CharacterSet(charactersIn: ":/"))]
        case "--uti": args.uti = value(flag)
        case "--ext":
            let ext = value(flag).trimmingCharacters(in: CharacterSet(charactersIn: "."))
            guard let type = UTType(filenameExtension: ext) else { fail("No UTI found for extension .\(ext)") }
            args.uti = type.identifier
        case "--browser", "--internet", "--web": args.schemes = ["http", "https"]
        case "--mail", "--email", "--e-mail": args.schemes = ["mailto"]
        case "--ftp": args.schemes = ["ftp"]
        case "--rss": args.schemes = ["feed"]
        case "--news": args.schemes = ["news"]
        case "--app", "--application": args.app = value(flag)
        case "--role":
            let name = value(flag)
            guard let role = Role(name: name) else { fail("Invalid role: \(name). Use Viewer, Editor, Shell, or All.") }
            args.role = role
        case "--all": args.all = true
        case "-h", "--help": printUsage(); exit(0)
        default: fail("Unknown option: \(flag). See `swda --help`.")
        }
        i += 1
    }
    return args
}

/// Runs an asynchronous LaunchServices operation and waits for its result.
func waitFor(_ body: (@escaping (Error?) -> Void) -> Void) -> Error? {
    var result: Error?
    var done = false
    body { error in result = error; done = true }
    while !done { RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.05)) }
    return result
}

// MARK: - Commands

func getHandler(_ args: Args) {
    if let uti = args.uti {
        if args.all {
            LaunchServices.candidates(forUTI: uti, role: args.role).forEach { print(LaunchServices.display($0)) }
        } else {
            print(LaunchServices.display(LaunchServices.defaultApp(forUTI: uti, role: args.role)))
        }
        return
    }
    guard !args.schemes.isEmpty else { fail("getHandler needs --URL, --UTI, --ext, or a shortcut such as --browser.") }
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
    guard let query = args.app else { fail("setHandler needs --app <application>.") }
    if query.caseInsensitiveCompare("None") == .orderedSame {
        fail("\"None\" is no longer supported: modern macOS doesn't allow leaving a type without an application.")
    }
    let appURL = attempt { try LaunchServices.resolveApp(query) }

    if let uti = args.uti {
        if let error = waitFor({ LaunchServices.setDefault(app: appURL, forUTI: uti, role: args.role, completion: $0) }) {
            fail("Could not change the handler for \(uti): \(error.localizedDescription)")
        }
        print("Default handler for \(uti) is now \(LaunchServices.display(LaunchServices.defaultApp(forUTI: uti, role: args.role))).")
        return
    }

    guard !args.schemes.isEmpty else { fail("setHandler needs --URL, --UTI, --ext, or a shortcut such as --browser.") }
    for scheme in args.schemes {
        if let error = waitFor({ LaunchServices.setDefault(app: appURL, forScheme: scheme, completion: $0) }) {
            fail("Could not change the handler for \(scheme): \(error.localizedDescription)")
        }
        print("Default handler for \(scheme) is now \(LaunchServices.display(LaunchServices.defaultApp(forScheme: scheme))).")
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
default: fail("Unknown command: \(args.command). See `swda --help`.")
}
