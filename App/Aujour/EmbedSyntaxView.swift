import SwiftUI
import AujourCore

/// How Aujour writes an embed when a photograph goes into a day — the
/// embed-syntax Journal Setting, as something the user can change.
///
/// It sits beside the entry path, under the folder, because all three are the
/// same question asked in three places: *what is in my folder, and what does
/// it say?* The folder is where the files are, the entry path is what the days
/// are called, and this is the one line Aujour writes into a day that is not
/// the user's own words.
///
/// Changing it moves nothing and rewrites nothing. Both spellings are drawn as
/// the picture they name wherever they are written (`EmbedTarget`), so the
/// pictures already in the journal are unaffected — this decides what the next
/// one is written as, which is the whole of the setting.
struct EmbedSyntaxSection: View {
    let journal: Journal

    /// The setting, and changing it. A binding rather than local state,
    /// because the setting travels: one changed on the iPad arrives here while
    /// the sheet is up (ADR 0003), and a control showing its own last answer
    /// would be showing something that is no longer true.
    private var syntax: Binding<EmbedSyntax> {
        Binding(
            get: { journal.embedSyntax },
            set: { chosen in Task { await journal.changeTheEmbedSyntax(to: chosen) } }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("How photos are written into a day")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)

            Picker("How photos are written into a day", selection: syntax) {
                Text("Markdown").tag(EmbedSyntax.standardMarkdown)
                Text("Wiki-style").tag(EmbedSyntax.obsidianWikiLink)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .accessibilityIdentifier("embedSyntax")

            // The setting made concrete on the day the user is in, the way the
            // entry path is: two spellings described in words are two
            // spellings somebody has to imagine, and this is the line that
            // would go in their file.
            if let example = journal.exampleEmbed {
                Text(example)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("embedSyntaxExample")
            }

            Text(
                """
                Aujour shows both kinds wherever they're written — this only \
                decides what it writes. Wiki-style matches Obsidian; markdown \
                is what everything else reads.
                """
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
