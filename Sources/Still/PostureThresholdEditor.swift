import AppKit
import SwiftUI
import StillCore

enum PostureSemanticColor {
    static let error = Color(nsColor: NSColor(
        name: NSColor.Name("local.still.posture.error"),
        dynamicProvider: { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(srgbRed: 255 / 255, green: 138 / 255, blue: 138 / 255, alpha: 1)
                : NSColor(srgbRed: 197 / 255, green: 48 / 255, blue: 48 / 255, alpha: 1)
        }
    ))

    static let warning = Color(nsColor: NSColor(
        name: NSColor.Name("local.still.posture.warning"),
        dynamicProvider: { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(srgbRed: 245 / 255, green: 185 / 255, blue: 89 / 255, alpha: 1)
                : NSColor(srgbRed: 154 / 255, green: 91 / 255, blue: 0 / 255, alpha: 1)
        }
    ))
}

@MainActor
final class PostureThresholdEditingState: ObservableObject {
    @Published var notice = "点击数字直接修改，回车或移开焦点自动保存；按 Esc 可撤销未保存的输入。"
    @Published var errors: [PostureThreshold: String] = [:]
    @Published var resetID = UUID()

    func setError(_ message: String?, for field: PostureThreshold) {
        if let message {
            errors[field] = message
        } else {
            errors.removeValue(forKey: field)
        }
    }

    func clearErrors() {
        errors.removeAll()
    }
}

@MainActor
private final class PostureNumberEditingState: ObservableObject {
    @Published var draft = ""
    @Published var errorMessage: String?

    var invalid: Bool { errorMessage != nil }
}

/// A blank in the rule sentence. Editing stays local until Return or focus leaves the field.
struct InlinePostureNumber: View {
    let field: PostureThreshold
    @Binding var value: Double
    var onSaved: (String) -> Void
    var onValidationChange: (PostureThreshold, String?) -> Void
    @StateObject private var edit = PostureNumberEditingState()
    @FocusState private var focused: Bool

    var body: some View {
        TextField("", text: $edit.draft)
            .textFieldStyle(.plain)
            .multilineTextAlignment(.center)
            .font(.system(size: 13, weight: .medium))
            .monospacedDigit()
            .foregroundStyle(Palette.ink)
            .tint(Palette.accent)
            .padding(.horizontal, 5)
            .frame(width: field.decimalPlaces == 2 ? 58 : 46, height: 28)
            .background(
                (edit.invalid ? PostureSemanticColor.error.opacity(0.10) : Palette.accent.opacity(focused ? 0.10 : 0.05)),
                in: RoundedRectangle(cornerRadius: 6, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(
                        edit.invalid ? PostureSemanticColor.error : focused ? Palette.accent : Palette.line,
                        lineWidth: focused || edit.invalid ? 1.5 : 1
                    )
            }
            .focused($focused)
            .accessibilityLabel(field.title)
            .accessibilityValue(edit.errorMessage.map { "\(edit.draft)，输入无效：\($0)" } ?? edit.draft)
            .accessibilityHint("有效范围 \(field.rangeDescription)，回车或移开焦点保存")
            .help(edit.errorMessage ?? "\(field.title)：\(field.rangeDescription)，回车或移开焦点保存")
            .onAppear {
                edit.draft = field.formatted(value)
                edit.errorMessage = nil
                onValidationChange(field, nil)
            }
            .onSubmit {
                commit()
                focused = false
            }
            .onExitCommand {
                edit.draft = field.formatted(value)
                edit.errorMessage = nil
                onValidationChange(field, nil)
                focused = false
            }
            .onChange(of: focused) { isFocused in
                if !isFocused { commit() }
            }
            .onChange(of: value) { updated in
                edit.draft = field.formatted(updated)
                edit.errorMessage = nil
                onValidationChange(field, nil)
            }
    }

    private func commit() {
        guard edit.draft != field.formatted(value) else {
            edit.errorMessage = nil
            onValidationChange(field, nil)
            return
        }
        guard let parsed = field.parsed(edit.draft) else {
            let message = "请输入 \(field.rangeDescription)，当前输入尚未保存。"
            edit.errorMessage = message
            onValidationChange(field, message)
            announceValidationError("\(field.title)：\(message)")
            return
        }
        value = parsed
        edit.draft = field.formatted(parsed)
        edit.errorMessage = nil
        onValidationChange(field, nil)
        onSaved("已保存「\(field.title)」· 坐姿校准保留，偏离计时重新开始")
    }

    private func announceValidationError(_ message: String) {
        NSAccessibility.post(
            element: NSApp as Any,
            notification: .announcementRequested,
            userInfo: [
                .announcement: message,
                .priority: NSAccessibilityPriorityLevel.high.rawValue
            ]
        )
    }
}

/// Inline validation feedback displayed directly beneath the rule row that owns the invalid field(s).
struct PostureInlineErrorRow: View {
    let fields: [PostureThreshold]
    let errors: [PostureThreshold: String]

    private var activeErrors: [(field: PostureThreshold, message: String)] {
        fields.compactMap { field in
            guard let message = errors[field] else { return nil }
            return (field, message)
        }
    }

    var body: some View {
        if !activeErrors.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(activeErrors, id: \.field.rawValue) { item in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Image(systemName: "exclamationmark.circle.fill")
                            .font(.system(size: 11))
                            .accessibilityHidden(true)
                        Text("\(item.field.title)：\(item.message)")
                            .font(.system(size: 12, weight: .medium))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .foregroundStyle(PostureSemanticColor.error)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("输入错误，\(item.field.title)：\(item.message)")
                }
            }
            .padding(.top, 2)
        }
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
