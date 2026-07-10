import SwiftUI

struct OverviewView: View {
    @EnvironmentObject var modem: Modem
    @EnvironmentObject var settings: AppSettings

    private var fields: [InfoField] { settings.visibleFields.compactMap(fieldCatalogEntry) }

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    HStack(spacing: 10) {
                        ForEach(row) { f in Tile(field: f, value: f.get(modem.info)) }
                        if row.count == 1 && !(row.first?.wide ?? false) { Color.clear.frame(maxWidth: .infinity) }
                    }
                }

                SectionCard(title: "载波聚合 / 服务小区") {
                    Text(caText)
                        .font(.system(size: 11.5, design: .monospaced))
                        .foregroundStyle(.secondary).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(16)
            .animation(.smooth, value: modem.info)
        }
    }

    private var caText: String {
        let parts = [modem.info.carrierAggregation, modem.info.servingCell].filter { $0 != "-" && !$0.isEmpty }
        return parts.isEmpty ? "暂无载波聚合信息" : parts.joined(separator: "\n")
    }

    private var rows: [[InfoField]] {
        var result: [[InfoField]] = []
        var pending: InfoField?
        for f in fields {
            if f.wide {
                if let p = pending { result.append([p]); pending = nil }
                result.append([f])
            } else if let p = pending {
                result.append([p, f]); pending = nil
            } else { pending = f }
        }
        if let p = pending { result.append([p]) }
        return result
    }
}
