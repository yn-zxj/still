import AppKit
import AVFoundation
import SwiftUI
import StillCore

private enum PostureCameraIssue {
    case permissionDenied
    case permissionPending
    case interrupted
    case deviceOrStartFailure
}

@MainActor
private final class PostureDisclosureState: ObservableObject {
    @Published var isExpanded = false
}

struct PostureView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var monitor: PostureMonitor
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var thresholdEdit = PostureThresholdEditingState()
    @StateObject private var thresholdDisclosure = PostureDisclosureState()

    private var animated: Bool { model.settings.motionEnabled && !reduceMotion }
    private var shouldersAvailable: Bool { monitor.lastSample?.hasShoulders == true && monitor.baseline?.hasShoulders == true }
    private var thresholds: PostureThresholds { model.settings.postureThresholds }
    private var isSystemSuspended: Bool { !monitor.paused && !monitor.running && !monitor.starting && monitor.error == nil && monitor.statusTitle == "休息或锁屏期间暂停" }

    private var cameraIssue: PostureCameraIssue? {
        guard let error = monitor.error else { return nil }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .denied, .restricted:
            return .permissionDenied
        case .notDetermined:
            return .permissionPending
        case .authorized:
            if error.contains("权限未开启") { return .permissionDenied }
            if error.contains("中断") { return .interrupted }
            return .deviceOrStartFailure
        @unknown default:
            return .deviceOrStartFailure
        }
    }

    private var statusBadge: (title: String, color: Color) {
        if monitor.paused { return ("已暂停", Palette.secondary) }
        if monitor.starting { return ("正在开启", Palette.accent) }
        if let issue = cameraIssue {
            switch issue {
            case .permissionDenied: return ("需要摄像头权限", PostureSemanticColor.error)
            case .permissionPending: return ("等待授权", Palette.accent)
            case .interrupted: return ("连接已中断", PostureSemanticColor.warning)
            case .deviceOrStartFailure: return ("摄像头不可用", PostureSemanticColor.error)
            }
        }
        if isSystemSuspended { return ("暂歇中", Palette.secondary) }
        guard monitor.running else { return ("未开启", Palette.secondary) }
        switch monitor.assessment.state {
        case .uncalibrated: return ("待校准", Palette.accent)
        case .calibrating: return ("校准中", Palette.accent)
        case .unavailable: return ("等待识别", PostureSemanticColor.warning)
        case .aligned: return ("坐姿正常", Palette.green)
        case .deviation: return ("检测到偏离", PostureSemanticColor.warning)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack(alignment: .center) {
                SectionHeading(title: "坐姿关照")
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                if monitor.running {
                    Button("暂停监测") { monitor.togglePause() }
                        .buttonStyle(SettingsButtonStyle())
                }
            }

            HStack(alignment: .top, spacing: 20) {
                cameraPreviewColumn
                statusActionCard
            }

            liveFeedbackSection
            toneAndPreviewCard
            reminderRulesSection
            PostureMethodView(animated: animated)
        }
        .onAppear { monitor.setPreviewVisible(true) }
        .onDisappear { monitor.setPreviewVisible(false) }
    }

    private var cameraPreviewColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            GeometryReader { geometry in
                ZStack {
                    RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color(hex: 0x1B1C29))
                    if monitor.running {
                        PostureCameraPreview(session: monitor.session, overlay: monitor.overlay)
                            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    } else {
                        VStack(spacing: 20) {
                            PostureIllustration()
                                .stroke(
                                    Palette.accent.opacity(0.85),
                                    style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
                                )
                                .frame(width: 180, height: 160)
                            Text(previewPlaceholderText)
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(Color.white.opacity(0.82))
                        }
                    }
                    VStack {
                        HStack(spacing: 7) {
                            LineIcon(systemName: "camera", size: 13)
                            Text("本机分析 · 不录像").font(.system(size: 12, weight: .medium))
                            Spacer()
                            if monitor.running { Circle().fill(Palette.mint).frame(width: 7, height: 7) }
                        }
                        .foregroundStyle(Color.white.opacity(0.9))
                        Spacer()
                        if monitor.assessment.state == .calibrating {
                            VStack(spacing: 9) {
                                Text("保持自然坐姿 · \(Int(monitor.assessment.calibrationProgress * 100))%")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(Color.white)
                                    .monospacedDigit()
                                ProgressView(value: monitor.assessment.calibrationProgress).tint(Palette.mint)
                            }
                            .padding(16)
                            .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                    }
                    .padding(16)
                    .allowsHitTesting(false)
                }
                .frame(width: geometry.size.width, height: geometry.size.height)
            }
            .frame(height: 320)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("摄像头预览，\(statusBadge.title)，\(monitor.statusTitle)")

            HStack {
                Text(monitor.cameraName).font(.system(size: 12)).foregroundStyle(Palette.secondary)
                Spacer()
                Text("实时关键点 · 本机处理").font(.system(size: 12)).foregroundStyle(Palette.secondary)
            }
            .padding(.top, 12)
        }
        .frame(maxWidth: .infinity)
    }

    private var previewPlaceholderText: String {
        if monitor.paused { return "监测已暂停，摄像头已关闭" }
        if monitor.starting { return "正在连接摄像头…" }
        if cameraIssue == .permissionDenied { return "需要摄像头权限才能开启坐姿参照" }
        if cameraIssue == .deviceOrStartFailure { return "未能启动摄像头" }
        if isSystemSuspended { return "休息或锁屏期间自动暂歇" }
        return "让坐姿，有一个温柔的参照"
    }

    private var statusActionCard: some View {
        let badge = statusBadge
        return VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Circle().fill(badge.color).frame(width: 7, height: 7)
                Text(badge.title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(badge.color == Palette.secondary ? Palette.secondary : badge.color)
            }

            if monitor.running, let sample = monitor.lastSample {
                Text(sample.hasShoulders && monitor.baseline?.hasShoulders != false ? "头部与肩部识别可用" : "仅头部 · 肩部暂不可用")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Palette.accentDark)
            }

            Text(monitor.statusTitle)
                .font(.system(size: 19, weight: .semibold, design: .rounded))
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)

            if let error = monitor.error {
                Text(error)
                    .font(.system(size: 13))
                    .foregroundStyle(cameraIssue == .permissionPending ? Palette.secondary : PostureSemanticColor.error)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text(statusDetail)
                    .font(.system(size: 13))
                    .foregroundStyle(Palette.secondary)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 4)

            primaryActionArea

            if monitor.running {
                calibrationInlineTip
            }
        }
        .frame(width: 264, alignment: .leading)
        .padding(21)
        .frame(minHeight: 320, alignment: .top)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Palette.line.opacity(0.7), lineWidth: 1)
        )
    }

    @ViewBuilder
    private var primaryActionArea: some View {
        if monitor.paused {
            Button("继续监测") { monitor.togglePause() }
                .buttonStyle(SettingsButtonStyle(prominent: true))
                .disabled(monitor.starting)
        } else if monitor.starting {
            Button("正在开启摄像头…") {}
                .buttonStyle(SettingsButtonStyle(prominent: true))
                .disabled(true)
        } else if let issue = cameraIssue {
            VStack(alignment: .leading, spacing: 10) {
                switch issue {
                case .permissionDenied:
                    Button("打开摄像头权限设置") { openCameraPrivacySettings() }
                        .buttonStyle(SettingsButtonStyle(prominent: true))
                    Button("重新检查权限") { monitor.reconnect() }
                        .buttonStyle(.plain)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Palette.accentDark)
                case .permissionPending:
                    Button("开启摄像头") { monitor.reconnect() }
                        .buttonStyle(SettingsButtonStyle(prominent: true))
                case .interrupted:
                    Button("重新连接摄像头") { monitor.reconnect() }
                        .buttonStyle(SettingsButtonStyle(prominent: true))
                    Button("检查摄像头权限") { openCameraPrivacySettings() }
                        .buttonStyle(.plain)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Palette.accentDark)
                case .deviceOrStartFailure:
                    Button("重新连接摄像头") { monitor.reconnect() }
                        .buttonStyle(SettingsButtonStyle(prominent: true))
                }
            }
        } else if isSystemSuspended {
            Text("休息结束或解锁后自动恢复监测。")
                .font(.system(size: 12))
                .foregroundStyle(Palette.secondary)
        } else if monitor.running {
            let needsCalibration = monitor.baseline == nil || monitor.assessment.state == .calibrating
            Button(
                monitor.assessment.state == .calibrating
                    ? "重新开始校准"
                    : monitor.baseline == nil ? "校准我的坐姿" : "重新校准"
            ) {
                monitor.calibrate()
            }
            .buttonStyle(SettingsButtonStyle(prominent: needsCalibration))
        } else {
            Button("开启摄像头") { monitor.reconnect() }
                .buttonStyle(SettingsButtonStyle(prominent: true))
                .disabled(monitor.starting)
        }
    }

    private var calibrationInlineTip: some View {
        HStack(alignment: .top, spacing: 8) {
            LineIcon(systemName: "scan-face", size: 14)
                .foregroundStyle(Palette.accentDark)
                .padding(.top, 2)
            Text("校准要点：镜头固定、背部有支撑、肩颈放松，面部完整入镜保持 4 秒。")
                .font(.system(size: 12))
                .foregroundStyle(Palette.secondary)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.background.opacity(0.75), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
    }

    private func openCameraPrivacySettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera")!)
    }

    private var liveFeedbackSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("实时反馈")
                        .font(.system(size: 16, weight: .semibold))
                        .accessibilityAddTraits(.isHeader)
                    Text(liveFeedbackSummary)
                        .font(.system(size: 13))
                        .foregroundStyle(
                            monitor.assessment.state == .deviation ? PostureSemanticColor.warning : Palette.secondary
                        )
                        .monospacedDigit()
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                if let lastReminder = monitor.lastReminder {
                    Text(lastReminder)
                        .font(.system(size: 12))
                        .foregroundStyle(Palette.secondary)
                        .monospacedDigit()
                }
            }

            if monitor.running && monitor.assessment.state == .deviation && monitor.assessment.cooldownRemaining == 0 {
                ProgressView(value: min(1, monitor.assessment.deviationSeconds / thresholds.sustainSeconds))
                    .tint(Palette.accent)
            }

            HStack(spacing: 14) {
                cue(
                    "头部侧倾",
                    value: delta(monitor.lastSample?.headRoll, monitor.baseline?.headRoll, suffix: "°"),
                    detail: headCueDetail,
                    icon: "scan-face"
                )
                cue(
                    "俯仰变化",
                    value: delta(monitor.lastSample?.pitch, monitor.baseline?.pitch, suffix: "°"),
                    detail: headCueDetail,
                    icon: "scan-face"
                )
                cue(
                    "肩线变化",
                    value: shouldersAvailable ? delta(monitor.lastSample?.shoulderRoll, monitor.baseline?.shoulderRoll, suffix: "°") : "—",
                    detail: shoulderCueDetail,
                    icon: "person-standing"
                )
                cue(
                    "头肩比例变化",
                    value: ratioText,
                    detail: shoulderCueDetail,
                    icon: "focus"
                )
            }

            HStack(spacing: 10) {
                ruleStatusChip("头部侧倾", needsShoulders: false)
                ruleStatusChip("肩线倾斜", needsShoulders: true)
                ruleStatusChip("持续低头", needsShoulders: false)
                ruleStatusChip("疑似探头", needsShoulders: true)
            }
        }
        .card(padding: 22)
    }

    private var liveFeedbackSummary: String {
        if monitor.paused { return "监测已暂停，恢复后会实时显示姿态偏差与提醒计时。" }
        if !monitor.running { return "开启摄像头并完成 4 秒校准后，这里会实时显示姿态偏差与提醒计时。" }
        if monitor.baseline == nil { return "完成 4 秒自然坐姿校准后开始计算偏差。" }
        return reminderFeedback
    }

    private var headCueDetail: String {
        if !monitor.running { return "未监测" }
        if monitor.baseline == nil { return "校准后显示" }
        if monitor.lastSample == nil { return "等待识别" }
        return "相对本次校准"
    }

    private var shoulderCueDetail: String {
        if !monitor.running { return "未监测" }
        if monitor.baseline == nil { return "校准后显示" }
        if monitor.lastSample == nil { return "等待识别" }
        return shouldersAvailable ? "相对本次校准" : "肩部暂不可用"
    }

    private func ruleStateText(needsShoulders: Bool) -> String {
        !monitor.running ? "未监测" : monitor.baseline == nil ? "待校准"
            : monitor.lastSample == nil ? "等待识别" : needsShoulders && !shouldersAvailable ? "肩部不可用" : "检测中"
    }

    private func ruleStatusChip(_ title: String, needsShoulders: Bool) -> some View {
        let state = ruleStateText(needsShoulders: needsShoulders)
        let active = state == "检测中"
        return HStack(spacing: 6) {
            Circle()
                .fill(active ? Palette.green : Palette.secondary.opacity(0.6))
                .frame(width: 6, height: 6)
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Palette.ink)
            Spacer(minLength: 4)
            Text(state)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(active ? Palette.accentDark : Palette.secondary)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(Palette.background.opacity(0.75), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private var toneAndPreviewCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 15) {
                LineIcon(systemName: "bell", size: 20).foregroundStyle(Palette.accent)
                VStack(alignment: .leading, spacing: 6) {
                    Text("提醒的语气")
                        .font(.system(size: 14, weight: .medium))
                        .accessibilityAddTraits(.isHeader)
                    Text("偏离累计 \(Int(thresholds.sustainSeconds)) 秒后提醒；顶部展示 \(Int(thresholds.displaySeconds)) 秒，冷却 \(Int(thresholds.cooldownSeconds)) 秒。")
                        .font(.system(size: 12))
                        .foregroundStyle(Palette.secondary)
                        .monospacedDigit()
                }
                Spacer()
                CompactMenuPicker(
                    selection: $model.settings.posturePlayful,
                    values: [true, false],
                    title: { $0 ? "轻松吐槽" : "温柔提醒" },
                    accessibilityTitle: "坐姿提醒语气"
                )
            }
            Divider().overlay(Palette.line)
            HStack {
                Text("12 条轻松吐槽 · 4 条温柔提醒\n预览会轮换四类动作，不影响真实检测与冷却。")
                    .font(.system(size: 13))
                    .foregroundStyle(Palette.secondary)
                    .lineSpacing(3)
                Spacer()
                Button("预览提醒") { monitor.previewAlert() }
                    .buttonStyle(SettingsButtonStyle())
            }
        }
        .card(padding: 22)
    }

    private var reminderFeedback: String {
        let assessment = monitor.assessment
        if assessment.state == .unavailable { return "识别暂不可用 · 不累积提醒时间" }
        if assessment.cooldownRemaining > 0 { return "提醒冷却中 · 还剩 \(Int(ceil(assessment.cooldownRemaining))) 秒" }
        if assessment.state == .deviation { return "偏离累计 \(Int(assessment.deviationSeconds)) / \(Int(thresholds.sustainSeconds)) 秒，达到后提醒" }
        return "尚未达到提醒阈值 · 正常移动不会立即提醒"
    }

    private var reminderRulesSection: some View {
        let expanded = thresholdDisclosure.isExpanded
        return VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text("触发规则与阈值参数")
                            .font(.system(size: 16, weight: .semibold))
                            .accessibilityAddTraits(.isHeader)
                        if expanded && !thresholdEdit.errors.isEmpty {
                            Text("\(thresholdEdit.errors.count) 项待修正")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(PostureSemanticColor.error)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(PostureSemanticColor.error.opacity(0.12), in: Capsule())
                        }
                    }
                    Text("默认参数已适配常规桌面场景；如需微调，可展开原位编辑 14 项触发与识别阈值。")
                        .font(.system(size: 12))
                        .foregroundStyle(Palette.secondary)
                }
                Spacer()
                if expanded {
                    Button("恢复默认") {
                        NSApp.keyWindow?.makeFirstResponder(nil)
                        model.settings.postureThresholds = PostureThresholds()
                        thresholdEdit.clearErrors()
                        thresholdEdit.resetID = UUID()
                        thresholdEdit.notice = "已恢复默认阈值"
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Palette.accentDark)
                }
                Button {
                    withAnimation(animated ? .easeInOut(duration: 0.2) : nil) {
                        if thresholdDisclosure.isExpanded {
                            NSApp.keyWindow?.makeFirstResponder(nil)
                            thresholdEdit.clearErrors()
                        }
                        thresholdDisclosure.isExpanded.toggle()
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text(expanded ? "收起 14 项参数" : "自定义 14 项参数")
                        LineIcon(systemName: "chevron-down", size: 13)
                            .rotationEffect(.degrees(expanded ? 180 : 0))
                    }
                }
                .buttonStyle(SettingsButtonStyle())
                .accessibilityHint(expanded ? "收起阈值参数列表" : "展开 14 项可编辑阈值参数")
            }

            if expanded {
                Divider().overlay(Palette.line)

                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        PostureRuleFlow {
                            Text("相对你校准时的自然坐姿，").frame(height: 28)
                            blank("同一类偏离累计", .sustainSeconds, "秒才提醒，回正后清零。")
                            blank("提醒展示", .displaySeconds, "秒，")
                            blank("之后冷却", .cooldownSeconds, "秒。")
                        }
                        PostureInlineErrorRow(
                            fields: [.sustainSeconds, .displaySeconds, .cooldownSeconds],
                            errors: thresholdEdit.errors
                        )
                    }

                    Divider().overlay(Palette.line)

                    ruleRow("头部侧倾", needsShoulders: false, fields: [.headTiltDegrees]) {
                        blank("左右歪头变化 >", .headTiltDegrees, "°")
                    }
                    Divider().overlay(Palette.line)
                    ruleRow("肩线倾斜", needsShoulders: true, fields: [.shoulderTiltDegrees]) {
                        blank("左右肩线角度变化 >", .shoulderTiltDegrees, "°")
                    }
                    Divider().overlay(Palette.line)
                    ruleRow("持续低头", needsShoulders: false, fields: [.loweredPitchDegrees, .loweredHeadDrop, .headOnlyPitchDegrees]) {
                        blank("有肩部：低头变化 >", .loweredPitchDegrees, "°，")
                        blank("且头肩距离 / 肩宽比下降 >", .loweredHeadDrop, "；")
                        blank("仅头部：低头变化 >", .headOnlyPitchDegrees, "°")
                    }
                    Divider().overlay(Palette.line)
                    ruleRow("疑似探头", needsShoulders: true, fields: [.forwardScalePercent, .forwardPitchDegrees, .forwardHeadDrop]) {
                        blank("头部大小 / 肩宽比增加 >", .forwardScalePercent, "%，")
                        blank("并满足任一项：低头变化 >", .forwardPitchDegrees, "°，")
                        blank("或头肩距离 / 肩宽比下降 >", .forwardHeadDrop)
                    }

                    Divider().overlay(Palette.line)

                    VStack(alignment: .leading, spacing: 6) {
                        PostureRuleFlow {
                            blank("转头 ≥", .maxYawDegrees, "°、")
                            blank("俯仰 ≥", .maxPitchDegrees, "°时暂停判断。")
                            blank("识别丢失不超过", .observationGraceSeconds, "秒时保留进度，但不计时。")
                        }
                        PostureInlineErrorRow(
                            fields: [.maxYawDegrees, .maxPitchDegrees, .observationGraceSeconds],
                            errors: thresholdEdit.errors
                        )
                    }
                }
                .id(thresholdEdit.resetID)
                .font(.system(size: 13))
                .foregroundStyle(Palette.secondary)

                Text(thresholdEdit.notice)
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.accentDark)
                    .fixedSize(horizontal: false, vertical: true)

                Text("面部遮挡或多人入镜时暂停判断；识别丢失超过设定时长后，清除偏离计时。正面镜头不能判断所有不良坐姿。")
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.secondary)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .card(padding: 22)
    }

    private func blank(_ prefix: String, _ field: PostureThreshold, _ suffix: String = "") -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(prefix)
            InlinePostureNumber(
                field: field,
                value: Binding(
                    get: { model.settings.postureThresholds[field] },
                    set: { model.settings.postureThresholds[field] = $0 }
                ),
                onSaved: { thresholdEdit.notice = $0 },
                onValidationChange: { target, message in
                    thresholdEdit.setError(message, for: target)
                }
            )
            if !suffix.isEmpty { Text(suffix) }
        }
        .fixedSize()
        .frame(height: 28)
    }

    private func ruleRow<Content: View>(
        _ title: String,
        needsShoulders: Bool,
        fields: [PostureThreshold],
        @ViewBuilder content: () -> Content
    ) -> some View {
        let state = ruleStateText(needsShoulders: needsShoulders)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 18) {
                Text(title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Palette.ink)
                    .frame(width: 84, height: 28, alignment: .leading)
                VStack(alignment: .leading, spacing: 6) {
                    PostureRuleFlow { content() }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    PostureInlineErrorRow(fields: fields, errors: thresholdEdit.errors)
                }
                Text(state)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(state == "检测中" ? Palette.accentDark : Palette.secondary)
                    .frame(width: 76, height: 28, alignment: .trailing)
            }
        }
    }

    private var statusDetail: String {
        if monitor.paused { return "摄像头已关闭并暂停后台检测；点击下方按钮继续监测。" }
        if monitor.starting { return "正在连接摄像头并准备本机识别模型，请稍候。" }
        if isSystemSuspended { return "休息、锁屏或系统睡眠期间会自动暂停监测，不会消耗摄像头资源。" }
        if !monitor.running { return "开启摄像头后，先以自然坐姿完成 4 秒校准，即可在后台温和提醒。" }

        if monitor.assessment.state == .deviation {
            return "偏离已累计 \(Int(monitor.assessment.deviationSeconds)) 秒。放松一下，换个舒服的姿势。"
        }

        if monitor.lastSample != nil && monitor.lastSample?.hasShoulders == false {
            if monitor.assessment.state == .calibrating { return "正在校准头部姿势。肩部识别不足，先启用歪头与低头监测；保持自然坐姿 4 秒。" }
            if monitor.baseline != nil { return "头部监测中。肩部识别不足，肩线和探头判断暂不可用。双肩识别稳定后会自动补充参照。" }
            return "面部已识别，可先校准头部姿势。肩部识别不足时，肩线与探头判断保持关闭。"
        }
        if monitor.baseline?.hasShoulders == false { return "头部校准已保留，肩部识别稳定后会自动补充参照，无需从头校准。" }

        if monitor.assessment.state == .calibrating { return "保持稳定，坐姿变化或识别不清会重新计时。校准会在本次监测中使用。" }
        if monitor.assessment.state == .aligned { return "关闭窗口后仍会后台监测；休息、锁屏或睡眠时暂停。" }
        if monitor.assessment.state == .unavailable { return "光线、遮挡、转头或多人入镜会暂停判断，不会算作不良坐姿。" }
        return "先用自然坐姿建立参照。前后移动和短暂离开会保留校准；镜头角度明显改变时，再手动校准。"
    }

    private func delta(_ value: Double?, _ reference: Double?, suffix: String) -> String {
        guard let value, let reference else { return "—" }
        return String(format: "%.0f", abs(value - reference)) + suffix
    }

    private var ratioText: String {
        guard shouldersAvailable, let s = monitor.lastSample, let b = monitor.baseline else { return "—" }
        let value = ((s.faceHeight / s.shoulderWidth) / (b.faceHeight / b.shoulderWidth) - 1) * 100
        return String(format: "%+.0f%%", value)
    }

    private func cue(_ title: String, value: String, detail: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                LineIcon(systemName: icon, size: 17)
                Text(title).font(.system(size: 13))
            }
            .foregroundStyle(Palette.secondary)
            Text(value)
                .font(.system(size: 26, weight: .medium, design: .rounded))
                .monospacedDigit()
            Text(detail)
                .font(.system(size: 12))
                .foregroundStyle(Palette.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.background.opacity(0.75), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

private struct PostureIllustration: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.addEllipse(in: CGRect(x: rect.width * 0.35, y: rect.height * 0.08, width: rect.width * 0.3, height: rect.height * 0.33))
        p.move(to: CGPoint(x: rect.width * 0.43, y: rect.height * 0.43))
        p.addLine(to: CGPoint(x: rect.width * 0.42, y: rect.height * 0.54))
        p.addQuadCurve(to: CGPoint(x: rect.width * 0.13, y: rect.height * 0.9), control: CGPoint(x: rect.width * 0.13, y: rect.height * 0.55))
        p.move(to: CGPoint(x: rect.width * 0.57, y: rect.height * 0.43))
        p.addLine(to: CGPoint(x: rect.width * 0.58, y: rect.height * 0.54))
        p.addQuadCurve(to: CGPoint(x: rect.width * 0.87, y: rect.height * 0.9), control: CGPoint(x: rect.width * 0.87, y: rect.height * 0.55))
        return p
    }
}

private final class CameraPreviewView: NSView {
    let preview = AVCaptureVideoPreviewLayer()
    private let lines = CAShapeLayer()
    private let dots = CAShapeLayer()
    var overlay = PostureOverlay.empty { didSet { updateOverlay() } }
    override init(frame: NSRect) {
        super.init(frame: frame); wantsLayer = true; layer?.addSublayer(preview); preview.videoGravity = .resizeAspect
        lines.strokeColor = NSColor(srgbRed: 0.55, green: 1, blue: 0.81, alpha: 0.95).cgColor
        lines.fillColor = nil; lines.lineWidth = 1.7; lines.lineCap = .round; lines.lineJoin = .round
        lines.shadowColor = NSColor.black.cgColor; lines.shadowOpacity = 0.45; lines.shadowRadius = 2
        dots.fillColor = NSColor.white.cgColor
        preview.addSublayer(lines); preview.addSublayer(dots)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func layout() { super.layout(); preview.frame = bounds; updateOverlay() }
    private func updateOverlay() {
        let strokes = CGMutablePath(), points = CGMutablePath()
        func project(_ p: CGPoint) -> CGPoint {
            let point = preview.layerPointConverted(fromCaptureDevicePoint: CGPoint(x: p.x, y: 1 - p.y))
            // AVFoundation returns top-origin layer points; AppKit's backing layer uses bottom-origin paths.
            return CGPoint(x: point.x, y: preview.bounds.height - point.y)
        }
        for line in overlay.contours {
            guard let first = line.first else { continue }
            strokes.move(to: project(first))
            for point in line.dropFirst() { strokes.addLine(to: project(point)) }
        }
        for point in overlay.joints {
            let p = project(point)
            points.addEllipse(in: CGRect(x: p.x - 2.7, y: p.y - 2.7, width: 5.4, height: 5.4))
        }
        CATransaction.begin(); CATransaction.setDisableActions(true)
        lines.frame = preview.bounds; dots.frame = preview.bounds
        lines.path = strokes; dots.path = points
        CATransaction.commit()
    }
}
private struct PostureCameraPreview: NSViewRepresentable {
    let session: AVCaptureSession
    let overlay: PostureOverlay
    func makeNSView(context: Context) -> CameraPreviewView {
        let view = CameraPreviewView(); view.preview.session = session
        if let connection = view.preview.connection, connection.isVideoMirroringSupported {
            connection.automaticallyAdjustsVideoMirroring = false; connection.isVideoMirrored = true
        }
        return view
    }
    func updateNSView(_ nsView: CameraPreviewView, context: Context) { nsView.overlay = overlay }
    static func dismantleNSView(_ nsView: CameraPreviewView, coordinator: ()) { nsView.preview.session = nil }
}

@MainActor
final class PostureAlertController {
    private var panel: NSPanel?
    private var dismissTask: Task<Void, Never>?
    private var rotation = PostureMessageRotation()
    private var previewRotation = PostureMessageRotation()
    var appearance: NSAppearance? { didSet { panel?.appearance = appearance } }
    func show(issue: PostureIssue, playful: Bool, displaySeconds: Double = 5, preview: Bool = false) {
        close()
        guard let screen = NSApp.keyWindow?.screen ?? NSApp.mainWindow?.screen ?? NSScreen.main else { return }
        let message = preview ? previewRotation.message(for: issue, playful: playful) : rotation.message(for: issue, playful: playful)
        let maxWidth = min(860, screen.visibleFrame.width - 48)
        let textSize = (message as NSString).boundingRect(with: NSSize(width: maxWidth - 32, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: [.font: NSFont.systemFont(ofSize: 14, weight: .medium)])
        let width = min(maxWidth, ceil(textSize.width) + 32), height = ceil(textSize.height) + 20
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: width, height: height),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.title = preview ? "息间 · 坐姿提醒预览" : "息间 · 坐姿提醒"
        panel.isFloatingPanel = true
        // isFloatingPanel sets the level to floating; apply our final level afterwards.
        panel.level = .screenSaver; panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isReleasedWhenClosed = false; panel.appearance = appearance
        panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.contentView = NSHostingView(rootView: PostureAlertView(message: message, width: width, height: height))
        panel.setFrameOrigin(NSPoint(x: screen.visibleFrame.midX - width / 2, y: screen.visibleFrame.maxY - height - 8))
        self.panel = panel; panel.orderFrontRegardless()
        dismissTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(PostureThreshold.displaySeconds.normalized(displaySeconds) * 1_000_000_000))
            guard !Task.isCancelled else { return }; self?.close()
        }
    }
    func close() { dismissTask?.cancel(); dismissTask = nil; panel?.orderOut(nil); panel?.contentView = nil; panel?.close(); panel = nil }
}
private struct PostureAlertView: View {
    let message: String
    let width: CGFloat
    let height: CGFloat
    var body: some View {
        Text(message)
            .font(.system(size: 14, weight: .medium)).lineSpacing(3).multilineTextAlignment(.center)
            .padding(.horizontal, 16).padding(.vertical, 10).foregroundStyle(Palette.ink).frame(width: width, height: height)
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Palette.line, lineWidth: 1))
    }
}

private struct PostureMethodView: View {
    let animated: Bool
    @StateObject private var referencesDisclosure = PostureDisclosureState()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("一个正面镜头，能看清什么？")
                .font(.system(size: 16, weight: .semibold))
                .accessibilityAddTraits(.isHeader)
            Text("本机运行 Lightweight OpenPose：用关键点热力图定位鼻部、颈部、肩部，再用 PAF 肢体关联场校验连接，避免把背景或另一人的点接过来。面部方向由 Apple Vision 提供。与 4 秒个人校准比较，观察头部侧倾、俯仰、肩线及头肩比例；连续偏离才提醒，短暂转头和识别丢失不累积。画面里的线来自实际检测结果，肩部不可靠时只标记面部。")
                .font(.system(size: 13)).foregroundStyle(Palette.secondary).lineSpacing(5).fixedSize(horizontal: false, vertical: true)
            Text("正面画面不能可靠测量标准头前倾角度，不能判断颈椎曲度、驼背或腰椎状态。「疑似探头」需多个信号共同出现，单纯靠近镜头不会触发。")
                .font(.system(size: 13)).foregroundStyle(Palette.secondary).lineSpacing(5).fixedSize(horizontal: false, vertical: true)
            Divider().overlay(Palette.line)
            HStack {
                Text("研究参考（3 篇）")
                    .font(.system(size: 14, weight: .semibold))
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Button {
                    withAnimation(animated ? .easeInOut(duration: 0.2) : nil) {
                        referencesDisclosure.isExpanded.toggle()
                    }
                } label: {
                    HStack(spacing: 5) {
                        Text(referencesDisclosure.isExpanded ? "收起参考" : "展开参考")
                        LineIcon(systemName: "chevron-down", size: 12)
                            .rotationEffect(.degrees(referencesDisclosure.isExpanded ? 180 : 0))
                    }
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Palette.accentDark)
                }
                .buttonStyle(.plain)
            }
            if referencesDisclosure.isExpanded {
                reference("二维关键点如何描述人体姿态", detail: "Cao 等 · CVPR 2017。提出关键点热力图和 PAF 肢体连接方法，是本应用肩颈骨架检测所用轻量模型的基础。",
                    title: "Realtime Multi-Person 2D Pose Estimation Using Part Affinity Fields",
                    url: "https://openaccess.thecvf.com/content_cvpr_2017/html/Cao_Realtime_Multi-Person_2D_CVPR_2017_paper.html")
                reference("本应用实际采用的轻量模型", detail: "Osokin · 2018。Lightweight OpenPose 在 OpenPose 方法上使用轻量网络。本应用将作者预训练权重转换为 Core ML，在本机运行，并校验肩颈连接的 PAF 一致性。",
                    title: "Real-time 2D Multi-Person Pose Estimation on CPU: Lightweight OpenPose",
                    url: "https://arxiv.org/abs/1811.12004")
                reference("头前倾为什么需要侧面参考", detail: "Titcomb 等 · International Journal of Exercise Science，2024。研究采用颅椎角比较站姿和坐姿，说明拍摄方向及身体姿势会影响测量。正面提醒无法替代这类评估。",
                    title: "Evaluation of the Craniovertebral Angle in Standing versus Sitting Positions",
                    url: "https://pubmed.ncbi.nlm.nih.gov/38665167/")
                Text("以上论文解释方法与边界，不代表本应用的阈值已通过临床验证。保持自然、经常换姿势，比一直保持一个位置更重要。")
                    .font(.system(size: 12)).foregroundStyle(Palette.secondary).lineSpacing(4).fixedSize(horizontal: false, vertical: true)
            }
        }.card(padding: 23)
    }
    private func reference(_ heading: String, detail: String, title: String, url: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(heading).font(.system(size: 14, weight: .medium))
            Text(detail).font(.system(size: 13)).foregroundStyle(Palette.secondary).lineSpacing(4).fixedSize(horizontal: false, vertical: true)
            Link(destination: URL(string: url)!) {
                HStack(alignment: .top, spacing: 7) {
                    Text(title).font(.system(size: 12)).lineLimit(2)
                    LineIcon(systemName: "external-link", size: 13)
                }.foregroundStyle(Palette.accentDark)
            }.buttonStyle(.plain)
        }.padding(15).frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.background, in: RoundedRectangle(cornerRadius: 12))
    }
}

struct UpdateSettingsView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var updater: AppUpdater
    var body: some View {
        VStack(alignment: .leading, spacing: 19) {
            HStack(spacing: 15) {
                LineIcon(systemName: "download", size: 21).frame(width: 25).foregroundStyle(Palette.accent)
                VStack(alignment: .leading, spacing: 6) {
                    Text("版本更新").font(.system(size: 15, weight: .semibold))
                    Text("当前版本 \(updater.currentVersion)").font(.system(size: 13)).foregroundStyle(Palette.secondary)
                }
                Spacer()
                if updater.busy { ProgressView().controlSize(.small) }
                Button("检查更新") { updater.check() }.buttonStyle(SettingsButtonStyle()).disabled(updater.busy)
            }
            Text(updater.message).font(.system(size: 13)).foregroundStyle(Palette.secondary).lineSpacing(4).fixedSize(horizontal: false, vertical: true)
            if let release = updater.release, updater.hasUpdate {
                VStack(alignment: .leading, spacing: 12) {
                    Text(release.tagName).font(.system(size: 17, weight: .semibold, design: .rounded))
                    if let body = release.body, !body.isEmpty { Text(String(body.prefix(1600))).font(.system(size: 12)).textSelection(.enabled).lineLimit(10).foregroundStyle(Palette.secondary) }
                    HStack {
                        if updater.downloadedURL != nil {
                            Button("在访达中显示安装包") { updater.revealDownload() }.buttonStyle(SettingsButtonStyle(prominent: true))
                        } else {
                            Button(updater.downloading ? "下载中…" : "下载更新") { updater.download() }
                                .buttonStyle(SettingsButtonStyle(prominent: true)).disabled(updater.busy)
                        }
                        Button("查看 Release") { updater.openReleasePage() }.buttonStyle(SettingsButtonStyle())
                    }
                }.padding(16).frame(maxWidth: .infinity, alignment: .leading).background(Palette.lavender, in: RoundedRectangle(cornerRadius: 13))
            }
            Divider().overlay(Palette.line)
            HStack {
                Text("自动检查更新").font(.system(size: 14, weight: .medium))
                Spacer()
                Toggle("自动检查更新", isOn: $model.settings.automaticUpdateChecks).labelsHidden().toggleStyle(.switch)
            }
            if let checked = updater.lastChecked { Text("上次检查：\(checked.formatted(.dateTime.month().day().hour().minute()))").font(.system(size: 12)).foregroundStyle(Palette.secondary) }
            HStack {
                Spacer()
                Button("在浏览器查看版本") { updater.openReleasePage() }.buttonStyle(.plain).font(.system(size: 13)).foregroundStyle(Palette.secondary)
            }
        }.card(padding: 25).id("app-updates")
    }
}
