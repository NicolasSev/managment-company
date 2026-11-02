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
        items.removeAll { $0.scheduleId == scheduleId && $0.kind == nil }
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

    /// Lease v2: parks `POST /v1/lease-charges/:id/payments` for retry. Unlike mark-paid it never
    /// replaces an earlier entry for the same charge: every entry is a separate user intent with
    /// its own `Idempotency-Key`, so two partial payments must both survive.
    func enqueueLeaseChargePayment(
        chargeId: String,
        leaseId: String,
        body: PayChargeRequest,
        idempotencyKey: String
    ) throws {
        let data = try JSONEncoder().encode(body)
        guard !items.contains(where: { $0.idempotencyKey == idempotencyKey }) else { return }
        items.append(
            QueuedMarkPaidMutation(
                idempotencyKey: idempotencyKey,
                scheduleId: chargeId,
                leaseId: leaseId,
                bodyJSON: data,
                attemptCount: 0,
                createdAt: Date(),
                kind: QueuedMutationKind.leaseChargePayment
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
                if first.kind == QueuedMutationKind.leaseChargePayment {
                    let body = try JSONDecoder().decode(PayChargeRequest.self, from: first.bodyJSON)
                    _ = try await APIClient.shared.request(
                        "/v1/lease-charges/\(first.scheduleId)/payments",
                        method: "POST",
                        body: body,
                        idempotencyKey: first.idempotencyKey,
                        tokenProvider: { await MainActor.run { authManager.accessToken } },
                        refreshAndRetry: { await authManager.refreshToken() }
                    ) as LeaseCommandResult
                } else {
                    let body = try JSONDecoder().decode(MarkSchedulePaidRequest.self, from: first.bodyJSON)
                    _ = try await APIClient.shared.request(
                        "/v1/payment-schedules/\(first.scheduleId)/mark-paid",
                        method: "POST",
                        body: body,
                        idempotencyKey: first.idempotencyKey,
                        tokenProvider: { await MainActor.run { authManager.accessToken } },
                        refreshAndRetry: { await authManager.refreshToken() }
                    ) as SchedulePaymentResult
                }
                let leaseId = first.leaseId
                items.removeFirst()
                save()
                Self.notifyLeaseAffected(leaseId)
            } catch let api as APIError {
                switch (api.statusCode, api) {
                case (409, _), (422, _):
                    let leaseId = first.leaseId
                    items.removeFirst()
                    save()
                    Self.notifyLeaseAffected(leaseId)
                case (let code?, _) where [502, 503, 504].contains(code):
                    bumpFirstAttempt()
                    save()
                    break processingLoop
                case (_, .unauthorized):
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
        if let status = (error as? APIError)?.statusCode {
            return [502, 503, 504].contains(status)
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

/// Discriminator of queued entries; `nil` (entries written before lease v2) means mark-paid.
private enum QueuedMutationKind {
    static let leaseChargePayment = "lease_charge_payment"
}

/// `scheduleId` holds the payment-schedule id for mark-paid and the lease charge id for
/// `lease_charge_payment` entries.
private struct QueuedMarkPaidMutation: Codable, Equatable {
    let idempotencyKey: String
    let scheduleId: String
    let leaseId: String
    var bodyJSON: Data
    var attemptCount: Int
    let createdAt: Date
    var kind: String? = nil
}
