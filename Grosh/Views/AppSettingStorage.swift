import SwiftUI

extension AppStorage where Value == Bool {
    /// The stored value of `setting`, under its key and starting at its default.
    init(_ setting: AppSetting<Bool>) {
        self.init(wrappedValue: setting.defaultValue, setting.key)
    }
}

extension AppStorage where Value == String {
    /// The stored value of `setting`, under its key and starting at its default.
    init(_ setting: AppSetting<String>) {
        self.init(wrappedValue: setting.defaultValue, setting.key)
    }
}

extension AppStorage where Value: RawRepresentable & Sendable, Value.RawValue == String {
    /// The stored value of `setting`, kept as its raw value under its key and starting at its default.
    init(_ setting: AppSetting<Value>) {
        self.init(wrappedValue: setting.defaultValue, setting.key)
    }
}
