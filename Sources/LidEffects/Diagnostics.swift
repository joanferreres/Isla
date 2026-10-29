// Adapted from Mac Duo, Apache-2.0; see THIRD-PARTY-NOTICES.md.
import Foundation
import os

/// Read with:
///
///     log show --last 5m --predicate 'subsystem == "local.personal.isla"'
///
/// Notice level, not info: info level lives only in memory, and `log show`
/// reads the on-disk store.
enum Diagnostics {
    static let geometry = Logger(subsystem: "local.personal.isla", category: "geometry")
    static let lid = Logger(subsystem: "local.personal.isla", category: "lid")
}
