import Foundation
import Testing
@testable import PortlyCore

struct ProjectConfigResolverTests {

    private func json(_ string: String) -> Data {
        Data(string.utf8)
    }

    @Test func parsesWellFormedLabels() {
        let config = ProjectConfigResolver.parse(json(#"{"labels": {"3000": "web frontend", "8000": "api"}}"#))
        #expect(config.labels == [3000: "web frontend", 8000: "api"])
    }

    @Test func dropsInvalidEntriesButKeepsValidOnes() {
        let config = ProjectConfigResolver.parse(json(
            #"{"labels": {"3000": "web", "abc": "bad key", "8000": 42, "70000": "out of range", "9000": "   "}}"#
        ))
        #expect(config.labels == [3000: "web"])
    }

    @Test func returnsEmptyForGarbageOrMissingLabelsKey() {
        #expect(ProjectConfigResolver.parse(json("not json at all")).isEmpty)
        #expect(ProjectConfigResolver.parse(json(#"{"ports": {"3000": "web"}}"#)).isEmpty)
        #expect(ProjectConfigResolver.parse(json(#"[1, 2, 3]"#)).isEmpty)
    }

    @Test func parsesHealthPaths() {
        let config = ProjectConfigResolver.parse(json(#"{"health": {"8000": "/api/health"}}"#))
        #expect(config.healthPaths == [8000: "/api/health"])
        #expect(config.healthTarget(for: 8000).path == "/api/health")
        #expect(config.healthTarget(for: 9999).path == "/")
    }

    @Test func parsesTLSPorts() {
        let config = ProjectConfigResolver.parse(json(#"{"https": {"3000": true, "8000": false}}"#))
        #expect(config.tlsPorts == [3000])
        #expect(config.healthTarget(for: 3000).useTLS)
        #expect(!config.healthTarget(for: 8000).useTLS)
    }

    /// Labels already declare a port, so they count as expectations too -- but a
    /// project can also list ports it uses without naming them.
    @Test func derivesExpectedPortsFromLabelsAndExpects() {
        let config = ProjectConfigResolver.parse(json(#"{"labels": {"3000": "web"}, "expects": [8080, 9000]}"#))
        #expect(config.expectedPorts == [3000, 8080, 9000])
    }

    @Test func acceptsStringPortsInExpects() {
        let config = ProjectConfigResolver.parse(json(#"{"expects": ["8080"]}"#))
        #expect(config.expectedPorts == [8080])
    }

    @Test func normalisesHealthPathsMissingALeadingSlash() {
        let target = HealthChecker.Target(path: "healthz")
        #expect(target.path == "/healthz")
    }

    @Test func findsConfigAtGitRootFromNestedSubdirectory() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("portly-config-test-\(UUID().uuidString)")
        let nested = root.appendingPathComponent("src/deep")
        try fm.createDirectory(at: nested, withIntermediateDirectories: true)
        try fm.createDirectory(at: root.appendingPathComponent(".git"), withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }

        try json(#"{"labels": {"3000": "web"}}"#)
            .write(to: root.appendingPathComponent(ProjectConfigResolver.fileName))

        let resolver = ProjectConfigResolver()
        #expect(resolver.labels(fromDirectory: nested.path) == [3000: "web"])
    }

    @Test func picksUpFileEditsViaMtime() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("portly-config-test-\(UUID().uuidString)")
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        let configURL = root.appendingPathComponent(ProjectConfigResolver.fileName)

        let resolver = ProjectConfigResolver()
        #expect(resolver.labels(fromDirectory: root.path).isEmpty)

        try json(#"{"labels": {"3000": "web"}}"#).write(to: configURL)
        #expect(resolver.labels(fromDirectory: root.path) == [3000: "web"])

        try json(#"{"labels": {"3000": "renamed"}}"#).write(to: configURL)
        // Force a distinct mtime in case both writes land in the same filesystem tick.
        try fm.setAttributes([.modificationDate: Date().addingTimeInterval(2)], ofItemAtPath: configURL.path)
        #expect(resolver.labels(fromDirectory: root.path) == [3000: "renamed"])
    }
}
