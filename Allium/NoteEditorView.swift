//
//  NoteEditorView.swift
//  Allium
//
//  Created by Snoolie Keffaber on 2025/05/27.
//

import SwiftUI
import UniformTypeIdentifiers
import ZIPFoundation
import Down

// MARK: - Updated Note Editor
struct MarkdownEditorView: View {
    @Binding var text: String
    @Binding var currentSelection: NSRange?
    @State private var editorMode: EditorMode = .edit
    @State private var formattedText = NSAttributedString()
    
    enum EditorMode: String, CaseIterable {
        case edit = "Edit"
        case preview = "Preview"
    }
    
    var body: some View {
        /*VStack(spacing: 0) {
            Picker("Mode", selection: $editorMode) {
                ForEach(EditorMode.allCases, id: \.self) { mode in
                    Text(mode.rawValue)
                }
            }
            .pickerStyle(.segmented)
            .padding()
            
            Group {
                switch editorMode {
                case .edit:
                    SyntaxHighlightedEditor(text: $text)
                case .preview:
                    ScrollView {
                        MarkdownPreview(text: text)
                            .padding()
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }*/
        VStack(spacing: 0) {
            SyntaxHighlightedEditor(text: $text, currentSelection: $currentSelection)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

// MARK: - Syntax Highlighted Editor
struct SyntaxHighlightedEditor: UIViewRepresentable {
    @Binding var text: String
    @Binding var currentSelection: NSRange?
    let syntaxHighlighter = SyntaxHighlighter()
    
    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.delegate = context.coordinator
        textView.font = .monospacedSystemFont(ofSize: 17, weight: .regular)
        textView.autocapitalizationType = .none
        textView.autocorrectionType = .no
        return textView
    }
    
    func updateUIView(_ uiView: UITextView, context: Context) {
        if uiView.attributedText.string != text {
            let highlightedText = syntaxHighlighter.highlight(text)
            uiView.attributedText = highlightedText
        }
                
        if let range = currentSelection {
            uiView.selectedRange = range
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, currentSelection: $currentSelection)
    }
    
    class Coordinator: NSObject, UITextViewDelegate {
        @Binding var text: String
        @Binding var currentSelection: NSRange?
        
        init(text: Binding<String>, currentSelection: Binding<NSRange?>) {
            _text = text
            _currentSelection = currentSelection
        }
        
        func textViewDidChange(_ textView: UITextView) {
            text = textView.text
        }
        
        func textViewDidChangeSelection(_ textView: UITextView) {
            currentSelection = textView.selectedRange
        }
    }
}

// MARK: - Syntax Highlighter
class SyntaxHighlighter {
    private let styles: [NSAttributedString.Key: Any] = [
        .font: UIFont.monospacedSystemFont(ofSize: 17, weight: .regular),
        .foregroundColor: UIColor.label
    ]
    
    private let patterns: [(pattern: String, attributes: [NSAttributedString.Key: Any])] = [
        (pattern: "\\*\\*(.*?)\\*\\*", attributes: [.font: UIFont.boldSystemFont(ofSize: 17)]),
        (pattern: "\\*(.*?)\\*", attributes: [.font: UIFont.italicSystemFont(ofSize: 17)]),
        (pattern: "#{1,6}\\s(.*?)$", attributes: [
            .font: UIFont.systemFont(ofSize: 24, weight: .bold),
            .foregroundColor: UIColor.systemBlue
        ]),
        (pattern: "`{3}(\\n|.)*?`{3}", attributes: [
            .backgroundColor: UIColor.secondarySystemBackground,
            .font: UIFont.monospacedSystemFont(ofSize: 15, weight: .regular)
        ]),
        (pattern: "`(.*?)`", attributes: [
            .backgroundColor: UIColor.secondarySystemBackground,
            .font: UIFont.monospacedSystemFont(ofSize: 15, weight: .regular)
        ])
    ]
    
    func highlight(_ text: String) -> NSAttributedString {
        let attributedString = NSMutableAttributedString(string: text, attributes: styles)
        
        for (pattern, attributes) in patterns {
            do {
                let regex = try NSRegularExpression(pattern: pattern, options: [])
                let matches = regex.matches(in: text, options: [], range: NSRange(location: 0, length: text.utf16.count))
                
                for match in matches {
                    attributedString.addAttributes(attributes, range: match.range)
                }
            } catch {
                print("Regex error: \(error)")
            }
        }
        
        return attributedString
    }
}

// MARK: - Markdown Preview
struct MarkdownPreview: UIViewRepresentable {
    let text: String
    let down = Down(markdownString: "")
    
    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.isEditable = false
        textView.backgroundColor = .clear
        return textView
    }
    
    func updateUIView(_ uiView: UITextView, context: Context) {
        let down = Down(markdownString: text)
        do {
            let attributedString = try down.toAttributedString()
            uiView.attributedText = attributedString
        } catch {
            uiView.text = text
        }
    }
}

// MARK: - Text Editor View
struct NoteEditorView: View {
    let note: Note
    @ObservedObject var manager: NotesManager
    @State private var modifiedNote: Note
    @State private var showFindReplace = false
    @State private var searchText = ""
    @State private var replaceText = ""
    @FocusState private var isEditorFocused: Bool
    @State private var currentSelection: NSRange?
    @State private var searchResults: [Range<String.Index>] = []
    @State private var currentSearchIndex = 0
    
    init(note: Note, manager: NotesManager) {
        self.note = note
        self.manager = manager
        self._modifiedNote = State(initialValue: note)
    }
    
    var body: some View {
        VStack(spacing: 0) {
            TextField("Title", text: $modifiedNote.title)
                .font(.title.bold())
                .padding()
                .focused($isEditorFocused)
            
            Divider()
            
            /*TextEditor(text: $modifiedNote.content)
                .font(.system(.body, design: .monospaced))
                .padding()
                .focused($isEditorFocused)
                .onChange(of: modifiedNote) { newValue in
                    manager.updateNote(newValue)
                }*/
            
            MarkdownEditorView(text: $modifiedNote.content, currentSelection: $currentSelection)
            .onChange(of: modifiedNote) { newValue in
                manager.updateNote(newValue)
            }
            
            FormattingToolbar(
                onBold: { formatSelection(prefix: "**", suffix: "**") },
                onItalic: { formatSelection(prefix: "*", suffix: "*") },
                onSearch: { showFindReplace = true },
                onCodeBlock: { wrapCodeBlock() }
            )
            .padding(.horizontal)
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                HStack {
                    Button(action: { showFindReplace = true }) {
                        Image(systemName: "magnifyingglass")
                    }
                    
                    Spacer()
                    
                    Button("Done") { isEditorFocused = false }
                }
            }
            
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button(action: { showFindReplace = true }) {
                        Label("Find & Replace", systemImage: "doc.text.magnifyingglass")
                    }
                    
                    Button {
                        exportNote()
                    } label: {
                        Label("Export", systemImage: "square.and.arrow.up")
                    }
                    
                    Button {
                        togglePin()
                    } label: {
                        Label(
                            modifiedNote.isPinned ? "Unpin" : "Pin",
                            systemImage: modifiedNote.isPinned ? "pin.slash" : "pin"
                        )
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $showFindReplace) {
            FindReplaceView(
                searchText: $searchText,
                replaceText: $replaceText,
                onFind: { searchOperation() },
                onReplace: { replaceOperation() },
                onReplaceAll: { replaceAllOperation() }
            )
        }
    }
    
    private func formatSelection(prefix: String, suffix: String) {
        print("test0")
        guard let range = currentSelection else { return }
        print("test1")
        // Maybe there's a better way but I'm using NSString because I'm too objc-brained, if there is PR it
        let nsString = modifiedNote.content as NSString
        let selectedText = nsString.substring(with: range)
        let formatted = "\(prefix)\(selectedText)\(suffix)"
        modifiedNote.content = nsString.replacingCharacters(in: range, with: formatted)
    }
    
    private func searchOperation() {
        let occurrences = manager.findAllOccurrences(in: modifiedNote, searchText: searchText)
        guard !occurrences.isEmpty else { return }
        // TODO: Do this later I'm bored right now
    }
    
    private func replaceOperation() {
        guard !searchText.isEmpty else { return }
        if let range = modifiedNote.content.range(of: searchText, options: .caseInsensitive) {
            modifiedNote.content.replaceSubrange(range, with: replaceText)
        }
    }
    
    private func replaceAllOperation() {
        modifiedNote = manager.replaceAllOccurrences(
            in: modifiedNote,
            searchText: searchText,
            replaceText: replaceText
        )
    }
    
    private func exportNote() {
        do {
            let url = try manager.exportNote(modifiedNote)
            presentShareSheet(items: [url])
        } catch {
            // TODO: Do an error handling too, right now too lazy to implement
        }
    }
    
    private func togglePin() {
        modifiedNote.isPinned.toggle()
        manager.updateNote(modifiedNote)
    }
    
    private func presentShareSheet(items: [Any]) {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                let rootVC = windowScene.windows.first?.rootViewController else { return }
            
        let activityVC = UIActivityViewController(activityItems: items, applicationActivities: nil)
        rootVC.present(activityVC, animated: true)
    }
    
    private func wrapCodeBlock() {
        modifiedNote.content += "\n```\n// Your code here\n```"
    }
}

// MARK: - Formatting stuff
struct HighlightedText: View {
    let text: String
    let ranges: [Range<String.Index>]
    let currentIndex: Int
    
    var body: some View {
        ZStack(alignment: .topLeading) {
            Text(text)
                .foregroundColor(.clear)
            
            ForEach(Array(ranges.enumerated()), id: \.offset) { index, range in
                Text(String(text[range]))
                    .background(index == currentIndex ? Color.yellow : Color.yellow.opacity(0.4))
                    .offset(
                        x: CGFloat(text.distance(from: text.startIndex, to: range.lowerBound)) * 10,
                        y: 0
                    )
            }
        }
    }
}

struct FormattingToolbar: View {
    var onBold: () -> Void
    var onItalic: () -> Void
    var onSearch: () -> Void
    var onCodeBlock: () -> Void
    
    var body: some View {
        HStack {
            Button(action: onBold) {
                Image(systemName: "bold")
            }
            Button(action: onItalic) {
                Image(systemName: "italic")
            }
            /*Button(action: onSearch) {
                Image(systemName: "magnifyingglass")
            }*/
            /*Button(action: onCodeBlock) {
                Image(systemName: "chevron.left.forwardslash.chevron.right")
            }*/
            Spacer()
        }
        .buttonStyle(.bordered)
        .padding(.vertical, 8)
    }
}

// MARK: - Find/Replace View
struct FindReplaceView: View {
    @Binding var searchText: String
    @Binding var replaceText: String
    var onFind: () -> Void
    var onReplace: () -> Void
    var onReplaceAll: () -> Void
    
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            Form {
                Section {
                    TextField("Find", text: $searchText)
                    TextField("Replace with", text: $replaceText)
                }
                
                Section {
                    Button("Find Next", action: onFind)
                    Button("Replace", action: onReplace)
                    Button("Replace All", action: onReplaceAll)
                }
            }
            .navigationTitle("Find & Replace")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}
