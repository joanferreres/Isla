import SwiftUI
import IslandCore
@MainActor final class PreferencesStore: ObservableObject {
 @Published var value: Preferences { didSet { if let data = try? JSONEncoder().encode(value.normalized()) { UserDefaults.standard.set(data, forKey: "preferences") } } }
 init() { value = UserDefaults.standard.data(forKey: "preferences").flatMap { try? JSONDecoder().decode(Preferences.self, from: $0) }?.normalized() ?? Preferences() }
}
