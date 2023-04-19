//
//  ContentView.swift
//  File Finder
//
//  Created by Ben Waco on 4/17/23.
//  Copyright © 2023 Ben Waco. All rights reserved.
//

import SwiftUI
import AppKit
import Foundation

struct ContentView: View {
    @State private var inputFilePath: String = ""
    @State private var outputFolderPath: String = ""
    @State private var excludeSystemFolders: Bool = true
    @State private var consoleText: String = ""
    @State private var isSearching: Bool = false
    @State private var filesScanned: Int = 0
    @State private var filesCopied: Int = 0
    @State private var startTime: Date = Date()
    @State private var hasRequestedFullDiskAccess = false
    
    func getFileNames(from textFile: URL) -> [String] {
        do {
            let fileContent = try String(contentsOf: textFile, encoding: .utf8)
            let lines = fileContent.split(separator: "\n")
            return lines.map { String($0) }
        } catch {
            print("Error reading file: \(error)")
            return []
        }
    }
    
    func searchFiles(in directory: URL, names: [String]) -> [URL] {
        let fileManager = FileManager.default
        let enumerator = fileManager.enumerator(at: directory, includingPropertiesForKeys: nil, options: excludeSystemFolders ? [.skipsPackageDescendants] : [])
        var foundFiles: [URL] = []
        
        while let file = enumerator?.nextObject() as? URL {
            if excludeSystemFolders {
                if isSystemFolder(file.path) {
                    enumerator?.skipDescendants()
                    continue
                } else if file.pathComponents.contains(where: { $0.hasPrefix(".") }) && !file.path.starts(with: FileManager.default.homeDirectoryForCurrentUser.path) {
                    continue
                }
                DispatchQueue.main.async {
                    self.filesScanned += 1
                }
            }
            if names.contains(file.lastPathComponent) {
                foundFiles.append(file)
            }
            
        }
        
        return foundFiles
    }
    
    func searchFilesConcurrently(in directories: [URL], names: [String]) -> [URL] {
        let queue = DispatchQueue(label: "searchFiles", qos: .userInitiated, attributes: .concurrent)
        let group = DispatchGroup()
        var foundFiles: [URL] = []
        
        DispatchQueue.concurrentPerform(iterations: directories.count) { index in
            group.enter()
            let directory = directories[index]
            let results = searchFiles(in: directory, names: names)
            queue.async(flags: .barrier) {
                foundFiles.append(contentsOf: results)
                group.leave()
            }
        }
        
        group.wait()
        
        return foundFiles
    }
    
    
    func isSystemFolder(_ path: String) -> Bool {
        let systemFolders = [
            "/System",
            "/private",
            "/sbin",
            "/usr",
            "/bin",
            "/cores",
            "/etc",
            "/opt",
            "/tmp",
            "/var"
        ]
        return systemFolders.contains { path.starts(with: $0) }
    }
    
    
    
    
    
    func copyFiles(_ files: [URL], to destination: URL) {
        let fileManager = FileManager.default
        var failedCopies = 0
        
        for file in files {
            let target = destination.appendingPathComponent(file.lastPathComponent)
            
            do {
                try fileManager.copyItem(at: file, to: target)
                DispatchQueue.main.async {
                    self.filesCopied += 1
                }
            } catch {
                print("Error copying file: \(error)")
                failedCopies += 1
            }
        }
        
        DispatchQueue.main.async {
            self.consoleText += "Searched \(self.filesScanned) files\n"
            self.consoleText += "Copied \(self.filesCopied) files\n"
            
            // Calculate the elapsed time
            let elapsedTime = Date().timeIntervalSince(self.startTime)
            let elapsedTimeFormatted = String(format: "%.2f", elapsedTime)
            self.consoleText += "Time elapsed: \(elapsedTimeFormatted) seconds\n"
        }
        
    }
    
    func hasFullDiskAccess() -> Bool {
        let protectedFolder = URL(fileURLWithPath: "/Library/Application Support/com.apple.TCC")
        let fileManager = FileManager.default
        
        do {
            let _ = try fileManager.contentsOfDirectory(atPath: protectedFolder.path)
            return true
        } catch {
            return false
        }
    }
    
    
    func requestFullDiskAccess() -> Bool {
        guard !hasFullDiskAccess() else { return true }
        let alert = NSAlert()
        alert.messageText = "Full Disk Access Required"
        alert.informativeText = """
        This app requires full disk access to search for files across your system.
        
        Please follow these steps:
        
        1. Open System Preferences.
        2. Go to Security & Privacy > Privacy > Full Disk Access.
        3. Click the lock icon to make changes.
        4. Click the '+' button and add this app to the list.
        
        Once you have granted full disk access, you can use this app to search for files. If the app doesn't work as expected, please try restarting it.
        """
        alert.addButton(withTitle: "Open System Preferences")
        alert.addButton(withTitle: "Cancel")
        
        let response = alert.runModal()
        
        if response == .alertFirstButtonReturn {
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
                NSWorkspace.shared.open(url)
            } else {
                consoleText += "Failed to open System Preferences. Please open it manually and grant access to this app.\n"
            }
        }
        return false
    }
    
    
    
    func startProcessing() {
        consoleText = "" // Clear the console when starting a new search
        consoleText += "Starting file processing...\n"
        startTime = Date() // Record the start time
        
        guard let inputFileURL = URL(string: "file://" + inputFilePath),
              let outputFolderURL = URL(string: "file://" + outputFolderPath) else {
            consoleText += "Invalid input file or output folder path\n"
            return
        }
        
        isSearching = true // Set isSearching to true when starting the search
        filesScanned = 0 // Reset filesScanned when starting the search
        filesCopied = 0 // Reset filesCopied when starting the search
        DispatchQueue.global(qos: .userInitiated).async {
            let fileNames = self.getFileNames(from: inputFileURL)
            
            // Search in the user's home directory and mounted volumes
            let homeDirectory = FileManager.default.homeDirectoryForCurrentUser
            if let volumes = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: nil, options: []) {
                let directories = [homeDirectory] + volumes
                let foundFiles = self.searchFilesConcurrently(in: directories, names: fileNames)
                
                self.copyFiles(foundFiles, to: outputFolderURL)
                self.isSearching = false
            }
        }
    }
    
    
    
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Input File:")
                TextField("Input File", text: $inputFilePath)
                Button("Browse") {
                    browseInputFile()
                }
            }
            
            HStack {
                Text("Output Folder:")
                TextField("Output Folder", text: $outputFolderPath)
                Button("Browse") {
                    browseOutputFolder()
                }
            }
            
            Toggle("Exclude system folders", isOn: $excludeSystemFolders)
            
            Button("Start") {
                if requestFullDiskAccess() {
                    startProcessing()
                }
            }
            .disabled(isSearching) // Disable the button when isSearching is true
            
            if isSearching {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle())
                Text("\(filesScanned) files scanned")
            }
            
            ScrollView {
                Text(consoleText)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding()
            }
        }
        .padding()
        
        HStack() {
            Text("Developed by Ben Waco. Source Code: https://github.com/benwaco/FileFinder").padding()
            
        }
    }
    
    func browseInputFile() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canCreateDirectories = false
        panel.allowedFileTypes = ["txt"]
        
        if panel.runModal() == .OK {
            if let url = panel.url {
                inputFilePath = url.path
            }
        }
    }
    
    func browseOutputFolder() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        
        if panel.runModal() == .OK {
            if let url = panel.url {
                outputFolderPath = url.path
            }
        }
    }
    
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
