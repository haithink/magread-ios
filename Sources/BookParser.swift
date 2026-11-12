import Foundation
import PDFKit
import UIKit
import SwiftSoup
import ZIPFoundation

struct ParsedBook {
    var title: String
    var articles: [Article]
    var cover: Data?
}

enum BookParser {
    // Read individual ZIP entries in memory. Never extract publisher paths onto the filesystem.
    static func parseEPUB(_ url: URL) throws -> ParsedBook {
        let archive = try Archive(url: url, accessMode: .read)
        var total = 0
        func data(_ path: String) throws -> Data {
            guard let entry = archive[path], entry.type == .file,
                  entry.uncompressedSize <= 24 * 1024 * 1024 else {
                throw ReaderError.message("EPUB 内容缺失或单个章节过大：\(path)")
            }
            total += Int(entry.uncompressedSize)
            guard total < 180 * 1024 * 1024 else { throw ReaderError.message("EPUB 解压内容过大。") }
            var output = Data()
            _ = try archive.extract(entry) { output.append($0) }
            return output
        }
        func xml(_ path: String) throws -> Document {
            let raw = try data(path)
            guard let text = String(data: raw, encoding: .utf8) else {
                throw ReaderError.message("EPUB 不是有效的 UTF-8 文档。")
            }
            return try SwiftSoup.parse(text, "", Parser.xmlParser())
        }
        let container = try xml("META-INF/container.xml")
        guard let root = try container.select("rootfile").first(),
              !(try root.attr("full-path")).isEmpty else {
            throw ReaderError.message("EPUB 缺少包文档位置。")
        }
        let opfPath = try root.attr("full-path")
        let package = try xml(opfPath)
        let directory = (opfPath as NSString).deletingLastPathComponent
        let title = try package.getElementsByTag("dc:title").first()?.text()
        var manifest: [String: String] = [:]
        var coverPath: String?
        let coverID = try package.select("metadata meta[name=cover]").first()?.attr("content")
        for item in try package.select("manifest item") {
            let id = try item.attr("id")
            let path = try resolve(try item.attr("href"), relativeTo: directory)
            manifest[id] = path
            if (try item.attr("properties")).contains("cover-image") || id == coverID {
                coverPath = path
            }
        }
        var articles: [Article] = []
        for ref in try package.select("spine itemref") {
            try Task.checkCancellation()
            guard let path = manifest[try ref.attr("idref")] else { continue }
            if (try ref.attr("linear")) == "no" { continue }
            let file = (path as NSString).lastPathComponent.lowercased()
            if ["cover", "toc", "nav.", "titlepage", "colophon", "masthead"].contains(where: file.contains) { continue }
            let raw = try data(path)
            guard let html = String(data: raw, encoding: .utf8) else { continue }
            let doc = try SwiftSoup.parse(html)
            try doc.select("script, style, nav, aside").remove()
            let heading = try doc.select("h1, h2").first()?.text().trimmed
            var paragraphs: [String] = []
            for element in try doc.select("p, h1, h2, h3, blockquote, li") {
                // Avoid doubling p elements nested inside blockquotes or list items.
                if ["blockquote", "li"].contains(element.tagName()), !(try element.select("p")).isEmpty() { continue }
                let text = try element.text().trimmed
                if !text.isEmpty { paragraphs.append(text) }
            }
            if paragraphs.isEmpty, let text = try doc.body()?.text().trimmed, !text.isEmpty { paragraphs = [text] }
            guard !paragraphs.isEmpty else { continue }
            let fallback = (try doc.title()).trimmed
            let articleTitle = heading.flatMap { $0.isEmpty ? nil : $0 }
                ?? (fallback.isEmpty ? paragraphs[0].prefixText(90) : fallback)
            if paragraphs.count > 1, paragraphs.first == articleTitle { paragraphs.removeFirst() }
            articles.append(Article(id: articles.count, title: articleTitle, paragraphs: paragraphs))
        }
        guard !articles.isEmpty else { throw ReaderError.message("EPUB 中没有找到可阅读的章节。") }
        let cover = coverPath.flatMap { try? data($0) }.flatMap { UIImage(data: $0)?.jpegData(compressionQuality: 0.8) }
        return ParsedBook(title: title?.trimmed.isEmpty == false ? title! : url.deletingPathExtension().lastPathComponent,
                          articles: articles, cover: cover)
    }

    static func resolve(_ href: String, relativeTo directory: String) throws -> String {
        let withoutFragment = String(href.split(separator: "#", omittingEmptySubsequences: false)[0])
        guard let decoded = withoutFragment.removingPercentEncoding,
              !decoded.contains(":"), !decoded.hasPrefix("/"), !decoded.contains("\\") else {
            throw ReaderError.message("EPUB 含有无效资源路径。")
        }
        var components: [String] = []
        for component in (directory + "/" + decoded).split(separator: "/") {
            if component == "." { continue }
            if component == ".." {
                guard !components.isEmpty else { throw ReaderError.message("EPUB 资源路径越界。") }
                components.removeLast()
            } else { components.append(String(component)) }
        }
        return components.joined(separator: "/")
    }

    static func parsePDF(_ url: URL) throws -> ParsedBook {
        guard let document = PDFDocument(url: url), document.pageCount > 0 else {
            throw ReaderError.message("无法打开 PDF，文件可能受密码保护或已损坏。")
        }
        guard !document.isLocked else { throw ReaderError.message("请先移除 PDF 密码后再导入。") }
        let title = (document.documentAttributes?[PDFDocumentAttribute.titleAttribute] as? String)?.trimmed
        let cover = document.page(at: 0)?.thumbnail(of: CGSize(width: 400, height: 560), for: .mediaBox)
            .jpegData(compressionQuality: 0.8)
        return ParsedBook(title: title?.isEmpty == false ? title! : url.deletingPathExtension().lastPathComponent,
                          articles: [], cover: cover)
    }
}
