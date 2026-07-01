import Foundation

enum FrameworkDetector {

    /// Maps a raw process name + full command line to a friendly framework label,
    /// mirroring the "smart filtering" Ports App advertises (Node/Vite/Next/Python/
    /// Rails/Go/Bun/Deno, etc.). Returns nil when nothing recognizable matches.
    static func detect(processName: String, commandLine: String) -> String? {
        let command = commandLine.lowercased()

        // Order matters: check specific dev-tool signatures in a command line
        // before falling back to the generic runtime name.
        let signatures: [(String, String)] = [
            ("vite", "Vite"),
            ("next dev", "Next.js"),
            ("next-server", "Next.js"),
            ("nuxt", "Nuxt"),
            ("webpack-dev-server", "Webpack"),
            ("react-scripts", "Create React App"),
            ("ng serve", "Angular"),
            ("@angular/cli", "Angular"),
            ("rails s", "Rails"),
            ("rails server", "Rails"),
            ("puma", "Rails"),
            ("manage.py runserver", "Django"),
            ("django", "Django"),
            ("flask", "Flask"),
            ("uvicorn", "FastAPI"),
            ("gunicorn", "Gunicorn")
        ]
        for (signature, label) in signatures where command.contains(signature) {
            return label
        }

        switch processName.lowercased() {
        case "node": return "Node"
        case "bun": return "Bun"
        case "deno": return "Deno"
        case "python", "python3": return "Python"
        case "ruby": return "Ruby"
        case "go": return "Go"
        default: return nil
        }
    }
}
