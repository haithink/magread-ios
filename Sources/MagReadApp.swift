import SwiftUI

extension Color {
    static let ink = Color(red: 0.12, green: 0.25, blue: 0.29)
    static let paper = Color(uiColor: .systemGroupedBackground)
}

@main
struct MagReadApp: App {
    @StateObject private var library = LibraryStore()
    @StateObject private var settings = SettingsStore()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            TabView {
                LibraryView().tabItem { Label("书架", systemImage: "books.vertical") }
                NavigationStack { WordbookView() }.tabItem { Label("生词本", systemImage: "character.book.closed") }
                NavigationStack { SettingsView() }.tabItem { Label("设置", systemImage: "slider.horizontal.3") }
            }
            .tint(.ink)
            .environmentObject(library)
            .environmentObject(settings)
            .alert("提示", isPresented: Binding(get: { library.error != nil }, set: { if !$0 { library.error = nil } })) {
                Button("好") { library.error = nil }
            } message: { Text(library.error ?? "") }
            .onChange(of: scenePhase) { _, phase in if phase != .active { library.flush() } }
        }
    }
}

struct JobProgressView: View {
    @ObservedObject var job: GenerationJob
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if job.running {
                HStack {
                    ProgressView()
                    VStack(alignment: .leading, spacing: 4) {
                        Text(job.progress.phase).font(.subheadline.weight(.medium))
                        TimelineView(.periodic(from: job.started, by: 1)) { timeline in
                            Text("\(Int(timeline.date.timeIntervalSince(job.started))) 秒 · 已接收 \(job.progress.characters) 字")
                                .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                        }
                    }
                    Spacer()
                    Button("取消") { job.cancel() }.font(.subheadline)
                }
            }
            if let error = job.error { Text(error).font(.callout).foregroundStyle(.red).textSelection(.enabled) }
        }
        .padding(job.running || job.error != nil ? 14 : 0)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
    }
}
