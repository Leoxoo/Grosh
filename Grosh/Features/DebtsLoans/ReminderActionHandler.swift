import SwiftData
import SwiftUI
import UserNotifications

/// Where a tap on a reminder's "Text them" action leaves the Text them request until the app shows it
/// (``View/presentsTextThem(_:)``).
@Observable
final class TextThemInbox {
    var reminder: TextReminder?
}

/// Receives the user's taps on reminder notification actions. "Text them" opens the app and fills the inbox with the
/// message for the Person the notification names, which the root view presents as the Messages compose sheet. Nothing is
/// sent here: the user taps Send in the sheet.
final class ReminderActionHandler: NSObject, UNUserNotificationCenterDelegate {
    private let inbox: TextThemInbox
    private let context: ModelContext

    private init(inbox: TextThemInbox, context: ModelContext) {
        self.inbox = inbox
        self.context = context
    }

    /// Makes the handler the notification center's delegate and registers the notification actions
    /// (``LocalNotificationReminders/registerActions(on:)``). Called once, as the app starts, so a notification that
    /// launches the app is delivered to it. The center holds its delegate weakly: the caller keeps the result.
    static func install(inbox: TextThemInbox, context: ModelContext) -> ReminderActionHandler {
        let handler = ReminderActionHandler(inbox: inbox, context: context)
        UNUserNotificationCenter.current().delegate = handler
        LocalNotificationReminders.registerActions()
        return handler
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse
    ) async {
        guard response.actionIdentifier == LocalNotificationReminders.textThemAction else { return }
        let info = response.notification.request.content.userInfo as? [String: String] ?? [:]
        await openTextThem(info)
    }

    /// Fills the inbox with the message for the Person `info` (a notification's user info) names, using their number and
    /// Contacts link as they are in the store now.
    private func openTextThem(_ info: [String: String]) {
        let name = info[TextReminder.InfoKey.person] ?? ""
        let people = (try? context.fetch(Person.everyone)) ?? []
        inbox.reminder = TextReminder(userInfo: info, person: PeopleByName(people).person(named: name))
    }
}

extension View {
    /// Presents Text them when a reminder notification's "Text them" action asks for it. Use once, at the app's top
    /// level.
    func presentsTextThem(_ inbox: TextThemInbox) -> some View {
        modifier(TextThemPresenter(inbox: inbox))
    }
}

private struct TextThemPresenter: ViewModifier {
    @Bindable var inbox: TextThemInbox

    func body(content: Content) -> some View {
        content
            .textThemSheet($inbox.reminder)
    }
}
