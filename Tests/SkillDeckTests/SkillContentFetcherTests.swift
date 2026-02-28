import XCTest
@testable import SkillDeck

/// Unit tests for SkillContentFetcher — the actor that fetches SKILL.md from GitHub
///
/// These tests verify URL construction, candidate URL generation, and cache key logic
/// without making actual network requests.
/// Network-dependent behavior (fetch success/failure, branch fallback) requires integration tests
/// or mock injection, which is complex with Swift's `actor` type.
///
/// XCTest is Swift's testing framework (similar to JUnit or Go's testing package).
/// Test methods must start with "test" prefix. Use XCTAssert* for assertions.
final class SkillContentFetcherTests: XCTestCase {

    // MARK: - URL Construction Tests

    /// Test that the raw GitHub URL is correctly constructed for flat layout on main branch
    ///
    /// Verifies the URL pattern:
    /// `https://raw.githubusercontent.com/{owner}/{repo}/{branch}/{path}/SKILL.md`
    ///
    /// `async` is needed because SkillContentFetcher is an `actor` —
    /// accessing its methods from outside requires `await` (Swift's data race safety guarantee).
    func testBuildRawURLFlatLayout() async {
        let fetcher = SkillContentFetcher()
        let url = await fetcher.buildRawURL(
            source: "vercel-labs/agent-skills",
            path: "vercel-react-best-practices",
            branch: "main"
        )

        XCTAssertEqual(
            url.absoluteString,
            "https://raw.githubusercontent.com/vercel-labs/agent-skills/main/vercel-react-best-practices/SKILL.md"
        )
    }

    /// Test URL construction for monorepo layout (skills/ subdirectory)
    ///
    /// Many repos like `inference-sh/skills` store skills under `skills/{skillId}/SKILL.md`.
    func testBuildRawURLMonorepoLayout() async {
        let fetcher = SkillContentFetcher()
        let url = await fetcher.buildRawURL(
            source: "inference-sh/skills",
            path: "skills/remotion-render",
            branch: "main"
        )

        XCTAssertEqual(
            url.absoluteString,
            "https://raw.githubusercontent.com/inference-sh/skills/main/skills/remotion-render/SKILL.md"
        )
    }

    /// Test that the raw GitHub URL is correctly constructed for the master branch fallback
    func testBuildRawURLMasterBranch() async {
        let fetcher = SkillContentFetcher()
        let url = await fetcher.buildRawURL(
            source: "some-user/some-repo",
            path: "my-skill",
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
            path: "skill-with-hyphens",
            branch: "main"
        )

        XCTAssertEqual(
            url.absoluteString,
            "https://raw.githubusercontent.com/my-org/my.repo-name/main/skill-with-hyphens/SKILL.md"
        )
    }

    // MARK: - Candidate URL Tests

    /// Test that candidateURLs generates all 8 expected URLs in the correct order
    ///
    /// The fetch strategy tries 4 layouts × 2 branches = 8 URLs:
    /// main/flat → main/skills/ → main/.claude/skills/ → main/root →
    /// master/flat → master/skills/ → master/.claude/skills/ → master/root
    func testCandidateURLsGeneratesAllCombinations() async {
        let fetcher = SkillContentFetcher()
        let urls = await fetcher.candidateURLs(
            source: "inference-sh/skills",
            skillId: "remotion-render"
        )

        // Should produce exactly 8 candidate URLs (2 branches × 4 layouts)
        XCTAssertEqual(urls.count, 8)

        let urlStrings = urls.map(\.absoluteString)

        // 1. main branch, flat layout
        XCTAssertEqual(
            urlStrings[0],
            "https://raw.githubusercontent.com/inference-sh/skills/main/remotion-render/SKILL.md"
        )
        // 2. main branch, monorepo layout (skills/ subdirectory)
        XCTAssertEqual(
            urlStrings[1],
            "https://raw.githubusercontent.com/inference-sh/skills/main/skills/remotion-render/SKILL.md"
        )
        // 3. main branch, plugin-style layout (.claude/skills/ subdirectory)
        XCTAssertEqual(
            urlStrings[2],
            "https://raw.githubusercontent.com/inference-sh/skills/main/.claude/skills/remotion-render/SKILL.md"
        )
        // 4. main branch, root layout (SKILL.md at repo root)
        XCTAssertEqual(
            urlStrings[3],
            "https://raw.githubusercontent.com/inference-sh/skills/main/SKILL.md"
        )
        // 5. master branch, flat layout
        XCTAssertEqual(
            urlStrings[4],
            "https://raw.githubusercontent.com/inference-sh/skills/master/remotion-render/SKILL.md"
        )
        // 6. master branch, monorepo layout
        XCTAssertEqual(
            urlStrings[5],
            "https://raw.githubusercontent.com/inference-sh/skills/master/skills/remotion-render/SKILL.md"
        )
        // 7. master branch, plugin-style layout
        XCTAssertEqual(
            urlStrings[6],
            "https://raw.githubusercontent.com/inference-sh/skills/master/.claude/skills/remotion-render/SKILL.md"
        )
        // 8. master branch, root layout
        XCTAssertEqual(
            urlStrings[7],
            "https://raw.githubusercontent.com/inference-sh/skills/master/SKILL.md"
        )
    }

    /// Test candidate URLs for a repo that uses flat layout
    ///
    /// Even for flat-layout repos, all 8 URLs are generated — the fetcher
    /// tries them in order and stops on the first 200 response.
    func testCandidateURLsFlatLayoutRepo() async {
        let fetcher = SkillContentFetcher()
        let urls = await fetcher.candidateURLs(
            source: "vercel-labs/agent-skills",
            skillId: "vercel-react-best-practices"
        )

        XCTAssertEqual(urls.count, 8)
        // First URL should be the flat layout on main (most likely to succeed)
        XCTAssertTrue(
            urls[0].absoluteString.contains("/main/vercel-react-best-practices/SKILL.md")
        )
    }

    /// Test that buildRawURL handles empty path correctly (root-level SKILL.md)
    ///
    /// When path is empty, the URL should be `/{branch}/SKILL.md` without a double slash.
    /// This covers single-skill repos that place SKILL.md directly at the repository root.
    func testBuildRawURLEmptyPath() async {
        let fetcher = SkillContentFetcher()
        let url = await fetcher.buildRawURL(
            source: "some-user/some-repo",
            path: "",
            branch: "main"
        )

        // Should NOT contain a double slash before SKILL.md
        XCTAssertEqual(
            url.absoluteString,
            "https://raw.githubusercontent.com/some-user/some-repo/main/SKILL.md"
        )
        XCTAssertFalse(url.absoluteString.contains("//SKILL.md"))
    }

    /// Test URL construction for plugin-style layout (.claude/skills/ subdirectory)
    ///
    /// Some repos like `nextlevelbuilder/ui-ux-pro-max-skill` store SKILL.md at
    /// `.claude/skills/{skillId}/SKILL.md`.
    func testBuildRawURLPluginStylePath() async {
        let fetcher = SkillContentFetcher()
        let url = await fetcher.buildRawURL(
            source: "nextlevelbuilder/ui-ux-pro-max-skill",
            path: ".claude/skills/ui-ux-pro-max",
            branch: "main"
        )

        XCTAssertEqual(
            url.absoluteString,
            "https://raw.githubusercontent.com/nextlevelbuilder/ui-ux-pro-max-skill/main/.claude/skills/ui-ux-pro-max/SKILL.md"
        )
    }

    /// Test that candidate URLs maintain the correct priority order
    ///
    /// Flat and monorepo layouts should come before plugin-style and root layouts,
    /// since they are the most common patterns. This ensures the fast path is tried first.
    func testCandidateURLsOrderPriority() async {
        let fetcher = SkillContentFetcher()
        let urls = await fetcher.candidateURLs(
            source: "owner/repo",
            skillId: "my-skill"
        )

        let urlStrings = urls.map(\.absoluteString)

        // Flat layout (most common) should be first
        XCTAssertTrue(urlStrings[0].contains("/main/my-skill/SKILL.md"))
        // Monorepo layout should be second
        XCTAssertTrue(urlStrings[1].contains("/main/skills/my-skill/SKILL.md"))
        // Plugin-style layout should be third
        XCTAssertTrue(urlStrings[2].contains("/main/.claude/skills/my-skill/SKILL.md"))
        // Root layout should be fourth
        XCTAssertTrue(urlStrings[3].hasSuffix("/main/SKILL.md"))
        // Then the same order repeats for master branch
        XCTAssertTrue(urlStrings[4].contains("/master/my-skill/SKILL.md"))
        XCTAssertTrue(urlStrings[5].contains("/master/skills/my-skill/SKILL.md"))
        XCTAssertTrue(urlStrings[6].contains("/master/.claude/skills/my-skill/SKILL.md"))
        XCTAssertTrue(urlStrings[7].hasSuffix("/master/SKILL.md"))
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
