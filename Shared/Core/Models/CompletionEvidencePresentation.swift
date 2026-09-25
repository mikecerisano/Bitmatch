enum CompletionEvidencePresentation {
    static func shouldShowProjectMedia(hasDashboardJob: Bool, hasCardIngests: Bool) -> Bool {
        hasDashboardJob && hasCardIngests
    }
}
