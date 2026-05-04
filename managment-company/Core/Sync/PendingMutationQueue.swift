import Combine
import Foundation
import Network

/// Локальная очередь «провести оплату по графику» при сбое сети / 5xx. Ключ `Idempotency-Key` фиксирован на одну попытку пользователя и повторно шлётся при доставке из очереди.
@MainActor
final class PendingMutationQueue: ObservableObject {
    static let shared = PendingMutationQueue()

    @Published private(set) var pendingCount: Int = 0

    private var items: [QueuedMarkPaidMutation] = []
    private var pathMonitor: NWPathMonitor?
    private let monitorQueue = DispatchQueue(label: "PendingMutationQueue.network")
    private var isProcessing = false

    private var fileURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("pending-mark-paid-mutations.json", isDirectory: false)
    }

    private init() {
        load()
    }

    func startMonitoring(authManager: AuthManager) {
        if pathMonitor != nil { return }
        let mon = NWPathMonitor()
        pathMonitor = mon
        mon.pathUpdateHandler = { [weak self] path in
            guard path.status == .satisfied else { return }
            Task { @MainActor in
                await self?.processQueue(authManager: authManager)
            }
        }
        mon.start(queue: monitorQueue)
    }

    func stopMonitoring() {
        pathMonitor?.cancel()
        pathMonitor = nil
    }

    /// Убирает предыдущую невыполненную запись по тому же `scheduleId`, подставляет новую (последняя побеждает).
    func enqueueMarkPaid(
        scheduleId: String,
        leaseId: String,
        body: MarkSchedulePaidRequest,
        idempotencyKey: String
    ) throws {
        let data = try JSONEncoder().encode(body)
        items.removeAll { $0.scheduleId == scheduleId }
        items.append(
            QueuedMarkPaidMutation(
                idempotencyKey: idempotencyKey,
                scheduleId: scheduleId,
                leaseId: leaseId,
                bodyJSON: data,
                attemptCount: 0,
                createdAt: Date()
            )
        )
        save()
    }

    func processQueue(authManager: AuthManager) async {
        guard !items.isEmpty, !isProcessing else { return }
        guard authManager.isAuthenticated else { return }
        isProcessing = true
        defer { isProcessing = false }

        processingLoop: while let first = items.first {
            do {
                let body = try JSONDecoder().decode(MarkSchedulePaidRequest.self, from: first.bodyJSON)
                _ = try await APIClient.shared.request(
                    "/v1/payment-schedules/\(first.scheduleId)/mark-paid",
                    method: "POST",
                    body: body,
                    idempotencyKey: first.idempotencyKey,
                    tokenProvider: { await MainActor.run { authManager.accessToken } },
                    refreshAndRetry: { await authManager.refreshToken() }
                ) as SchedulePaymentResult
                let leaseId = first.leaseId
                items.removeFirst()
                save()
                Self.notifyLeaseAffected(leaseId)
            } catch let api as APIError {
                switch api {
                case .httpStatus(409), .httpStatus(422):
                    let leaseId = first.leaseId
                    items.removeFirst()
                    save()
                    Self.notifyLeaseAffected(leaseId)
                case .httpStatus(let code) where [502, 503, 504].contains(code):
                    bumpFirstAttempt()
                    save()
                    break processingLoop
                case .unauthorized:
                    break processingLoop
                default:
                    break processingLoop
                }
            } catch {
                if Self.isRetryableTransportError(error) {
                    bumpFirstAttempt()
                    save()
                    break processingLoop
                }
                break processingLoop
            }
        }
    }

    private func bumpFirstAttempt() {
        guard !items.isEmpty else { return }
        items[0].attemptCount += 1
        if items[0].attemptCount > 25 {
            items.removeFirst()
        }
    }

    static func isRetryableTransportError(_ error: Error) -> Bool {
        if let url = error as? URLError {
            switch url.code {
            case .notConnectedToInternet, .networkConnectionLost, .timedOut, .cannotFindHost,
                 .cannotConnectToHost, .dnsLookupFailed, .internationalRoamingOff:
                return true
            default:
                break
            }
        }
        let ns = error as NSError
        if ns.domain == NSURLErrorDomain {
            let code = ns.code
            if [NSURLErrorNotConnectedToInternet, NSURLErrorNetworkConnectionLost, NSURLErrorTimedOut,
                NSURLErrorCannotFindHost, NSURLErrorCannotConnectToHost, NSURLErrorDNSLookupFailed].contains(code) {
                return true
            }
        }
        if let api = error as? APIError, case .httpStatus(let c) = api {
            return [502, 503, 504].contains(c)
        }
        return false
    }

    private func load() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            items = []
            pendingCount = 0
            return
        }
        do {
            let data = try Data(contentsOf: fileURL)
            items = try JSONDecoder().decode([QueuedMarkPaidMutation].self, from: data)
            pendingCount = items.count
        } catch {
            items = []
            pendingCount = 0
        }
    }

    private func save() {
        pendingCount = items.count
        do {
            let data = try JSONEncoder().encode(items)
            try data.write(to: fileURL, options: [.atomic])
        } catch {
            // keep in-memory queue; next launch may lose — acceptable for edge case
        }
    }

    private static func notifyLeaseAffected(_ leaseID: String) {
        NotificationCenter.default.post(
            name: .pendingMarkPaidQueueLeaseAffected,
            object: nil,
            userInfo: ["leaseId": leaseID]
        )
    }
}

extension Notification.Name {
    /// После успешной отправки mark-paid из очереди или сброса записи по 409/422. `userInfo["leaseId"]` — `String`.
    static let pendingMarkPaidQueueLeaseAffected = Notification.Name("app.propmanager.pendingMarkPaidQueueLeaseAffected")
}

private struct QueuedMarkPaidMutation: Codable, Equatable {
    let idempotencyKey: String
    let scheduleId: String
    let leaseId: String
    var bodyJSON: Data
    var attemptCount: Int
    let createdAt: Date
}
