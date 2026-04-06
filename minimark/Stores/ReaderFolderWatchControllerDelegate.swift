import Foundation

@MainActor
protocol ReaderFolderWatchControllerDelegate: AnyObject {
    func folderWatchControllerCurrentDocumentFileURL(_ controller: ReaderFolderWatchController) -> URL?
    func folderWatchControllerOpenDocumentFileURLs(_ controller: ReaderFolderWatchController) -> [URL]
    func folderWatchController(_ controller: ReaderFolderWatchController, handleEvents events: [ReaderFolderWatchChangeEvent], in session: ReaderFolderWatchSession, origin: ReaderOpenOrigin)
    func folderWatchControllerShouldSelectNewestDocument(_ controller: ReaderFolderWatchController)
    func folderWatchController(_ controller: ReaderFolderWatchController, didLiveAutoOpenFileURLs urls: [URL])
    func folderWatchControllerStateDidChange(_ controller: ReaderFolderWatchController)
}
