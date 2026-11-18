// Copyright 2026 The Clair Authors
// You can use, redistribute, and/or modify this source code under
// the terms of the GPL-3.0 license that can be found in the LICENSE file.

import Foundation
import XCTest

/// The certificate data check (keep-certificate-data-current D6): the
/// component updater lets the PKI metadata component through, fetches it over
/// HTTPS and installs it into the data folder.
@MainActor
final class CertificateDataTests: RuntimeTestCase {
  override func setUp() async throws {
    // The first component check runs about a minute after launch, and the
    // test waits up to three minutes for the component, past run.sh's default
    // allowance.
    executionTimeAllowance = 300
    try await super.setUp()
  }

  /// The files a PKI metadata component holds: the Certificate Transparency
  /// log list, the static key pins and the Chrome Root Store.
  static let pkiMetadataFiles = ["ct_config.pb", "kp_pinslist.pb", "crs.pb"]

  /// The version folders in `PKIMetadata` that hold every file the component
  /// carries.
  func installedPKIMetadata(in dataDirectory: URL) -> [String] {
    let root = dataDirectory.appending(path: "PKIMetadata")
    let versions = (try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? []
    return versions.filter { version in
      Self.pkiMetadataFiles.allSatisfy {
        FileManager.default.fileExists(atPath: root.appending(path: version).appending(path: $0).path)
      }
    }
  }

  func testFetchesPKIMetadataOnAFreshDataFolder() async throws {
    let browser = try await startBrowser()
    try require(
      installedPKIMetadata(in: browser.dataDirectory).isEmpty,
      "A fresh data folder already holds PKI metadata")
    let installed = await Harness.wait(for: 180) {
      !self.installedPKIMetadata(in: browser.dataDirectory).isEmpty
    }
    XCTAssertTrue(
      installed,
      "No PKIMetadata/<version>/ with \(Self.pkiMetadataFiles.joined(separator: ", ")) within three minutes")
  }
}
