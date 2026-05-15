# MyMinimax

基于 Flutter 开发的个人 AI Agent 应用，集成 Minimax API，支持 Android 平台的多模态智能助手。

## 功能概览

### 智能对话
- 多轮对话上下文管理，支持长会话记忆
- Markdown 富文本渲染，代码块语法高亮
- LaTeX 数学公式渲染（flutter_math_fork）
- 流式输出与打字机效果
- 中/英文国际化支持

### Agent 引擎
- **决策引擎** — 自主分析用户意图，选择执行策略
- **任务编排器** — 复杂任务自动拆解为多步骤执行
- **工具调用** — 动态注册与调用，支持工具链串联
- **循环监控** — 检测无限循环与异常重复调用，自动熔断
- **电池感知** — 根据电量状态调整后台任务频率
- **网络韧性** — 断网重连、请求重试、超时降级
- **反馈处理** — 任务结果评估与自我纠错
- **状态持久化** — Agent 会话状态保存与恢复

### 浏览器自动化
- Chrome DevTools Protocol (CDP) 驱动真实网页操作
- 页面元素树解析与智能定位
- 页面内容智能提取与结构化输出
- 页面停滞检测与动作循环检测
- WebSocket 长连接事件桥接

### 地图导航
- 高德地图 Android 原生 SDK 深度集成
- 实时位置追踪与用户标记
- 路线规划（驾车、步行、骑行）
- 箭头折线绘制路线方向指示
- POI 搜索与周边推荐
- 地图标记自动生成

### 语音交互
- Vosk 离线语音识别，无需联网
- 离线语音模型加载与管理
- 实时语音输入转文字

### 视觉与 OCR
- 摄像头拍照识别
- 相册图片选取分析
- PaddleOCR v5 移动端离线 OCR（ncnn 推理）
  - 文字检测模型 + 文字识别模型
  - JNI 原生调用，低延迟
- 识别结果后处理与结构化

### 记忆系统
- 用户偏好自动记忆与更新
- 上下文关联记忆召回
- 记忆新鲜度衰减与清理
- 双层缓存架构（内存 + 本地数据库）

### 屏幕与通知
- 前台悬浮窗服务，常驻运行
- 屏幕内容截图捕获
- 系统通知监听与内容提取
- 本地通知推送
- 开机自启（BootReceiver）

### 系统集成
- **短信** — 短信收发、内容解析、广播接收
- **通话** — 来电/去电状态监听与处理
- **日历** — 日程创建、查询、提醒
- **联系人** — 通讯录读取与搜索
- **文件** — SAF 文件访问、文件选择器

### 内容创作
- **图片生成** — AI 文生图
- **视频生成** — AI 文生视频
- **音乐生成** — AI 音乐创作
- **文档编辑器** — 富文本编辑（flutter_quill）
- **文档转换** — Markdown ↔ PDF 互转
- **文档生成** — 智能排版与样式输出

### 设计系统
- Galaxy UI 设计风格（来自 Galaxy Buds 灵感）
- 组件配方库（Component Recipes）
- 配色方案自动生成（Color Tokens）
- 字体配对推荐（Font Pairings）
- 登录页模式库（Landing Patterns）
- 产品路由引导（Product Router）
- UX 规则引擎与风格预设
- 页面自动生成器

### 技能与扩展
- **Skill 系统** — 可扩展的技能注册与调度框架
- **Hook 系统** — 任务生命周期钩子，支持前置/后置拦截
- **MCP 协议** — Model Context Protocol 支持，外部工具集成
- **工具面板** — 可视化工具选择与参数配置

### 其他服务
- 天气查询（集成高德天气 API）
- 快递查询（集成快递 100 API）
- 全球时区查询
- 联网搜索与实时信息获取

## 技术栈

| 领域 | 技术 |
|------|------|
| 框架 | Flutter 3.x / Dart |
| 状态管理 | Riverpod |
| 网络请求 | Dio |
| 本地存储 | SQLite (sqflite)、SharedPreferences |
| 序列化 | Freezed + json_serializable |
| 语音识别 | Vosk (离线) |
| 地图 | 高德地图 Android SDK |
| OCR | PaddleOCR v5 (ncnn 推理) |
| 浏览器 | CDP (Chrome DevTools Protocol) |
| 文档 | flutter_quill、pdf、markdown |
| 后台任务 | flutter_foreground_task |

## 项目结构

```
lib/
├── agent/           # 后台 Agent 入口
├── app/             # 应用入口、主题、启动屏
├── core/            # 核心模块
│   ├── api/         # API 客户端（Minimax、高德、天气、快递等）
│   ├── asr/         # 语音识别服务
│   ├── browser/     # 浏览器自动化（CDP）
│   ├── design/      # 设计系统（Galaxy UI Tokens）
│   ├── engine/      # Agent 决策引擎
│   ├── hooks/       # Hook 系统
│   ├── i18n/        # 国际化（中/英）
│   ├── mcp/         # MCP 协议支持
│   ├── map/         # 地图模块
│   ├── orchestrator/# 任务编排器
│   ├── skills/      # 技能系统
│   ├── storage/     # 数据持久化
│   ├── tools/       # 工具注册与执行
│   └── widgets/     # 通用组件
├── features/        # 功能模块
│   ├── chat/        # 对话
│   ├── browser/     # 浏览器
│   ├── map/         # 地图导航
│   ├── memory/      # 记忆管理
│   ├── speech/      # 语音
│   ├── vision/      # 视觉
│   ├── creation/    # 内容创作
│   ├── files/       # 文件管理
│   ├── tools/       # 工具面板
│   ├── settings/    # 设置
│   └── trends/      # 趋势
└── shared/          # 共享模块（文档转换、编辑器等）
```

## 开始开发

### 环境要求
- Flutter SDK >= 3.5.0
- Android SDK 21+
- JDK 17+

### 安装
```bash
git clone https://github.com/shifangZhao/MyMinimax.git
cd MyMinimax
flutter pub get
```

### 运行
```bash
flutter run -d android
```

### 构建

#### APK（安装包）

```bash
# 单包（包含所有 ABI，体积较大）
flutter build apk --release

# 按架构拆分（推荐发布用，体积更小）
flutter build apk --release --target-platform android-arm64,android-arm --split-per-abi

# 仅 64 位（大部分新机型）
flutter build apk --release --target-platform android-arm64

# 仅 32 位（老旧设备兼容）
flutter build apk --release --target-platform android-arm
```

构建产物在 `build/app/outputs/flutter-apk/` 下：

| 文件 | 适用设备 |
|------|----------|
| `app-arm64-v8a-release.apk` | 大多数现代手机（骁龙 8 系、天玑等） |
| `app-armeabi-v7a-release.apk` | 老旧 32 位设备 |
| `app-release.apk` | 通用包（体积大，兼容所有设备） |

#### AppBundle（上架 Google Play）

```bash
flutter build appbundle --release
```

产物：`build/app/outputs/bundle/release/app-release.aab`

#### 调试包

```bash
# Debug 模式（热重载、调试工具）
flutter build apk --debug

# Profile 模式（性能分析）
flutter build apk --profile
```

#### Web

```bash
flutter build web --release
```

产物：`build/web/`

## 参考与致谢

本项目在开发过程中参考了以下开源项目的设计思想与实现，特此致谢：

| 项目 | 参考模块 |
|------|----------|
| [browser-use](https://github.com/browser-use/browser-use) | 浏览器自动化（CDP 协议、页面操作） |
| [instructor](https://github.com/instructor-ai/instructor) | LLM 结构化输出 |
| [mem0](https://github.com/mem0ai/mem0) | 记忆层设计 |
| [MarkItDown](https://github.com/microsoft/markitdown) | 文档格式转换 |
| [TrendRadar](https://github.com/sansan0/TrendRadar) | 趋势热点追踪 |
| PageIndex | 页面索引与检索 |
| [remotion](https://github.com/remotion-dev/remotion) | 视频生成编排 |
| Galaxy UI | 设计系统 Token |
| [UI UX Pro Max](https://github.com/nextlevelbuilder/ui-ux-pro-max-skill) | UX 规则引擎 |
| [shadcn/ui](https://github.com/shadcn-ui/ui) | UI 组件设计 |
| Skills (anthropic) | 技能注册与调度 |
| [ncnn](https://github.com/Tencent/ncnn) | 深度学习推理框架 |
| ncnn-android-ppocrv5 | PaddleOCR v5 移动端适配 |
| [busybox-ndk](https://github.com/Magisk-Modules-Repo/busybox-ndk) | BusyBox Android NDK |
| [Umi-OCR](https://github.com/hiroi-sora/Umi-OCR) | OCR 离线识别方案 |

以上项目各属其原作者所有。

## 许可证

MIT License
