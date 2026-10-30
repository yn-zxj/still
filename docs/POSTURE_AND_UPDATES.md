# 坐姿关照与版本更新

## 检测能说明什么

单个正面摄像头会丢失侧面深度信息。息间使用 Apple Vision 的面部方向和 Lightweight OpenPose 的二维肩颈关键点，比较本次个人校准后的变化，辅助提醒歪头、肩线倾斜、持续低头以及疑似探头；不输出医学评分，不测量颈椎曲度、驼背程度或标准头前倾角度。

参考依据：

- [Apple：Detecting Human Body Poses in Images](https://developer.apple.com/documentation/vision/detecting-human-body-poses-in-images)：关键点有置信度，视野、遮挡和检测质量会影响结果。
- Apple SDK `VNObservation.h`：面部 pitch 为弧度，正方向表示低头；roll/yaw/pitch 均可能为 nil。实现缺少任一方向值时停止判断。
- [OSHA：Computer Workstations — Positions](https://www.osha.gov/etools/computer-workstations/positions)：头颈与躯干保持自然关系，并经常变化姿势；不是保持一个位置不动。
- [Evaluation of the Craniovertebral Angle in Standing versus Sitting Positions…](https://pubmed.ncbi.nlm.nih.gov/38665167/)：头前倾属于矢状面关系，摄影测量采用侧面参考。由此，本项目不将正面头肩比例直接当成标准头前倾角度。

这些资料支持功能边界与校准引导，**不验证本项目阈值的临床有效性**。当前判断是保守的产品规则，尚没有真人标注数据集的准确率/召回率证据。后续需要在用户同意下收集不同光线、身形、眼镜、镜头角度的匿名数值测试记录，并由人工标记姿态变化；目前不采集或存储这类记录。

## 可编辑的提醒阈值

「什么时候会提醒？」保留说明句式，所有数字原位显示为带浅底与下划线的输入框，类似填空题。回车或移开焦点保存，支持小数和键盘 Tab；不用弹窗或单独保存页。空值、非数字和越界输入保留旧值，并就地提示范围。「恢复默认」统一还原。

- 可改 14 项：累计时间 1–120 秒、展示时间 1–15 秒、冷却 5–600 秒；歪头/肩线/有肩部低头/仅头部低头/探头辅助低头角度各 1–30°；低头和探头的头肩距离比各 0.01–0.50；探头头肩比例增加 5–60%；转头识别上限 10–45°、俯仰上限 20–60°、识别丢失容忍 0–3 秒。
- 保存到现有 `settings.v1.postureThresholds`，旧设置和缺失字段默认兼容；解码和引擎入口对非有限/越界数值归一化。修改后清除旧偏离证据，保留个人坐姿基准和上次提醒时间；无需重新校准，冷却按新时长计算。关闭/重连摄像头不会重置自定义阈值。
- 页面阈值、进度条、检测规则、画面可用性和悬浮窗展示时间都使用同一配置。校准稳定条件、模型热力图/PAF/置信度和分析频率仍由算法管理。

## 默认判断规则

- 优先使用 1280×720 以保持预览和识别坐标一致，设备不支持时回退 VGA。坐姿页面最多每秒 4 次分析；后台每秒最多 2 次，丢弃过期帧并串行执行。可见页面额外提取面部轮廓与五官关键点；有可靠肩部结果才画肩线及上臂，未识别的点不绘制。
- 面部识别必须唯一，置信度至少 0.6，并有 yaw/roll/pitch。肩颈检测使用作者的 Lightweight OpenPose 权重（MobileNet + 初始阶段 + 一次 refinement），按论文采用热力图及 PAF。峰值响应至少 0.15，颈→鼻、颈→双肩连接沿线采样 10 点、至少 9 点的方向一致性超过 0.05，再与唯一面部及人体几何关系匹配；该响应不是概率，也不是医学评分。识别不足时保留头部模式，不补画假肩部。
- 模型输入 456×256 BGR，标准化 (pixel−128)/256，16 位权重；输出 19 个热力图和 38 个 PAF 通道。使用 Vision 的 scaleFit，解码还原补边，渲染通过预览层映射并修正 AppKit 坐标方向。CPU/GPU/神经网络引擎由 Core ML 调度，应用不依赖 Python 或网络推理。
- 先自然坐好，镜头固定，正脸及双肩完整入镜，稳定 4 秒且至少 6 个有效样本；即使肩部不可靠也可建立头部基准。采样中位数构成基准；图像和基准都不落盘。移动、缺失或采样间隔超过 2 秒会重置校准进度。
- 歪头：相对基准 roll 变化超过 12°。肩线：相对基准倾斜超过 10°，角度计算校正图像宽高比。
- 低头：有肩部基准时，头肩垂直距离按肩宽归一化后下降超过 0.12，且面部低头方向 pitch 增大超过 12°；仅头部模式使用低头方向 pitch 增大超过 15°。抬头的负向 pitch 不触发低头判断。
- 疑似探头：头部/肩宽的比例相对基准增大超过 20%，且同时有归一化头位下降超过 0.10 或低头 pitch 增大超过 10°。只有脸框变大或整个人等比例靠近不能触发。
- 正常前后移动、等比例距离变化或横向平移保留校准；头部方向和归一化头肩比例不依赖屏幕中的绝对位置。自动化只证明这些启发式规则按设计工作，不证明真实头前倾均可检出。
- 肩线与疑似探头仅在基准、当前帧都可靠识别双肩时判断；头部基准后来遇到可靠肩部时，在头部接近原参照、肩线稳定的条件下观察 4 秒，自动补充肩部参照，不改变原头部角度基准；持续偏离不自动学习成正常姿势。肩部不可用时对应指标显示 —。
- 每一类偏离分别累计 12 秒才提醒，提醒至少间隔 60 秒；新增或消失另一类偏离不重置仍持续的动作，提醒文案对应真正达到时间的类型。正常姿态清除对应证据。识别短暂丢失不超过 1.5 秒时暂停累计，不计入未观察到的时间；肩部暂不可用只暂停肩部相关证据，不阻断有效头部判断。持续丢失、时间倒退或长帧间隔清除证据，保留个人基准；超过 4 秒没有摄像头结果时清除当前判断。
- 提醒为屏幕顶部居中的纯文字长条、`.screenSaver` 级非激活悬浮面板，不抢键盘焦点；没有标题、图标、关闭/导航/延后按钮，鼠标可穿透，5 秒自动消失。14pt 中等字重，按实际文字宽度加左右各 16pt 留白，上下各 10pt；距可用屏幕顶部 8pt，长文按屏宽自动换行。可选择轻松吐槽/温柔提醒。系统锁屏或系统级窗口仍由 macOS 控制，不能承诺覆盖。
- 文案共 12 条吐槽（四类动作各三条）和 4 条温柔提醒；同一类型循环轮换。预览轮换四类动作，独立于真实文案轮换、证据和冷却，不会代替算法检测。页面展示具体阈值、当前检测可用性、偏离进度、冷却剩余和最近实际提醒时间；最近提醒只在内存，不产生坐姿历史记录。

## 生命周期与隐私

- 设置开关默认关闭。打开后显示「坐姿关照」导航；首次由系统询问摄像头权限。拒绝时显示原因和系统设置入口。
- 只有启用功能且没有手动暂停/系统睡眠/锁屏/休息才运行摄像头。关闭主窗口或切换页面可继续后台分析。
- 暂停、关闭开关、系统休息与退出会停止 session 并释放输入输出；普通暂停/休息恢复保留已有参照，只重置连续偏离证据；关闭功能、显式重新连接和退出应用清除内存参照。镜头角度改变时可手动重新校准。
- 手动暂停状态保存在当前用户的 `posture.paused.v1`；重启不会擅自重新打开已暂停的摄像头，校准仍只在本次运行内存保留。
- 画面不录制、不保存、不上传；不创建姿态照片或健康记录。只在本机内存里保留当前识别数值与本次校准，当前版本没有历史坐姿分数。
- 摄像头接入、光照和长时功耗需要真机验收。自动化的合成关键点测试不能替代真人误报/漏报评估。

## GitHub Release 更新

- 固定源：`yn-zxj/still`，GitHub REST `GET /repos/yn-zxj/still/releases/latest`，只接受正式稳定版。
- 设置页和应用菜单提供检查更新，自动检查最多每天一次成功检查（启动以及每小时检查时间门限）；网络或服务错误不会伪装成“最新版本”。
- 当前仓库为公开仓库，客户端匿名访问 GitHub REST 和 Release 附件，不要求账号、只读令牌或 Keychain 凭据。[GitHub 文档](https://docs.github.com/en/rest/releases/releases#get-the-latest-release)
- 仅接受同仓库 HTTPS Release 地址与数字稳定版本，版本按数值比较，按本机架构选择 ZIP；没有匹配安装包/校验文件时保持错误状态。
- Release 附件通过固定的 GitHub asset API 获取；到 CDN 重定向时仍移除任意 Authorization/Cookie，只允许 HTTPS GitHub 与 githubusercontent 主机。
- ZIP 下载到临时文件后核对字节数及 SHA-256，正确才提交到 `~/Library/Caches/Still/Updates`；失败不替换旧包。不自动解压执行下载内容。
- 安装：点击在访达中显示安装包，解压，正常退出息间，以新应用替换原位置，再次打开。当前没有后台自替换/自动重启；保留 `local.still.app` 和已有用户数据。
- SHA-256 检查保障附件与同一 Release 的校验文件一致，不替代 Developer ID、公证或独立签名信任。公开仓库保持源码可审查，第三方课程媒体、个人数据与凭据不进入 Git 历史或 Release。

## 方法与论文展示

坐姿页面提供简短的检测方法说明和论文入口：

- [Cao 等，CVPR 2017：Realtime Multi-Person 2D Pose Estimation Using Part Affinity Fields](https://openaccess.thecvf.com/content_cvpr_2017/html/Cao_Realtime_Multi-Person_2D_CVPR_2017_paper.html)：说明二维关键点及人体连接关系的研究背景。本应用确实运行派生的 Lightweight OpenPose 网络，并检查 PAF 肢体关联；不能据该论文宣称本应用的临床准确性。
- [Osokin，2018：Real-time 2D Multi-Person Pose Estimation on CPU: Lightweight OpenPose](https://arxiv.org/abs/1811.12004)：实际使用的轻量模型，来源/提交/权重摘要保存在 `Resources/Models/SOURCE.json`，附 Apache-2.0 许可证。转换脚本 `scripts/convert-posture-model.py` 只作为开发工具，不随应用运行。
- [Titcomb 等，2024：Evaluation of the Craniovertebral Angle in Standing versus Sitting Positions](https://pubmed.ncbi.nlm.nih.gov/38665167/)：作为侧面摄影测量及姿势影响测量的参考，不将其颅椎角阈值直接搬到正面摄像头。

## 模型供应与可复现构建

- 代码来源固定为 `Daniil-Osokin/lightweight-human-pose-estimation.pytorch` 的 `d23c284b09acf27a163e1febd511e7482cac25ed`。
- 检查点来自上游 README 指定的 Intel 下载地址，SHA-256 `517c86f769c6636583083f1467e3d212a0006c27109edb3aeffc19a79622d411`。
- 与上游 demo 一样只保留一次 refinement，严格核对所用参数；作者训练检查点的额外 refinement 阶段不导出，未随机补权重。
- Core ML 源模型约 7.8 MiB，SHA-256 由 SOURCE.json 记录，并由自动化和 Bundle 流水线校验；首次本机编译缓存按模型摘要区分版本。
- 官方转换用 PyTorch 2.5.1、coremltools 8.3.0、NumPy 1.x。重建前取上游固定提交，运行：`python scripts/convert-posture-model.py --upstream /path/to/pinned-source --checkpoint /path/to/checkpoint.pth --output Resources/Models/StillPose.mlmodel`。原检查点及 Python 环境不放入仓库或应用。
- 用户提供的同一张上半身截图：原 Vision 人体检测 0 个 observation；新模型通过鼻—颈—左右肩三条 PAF，Swift 原生路径检测到双肩，重复 3 次均通过。本机该静态样例平均推理约 15 ms，不代表全部设备/完整视频准确率或端到端提醒延迟。截图仅内存分析，未复制到仓库。

## 验证状态

实现后的自动化、普通应用 UI、摄像头真机以及 Release 状态分别记录在 PROJECT_STATUS.md，不以其中一项替代其它项。
