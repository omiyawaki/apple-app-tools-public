import XCTest
@testable import IconComposerBuild

final class IconComposerBuildTests: XCTestCase {
    func testOmitsDesignGenerationWhenFlagIsAbsent() throws {
        let options = try BuildOptions.parse([
            "build",
            "--icon", "/tmp/AppIcon.icon",
            "--out", "/tmp/icon-output"
        ])

        XCTAssertNil(options.designGeneration)
    }

    func testParsesDesignGeneration26() throws {
        let options = try BuildOptions.parse([
            "build",
            "--icon", "/tmp/AppIcon.icon",
            "--out", "/tmp/icon-output",
            "--design-generation", "26"
        ])

        XCTAssertEqual(options.designGeneration, 26)
    }

    func testParsesIconComposerTwoDesignGeneration() throws {
        let options = try BuildOptions.parse([
            "build",
            "--icon", "/tmp/AppIcon.icon",
            "--out", "/tmp/icon-output",
            "--design-generation", "27"
        ])

        XCTAssertEqual(options.designGeneration, 27)
    }

    func testRejectsUnsupportedDesignGeneration() {
        XCTAssertThrowsError(try BuildOptions.parse([
            "build",
            "--icon", "/tmp/AppIcon.icon",
            "--out", "/tmp/icon-output",
            "--design-generation", "25"
        ])) { error in
            XCTAssertEqual((error as? BuildError)?.message, "--design-generation must be 26 or 27.")
        }
    }
}
