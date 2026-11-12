import SwiftUI

/// The answers given before, newest first and grouped by day: each the problem and its
/// answer, opened again with a click.
struct HistoryView: View {
    @Bindable var model: LearnModel
    let history: History

    var body: some View {
        let days = groups()
        VStack(spacing: 0) {
            if history.entries.isEmpty {
                Text("No answers yet")
                    .font(.system(size: 14))
                    .foregroundStyle(Z.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                search
                    .padding(.top, 18)
                    .padding(.horizontal, 44)
                if days.isEmpty {
                    Text("Nothing matches")
                        .font(.system(size: 14))
                        .foregroundStyle(Z.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(days, id: \.title) { day in
                                Text(day.title)
                                    .font(.system(size: 12.5, weight: .semibold))
                                    .foregroundStyle(Z.secondary)
                                    .padding(.top, 18)
                                    .padding(.bottom, 8)
                                    .padding(.horizontal, 14)
                                ForEach(day.entries) { entry in row(entry) }
                            }
                        }
                        .frame(maxWidth: 760)
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 44)
                        .padding(.bottom, 24)
                    }
                }
            }
            footer(isEmpty: history.entries.isEmpty)
        }
        .confirmationDialog("Clear the history?", isPresented: $model.confirmsClear) {
            if history.entries.contains(where: \.isPinned) {
                Button("Clear All but Pinned", role: .destructive) { history.clear(keepingPinned: true) }
            }
            Button("Clear Everything", role: .destructive) { history.clear() }
        } message: {
            Text("The answers are removed from this Mac.")
        }
    }

    /// A field to find a past answer by what was asked or what came out.
    private var search: some View {
        TextField("Search", text: $model.historySearch)
            .textFieldStyle(.plain)
            .font(.system(size: 14))
            .padding(.horizontal, 12)
            .frame(height: 32)
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color.white.opacity(0.07)))
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
    }

    private func row(_ entry: History.Entry) -> some View {
        let id = "history.\(entry.id)"
        let hovered = model.hovered == id
        let opens = history.canOpen(entry)
        return HStack(alignment: .center, spacing: 18) {
            VStack(alignment: .leading, spacing: 2) {
                MathText(text: entry.question, size: 15, weight: .medium)
                    .foregroundStyle(Z.text)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if let topic = entry.topic {
                    Text(topic).font(.system(size: 11.5)).foregroundStyle(Z.tertiary)
                }
            }
            Spacer(minLength: 24)
            MathText(text: entry.answer, size: 15, weight: .semibold, plainFont: .system(size: 15, weight: .semibold).monospacedDigit())
                .foregroundStyle(model.softBlue)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: 280, alignment: .trailing)
            Text(entry.date.formatted(date: .omitted, time: .shortened))
                .font(.system(size: 12).monospacedDigit())
                .foregroundStyle(Z.tertiary)
                .frame(width: 64, alignment: .trailing)
        }
        .padding(.horizontal, 14)
        .frame(minHeight: entry.topic == nil ? 40 : 50)
        .padding(.vertical, MathText.pieces(entry.question) != nil || MathText.pieces(entry.answer) != nil ? 6 : 0)
        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color.white.opacity(hovered && opens ? 0.08 : 0)))
        .contentShape(Rectangle())
        .onTapGesture {
            guard opens else { return }
            if model.openEntry?(entry) != true { model.message = "MathPeek can't work that one out again." }
        }
        .hoverID(id, in: model)
        .help(opens ? "" : "Read from a picture, so it can't be opened again")
        .contextMenu {
            Button(entry.isPinned ? "Unpin" : "Pin") { history.togglePin(entry) }
            Button("Delete") { history.remove(entry) }
        }
    }

    private func footer(isEmpty: Bool) -> some View {
        HStack(spacing: 18) {
            // Back to the working as it was, or to the field for typing a problem.
            LinkButton(model: model, id: "history.back", title: "Back") {
                withAnimation(.easeOut(duration: 0.18)) { model.showsHistory = false }
            }
            if let message = model.message {
                Text(message).font(.system(size: 12.5)).foregroundStyle(Z.red)
            }
            Spacer()
            if !isEmpty {
                LinkButton(model: model, id: "history.clear", title: "Clear History") { model.confirmsClear = true }
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 62)
        .background(Color.black.opacity(0.2))
        .overlay(alignment: .top) { Rectangle().fill(Z.hairline).frame(height: 1) }
    }

    /// The entries matching the search: what's pinned first, then by day (Today, Yesterday,
    /// then the date).
    private func groups() -> [(title: String, entries: [History.Entry])] {
        let words = model.historySearch.lowercased().split(separator: " ").map(String.init)
        let matching = history.entries.filter { entry in
            let text = (entry.question + " " + entry.answer + " " + (entry.topic ?? "")).lowercased()
            return words.allSatisfy { text.contains($0) }
        }
        var result: [(title: String, entries: [History.Entry])] = []
        let pinned = matching.filter(\.isPinned)
        if !pinned.isEmpty { result.append(("Pinned", pinned)) }
        let calendar = Calendar.current
        for entry in matching where !entry.isPinned {
            let title: String
            if calendar.isDateInToday(entry.date) {
                title = "Today"
            } else if calendar.isDateInYesterday(entry.date) {
                title = "Yesterday"
            } else {
                title = entry.date.formatted(.dateTime.weekday(.wide).day().month(.wide))
            }
            if result.last?.title == title {
                result[result.count - 1].entries.append(entry)
            } else {
                result.append((title, [entry]))
            }
        }
        return result
    }
}
