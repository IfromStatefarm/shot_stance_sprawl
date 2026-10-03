import Flutter
import UIKit
import XCTest

class RunnerTests: XCTestCase {

  func testFirebaseConfigurationMatchesBuild() throws {
    let appBundle = Bundle.main
    let expectedProjectID = try XCTUnwrap(
      appBundle.object(forInfoDictionaryKey: "FirebaseExpectedProjectID") as? String
    )
    let serviceURL = try XCTUnwrap(
      appBundle.url(forResource: "GoogleService-Info", withExtension: "plist")
    )
    let serviceData = try Data(contentsOf: serviceURL)
    let serviceConfig = try XCTUnwrap(
      PropertyListSerialization.propertyList(from: serviceData, format: nil)
        as? [String: Any]
    )

    XCTAssertEqual(serviceConfig["PROJECT_ID"] as? String, expectedProjectID)
    XCTAssertEqual(
      serviceConfig["BUNDLE_ID"] as? String,
      appBundle.bundleIdentifier?.replacingOccurrences(of: ".RunnerTests", with: "")
    )
  }

}
