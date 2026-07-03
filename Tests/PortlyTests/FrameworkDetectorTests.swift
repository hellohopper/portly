import Testing
@testable import PortlyCore

struct FrameworkDetectorTests {

    @Test func detectsViteFromCommandLine() {
        let label = FrameworkDetector.detect(
            processName: "node", commandLine: "node /project/node_modules/.bin/vite --port 5173"
        )
        #expect(label == "Vite")
    }

    @Test func detectsNextDevFromCommandLine() {
        let label = FrameworkDetector.detect(processName: "node", commandLine: "next dev")
        #expect(label == "Next.js")
    }

    @Test func detectsRailsFromPuma() {
        let label = FrameworkDetector.detect(processName: "ruby", commandLine: "puma 4.3.1 (tcp://0.0.0.0:3000)")
        #expect(label == "Rails")
    }

    @Test func detectsDjangoFromManagePy() {
        let label = FrameworkDetector.detect(processName: "python3", commandLine: "python3 manage.py runserver")
        #expect(label == "Django")
    }

    @Test func fallsBackToGenericRuntimeName() {
        #expect(FrameworkDetector.detect(processName: "node", commandLine: "node server.js") == "Node")
        #expect(FrameworkDetector.detect(processName: "python3", commandLine: "python3 app.py") == "Python")
        #expect(FrameworkDetector.detect(processName: "bun", commandLine: "bun run index.ts") == "Bun")
        #expect(FrameworkDetector.detect(processName: "deno", commandLine: "deno run main.ts") == "Deno")
    }

    @Test func returnsNilForUnrecognizedProcess() {
        #expect(FrameworkDetector.detect(processName: "rapportd", commandLine: "/usr/libexec/rapportd") == nil)
    }
}
