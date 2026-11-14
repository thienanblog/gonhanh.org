@testable import GoNhanh
import XCTest

// MARK: - Update Manager Tests

final class UpdateManagerTests: XCTestCase {
    func testSharedInstanceExists() {
        XCTAssertNotNil(UpdateManager.shared)
    }

    func testDefaultUpdateAvailableIsFalse() {
        XCTAssertFalse(UpdateManager.shared.updateAvailable)
    }

    // MARK: - Pending update restore

    private let repo = "thienanblog/gonhanh.org"

    private func keep(source: String?, version: String, current: String = "1.0.165") -> Bool {
        UpdateManager.shouldKeepPendingUpdate(source: source, version: version, currentVersion: current, updateRepository: repo)
    }

    func testKeepsNewerUpdateFromUpdateRepository() {
        XCTAssertTrue(keep(source: repo, version: "1.0.166"))
    }

    func testDiscardsUpdateWithoutSource() {
        // Downloaded before the source was recorded (e.g. from upstream)
        XCTAssertFalse(keep(source: nil, version: "1.0.166"))
    }

    func testDiscardsUpdateFromOtherRepository() {
        XCTAssertFalse(keep(source: "khaphanspace/gonhanh.org", version: "1.0.166"))
    }

    func testDiscardsSameOrOlderVersion() {
        XCTAssertFalse(keep(source: repo, version: "1.0.165"))
        XCTAssertFalse(keep(source: repo, version: "1.0.164"))
    }

    func testDiscardsMissingVersion() {
        XCTAssertFalse(keep(source: repo, version: ""))
    }
}
