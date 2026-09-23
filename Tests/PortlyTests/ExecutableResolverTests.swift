import Testing
import Foundation
@testable import PortlyCore

struct ExecutableResolverTests {

    /// rc files are free to print banners; only the fenced PATH is taken.
    @Test func extractsPathBetweenMarkersIgnoringShellNoise() {
        let output = "Welcome back!\n__M__/opt/homebrew/bin:/usr/bin__M__\nlast login"
        #expect(ExecutableResolver.parseMarkedPath(output, marker: "__M__") == ["/opt/homebrew/bin", "/usr/bin"])
        #expect(ExecutableResolver.parseMarkedPath("no markers here", marker: "__M__") == [])
    }

    @Test func deduplicatesPreservingPriorityOrder() {
        #expect(ExecutableResolver.deduplicated(["/a", "/b", "", "/a", "/c"]) == ["/a", "/b", "/c"])
    }

    @Test func resolvesNamesAgainstTheGivenDirectoriesInOrder() {
        #expect(ExecutableResolver.resolve("sh", in: ["/nonexistent", "/bin"]) == "/bin/sh")
        #expect(ExecutableResolver.resolve("portly-no-such-tool", in: ["/bin", "/usr/bin"]) == nil)
    }

    /// Anything with a slash is a path: checked, never searched for.
    @Test func takesSlashedNamesAsPaths() {
        #expect(ExecutableResolver.resolve("/bin/sh", in: []) == "/bin/sh")
        #expect(ExecutableResolver.resolve("/bin/not-a-real-binary", in: ["/bin"]) == nil)
    }

    /// A missing executable used to "launch" fine via /usr/bin/env and report success.
    @Test func launcherReportsAMissingExecutableAsFailure() {
        #expect(!ProcessLauncher.launch(commandLine: "portly-no-such-tool --flag", workingDirectory: nil))
    }
}
