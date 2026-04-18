/// Which of the three mutually-exclusive surface states `DocumentSurfaceLayoutView`
/// should render. The host picks exactly one; the view doesn't need separate flags
/// plus mode plus overlay-text params.
enum DocumentSurfaceContent {
    case loading(LoadingOverlayState)
    case empty(ContentEmptyStateView.Variant)
    case document(DocumentViewMode)
}
