import Foundation

/// What the assistant needs from the page the user is looking at. The Mac's `Tab` and iOS's web view
/// implement it with their own injection calls; the rules for what context to gather live here.
@MainActor
public protocol PageSource: AnyObject {
    var pageURL: URL? { get }
    var pageTitle: String { get }
    /// True while a YouTube video is open (its transcript is the content).
    var isYouTubeVideo: Bool { get }
    /// The text last selected on the page, if any.
    var selectedText: String? { get }
    /// The readable text of the page (`dom.extract`), cut to `maxChars`.
    func extractPage(maxChars: Int) async throws -> PageContent
    func youTubeTranscript() async throws -> Transcript
    func seekVideo(to seconds: Double) async
}

/// Builds what an assistant request carries about the current page. Failures degrade to less context
/// rather than failing a chat; summaries and explanations report them.
@MainActor
public enum PageContext {
    public struct Gathered: Sendable {
        public var page: PageContent?
        public var transcript: Transcript?
        public var selection: String?
    }

    static func isWebPage(_ url: URL?) -> Bool { url?.scheme == "http" || url?.scheme == "https" }

    /// Page text, transcript and selection for a chat message.
    public static func gather(from source: (any PageSource)?, includePage: Bool, includeSelection: Bool) async -> Gathered {
        guard let source else { return Gathered() }
        var gathered = Gathered()
        if includePage, isWebPage(source.pageURL) {
            if source.isYouTubeVideo { gathered.transcript = try? await source.youTubeTranscript() }
            do {
                gathered.page = try await source.extractPage(maxChars: 120_000)
            } catch {
                Log.agent.info("Page extraction failed: \(String(describing: error), privacy: .public)")
                gathered.page = PageContent(url: source.pageURL?.absoluteString, title: source.pageTitle, text: "")
            }
        }
        gathered.selection = includeSelection ? source.selectedText : nil
        return gathered
    }

    /// A summary of the open video (its transcript) or page. Throws when the content can't be read.
    public static func summaryRequest(from source: any PageSource) async throws -> AssistantRequest {
        if source.isYouTubeVideo {
            var request = AssistantRequest(task: .summarizeVideo)
            request.transcript = try await source.youTubeTranscript()
            request.page = PageContent(url: source.pageURL?.absoluteString, title: source.pageTitle)
            return request
        }
        var request = AssistantRequest(task: .summarize)
        request.page = try await source.extractPage(maxChars: 200_000)
        return request
    }

    /// An explanation of `selection`, with a shorter slice of the page for context when it can be read.
    public static func explainRequest(_ selection: String, from source: (any PageSource)?) async -> AssistantRequest {
        var request = AssistantRequest(task: .explainSelection, selection: selection)
        request.page = try? await source?.extractPage(maxChars: 20_000)
        return request
    }
}
