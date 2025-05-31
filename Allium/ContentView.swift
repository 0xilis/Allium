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
    case importError(String)
    
    var errorDescription: String? {
        switch self {
        case .saveError: return "Failed to save notes"
        case .loadError: return "Failed to load notes"
        case .exportError: return "Failed to export note"
        case .invalidInput: return "Invalid input"
        case .importError(let message): return "Import failed: \(message)"
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
    
    func saveNotes() {
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
    
    func deleteNote(byId id: UUID) {
        if let index = notes.firstIndex(where: { $0.id == id }) {
            _ = withAnimation {
                notes.remove(at: index)
            }
            saveNotes()
        }
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
    
    func importNote(from url: URL) throws -> Note {
        guard url.startAccessingSecurityScopedResource() else {
            throw AppError.importError("Access denied")
        }
            
        defer { url.stopAccessingSecurityScopedResource() }
            
        let content = try String(contentsOf: url)
        let title = url.deletingPathExtension().lastPathComponent
            
        return Note(
            title: title,
            content: content,
            date: Date()
        )
    }
}

// MARK: - Main Content View
struct ContentView: View {
    @StateObject private var manager = NotesManager()
    @State private var selectedNote: Note?
    @State private var searchQuery = ""
    @State private var showingOnboarding: Bool
    @State private var isImporting = false
    
    init() {
        let hasCompletedOnboarding = UserDefaults.standard.bool(forKey: "hasCompletedOnboarding")
        _showingOnboarding = State(initialValue: !hasCompletedOnboarding)
    }
    
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
                        
                        Button {
                            isImporting = true
                        } label: {
                            Label("Import Note", systemImage: "square.and.arrow.down")
                        }
                                                
                        #if DEBUG || TESTFLIGHT
                        Button(action: resetOnboarding) {
                            Label("Reset Onboarding", systemImage: "arrow.clockwise")
                        }
                        #endif
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
                OnboardingView {
                    UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
                    showingOnboarding = false
                }
                .edgesIgnoringSafeArea(.all)
            })
            .onAppear() {
                showingOnboarding = !UserDefaults.standard.bool(forKey: "hasCompletedOnboarding")
            }
            .fileImporter(
                isPresented: $isImporting,
                allowedContentTypes: [.plainText, .text],
                allowsMultipleSelection: false
            ) { result in
                handleImportResult(result)
            }
            
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
    
    private func handleImportResult(_ result: Result<[URL], Error>) {
        do {
            let urls = try result.get()
            guard let url = urls.first else { return }
                
            let note = try manager.importNote(from: url)
            manager.notes.insert(note, at: 0)
            manager.saveNotes()
                
        } catch {
            manager.lastError = .importError(error.localizedDescription)
        }
    }
    
    private func resetOnboarding() {
        UserDefaults.standard.set(false, forKey: "hasCompletedOnboarding")
        showingOnboarding = true
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
