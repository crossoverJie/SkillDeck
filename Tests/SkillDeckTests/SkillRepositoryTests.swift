import XCTest
@testable import SkillDeck

final class SkillRepositoryTests: XCTestCase {

    func testConvertSSHToHTTPS() {
        let input = "git@github.com:org/repo.git"
        let output = SkillRepository.convertRepoURL(input, to: .httpsToken)
        XCTAssertEqual(output, "https://github.com/org/repo.git")
    }

    func testConvertHTTPSToSSH() {
        let input = "https://gitlab.com/team/private-skills.git"
        let output = SkillRepository.convertRepoURL(input, to: .ssh)
        XCTAssertEqual(output, "git@gitlab.com:team/private-skills.git")
    }

    func testConvertKeepsEnterpriseHost() {
        let input = "https://git.example.com/group/skills.git"
        let output = SkillRepository.convertRepoURL(input, to: .ssh)
        XCTAssertEqual(output, "git@git.example.com:group/skills.git")
    }

    func testConvertInvalidURLReturnsOriginal() {
        let input = "owner/repo"
        let output = SkillRepository.convertRepoURL(input, to: .httpsToken)
        XCTAssertEqual(output, input)
    }

    func testDecodeSyncOnLaunchDefaultsToFalseWhenMissing() throws {
        let json = """
        {
          "id": "11111111-1111-1111-1111-111111111111",
          "name": "team-skills",
          "repoURL": "https://example.com/org/repo.git",
          "authType": "httpsToken",
          "platform": "github",
          "isEnabled": true,
          "localSlug": "org-repo"
        }
        """

        let data = Data(json.utf8)
        let repo = try JSONDecoder().decode(SkillRepository.self, from: data)
        XCTAssertFalse(repo.syncOnLaunch)
    }

    func testDecodeSyncOnLaunchTrueWhenPresent() throws {
        let json = """
        {
          "id": "22222222-2222-2222-2222-222222222222",
          "name": "team-skills",
          "repoURL": "https://example.com/org/repo.git",
          "authType": "httpsToken",
          "platform": "github",
          "isEnabled": true,
          "localSlug": "org-repo",
          "syncOnLaunch": true
        }
        """

        let data = Data(json.utf8)
        let repo = try JSONDecoder().decode(SkillRepository.self, from: data)
        XCTAssertTrue(repo.syncOnLaunch)
    }
}
