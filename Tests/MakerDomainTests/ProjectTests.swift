import Testing
import MakerDomain

@Test
func projectGeneratesSlugFromName() {
    let project = Project(name: "Maker Portfolio", localPath: "/tmp/maker")
    #expect(project.slug == "maker-portfolio")
}

@Test
func runtimeProfileDefaultsToLocalProcessAdapter() {
    let project = Project(name: "Core", localPath: "/tmp/core")
    let profile = RuntimeProfile(projectID: project.id, name: "dev", entryCommand: "swift", workingDir: "/tmp/core")
    #expect(profile.adapterType == .localProcess)
}
