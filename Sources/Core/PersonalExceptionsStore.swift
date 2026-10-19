import Foundation
import os

public enum AddExceptionResult: Equatable, Sendable {
    case success(PersonalExceptionsPolicy, addedWord: String)
    case duplicate(String)
    case invalid(ExceptionValidationError)
}

/// Why a stored list could not be used as saved. Carries no stored words.
public enum PersonalExceptionsLoadIssue: Equatable, Sendable {
    /// Wrong type, unknown schema version, or more than the allowed entries: nothing was loaded
    /// and the stored value is left untouched until the next explicit edit.
    case unreadable
    /// The envelope was valid, but this many entries failed validation and were ignored.
    case skippedEntries(Int)
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
            loadLocked().policy
        }
    }

    /// Load the validated policy together with a recoverable issue for Settings to report.
    public func loadPolicyReportingIssue() -> (policy: PersonalExceptionsPolicy, issue: PersonalExceptionsLoadIssue?) {
        return lock.withLock {
            loadLocked()
        }
    }

    private func loadPolicyLocked() -> PersonalExceptionsPolicy {
        loadLocked().policy
    }

    private func loadLocked() -> (policy: PersonalExceptionsPolicy, issue: PersonalExceptionsLoadIssue?) {
        guard let stored = defaults.object(forKey: Self.preferenceKey) else {
            return (.empty, nil)
        }

        guard let dict = stored as? [String: Any],
              let version = dict["schemaVersion"] as? Int, version == Self.currentSchemaVersion,
              let wordsArray = dict["words"] as? [Any],
              wordsArray.count <= PersonalExceptionsPolicy.maxEntries else {
            return (.empty, .unreadable)
        }

        var validWords: Set<String> = []
        var skipped = 0
        for value in wordsArray {
            if let word = value as? String,
               case .success(let canonical) = PersonalExceptionsPolicy.validate(candidate: word) {
                validWords.insert(canonical)
            } else {
                skipped += 1
            }
        }

        return (PersonalExceptionsPolicy(words: validWords), skipped > 0 ? .skippedEntries(skipped) : nil)
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
