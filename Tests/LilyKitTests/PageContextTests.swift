import Foundation
import Testing
@testable import LilyKit

@MainActor
private final class FakePage: PageSource {
    var pageURL: URL? = URL(string: "https://example.com/a")
    var pageTitle = "Example"
    var isYouTubeVideo = false
    var selectedText: String? = "picked"
    var extractFails = false
    var transcriptFails = false
    var requestedChars: [Int] = []

    func extractPage(maxChars: Int) async throws -> PageContent {
        requestedChars.append(maxChars)
        if extractFails { throw IPCError.unavailable("down") }
        return PageContent(url: pageURL?.absoluteString, title: pageTitle, text: "body")
    }
    func youTubeTranscript() async throws -> Transcript {
        if transcriptFails { throw IPCError.unavailable("no captions") }
        return Transcript(videoId: "v", text: "words")
    }
    func seekVideo(to seconds: Double) async {}
}

@MainActor
@Suite struct PageContextTests {
    @Test func chatGetsPageAndSelection() async {
        let page = FakePage()
        let got = await PageContext.gather(from: page, includePage: true, includeSelection: true)
        #expect(got.page?.text == "body" && got.selection == "picked" && got.transcript == nil)
        #expect(page.requestedChars == [120_000])
    }

    @Test func pageAndSelectionAreOptional() async {
        let got = await PageContext.gather(from: FakePage(), includePage: false, includeSelection: false)
        #expect(got.page == nil && got.selection == nil)
    }

    @Test func nonWebPagesAreNotRead() async {
        let page = FakePage()
        page.pageURL = URL(string: "file:///tmp/a.html")
        let got = await PageContext.gather(from: page, includePage: true, includeSelection: false)
        #expect(got.page == nil && page.requestedChars.isEmpty)
    }

    @Test func failedExtractionDegradesToAnEmptyPage() async {
        let page = FakePage()
        page.extractFails = true
        let got = await PageContext.gather(from: page, includePage: true, includeSelection: false)
        #expect(got.page?.title == "Example" && got.page?.text == "")
    }

    @Test func videosAddTheirTranscriptAndSurviveWithoutCaptions() async {
        let page = FakePage()
        page.isYouTubeVideo = true
        var got = await PageContext.gather(from: page, includePage: true, includeSelection: false)
        #expect(got.transcript?.text == "words")
        page.transcriptFails = true
        got = await PageContext.gather(from: page, includePage: true, includeSelection: false)
        #expect(got.transcript == nil && got.page != nil)
    }

    @Test func noSourceMeansNoContext() async {
        let got = await PageContext.gather(from: nil, includePage: true, includeSelection: true)
        #expect(got.page == nil && got.transcript == nil && got.selection == nil)
    }

    @Test func summariesChooseVideoOrPageAndReportFailures() async throws {
        let page = FakePage()
        let pageRequest = try await PageContext.summaryRequest(from: page)
        #expect(pageRequest.task == .summarize && pageRequest.page?.text == "body")
        #expect(page.requestedChars == [200_000])
        page.isYouTubeVideo = true
        let video = try await PageContext.summaryRequest(from: page)
        #expect(video.task == .summarizeVideo && video.transcript?.text == "words" && video.page?.title == "Example")
        page.transcriptFails = true
        await #expect(throws: (any Error).self) { try await PageContext.summaryRequest(from: page) }
    }

    @Test func explainingUsesASmallerSliceAndToleratesFailure() async {
        let page = FakePage()
        let request = await PageContext.explainRequest("why", from: page)
        #expect(request.task == .explainSelection && request.selection == "why" && request.page?.text == "body")
        #expect(page.requestedChars == [20_000])
        page.extractFails = true
        let degraded = await PageContext.explainRequest("why", from: page)
        #expect(degraded.page == nil && degraded.selection == "why")
    }
}
