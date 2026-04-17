import Foundation

@MainActor
protocol FolderWatchControllerDelegate: AnyObject {
    func folderWatchControllerCurrentDocumentFileURL(_ controller: FolderWatchController) -> URL?
    func folderWatchControllerOpenDocumentFileURLs(_ controller: FolderWatchController) -> [URL]
    func folderWatchController(_ controller: FolderWatchController, handleEvents events: [FolderWatchChangeEvent], in session: FolderWatchSession, origin: ReaderOpenOrigin)
    func folderWatchControllerShouldSelectNewestDocument(_ controller: FolderWatchController)
    func folderWatchController(_ controller: FolderWatchController, didLiveAutoOpenFileURLs urls: [URL])
    func folderWatchControllerStateDidChange(_ controller: FolderWatchController)
}
