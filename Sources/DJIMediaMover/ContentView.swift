import SwiftUI

struct ContentView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Image(systemName: model.volumes.isEmpty ? "externaldrive.badge.questionmark" : "externaldrive.fill.badge.checkmark")
                    .font(.system(size: 34)).foregroundStyle(model.volumes.isEmpty ? Color.secondary : Color.green)
                VStack(alignment: .leading) {
                    Text(model.update.stage.rawValue).font(.title2.bold())
                    Text(model.volumes.isEmpty ? "Connect a DJI drone by USB" : model.volumes.map(\.lastPathComponent).joined(separator: " + "))
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            Grid(alignment: .leading, horizontalSpacing: 28, verticalSpacing: 8) {
                GridRow { Text("Found"); Text("\(model.update.found)").monospacedDigit() }
                GridRow { Text("Copied / verified"); Text("\(model.update.copied)").monospacedDigit() }
                GridRow { Text("Deleted"); Text("\(model.update.deleted)").monospacedDigit() }
                if model.update.bytesPerSecond > 0 {
                    GridRow { Text("Transfer speed"); Text(transferSpeed).monospacedDigit() }
                }
            }
            if model.update.found > 0 {
                ProgressView(value: Double(model.update.copied), total: Double(model.update.found))
            }
            if !model.update.currentFile.isEmpty { Text(model.update.currentFile).font(.caption).lineLimit(1).truncationMode(.middle) }
            if !model.update.message.isEmpty { Text(model.update.message).foregroundStyle(model.update.stage == .failed ? .red : .secondary) }
            if !model.update.copyErrors.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(model.update.copyErrors, id: \.self) { error in
                            Text(error).font(.caption).foregroundStyle(.red).textSelection(.enabled)
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }.frame(maxHeight: 90)
            }
            HStack {
                Text("Each source is removed immediately after its destination copy passes SHA-256 verification.")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
            }
        }
        .padding(24).frame(width: 620, height: 420)
    }

    private var transferSpeed: String {
        ByteCountFormatter.string(fromByteCount: Int64(model.update.bytesPerSecond), countStyle: .file) + "/s"
    }
}
