import Testing
import UIKit
@testable import Romy

@MainActor
struct LookAroundPictureTests {
    private let first = ProposalPlace(name: "最初の店", latitude: 35, longitude: 135)
    private let second = ProposalPlace(name: "次の店", latitude: 36, longitude: 136)
    private let size = CGSize(width: 600, height: 256)

    @Test func aCompletedLookupWithoutImageryStopsLoading() async {
        let model = LookAroundPictureModel(loadImage: { _, _ in nil })
        #expect(isLoading(model.phase(for: first)))
        await model.load(first, size: size)
        guard case .unavailable = model.phase(for: first) else {
            Issue.record("画像なしの取得が終わっても読み込み中のままです")
            return
        }
    }

    @Test func aNewPlaceDoesNotShowThePreviousPlacesImageBeforeItsTaskStarts() async {
        let image = UIImage()
        let model = LookAroundPictureModel(loadImage: { _, _ in image })
        await model.load(first, size: size)
        guard case let .available(loaded) = model.phase(for: first) else {
            Issue.record("取得した画像が表示されません")
            return
        }
        #expect(loaded === image)
        #expect(isLoading(model.phase(for: second)))
    }

    @Test(.timeLimit(.minutes(1)))
    func aLateAnswerFromThePreviousPlaceCannotReplaceTheCurrentImage() async {
        var pending: [String: CheckedContinuation<UIImage?, Never>] = [:]
        let model = LookAroundPictureModel(loadImage: { place, _ in
            await withCheckedContinuation { pending[place.name] = $0 }
        })
        let firstTask = Task { await model.load(first, size: size) }
        while pending[first.name] == nil { await Task.yield() }
        #expect(isLoading(model.phase(for: first)))
        let secondTask = Task { await model.load(second, size: size) }
        while pending[second.name] == nil { await Task.yield() }
        let current = UIImage()
        pending[second.name]?.resume(returning: current)
        await secondTask.value
        pending[first.name]?.resume(returning: UIImage())
        await firstTask.value
        guard case let .available(loaded) = model.phase(for: second) else {
            Issue.record("次の店の画像が失われました")
            return
        }
        #expect(loaded === current)
    }

    @Test(.timeLimit(.minutes(1)))
    func aCancelledLookupDoesNotPublishAnImageEvenIfTheLoaderReturnsOne() async {
        var pending: CheckedContinuation<UIImage?, Never>?
        let model = LookAroundPictureModel(loadImage: { _, _ in
            await withCheckedContinuation { pending = $0 }
        })
        let task = Task { await model.load(first, size: size) }
        while pending == nil { await Task.yield() }
        task.cancel()
        pending?.resume(returning: UIImage())
        await task.value
        #expect(isLoading(model.phase(for: first)))
    }

    @Test func aPictureThatComesBackAtOnceStillLoadsForTheMinimumTime() async {
        let model = LookAroundPictureModel(minimumLoading: .milliseconds(150), loadImage: { _, _ in UIImage() })
        let clock = ContinuousClock()
        let started = clock.now
        await model.load(first, size: size)
        #expect(clock.now - started >= .milliseconds(150))
        guard case .available = model.phase(for: first) else {
            Issue.record("最短時間のあとに画像が表示されません")
            return
        }
    }

    private func isLoading(_ phase: LookAroundPictureModel.Phase) -> Bool {
        if case .loading = phase { return true }
        return false
    }
}
