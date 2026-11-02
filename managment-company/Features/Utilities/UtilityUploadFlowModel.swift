import Combine
import Foundation

/// Where an upload ended, as the flow sheet shows it.
enum UtilityUploadPhase: Equatable {
    case idle
    /// The file is on its way to the server.
    case uploading
    /// The server queued the extraction; the app polls for a bounded time.
    case recognizing
    /// A bill waits for the owner's check (`needs_review`).
    case bill(UtilityBillBrief)
    /// The same file is already on a bill of the owner.
    case duplicate(UtilityBillBrief?)
    /// The document is not a utility bill: a transfer the owner links to the rent or rejects.
    case other(uploadId: String, UtilityOtherResult)
    /// The extraction failed for good; the bill (if any) can be filled in by hand.
    case failed(message: String, bill: UtilityBillBrief?)
    /// 30 seconds passed: the result comes as a push notification.
    case deferred(uploadId: String)
    /// The upload itself was refused or the connection failed.
    case error(String, canRetry: Bool)
}

/// The upload of one document: `POST uploads`, then `GET uploads/:id` for a bounded time (no more than
/// `pollLimit`), then «придёт уведомление». It never polls without a limit.
@MainActor
final class UtilityUploadFlowModel: ObservableObject {
    @Published private(set) var phase: UtilityUploadPhase = .idle
    @Published private(set) var isRejecting = false
    @Published private(set) var didRejectOther = false

    /// Polls made for the current upload (a test reads it to check the limit).
    private(set) var pollCount = 0

    /// 30 s of waiting at 2 s per poll.
    nonisolated static let defaultPollInterval: Duration = .seconds(2)
    nonisolated static let defaultPollLimit: Duration = .seconds(30)
    /// One `GET uploads/:id` that does not answer in this time counts as a missed poll.
    nonisolated static let defaultRequestTimeout: Duration = .seconds(10)

    let target: UtilityUploadTarget
    private let service: UtilityBillsService
    private let pollInterval: Duration
    private let sleep: (Duration) async throws -> Void
    private let maxPolls: Int
    private let pollLimit: Duration
    private let requestTimeout: Duration
    private let now: () -> Date
    private var lastUpload: RecognitionUpload?

    init(
        service: UtilityBillsService,
        target: UtilityUploadTarget = UtilityUploadTarget(),
        pollInterval: Duration = UtilityUploadFlowModel.defaultPollInterval,
        pollLimit: Duration = UtilityUploadFlowModel.defaultPollLimit,
        requestTimeout: Duration = UtilityUploadFlowModel.defaultRequestTimeout,
        now: @escaping () -> Date = { Date() },
        sleep: @escaping (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) {
        self.service = service
        self.target = target
        self.pollInterval = pollInterval
        self.sleep = sleep
        self.pollLimit = pollLimit
        self.requestTimeout = requestTimeout
        self.now = now
        let step = max(0.001, Self.seconds(pollInterval))
        self.maxPolls = max(1, Int((Self.seconds(pollLimit) / step).rounded(.up)))
    }

    private static func seconds(_ duration: Duration) -> Double {
        Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
    }

    var isWorking: Bool {
        switch phase {
        case .uploading, .recognizing: return true
        default: return false
        }
    }

    /// Starts the upload once, detached from the lifetime of the view that shows it: a sheet that is
    /// redrawn or minimised must not cancel a file on its way («Свернуть» keeps it going).
    func begin(_ upload: RecognitionUpload) {
        guard task == nil else { return }
        task = Task { [weak self] in await self?.start(upload) }
    }

    private var task: Task<Void, Never>?

    /// Uploads the document and follows the extraction until a result, a failure or the poll limit.
    func start(_ upload: RecognitionUpload) async {
        guard !isWorking else { return }
        lastUpload = upload
        pollCount = 0
        phase = .uploading
        do {
            let result = try await service.upload(upload, target: target)
            if result.duplicateOf != nil {
                phase = .duplicate(result.bill)
                return
            }
            guard let uploadId = result.uploadId else {
                phase = .error(UtilityBillsError.unknown.userMessage, canRetry: true)
                return
            }
            phase = .recognizing
            await poll(uploadId: uploadId)
        } catch let error as UtilityBillsError {
            phase = .error(Self.message(for: error), canRetry: Self.canRetry(error))
        } catch is CancellationError {
            // Nobody is waiting any more; the server keeps the upload and the push tells the result.
        } catch {
            phase = .error(UtilityBillsError.unknown.userMessage, canRetry: true)
        }
    }

    /// Tries the same document again after an error.
    func retry() async {
        guard let lastUpload else { return }
        await start(lastUpload)
    }

    private func poll(uploadId: String) async {
        // Two limits: the number of polls and the wall clock (a slow answer cannot stretch the wait).
        let deadline = now().addingTimeInterval(Self.seconds(pollLimit))
        for attempt in 0..<maxPolls {
            if attempt > 0 && now() >= deadline { break }
            pollCount += 1
            do {
                let state = try await fetchState(uploadId)
                if let finished = Self.phase(for: state) {
                    phase = finished
                    return
                }
            } catch let error as UtilityBillsError {
                phase = .error(Self.message(for: error), canRetry: Self.canRetry(error))
                return
            } catch is CancellationError {
                return
            } catch is UploadPollTimeout {
                // No answer in time: try again until the deadline.
            } catch {
                phase = .error(UtilityBillsError.unknown.userMessage, canRetry: true)
                return
            }
            if attempt < maxPolls - 1 && now() < deadline {
                do { try await sleep(pollInterval) } catch { return }
            }
        }
        phase = .deferred(uploadId: uploadId)
    }

    private struct UploadPollTimeout: Error {}

    /// `GET uploads/:id` with a time limit of its own.
    private func fetchState(_ uploadId: String) async throws -> UtilityUploadState {
        let service = self.service
        let timeout = requestTimeout
        return try await withThrowingTaskGroup(of: UtilityUploadState?.self) { group in
            group.addTask { try await service.uploadState(id: uploadId) }
            group.addTask {
                try await Task.sleep(for: timeout)
                return nil
            }
            defer { group.cancelAll() }
            guard let first = try await group.next() else { throw UploadPollTimeout() }
            guard let state = first else { throw UploadPollTimeout() }
            return state
        }
    }

    /// The end phase of a state answer, or `nil` while the worker has not finished.
    static func phase(for state: UtilityUploadState) -> UtilityUploadPhase? {
        switch state.status {
        case .queued, .running:
            return nil
        case .failed:
            return .failed(
                message: "Не удалось распознать документ. Введите данные вручную.",
                bill: state.bill
            )
        case .succeeded:
            if state.documentKind == .other, let other = state.other {
                return .other(uploadId: state.uploadId, other)
            }
            if let bill = state.bill { return .bill(bill) }
            return .failed(message: "Документ не распознан как коммунальный счёт.", bill: nil)
        case .unknown:
            return nil
        }
    }

    /// «Отклонить» on an `other` result.
    func rejectOther() async {
        guard case .other(let uploadId, _) = phase, !isRejecting else { return }
        isRejecting = true
        defer { isRejecting = false }
        do {
            _ = try await service.rejectUpload(id: uploadId)
            didRejectOther = true
        } catch let error as UtilityBillsError {
            phase = .error(error.userMessage, canRetry: false)
        } catch {
            phase = .error(UtilityBillsError.unknown.userMessage, canRetry: false)
        }
    }

    private static func message(for error: UtilityBillsError) -> String {
        if error.isFileProblem {
            return "Файл не подошёл. Загрузите JPEG, PNG, HEIC или PDF до 10 МБ (PDF — до 5 страниц)."
        }
        return error.userMessage
    }

    private static func canRetry(_ error: UtilityBillsError) -> Bool {
        switch error {
        case .transport, .unknown: return true
        default: return false
        }
    }
}
