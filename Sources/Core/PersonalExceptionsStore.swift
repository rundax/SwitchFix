import Foundation
import os

public enum AddExceptionResult: Equatable, Sendable {
    case success(PersonalExceptionsPolicy, addedWord: String)
    case duplicate(String)
    case invalid(ExceptionValidationError)
}

public final class PersonalExceptionsStore: @unchecked Sendable {
    public static let preferenceKey = "SwitchFix_personalExceptions_v1"
    public static let currentSchemaVersion = 1

    private let defaults: UserDefaults
    private let lock = OSAllocatedUnfairLock(initialState: ())

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Load validated policy snapshot from storage.
    /// If storage is empty, returns empty policy.
    /// If envelope is invalid/oversized/unknown-version, leaves stored value untouched and returns empty policy.
    public func loadPolicy() -> PersonalExceptionsPolicy {
        return lock.withLock {
            loadPolicyLocked()
        }
    }

    private func loadPolicyLocked() -> PersonalExceptionsPolicy {
        guard let dict = defaults.dictionary(forKey: Self.preferenceKey) else {
            return PersonalExceptionsPolicy.empty
        }

        guard let version = dict["schemaVersion"] as? Int, version == Self.currentSchemaVersion else {
            return PersonalExceptionsPolicy.empty
        }

        guard let wordsArray = dict["words"] as? [String] else {
            return PersonalExceptionsPolicy.empty
        }

        // Reject oversized envelope
        guard wordsArray.count <= PersonalExceptionsPolicy.maxEntries else {
            return PersonalExceptionsPolicy.empty
        }

        var validWords: Set<String> = []
        for word in wordsArray {
            if case .success(let canonical) = PersonalExceptionsPolicy.validate(candidate: word) {
                validWords.insert(canonical)
            }
        }

        return PersonalExceptionsPolicy(words: validWords)
    }

    /// Add a word to personal exceptions.
    public func add(candidate: String) -> AddExceptionResult {
        return lock.withLock {
            let validationResult = PersonalExceptionsPolicy.validate(candidate: candidate)
            guard case .success(let canonical) = validationResult else {
                if case .failure(let error) = validationResult {
                    return .invalid(error)
                }
                return .invalid(.empty)
            }

            var current = loadPolicyLocked().words
            if current.contains(canonical) {
                return .duplicate(canonical)
            }

            guard current.count < PersonalExceptionsPolicy.maxEntries else {
                return .invalid(.capacityExceeded)
            }

            current.insert(canonical)
            persistLocked(words: current)
            let newPolicy = PersonalExceptionsPolicy(words: current)
            return .success(newPolicy, addedWord: canonical)
        }
    }

    /// Remove a word from personal exceptions.
    @discardableResult
    public func remove(word: String) -> PersonalExceptionsPolicy {
        return lock.withLock {
            let canonical = PersonalExceptionsPolicy.canonicalize(word)
            var current = loadPolicyLocked().words
            current.remove(canonical)
            persistLocked(words: current)
            return PersonalExceptionsPolicy(words: current)
        }
    }

    /// Clear all exceptions (for tests or user reset).
    public func removeAll() {
        lock.withLock {
            defaults.removeObject(forKey: Self.preferenceKey)
        }
    }

    /// Direct persistence helper.
    private func persistLocked(words: Set<String>) {
        let sortedWords = words.sorted()
        let dict: [String: Any] = [
            "schemaVersion": Self.currentSchemaVersion,
            "words": sortedWords
        ]
        defaults.set(dict, forKey: Self.preferenceKey)
    }
}
