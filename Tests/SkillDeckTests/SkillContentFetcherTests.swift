import XCTest
@testable import SkillDeck

/// Unit tests for SkillContentFetcher — the actor that fetches SKILL.md from GitHub
///
/// These tests verify URL construction and cache key logic without making actual network requests.
/// Network-dependent behavior (fetch success/failure, branch fallback) requires integration tests
/// or mock injection, which is complex with Swift's `actor` type.
///
/// XCTest is Swift's testing framework (similar to JUnit or Go's testing package).
/// Test methods must start with "test" prefix. Use XCTAssert* for assertions.
final class SkillContentFetcherTests: XCTestCase {

    // MARK: - URL Construction Tests

    /// Test that the raw GitHub URL is correctly constructed for the main branch
    ///
    /// Verifies the URL pattern:
    /// `https://raw.githubusercontent.com/{owner}/{repo}/{branch}/{skillId}/SKILL.md`
    ///
    /// `async` is needed because SkillContentFetcher is an `actor` —
    /// accessing its methods from outside requires `await` (Swift's data race safety guarantee).
    func testBuildRawURLMainBranch() async {
        let fetcher = SkillContentFetcher()
        let url = await fetcher.buildRawURL(
            source: "vercel-labs/agent-skills",
            skillId: "vercel-react-best-practices",
            branch: "main"
        )

        XCTAssertEqual(
            url.absoluteString,
            "https://raw.githubusercontent.com/vercel-labs/agent-skills/main/vercel-react-best-practices/SKILL.md"
        )
    }

    /// Test that the raw GitHub URL is correctly constructed for the master branch fallback
    func testBuildRawURLMasterBranch() async {
        let fetcher = SkillContentFetcher()
        let url = await fetcher.buildRawURL(
            source: "some-user/some-repo",
            skillId: "my-skill",
            branch: "master"
        )

        XCTAssertEqual(
            url.absoluteString,
            "https://raw.githubusercontent.com/some-user/some-repo/master/my-skill/SKILL.md"
        )
    }

    /// Test URL construction with a source that contains special characters in the repo name
    ///
    /// GitHub repo names can contain hyphens and dots — verify they're preserved in the URL.
    func testBuildRawURLWithHyphensAndDots() async {
        let fetcher = SkillContentFetcher()
        let url = await fetcher.buildRawURL(
            source: "my-org/my.repo-name",
            skillId: "skill-with-hyphens",
            branch: "main"
        )

        XCTAssertEqual(
            url.absoluteString,
            "https://raw.githubusercontent.com/my-org/my.repo-name/main/skill-with-hyphens/SKILL.md"
        )
    }

    // MARK: - Cache Key Tests

    /// Test that the cache key is constructed as "{source}/{skillId}"
    ///
    /// The cache key must be unique per skill to prevent cache collisions.
    /// Using "source/skillId" as the key ensures skills from different repos don't collide.
    func testCacheKeyFormat() async {
        let fetcher = SkillContentFetcher()
        let key = await fetcher.cacheKey(
            source: "vercel-labs/agent-skills",
            skillId: "vercel-react-best-practices"
        )

        XCTAssertEqual(key, "vercel-labs/agent-skills/vercel-react-best-practices")
    }

    /// Test that different skills produce different cache keys
    func testCacheKeyUniqueness() async {
        let fetcher = SkillContentFetcher()

        let key1 = await fetcher.cacheKey(source: "org/repo", skillId: "skill-a")
        let key2 = await fetcher.cacheKey(source: "org/repo", skillId: "skill-b")
        let key3 = await fetcher.cacheKey(source: "other-org/repo", skillId: "skill-a")

        // Same repo, different skills → different keys
        XCTAssertNotEqual(key1, key2)
        // Same skill name, different repos → different keys
        XCTAssertNotEqual(key1, key3)
    }

    /// Test that cache clearing works without error
    ///
    /// After clearing the cache, subsequent fetches should hit the network (not cache).
    /// We can't directly verify cache emptiness from outside the actor,
    /// but we ensure the method doesn't throw or crash.
    func testClearCacheDoesNotThrow() async {
        let fetcher = SkillContentFetcher()
        // Should not throw or crash even when cache is already empty
        await fetcher.clearCache()
    }

    // MARK: - Error Type Tests

    /// Test that FetchError provides meaningful localized descriptions
    ///
    /// `LocalizedError` protocol's `errorDescription` is what users see in error messages.
    /// We verify each error case produces a non-nil, descriptive string.
    func testFetchErrorDescriptions() {
        let networkError = SkillContentFetcher.FetchError.networkError("timeout")
        XCTAssertTrue(networkError.localizedDescription.contains("timeout"))

        let notFound = SkillContentFetcher.FetchError.notFound
        XCTAssertTrue(notFound.localizedDescription.contains("not found"))

        let invalidResponse = SkillContentFetcher.FetchError.invalidResponse(500)
        XCTAssertTrue(invalidResponse.localizedDescription.contains("500"))

        let invalidEncoding = SkillContentFetcher.FetchError.invalidEncoding
        XCTAssertTrue(invalidEncoding.localizedDescription.contains("UTF-8"))
    }
}
