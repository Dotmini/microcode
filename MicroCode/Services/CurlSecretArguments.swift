import Foundation

/// Keeps secrets off `/usr/bin/curl`'s command line. Process arguments are visible to every local user (`ps`), so
/// `-H "Authorization: Bearer …"` or `-d '{"refresh_token":…}'` leaked session tokens. Headers, bodies and
/// credentials are moved into a curl config read from stdin (`--config -`); everything else stays in argv.
enum CurlSecretArguments {
    /// Flags whose value is moved to the config, mapped to curl config option names.
    private static let secretFlags: [String: String] = [
        "-H": "header", "--header": "header",
        "-d": "data", "--data": "data", "--data-raw": "data-raw", "--data-binary": "data-binary",
        "-u": "user", "--user": "user", "--oauth2-bearer": "oauth2-bearer", "--cookie": "cookie", "-b": "cookie"
    ]

    /// Returns the argv that remains (with `--config -` appended when anything moved) and the config text for stdin.
    static func split(_ arguments: [String]) -> (argv: [String], config: String) {
        var argv: [String] = []
        var lines: [String] = []
        var index = 0
        while index < arguments.count {
            let arg = arguments[index]
            if let option = secretFlags[arg], index + 1 < arguments.count {
                lines.append("\(option) = \"\(escape(arguments[index + 1]))\"")
                index += 2
                continue
            }
            argv.append(arg)
            index += 1
        }
        if !lines.isEmpty { argv += ["--config", "-"] }
        return (argv, lines.isEmpty ? "" : lines.joined(separator: "\n") + "\n")
    }

    /// curl config double-quoted strings understand \\ \" \t \n \r \v.
    static func escape(_ value: String) -> String {
        var out = ""
        for ch in value {
            switch ch {
            case "\\": out += "\\\\"
            case "\"": out += "\\\""
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            default: out.append(ch)
            }
        }
        return out
    }
}
