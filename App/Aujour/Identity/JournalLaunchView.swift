import SwiftUI

/// The system launch screen, continued only while the journal is opening.
/// Its image and dimensions also belong to LaunchScreen.storyboard; neither
/// presentation owns a timer or holds back a ready page.
struct JournalLaunchView: View {
    var body: some View {
        ZStack {
            Color("LaunchBackground")
            Image("LaunchIcon")
                .resizable()
                .scaledToFit()
                .frame(width: 112, height: 112)
        }
        .ignoresSafeArea()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Opening your journal")
        .accessibilityIdentifier("openingJournal")
    }
}
