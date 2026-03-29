import Foundation
import Testing
@testable import Leo

@Suite("Leo runtime and secret storage")
struct LeoRuntimeTests {

    @Test("Runtime paths default to Application Support/Leo")
    func runtimePathsDefaultToApplicationSupport() {
        let appSupport = URL(fileURLWithPath: "/tmp/AppSupport", isDirectory: true)
        let paths = LeoRuntimePaths.resolve(
            environment: [:],
            applicationSupportDirectory: appSupport
        )

        #expect(paths.rootDirectory.path == "/tmp/AppSupport/Leo")
        #expect(paths.booksDirectory.path == "/tmp/AppSupport/Leo/Books")
        #expect(paths.storeURL.path == "/tmp/AppSupport/Leo/Leo.store")
        #expect(paths.usesUITestIsolation == false)
    }

    @Test("Runtime paths honor isolated UI test directory")
    func runtimePathsHonorUITestIsolation() {
        let appSupport = URL(fileURLWithPath: "/tmp/AppSupport", isDirectory: true)
        let paths = LeoRuntimePaths.resolve(
            environment: ["LEO_UI_TEST_DATA_DIR": "/tmp/leo-test-root"],
            applicationSupportDirectory: appSupport
        )

        #expect(paths.rootDirectory.path == "/tmp/leo-test-root")
        #expect(paths.booksDirectory.path == "/tmp/leo-test-root/Books")
        #expect(paths.storeURL.path == "/tmp/leo-test-root/Leo.store")
        #expect(paths.usesUITestIsolation)
    }

    @Test("Book locator round-trips through stored data")
    func bookLocatorRoundTrip() {
        let book = Book(title: "活着", author: "余华", filePath: "/tmp/huozhe.epub", format: .epub)
        let locator = BookLocator(
            cfi: "epubcfi(/6/14[xchapter]!/4/2/8)",
            fraction: 0.418,
            updatedAt: Date(timeIntervalSince1970: 1234)
        )

        book.locator = locator

        #expect(book.lastLocator != nil)
        #expect(book.locator == locator)
    }

    @Test("Legacy defaults migrate into secure storage and clear plaintext keys")
    func secretMigrationMovesValuesIntoKeychainStore() {
        let defaults = MockDefaultsStore(values: [
            LeoSecretKey.openRouter.defaultsKey: "open-router-token",
            LeoSecretKey.inWorld.defaultsKey: "inworld-token",
        ])
        let secretStore = MockSecretStore()

        LeoSecretMigrator.migrateLegacyDefaults(defaults: defaults, secretStore: secretStore)

        #expect(secretStore.getSecret(for: .openRouter) == "open-router-token")
        #expect(secretStore.getSecret(for: .inWorld) == "inworld-token")
        #expect(defaults.string(forKey: LeoSecretKey.openRouter.defaultsKey) == nil)
        #expect(defaults.string(forKey: LeoSecretKey.inWorld.defaultsKey) == nil)
    }

    @Test("Migration preserves an existing secure secret")
    func secretMigrationDoesNotOverwriteExistingKeychainValue() {
        let defaults = MockDefaultsStore(values: [
            LeoSecretKey.openRouter.defaultsKey: "legacy-token",
        ])
        let secretStore = MockSecretStore(values: [
            .openRouter: "current-token",
        ])

        LeoSecretMigrator.migrateLegacyDefaults(defaults: defaults, secretStore: secretStore)

        #expect(secretStore.getSecret(for: .openRouter) == "current-token")
        #expect(defaults.string(forKey: LeoSecretKey.openRouter.defaultsKey) == nil)
    }
}

private final class MockDefaultsStore: LeoDefaultsStore {
    private var values: [String: String]

    init(values: [String: String]) {
        self.values = values
    }

    func string(forKey defaultName: String) -> String? {
        values[defaultName]
    }

    func removeObject(forKey defaultName: String) {
        values.removeValue(forKey: defaultName)
    }
}

private final class MockSecretStore: LeoSecretStore {
    private var values: [LeoSecretKey: String]

    init(values: [LeoSecretKey: String] = [:]) {
        self.values = values
    }

    func setSecret(_ secret: String, for key: LeoSecretKey) {
        values[key] = secret
    }

    func getSecret(for key: LeoSecretKey) -> String? {
        values[key]
    }

    func deleteSecret(for key: LeoSecretKey) {
        values.removeValue(forKey: key)
    }
}
