import SwiftUI

struct ClaudeLoginSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var adminKeyDraft = ""
    @State private var isSaving = false
    @State private var errorMessage: String?

    let localizer: Localizer
    let onSaveAdminKey: (String) async throws -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }

            Text(localizer.text(.claudePersonalAutoAuth))
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Divider()

            Text(localizer.text(.claudeAdminApiKeyHelp))
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                SecureField(localizer.text(.claudeAdminApiKeyPlaceholder), text: $adminKeyDraft)
                    .textFieldStyle(.roundedBorder)

                Button(localizer.text(.saveAndRefresh)) {
                    Task {
                        isSaving = true
                        defer { isSaving = false }

                        do {
                            try await onSaveAdminKey(adminKeyDraft)
                            adminKeyDraft = ""
                            dismiss()
                        } catch {
                            errorMessage = error.localizedDescription
                        }
                    }
                }
                .disabled(adminKeyDraft.isEmpty || isSaving)
            }

            Spacer()

            HStack {
                Spacer()
                Button(localizer.text(.cancel)) {
                    dismiss()
                }
            }
        }
        .padding(16)
        .frame(minWidth: 440, minHeight: 200)
    }
}
