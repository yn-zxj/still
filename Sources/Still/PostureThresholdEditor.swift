import SwiftUI
import StillCore

final class PostureThresholdEditingState: ObservableObject {
    @Published var notice = "点击数字直接修改，回车或移开焦点自动保存。"
    @Published var resetID = UUID()
}
private final class PostureNumberEditingState: ObservableObject {
    @Published var draft = ""
    @Published var invalid = false
}

/// A blank in the rule sentence. Editing stays local until Return or focus leaves the field.
struct InlinePostureNumber: View {
    let field: PostureThreshold
    @Binding var value: Double
    var onResult: (String) -> Void
    @StateObject private var edit = PostureNumberEditingState()
    @FocusState private var focused: Bool

    var body: some View {
        TextField("", text: $edit.draft)
            .textFieldStyle(.plain).multilineTextAlignment(.center)
            .font(.system(size: 13, weight: .medium)).monospacedDigit()
            .foregroundStyle(Palette.ink).tint(Palette.accent)
            .padding(.horizontal, 5).frame(width: field.decimalPlaces == 2 ? 58 : 46, height: 28)
            .background(Palette.accent.opacity(focused ? 0.10 : 0.05), in: RoundedRectangle(cornerRadius: 6))
            .overlay(alignment: .bottom) {
                RoundedRectangle(cornerRadius: 1).fill(edit.invalid ? Color.red : focused ? Palette.accent : Palette.accent.opacity(0.35))
                    .frame(height: focused || edit.invalid ? 2 : 1).padding(.horizontal, 5).padding(.bottom, 3)
            }
            .focused($focused)
            .accessibilityLabel(field.title).help("\(field.title)：\(field.rangeDescription)，回车或移开焦点保存")
            .onAppear { edit.draft = field.formatted(value) }
            .onSubmit { commit(); focused = false }
            .onChange(of: focused) { if !$0 { commit() } }
            .onChange(of: value) { edit.draft = field.formatted($0); edit.invalid = false }
    }
    private func commit() {
        guard edit.draft != field.formatted(value) else { edit.invalid = false; return }
        guard let parsed = field.parsed(edit.draft) else {
            edit.invalid = true
            onResult("\(field.title)：请输入 \(field.rangeDescription)，当前输入尚未保存。")
            return
        }
        value = parsed; edit.draft = field.formatted(parsed); edit.invalid = false
        onResult("已保存并生效 · 坐姿校准保留，偏离计时重新开始")
    }
}

/// Wrap complete sentence fragments while keeping each input next to its unit.
struct PostureRuleFlow: Layout {
    var spacing: CGFloat = 5
    var lineSpacing: CGFloat = 7
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrangement(width: proposal.width, subviews: subviews).size
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrangement(width: bounds.width, subviews: subviews)
        for (index, subview) in subviews.enumerated() {
            subview.place(at: CGPoint(x: bounds.minX + result.origins[index].x, y: bounds.minY + result.origins[index].y),
                anchor: .topLeading, proposal: ProposedViewSize(result.sizes[index]))
        }
    }
    private func arrangement(width: CGFloat?, subviews: Subviews) -> (origins: [CGPoint], sizes: [CGSize], size: CGSize) {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        let available = width ?? sizes.reduce(0) { $0 + $1.width + spacing }
        var origins: [CGPoint] = [], x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, usedWidth: CGFloat = 0
        for size in sizes {
            if x > 0 && x + size.width > available { x = 0; y += rowHeight + lineSpacing; rowHeight = 0 }
            origins.append(CGPoint(x: x, y: y))
            usedWidth = max(usedWidth, x + size.width)
            x += size.width + spacing; rowHeight = max(rowHeight, size.height)
        }
        return (origins, sizes, CGSize(width: width ?? usedWidth, height: y + rowHeight))
    }
}
