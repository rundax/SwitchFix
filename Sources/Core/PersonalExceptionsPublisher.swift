import Foundation

/// Forwards exception snapshots to the engine only when the set genuinely changes. Every
/// preference edit posts the same notification; republishing an unchanged set would invalidate
/// pending corrections and reset detector context for no reason.
public final class PersonalExceptionsPublisher {
    private var published: PersonalExceptionsPolicy?
    private let publish: (PersonalExceptionsPolicy) -> Void

    public init(publish: @escaping (PersonalExceptionsPolicy) -> Void) {
        self.publish = publish
    }

    @discardableResult
    public func publishIfChanged(_ policy: PersonalExceptionsPolicy) -> Bool {
        guard policy != published else { return false }
        published = policy
        publish(policy)
        return true
    }
}
