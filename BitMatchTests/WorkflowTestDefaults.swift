// WorkflowTestDefaults.swift
// A private settings store per test, so tests never read or change the
// app's remembered project type (the test host is the real app).
import Foundation
@testable import BitMatch

extension UserDefaults {
    /// Fresh store; with `workflow`, that project type is already remembered.
    static func isolatedWorkflowDefaults(remembering workflow: ProjectWorkflow? = nil) -> UserDefaults {
        let name = "bitmatch.workflow.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        if let workflow {
            defaults.set(workflow.rawValue, forKey: PhotographerJobViewModel.lastWorkflowKey)
        }
        return defaults
    }
}
