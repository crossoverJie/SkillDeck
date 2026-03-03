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
}
