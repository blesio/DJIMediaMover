import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        Form {
            Section("Import Destination") {
                HStack {
                    Text(model.destination?.path ?? "Not selected")
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button("Choose…") { model.chooseDestination() }
                        .disabled(model.isWorking)
                }
                Text("Media is organized into Photos/YYYY-MM-DD and Videos/YYYY-MM-DD.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Automation") {
                Toggle("Import immediately when DJI storage is connected", isOn: Binding(
                    get: { model.automaticImport },
                    set: { value in model.setAutomatic(value) }
                ))
                Toggle("Automatically unmount after a successful import", isOn: Binding(
                    get: { model.autoUnmount },
                    set: { value in model.setAutoUnmount(value) }
                ))
                Text("Unmounting occurs only after at least one media file is imported without errors.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
        .frame(width: 560, height: 380)
    }
}
