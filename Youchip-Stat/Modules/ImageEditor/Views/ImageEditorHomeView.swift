//
//  ImageEditorHomeView.swift
//  Youchip-Stat
//
//  Экран «Редактор»: список проектов редактора картинок. Создать (загрузить фото),
//  открыть, удалить, переименовать, скачать (ПКМ).
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ImageEditorHomeView: View {
    @ObservedObject private var manager = ImageEditorProjectsManager.shared
    @State private var renamingProject: ImageEditorProjectMeta?
    @State private var renameText: String = ""

    private let columns = [GridItem(.adaptive(minimum: 200, maximum: 260), spacing: 16)]

    var body: some View {
        homeContent
            .sheet(item: $renamingProject) { project in
                renameSheet(project)
            }
    }

    /// Открывает проект в отдельном окне.
    private func openProject(_ id: UUID) {
        ImageEditorWindowManager.shared.openProject(id) { manager.reload() }
    }

    private var homeContent: some View {
        VStack(spacing: 0) {
            HStack {
                Text(^String.Titles.editorImages)
                    .font(.title2).bold()
                Spacer()
                Button(action: { createProject() }) {
                    HStack(spacing: 6) { Image(systemName: "plus"); Text(^String.Titles.editorNewProject) }
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()

            Divider()

            if manager.projects.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: 48)).foregroundColor(.secondary)
                    Text(^String.Titles.editorNoProjects)
                        .foregroundColor(.secondary)
                    Button(action: { createProject() }) {
                        Text(^String.Titles.editorNewProject)
                    }
                    .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(manager.projects) { project in
                            projectCard(project)
                        }
                    }
                    .padding()
                }
            }
        }
    }

    private func projectCard(_ project: ImageEditorProjectMeta) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 8).fill(Color(NSColor.controlBackgroundColor))
                if let thumb = NSImage(contentsOf: manager.thumbnailURL(project.id)) {
                    Image(nsImage: thumb)
                        .resizable().scaledToFit()
                        .padding(6)
                } else {
                    Image(systemName: "photo").font(.system(size: 32)).foregroundColor(.secondary)
                }
            }
            .frame(height: 150)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(NSColor.separatorColor), lineWidth: 1))

            Text(project.name).font(.system(size: 13, weight: .medium)).lineLimit(1)
            Text(project.updatedAt, style: .date).font(.system(size: 11)).foregroundColor(.secondary)
        }
        .contentShape(Rectangle())
        .onTapGesture { openProject(project.id) }
        .contextMenu {
            Button(^String.Titles.open) { openProject(project.id) }
            Button(^String.Titles.download) { downloadProject(project) }
            Button(^String.Titles.editName) {
                renameText = project.name
                renamingProject = project
            }
            Divider()
            Button(role: .destructive) { manager.deleteProject(project.id) } label: {
                Text(^String.Titles.deleteButtonTitle)
            }
        }
    }

    private func renameSheet(_ project: ImageEditorProjectMeta) -> some View {
        VStack(spacing: 16) {
            Text(^String.Titles.editName).font(.headline)
            TextField("", text: $renameText)
                .textFieldStyle(.roundedBorder)
                .frame(width: 260)
            HStack {
                Button(^String.Titles.collectionsButtonCancel) { renamingProject = nil }
                Button(^String.Titles.saveButtonTitle) {
                    if !renameText.trimmingCharacters(in: .whitespaces).isEmpty {
                        manager.renameProject(project.id, to: renameText)
                    }
                    renamingProject = nil
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
    }

    // MARK: - Действия

    private func createProject() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.png, .jpeg, .tiff, .heic, .image]
        panel.prompt = ^String.Titles.editorChooseImage
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let baseName = url.deletingPathExtension().lastPathComponent
        if let meta = manager.createProject(fromImageAt: url, name: baseName.isEmpty ? "Project" : baseName) {
            openProject(meta.id)
        }
    }

    private func downloadProject(_ project: ImageEditorProjectMeta) {
        guard let image = manager.exportedImage(project.id),
              let png = ImageEditorProjectsManager.pngData(from: image) else { return }
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = "\(project.name).png"
        panel.begin { response in
            if response == .OK, let saveURL = panel.url {
                try? png.write(to: saveURL)
            }
        }
    }
}
