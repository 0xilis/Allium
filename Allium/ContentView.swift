//
//  ContentView.swift
//  Allium
//
//  Created by Snoolie K (0xilis) on 2025/05/15.
//

import SwiftUI
import UniformTypeIdentifiers
import ZIPFoundation

// MARK: - Data Model
struct Note: Identifiable, Codable, Equatable {
    let id: UUID
    var title: String
    var content: String
    var date: Date
    var isPinned: Bool
    
    init(id: UUID = UUID(), title: String = "", content: String = "", date: Date = Date(), isPinned: Bool = false) {
        self.id = id
        self.title = title
        self.content = content
        self.date = date
        self.isPinned = isPinned
    }
}

// MARK: - Error Handling
enum AppError: LocalizedError {
    case saveError
    case loadError
    case exportError
    case invalidInput
    
    var errorDescription: String? {
        switch self {
        case .saveError: return "Failed to save notes"
        case .loadError: return "Failed to load notes"
        case .exportError: return "Failed to export note"
        case .invalidInput: return "Invalid input"
        }
    }
}

// MARK: - Note Row View
struct NoteRowView: View {
    let note: Note
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                if note.isPinned {
                    Image(systemName: "pin.fill")
                        .foregroundColor(.orange)
                        .font(.caption)
                }
                
                Text(note.title.isEmpty ? "New Note" : note.title)
                    .font(.headline)
                    .lineLimit(1)
            }
            
            Text(note.date.formatted(date: .abbreviated, time: .shortened))
                .font(.caption)
                .foregroundStyle(.secondary)
            
            Text(note.content)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .padding(.vertical, 8)
    }
}

// MARK: - Data Manager
class NotesManager: ObservableObject {
    @Published var notes: [Note] = []
    @Published var lastError: AppError?
    
    init() {
        loadNotes()
    }
    
    private func saveNotes() {
        do {
            let data = try JSONEncoder().encode(notes)
            UserDefaults.standard.set(data, forKey: "notes")
        } catch {
            lastError = .saveError
        }
    }
    
    private func loadNotes() {
        do {
            guard let data = UserDefaults.standard.data(forKey: "notes") else {
                /*
                 * If no notes exist, we don't want to return an error,
                 * because likely, this is the first time the user has
                 * opened the app and they haven't created anything yet.
                 */
                notes = []
                return
            }
            let savedNotes = try JSONDecoder().decode([Note].self, from: data)
            notes = savedNotes.sorted { ($0.isPinned && !$1.isPinned) || $0.date > $1.date }
        } catch {
            lastError = .loadError
        }
    }
    
    func addNote() {
        let newNote = Note()
        withAnimation {
            notes.insert(newNote, at: 0)
        }
        saveNotes()
    }
    
    func deleteNote(at index: Int) {
        _ = withAnimation {
            notes.remove(at: index)
        }
        saveNotes()
    }
    
    // MARK: - Formatting Support
    func wrapSelection(_ text: String, prefix: String, suffix: String) -> String {
        return "\(prefix)\(text)\(suffix)"
    }
    
    func updateNote(_ note: Note) {
        if let index = notes.firstIndex(where: { $0.id == note.id }) {
            notes[index] = note
            saveNotes()
        }
    }
    
    func exportNote(_ note: Note) throws -> URL {
        let sanitizedTitle = note.title
            .components(separatedBy: .illegalCharacters)
            .joined()
            .replacingOccurrences(of: " ", with: "_")
        
        let tempURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("\(sanitizedTitle)_\(Date().timeIntervalSince1970)")
            .appendingPathExtension("md")
        
        do {
            try note.content.write(to: tempURL, atomically: true, encoding: .utf8)
            return tempURL
        } catch {
            throw AppError.exportError
        }
    }
    
    // MARK: - Find/Replace
    func findAllOccurrences(in note: Note, searchText: String) -> [Range<String.Index>] {
        guard !searchText.isEmpty else { return [] }
        var ranges: [Range<String.Index>] = []
        var searchStartIndex = note.content.startIndex
        
        while searchStartIndex < note.content.endIndex,
              let range = note.content.range(
                of: searchText,
                options: .caseInsensitive,
                range: searchStartIndex..<note.content.endIndex
              ) {
            ranges.append(range)
            searchStartIndex = range.upperBound
        }
        return ranges
    }
    
    func replaceAllOccurrences(in note: Note, searchText: String, replaceText: String) -> Note {
        var modifiedNote = note
        modifiedNote.content = note.content.replacingOccurrences(
            of: searchText,
            with: replaceText,
            options: .caseInsensitive
        )
        return modifiedNote
    }
    
    func exportAllNotes() throws -> URL {
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
            
        var usedFilenames = Set<String>()
        
        try notes.forEach { note in
            var fileName = "\(note.title.isEmpty ? "Untitled" : note.title).md"
            .components(separatedBy: .illegalCharacters)
            .joined()
            .replacingOccurrences(of: " ", with: "_")
            
            /*
             * This is bad but it's to prevent a case where
             * two notes share the same name, and one
             * overwrites the other. So I just add _number
             * to each note here.
             */
            let baseName = fileName
            var suffix = 2
            
            while usedFilenames.contains(fileName) {
                fileName = "\(baseName)_\(suffix).md"
                suffix += 1
            }
                
            usedFilenames.insert(fileName)
            let fileURL = tempDir.appendingPathComponent(fileName)
            try note.content.write(to: fileURL, atomically: true, encoding: .utf8)
        }
            
        let zipURL = tempDir.deletingLastPathComponent().appendingPathComponent("NotesArchive.zip")
        try FileManager.default.zipItem(at: tempDir, to: zipURL)
            
        return zipURL
    }
}

// MARK: - Main Content View
struct ContentView: View {
    @StateObject private var manager = NotesManager()
    @State private var selectedNote: Note?
    @State private var searchQuery = ""
    @State private var showingOnboarding = true
    
    var filteredNotes: [Note] {
        if searchQuery.isEmpty {
            return manager.notes
        }
        return manager.notes.filter {
            $0.title.localizedCaseInsensitiveContains(searchQuery) ||
            $0.content.localizedCaseInsensitiveContains(searchQuery)
        }
    }
    
    var body: some View {
        NavigationView {
            List {
                SearchBar(text: $searchQuery)
                    .padding(.vertical, 8)
                    .listRowSeparator(.hidden)
                
                ForEach(filteredNotes) { note in
                    NavigationLink(destination: NoteEditorView(note: note, manager: manager)) {
                        NoteRowView(note: note)
                    }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            confirmDelete(note: note)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                        
                        Button {
                            togglePin(note: note)
                        } label: {
                            Label(note.isPinned ? "Unpin" : "Pin", systemImage: note.isPinned ? "pin.slash" : "pin")
                        }
                        .tint(.orange)
                    }
                }
            }
            .navigationTitle("Notes")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button(action: manager.addNote) {
                            Label("New Note", systemImage: "plus")
                        }
                        
                        Button {
                            exportAllNotes()
                        } label: {
                            Label("Export All", systemImage: "square.and.arrow.up.on.square")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .overlay {
                if manager.notes.isEmpty {
                    EmptyStateView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color(.systemBackground))
                }
            }
            .alert("Error", isPresented: .constant(manager.lastError != nil), presenting: manager.lastError) { error in
                Button("OK", role: .cancel) { manager.lastError = nil }
            } message: { error in
                Text(error.errorDescription ?? "Unknown error")
            }
            .fullScreenCover(isPresented: $showingOnboarding, content: {
                OnboardingView.init()
                .edgesIgnoringSafeArea(.all)
            })
            
            Text("Select a note")
                .foregroundStyle(.secondary)
                .font(.largeTitle)
        }
        .navigationViewStyle(.columns)
    }
    
    private func confirmDelete(note: Note) {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let rootViewController = windowScene.windows.first?.rootViewController else {
            return
        }
        
        let alert = UIAlertController(
            title: "Delete Note",
            message: "Are you sure you want to delete this note?",
            preferredStyle: .alert
        )
        
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Delete", style: .destructive) { _ in
            if let index = manager.notes.firstIndex(of: note) {
                manager.deleteNote(at: index)
            }
        })
        
        rootViewController.present(alert, animated: true)
    }
    
    private func togglePin(note: Note) {
        if manager.notes.contains(note) {
            var modifiedNote = note
            modifiedNote.isPinned.toggle()
            manager.updateNote(modifiedNote)
        }
    }
    
    private func presentShareSheet(items: [Any]) {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                let rootVC = windowScene.windows.first?.rootViewController else { return }
            
        let activityVC = UIActivityViewController(activityItems: items, applicationActivities: nil)
        rootVC.present(activityVC, animated: true)
    }
    
    private func exportAllNotes() {
        do {
            let zipURL = try manager.exportAllNotes()
            presentShareSheet(items: [zipURL])
        } catch {
            // TODO: Do an error handling too, right now too lazy to implement
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
            
            TextEditor(text: $modifiedNote.content)
                .font(.system(.body, design: .monospaced))
                .padding()
                .focused($isEditorFocused)
                .onChange(of: modifiedNote) { newValue in
                    manager.updateNote(newValue)
                }
            FormattingToolbar(
                onBold: { formatSelection(prefix: "**", suffix: "**") },
                onItalic: { formatSelection(prefix: "*", suffix: "*") },
                onSearch: { showFindReplace = true }
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

struct SearchBar: UIViewRepresentable {
    @Binding var text: String
    
    func makeUIView(context: Context) -> UISearchBar {
        let searchBar = UISearchBar()
        searchBar.searchBarStyle = .minimal
        searchBar.autocapitalizationType = .none
        searchBar.placeholder = "Search for notes..."
        return searchBar
    }
    
    func updateUIView(_ uiView: UISearchBar, context: Context) {
        uiView.text = text
    }
}

struct EmptyStateView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "note.text")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            Text("No Notes Found")
                .font(.title2)
            Text("Tap the + button to create a new note")
                .foregroundColor(.secondary)
        }
        .padding()
    }
}
