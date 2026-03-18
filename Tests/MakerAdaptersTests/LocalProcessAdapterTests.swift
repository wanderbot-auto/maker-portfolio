import Testing
import MakerAdapters
import MakerDomain
import MakerSupport

@Test
func localProcessAdapterRequiresPreparationBeforeStart() async throws {
    let adapter = LocalProcessAdapter()

    let status = await adapter.getStatus()
    #expect(status == .idle)
    do {
        _ = try await adapter.start()
        Issue.record("Expected start() to fail when not prepared.")
    } catch {
        #expect(error is MakerError)
        #expect((error as? MakerError) == .invalidConfiguration("Runtime profile has not been prepared."))
    }
}
