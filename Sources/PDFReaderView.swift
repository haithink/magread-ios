import SwiftUI
import PDFKit

@MainActor
final class PDFReaderModel: ObservableObject {
    weak var view: PDFView?
    @Published var page = 0
    @Published var total = 0
    func context() -> String {
        if let selection = view?.currentSelection?.string, !selection.trimmed.isEmpty {
            return "PDF 第 \(page + 1) 页，选中文字：\n" + selection.prefixText(16000)
        }
        return "PDF 第 \(page + 1) 页正文：\n" + (view?.currentPage?.string ?? "").prefixText(16000)
    }
}

struct PDFReaderView: View {
    let book: Publication
    @EnvironmentObject private var library: LibraryStore
    @StateObject private var model = PDFReaderModel()
    @State private var asking = false
    @State private var context = ""
    @State private var pageInput = ""
    @State private var jumping = false
    var body: some View {
        VStack(spacing: 0) {
            PDFCanvas(url: library.file(book), initialPage: library.current(book).page, model: model) { page in
                library.progress(book, page: page)
            }
            HStack {
                Button("\(model.page + 1) / \(max(1, model.total)) 页") { pageInput = "\(model.page + 1)"; jumping = true }
                    .font(.subheadline.monospacedDigit())
                Spacer()
                Button { context = model.context(); asking = true } label: { Label("阅读问答", systemImage: "bubble.left.and.bubble.right") }
            }.padding(14).background(.bar)
        }
        .navigationTitle(book.title).navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $asking) {
            NavigationStack {
                ConversationView(book: book, articleID: -1, context: context, title: "PDF 阅读问答")
                    .safeAreaInset(edge: .top) {
                        Text("使用选中文字或当前页正文；扫描 PDF 暂不支持 OCR。")
                            .font(.caption).foregroundStyle(.secondary).padding(10).frame(maxWidth: .infinity).background(.bar)
                    }
                    .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("完成") { asking = false } } }
            }
        }
        .alert("跳转页码", isPresented: $jumping) {
            TextField("页码", text: $pageInput).keyboardType(.numberPad)
            Button("跳转") {
                if let page = Int(pageInput), let document = model.view?.document,
                   let target = document.page(at: max(0, min(page - 1, document.pageCount - 1))) { model.view?.go(to: target) }
            }
            Button("取消", role: .cancel) { }
        }
    }
}

struct PDFCanvas: UIViewRepresentable {
    let url: URL
    let initialPage: Int
    let model: PDFReaderModel
    let onPage: (Int) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(model: model, onPage: onPage) }
    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.backgroundColor = .secondarySystemBackground
        view.document = PDFDocument(url: url)
        model.view = view
        if let document = view.document, let page = document.page(at: min(max(0, initialPage), document.pageCount - 1)) { view.go(to: page) }
        context.coordinator.observe(view)
        return view
    }
    func updateUIView(_ view: PDFView, context: Context) { }

    @MainActor
    final class Coordinator: NSObject {
        let model: PDFReaderModel
        let onPage: (Int) -> Void
        init(model: PDFReaderModel, onPage: @escaping (Int) -> Void) { self.model = model; self.onPage = onPage }
        func observe(_ view: PDFView) {
            NotificationCenter.default.addObserver(self, selector: #selector(changed(_:)), name: .PDFViewPageChanged, object: view)
            DispatchQueue.main.async { self.update(view) }
        }
        @objc func changed(_ note: Notification) { if let view = note.object as? PDFView { update(view) } }
        func update(_ view: PDFView) {
            guard let document = view.document, let page = view.currentPage else { return }
            model.page = document.index(for: page)
            model.total = document.pageCount
            onPage(model.page)
        }
        deinit { NotificationCenter.default.removeObserver(self) }
    }
}
