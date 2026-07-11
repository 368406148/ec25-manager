import SwiftUI

// MARK: - Liquid Glass card

struct GlassCard: ViewModifier {
    var cornerRadius: CGFloat = 14
    var tint: Color? = nil
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        if #available(macOS 26.0, *) {
            let glass: Glass = tint.map { Glass.regular.tint($0) } ?? .regular
            content.glassEffect(glass, in: shape)
        } else {
            content
                .background(tint == nil ? AnyShapeStyle(.regularMaterial) : AnyShapeStyle(tint!.opacity(0.18)), in: shape)
                .overlay(shape.strokeBorder(Color.primary.opacity(0.08), lineWidth: 1))
        }
    }
}

extension View {
    func glassCard(cornerRadius: CGFloat = 14, tint: Color? = nil) -> some View {
        modifier(GlassCard(cornerRadius: cornerRadius, tint: tint))
    }
    /// Soft translucent tile fill (used for the small info cards).
    func tileBackground(cornerRadius: CGFloat = 11) -> some View {
        modifier(GlassCard(cornerRadius: cornerRadius))
    }
    /// Rounded input container (text fields / composer).
    func inputBox(cornerRadius: CGFloat = 10) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        return background(shape.fill(Color.primary.opacity(0.06)))
            .overlay(shape.strokeBorder(Color.primary.opacity(0.11), lineWidth: 1))
    }
}

// MARK: - Signal bars (animated)

struct SignalBars: View {
    var bars: Int
    var height: CGFloat = 30
    private let ratios: [CGFloat] = [0.42, 0.62, 0.82, 1.0]
    var body: some View {
        HStack(alignment: .bottom, spacing: 4) {
            ForEach(0..<4, id: \.self) { i in
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(i < bars
                          ? AnyShapeStyle(LinearGradient(colors: [Palette.goodC.opacity(0.85), Palette.goodC], startPoint: .top, endPoint: .bottom))
                          : AnyShapeStyle(Color.primary.opacity(0.18)))
                    .frame(width: 6, height: height * ratios[i])
            }
        }
        .frame(height: height)
        .animation(.smooth(duration: 0.35), value: bars)
    }
}

// MARK: - Info tile

struct Tile: View {
    let field: InfoField
    let value: String
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(field.label).font(.system(size: 11)).foregroundStyle(.secondary)
            Text(value.isEmpty ? "-" : value)
                .font(field.mono ? .system(size: 12, weight: .semibold, design: .monospaced) : .system(size: 14, weight: .bold))
                .foregroundStyle(.primary)
                .contentTransition(.numericText())
                .textSelection(.enabled)
                .lineLimit(3).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
        .padding(11)
        .tileBackground()
    }
}

// MARK: - Badge

struct Badge: View {
    let text: String
    var color: Color = Palette.brandC
    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .bold)).foregroundStyle(.white)
            .padding(.horizontal, 8).padding(.vertical, 2)
            .background(color, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
    }
}

struct SectionCard<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.system(size: 12, weight: .bold)).foregroundStyle(.secondary)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .glassCard()
    }
}
