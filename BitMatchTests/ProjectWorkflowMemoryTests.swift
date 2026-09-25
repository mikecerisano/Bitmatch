// ProjectWorkflowMemoryTests.swift
// Most people use one project type and never change it: Video / DIT comes
// first, and the last choice is remembered across launches.
import Foundation
import Testing
@testable import BitMatch

@MainActor
struct ProjectWorkflowMemoryTests {
    private func defaults() -> UserDefaults { .isolatedWorkflowDefaults() }

    /// Fails if the case order (which drives the picker) changes back.
    @Test func videoDITComesFirst() {
        #expect(ProjectWorkflow.allCases == [.videoDIT, .photography, .general])
    }

    /// With nothing remembered, the first option is selected.
    @Test func firstLaunchSelectsVideoDIT() {
        let model = PhotographerJobViewModel(store: InMemoryPhotographerJobStore(), workflowDefaults: defaults())
        #expect(model.selectedWorkflow == .videoDIT)
        #expect(model.draftRecipe == ProjectWorkflow.videoDIT.defaultRecipe)
    }

    /// Fails if `selectWorkflow` stops saving the choice, or init stops
    /// restoring it (with its folder recipe).
    @Test func lastChoiceIsRememberedAcrossLaunches() {
        let saved = defaults()
        let first = PhotographerJobViewModel(store: InMemoryPhotographerJobStore(), workflowDefaults: saved)
        first.selectWorkflow(.photography)

        let relaunched = PhotographerJobViewModel(store: InMemoryPhotographerJobStore(), workflowDefaults: saved)
        #expect(relaunched.selectedWorkflow == .photography)
        #expect(relaunched.draftRecipe == ProjectWorkflow.photography.defaultRecipe)
    }
}
