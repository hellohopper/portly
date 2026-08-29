import Foundation

public enum FrameworkDetector {

    /// Maps a raw process name + full command line to a friendly framework label,
    /// mirroring the "smart filtering" Ports App advertises (Node/Vite/Next/Python/
    /// Rails/Go/Bun/Deno, etc.). Returns nil when nothing recognizable matches.
    public static func detect(processName: String, commandLine: String) -> String? {
        let command = commandLine.lowercased()

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
        case "postgres": return "Postgres"
        case "redis-server": return "Redis"
        case "mysqld": return "MySQL"
        case "mongod": return "MongoDB"
        default: return nil
        }
    }

    /// Order matters: specific dev-tool signatures in a command line are checked
    /// before falling back to the generic runtime name. Hoisted out of `detect` --
    /// it's consulted once per port per refresh and never varies.
    static let signatures: [(String, String)] = [
        ("vite", "Vite"),
        ("next dev", "Next.js"),
        ("next-server", "Next.js"),
        ("nuxt", "Nuxt"),
        ("astro", "Astro"),
        ("svelte-kit", "SvelteKit"),
        ("sveltekit", "SvelteKit"),
        ("remix", "Remix"),
        ("storybook", "Storybook"),
        ("webpack-dev-server", "Webpack"),
        ("react-scripts", "Create React App"),
        ("ng serve", "Angular"),
        ("@angular/cli", "Angular"),
        ("http-server", "http-server"),
        ("rails s", "Rails"),
        ("rails server", "Rails"),
        ("puma", "Rails"),
        ("artisan serve", "Laravel"),
        ("manage.py runserver", "Django"),
        ("django", "Django"),
        ("flask", "Flask"),
        ("uvicorn", "FastAPI"),
        ("gunicorn", "Gunicorn"),
        ("phoenix", "Phoenix"),
        ("mix phx.server", "Phoenix"),
        ("spring-boot", "Spring Boot"),
        ("org.springframework", "Spring Boot"),
        ("air -c", "Air (Go)"),
        ("gin-bin", "Gin (Go)")
    ]
}
