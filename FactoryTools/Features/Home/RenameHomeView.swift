import SwiftData
import SwiftUI

struct RenameHomeView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appTheme) private var theme
    @State private var nameDraft = ""
    @State private var showingSaveError = false

    let home: HomeProfile
    let isPro: Bool

    private var canSave: Bool {
        !nameDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !home.usesDefaultName
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("home.createSection") {
                    TextField("settings.homeName", text: $nameDraft, prompt: Text("home.defaultName"))
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                }
            }
            .scrollContentBackground(.hidden)
            .background(theme.background)
            .navigationTitle("home.rename")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("common.cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("common.save") { save() }
                        .disabled(!canSave)
                }
            }
            .onAppear { nameDraft = home.usesDefaultName ? "" : home.name }
            .alert("error.saveFailed", isPresented: $showingSaveError) {
                Button("common.done", role: .cancel) {}
            } message: {
                Text("error.saveMessage")
            }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }

    private func save() {
        do {
            try HomeProfileService(modelContext: modelContext).setName(nameDraft, for: home, isPro: isPro)
            dismiss()
        } catch {
            showingSaveError = true
        }
    }
}
