/// User preferences (SumatraPDF's Options dialog and the matching settings-file
/// keys). Stored in the library file, like Sumatra keeps everything in one
/// settings file, so `-library` runs never see the user's choices.
public struct Settings: Codable, Hashable, Sendable {
    /// Layout for documents without remembered state (Sumatra's DefaultDisplayMode).
    public var defaultMode: ViewMode
    /// Zoom for documents without remembered state (Sumatra's DefaultZoom).
    public var defaultZoom: Zoom
    /// Reopen documents at the page, zoom and layout they were left in (RememberStatePerDocument).
    public var rememberStatePerDocument: Bool
    /// Reopen the last session's windows and tabs at launch (RestoreSession).
    public var restoreSession: Bool
    /// Reload a document when its file changes on disk (ReloadModifiedDocuments).
    public var reloadModifiedDocuments: Bool

    public init(
        defaultMode: ViewMode = ViewMode(), defaultZoom: Zoom = .fitPage, rememberStatePerDocument: Bool = true,
        restoreSession: Bool = true, reloadModifiedDocuments: Bool = true
    ) {
        self.defaultMode = defaultMode
        self.defaultZoom = defaultZoom
        self.rememberStatePerDocument = rememberStatePerDocument
        self.restoreSession = restoreSession
        self.reloadModifiedDocuments = reloadModifiedDocuments
    }

    /// How a document without remembered state is first shown.
    public var initialViewState: ViewState {
        ViewState(mode: defaultMode, zoom: defaultZoom, position: DocumentPosition(page: 0))
    }

    private enum CodingKeys: String, CodingKey {
        case defaultMode, defaultZoom, rememberStatePerDocument, restoreSession, reloadModifiedDocuments
    }

    /// Missing or unreadable keys (an older or newer version wrote the file)
    /// fall back to their defaults one by one instead of resetting everything.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = Settings()
        defaultMode = (try? c.decodeIfPresent(ViewMode.self, forKey: .defaultMode)) ?? defaults.defaultMode
        defaultZoom = (try? c.decodeIfPresent(Zoom.self, forKey: .defaultZoom)) ?? defaults.defaultZoom
        rememberStatePerDocument =
            (try? c.decodeIfPresent(Bool.self, forKey: .rememberStatePerDocument)) ?? defaults.rememberStatePerDocument
        restoreSession = (try? c.decodeIfPresent(Bool.self, forKey: .restoreSession)) ?? defaults.restoreSession
        reloadModifiedDocuments =
            (try? c.decodeIfPresent(Bool.self, forKey: .reloadModifiedDocuments)) ?? defaults.reloadModifiedDocuments
    }
}
