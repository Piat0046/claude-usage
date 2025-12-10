import SwiftUI

struct EnvItem: Identifiable {
    let id = UUID()
    var key: String
    var value: String
    let isSystem: Bool
}

struct ClaudeEnvEditorView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var envItems: [EnvItem] = []
    @State private var newKey = ""
    @State private var newValue = ""
    @State private var showingAddCustom = false
    @State private var errorMessage: String?

    private let systemKeys = ClaudeConfigService.systemKeys
    private let defaultEnv = ClaudeConfigService.defaultEnv

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Claude Code Environment Settings")
                    .font(.headline)
                Spacer()
            }
            .padding()

            Divider()

            // Error message
            if let error = errorMessage {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    Text(error)
                        .foregroundColor(.red)
                    Spacer()
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
            }

            // Table
            VStack(spacing: 0) {
                // Table Header
                HStack(spacing: 0) {
                    Text("Key")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                        .frame(width: 250, alignment: .leading)
                        .padding(.horizontal, 10)

                    Divider()
                        .frame(height: 14)

                    Text("Value")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 10)

                    Color.clear
                        .frame(width: 36)
                }
                .frame(height: 22)
                .background(Color(NSColor.controlBackgroundColor))

                Divider()

                // Table Content
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(Array(envItems.enumerated()), id: \.element.id) { index, item in
                            EnvTableRow(
                                item: item,
                                index: index,
                                onKeyChange: { newKey in
                                    updateKey(id: item.id, key: newKey)
                                },
                                onValueChange: { newValue in
                                    updateValue(id: item.id, value: newValue)
                                },
                                onDelete: {
                                    deleteItem(id: item.id)
                                }
                            )
                        }

                        // Add new row
                        if showingAddCustom {
                            HStack(spacing: 0) {
                                TextField("NEW_KEY", text: $newKey)
                                    .textFieldStyle(.plain)
                                    .font(.system(size: 12, design: .monospaced))
                                    .frame(width: 250, alignment: .leading)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 4)

                                Divider()
                                    .frame(height: 22)

                                TextField("value", text: $newValue)
                                    .textFieldStyle(.plain)
                                    .font(.system(size: 12, design: .monospaced))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 4)

                                HStack(spacing: 2) {
                                    Button(action: addCustomKey) {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundColor(.green)
                                    }
                                    .buttonStyle(.plain)

                                    Button(action: {
                                        showingAddCustom = false
                                        newKey = ""
                                        newValue = ""
                                    }) {
                                        Image(systemName: "xmark.circle.fill")
                                            .foregroundColor(.secondary)
                                    }
                                    .buttonStyle(.plain)
                                }
                                .frame(width: 36)
                            }
                            .background(Color(NSColor.controlBackgroundColor).opacity(0.3))

                            Divider()
                        }
                    }
                }
            }
            .background(Color(NSColor.textBackgroundColor))
            .cornerRadius(6)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color(NSColor.separatorColor), lineWidth: 1)
            )
            .padding(.horizontal)
            .padding(.vertical, 8)

            // Footer buttons
            HStack {
                Button(action: { showingAddCustom = true }) {
                    Label("Add", systemImage: "plus")
                }
                .disabled(showingAddCustom)

                Button(action: resetToDefaults) {
                    Label("Reset", systemImage: "arrow.counterclockwise")
                }

                Spacer()

                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button("Save") {
                    saveChanges()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
            .padding()
        }
        .frame(width: 600, height: 450)
        .onAppear {
            loadCurrentSettings()
        }
    }

    private func loadCurrentSettings() {
        let currentEnv = ClaudeConfigService.getAllEnv()
        var items: [EnvItem] = []

        for key in systemKeys.sorted() {
            items.append(EnvItem(
                key: key,
                value: currentEnv[key] ?? defaultEnv[key] ?? "",
                isSystem: true
            ))
        }

        for (key, value) in currentEnv where !systemKeys.contains(key) {
            items.append(EnvItem(key: key, value: value, isSystem: false))
        }

        envItems = items
    }

    private func updateKey(id: UUID, key: String) {
        guard let index = envItems.firstIndex(where: { $0.id == id }) else { return }

        if envItems.contains(where: { $0.key == key && $0.id != id }) {
            errorMessage = "Key '\(key)' already exists"
            return
        }

        envItems[index].key = key
        errorMessage = nil
    }

    private func updateValue(id: UUID, value: String) {
        guard let index = envItems.firstIndex(where: { $0.id == id }) else { return }
        envItems[index].value = value
    }

    private func deleteItem(id: UUID) {
        envItems.removeAll { $0.id == id }
    }

    private func addCustomKey() {
        let trimmedKey = newKey.trimmingCharacters(in: .whitespaces)
        guard !trimmedKey.isEmpty else { return }

        if envItems.contains(where: { $0.key == trimmedKey }) {
            errorMessage = "Key '\(trimmedKey)' already exists"
            return
        }

        envItems.append(EnvItem(key: trimmedKey, value: newValue, isSystem: false))
        newKey = ""
        newValue = ""
        showingAddCustom = false
        errorMessage = nil
    }

    private func resetToDefaults() {
        var items: [EnvItem] = []
        for key in systemKeys.sorted() {
            items.append(EnvItem(key: key, value: defaultEnv[key] ?? "", isSystem: true))
        }
        envItems = items
        errorMessage = nil
        showingAddCustom = false
    }

    private func saveChanges() {
        do {
            var env: [String: String] = [:]
            for item in envItems {
                let trimmedValue = item.value.trimmingCharacters(in: .whitespaces)
                if !trimmedValue.isEmpty {
                    env[item.key] = trimmedValue
                }
            }
            try ClaudeConfigService.saveAllEnv(env)
            dismiss()
        } catch {
            errorMessage = "Failed to save: \(error.localizedDescription)"
        }
    }
}

// MARK: - Table Row
struct EnvTableRow: View {
    let item: EnvItem
    let index: Int
    let onKeyChange: (String) -> Void
    let onValueChange: (String) -> Void
    let onDelete: () -> Void

    @State private var editingKey: String
    @State private var editingValue: String

    init(item: EnvItem, index: Int,
         onKeyChange: @escaping (String) -> Void,
         onValueChange: @escaping (String) -> Void,
         onDelete: @escaping () -> Void) {
        self.item = item
        self.index = index
        self.onKeyChange = onKeyChange
        self.onValueChange = onValueChange
        self.onDelete = onDelete
        _editingKey = State(initialValue: item.key)
        _editingValue = State(initialValue: item.value)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                // Key cell
                Group {
                    if item.isSystem {
                        Text(item.key)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundColor(.primary)
                    } else {
                        TextField("Key", text: $editingKey)
                            .textFieldStyle(.plain)
                            .font(.system(size: 12, design: .monospaced))
                            .onChange(of: editingKey) { newValue in
                                onKeyChange(newValue)
                            }
                    }
                }
                .frame(width: 250, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)

                Divider()
                    .frame(height: 22)

                // Value cell
                TextField("Value", text: $editingValue)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .onChange(of: editingValue) { newValue in
                        onValueChange(newValue)
                    }

                // Delete button
                Group {
                    if !item.isSystem {
                        Button(action: onDelete) {
                            Image(systemName: "trash")
                                .font(.system(size: 11))
                                .foregroundColor(.red.opacity(0.7))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .frame(width: 36)
            }
            .background(index % 2 == 0 ? Color.clear : Color(NSColor.controlBackgroundColor).opacity(0.3))

            Divider()
        }
    }
}

#Preview {
    ClaudeEnvEditorView()
}
