import FactoryToolsCore
import SwiftData
import SwiftUI

struct CreateHomeView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appTheme) private var theme
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var proPurchases: ProPurchaseManager
    @Query private var homes: [HomeProfile]
    @State private var name = ""
    @State private var showingSaveError = false

    private var canCreate: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && (homes.isEmpty || FeatureAccessRegistry.allows(.multipleHomeProfiles, isPro: proPurchases.hasPro))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("home.createSection") {
                    TextField("home.name", text: $name, prompt: Text("home.namePrompt"))
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                }
            }
            .scrollContentBackground(.hidden)
            .background(theme.background)
            .navigationTitle("home.create")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("common.cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("home.create") {
                        guard homes.isEmpty || FeatureAccessRegistry.allows(.multipleHomeProfiles, isPro: proPurchases.hasPro) else {
                            dismiss()
                            return
                        }
                        do {
                            _ = try HomeProfileService(modelContext: modelContext).createHome(
                                named: name,
                                isPro: proPurchases.hasPro
                            )
                            dismiss()
                        } catch {
                            showingSaveError = true
                        }
                    }
                    .disabled(!canCreate)
                }
            }
            .alert("error.saveFailed", isPresented: $showingSaveError) {
                Button("common.done", role: .cancel) {}
            } message: {
                Text("error.saveMessage")
            }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }
}
