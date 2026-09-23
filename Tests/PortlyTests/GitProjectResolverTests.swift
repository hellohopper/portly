import Testing
import Foundation
@testable import PortlyCore

struct GitProjectResolverTests {

    private func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("PortlyTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @Test func findGitDirWalksUpFromNestedSubdirectory() throws {
        let tempRoot = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let gitDir = tempRoot.appendingPathComponent(".git")
        try FileManager.default.createDirectory(at: gitDir, withIntermediateDirectories: true)

        let nested = tempRoot.appendingPathComponent("src/components")
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)

        let found = GitProjectResolver.findGitDir(startingAt: nested.path)

        #expect(found?.path == gitDir.path)
    }

    @Test func findGitDirReturnsNilWhenNoRepoPresent() throws {
        let tempRoot = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        #expect(GitProjectResolver.findGitDir(startingAt: tempRoot.path) == nil)
    }

    @Test func readBranchFromHeadOnBranch() throws {
        let tempRoot = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let gitDir = tempRoot.appendingPathComponent(".git")
        try FileManager.default.createDirectory(at: gitDir, withIntermediateDirectories: true)
        try "ref: refs/heads/main\n".write(
            to: gitDir.appendingPathComponent("HEAD"), atomically: true, encoding: .utf8
        )

        #expect(GitProjectResolver.readBranch(gitDir: gitDir) == "main")
    }

    @Test func readBranchFromDetachedHead() throws {
        let tempRoot = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let gitDir = tempRoot.appendingPathComponent(".git")
        try FileManager.default.createDirectory(at: gitDir, withIntermediateDirectories: true)
        try "abcdef1234567890\n".write(
            to: gitDir.appendingPathComponent("HEAD"), atomically: true, encoding: .utf8
        )

        #expect(GitProjectResolver.readBranch(gitDir: gitDir) == "abcdef1")
    }

    @Test func readBranchFollowsWorktreeGitdirFile() throws {
        let tempRoot = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let realGitDir = tempRoot.appendingPathComponent("real/.git")
        let worktreeGitDir = realGitDir.appendingPathComponent("worktrees/feature")
        try FileManager.default.createDirectory(at: worktreeGitDir, withIntermediateDirectories: true)
        try "ref: refs/heads/feature-branch\n".write(
            to: worktreeGitDir.appendingPathComponent("HEAD"), atomically: true, encoding: .utf8
        )

        let worktreeCheckout = tempRoot.appendingPathComponent("checkout")
        try FileManager.default.createDirectory(at: worktreeCheckout, withIntermediateDirectories: true)
        let gitFile = worktreeCheckout.appendingPathComponent(".git")
        try "gitdir: \(worktreeGitDir.path)\n".write(to: gitFile, atomically: true, encoding: .utf8)

        #expect(GitProjectResolver.readBranch(gitDir: gitFile) == "feature-branch")
    }

    /// Submodules write the gitdir relative to the `.git` file's own directory.
    @Test func readBranchFollowsRelativeSubmoduleGitdir() throws {
        let tempRoot = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let moduleGitDir = tempRoot.appendingPathComponent(".git/modules/lib")
        try FileManager.default.createDirectory(at: moduleGitDir, withIntermediateDirectories: true)
        try "ref: refs/heads/sub-branch\n".write(
            to: moduleGitDir.appendingPathComponent("HEAD"), atomically: true, encoding: .utf8
        )

        let submodule = tempRoot.appendingPathComponent("lib")
        try FileManager.default.createDirectory(at: submodule, withIntermediateDirectories: true)
        let gitFile = submodule.appendingPathComponent(".git")
        try "gitdir: ../.git/modules/lib\n".write(to: gitFile, atomically: true, encoding: .utf8)

        #expect(GitProjectResolver.readBranch(gitDir: gitFile) == "sub-branch")
    }
}
