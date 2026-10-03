# NEXT_TARGET

更新日期：2026-08-23

## 输入法下一目标

2026-08-01 已新增隔离的 `FlotisInputMethod` InputMethodKit target、version `1` session-bound commit request、MainActor service、直接 IMK client 提交控制器与 8 个纯策略测试。2026-08-02 又按用户明确要求完成 build `3` 的本机 ad-hoc 签名与用户级安装，补齐 background-only/输入源图标元数据并修复 legacy `IMKServer` 初始化崩溃；最终 server 启动稳定，输入法 8 tests 与当时主 App 61 tests 均通过。2026-08-04 主 App 当前行为最终确定为“开始 → 停止/审阅 → 复制并返回可见小胶囊”，固定 voice hotkey 为 `⌃⌥A`，不调用旧剪贴板注入器。2026-08-05 又在不改变最终剪贴板边界的前提下加入可选的 2–4 个 OpenAI Compatible recorded-file model route 对比：只录一次、并发返回候选；同日 Provider、对比选择、endpoint/model/options 和 API key 收口为 schema v2 `config.json`：一个 Provider 共享 endpoint/key 并拥有多个模型，Apple 不进入 canonical catalog，OpenRouter 使用 JSON+Base64；旧 canonical v1、UserDefaults / `secrets.json` 仅作迁移输入。2026-08-06 对比交互改为自动打开首个成功项、固定双列/四项 2×2，并在对比审阅期间用 `⌥←` / `⌥→` 循环查看，现有 `⌃⌥A` 复制当前项；Settings 的折叠标题和 route 也改为整行可点。2026-08-07 panel 显隐和两个对比导航组合键改为由用户配置并写入同一 `config.json`，旧组合保留为默认值；固定 voice hotkey 未开放修改，对比导航仍只在多候选审阅期间临时注册。同日 Settings 左栏改为“快捷键 / 转写”，移除品牌图标和快捷键页的重复说明，四项组合集中在一张卡。2026-08-16 该卡再次按用户要求收敛为四个 `52` pt 行和 `156×38` 的轻量组合键 surface，并移除常驻说明、铅笔与恢复控件；随后 voice 行也开放相同录制能力，四项一起写入 canonical `shortcuts`，voice 默认仍为 `⌃⌥A`，胶囊即时显示当前组合。默认单 route 路径仍保留。2026-08-21 又在不改变语音或输入法边界的前提下加入同进程 Quick Ask：默认 `⌃⌥Q` / Carbon ID `500` 打开独立 `420×560` 临时 Chat Completions panel，关闭销毁 messages/draft；不新增第二颗胶囊、Keychain/UserDefaults 或输入法接线。2026-08-22 按用户纠正，Quick Ask 的持久配置改为与转写相同的 Provider/Models 工作模式：同一 `config.json` 内使用独立 `quick_ask` catalog，支持多 Provider、每 Provider 多模型、共享 endpoint/API key、Active model、Connection/Models 和独立 Advanced；聊天数据域仍不混入转写 provider/comparison。当前登录会话仍未发现新输入源，输入法也仍未连接语音链路。

2026-08-22 compact 胶囊在保持 `96×36` 不变的前提下试装双快捷键显示：14 pt JetBrains Mono Semibold 的 `<voice>/<Quick Ask>`，默认 `⌃⌥A/⌃⌥Q`，任一设置变化即时更新；Computer Use 已确认原生截图仍为精确 `96×36`。这不改变语音或 Quick Ask 的动作、配置或输入法边界。

2026-08-23 Quick Ask 临时框已改为和胶囊一致的非激活 floating/跨 Space 置顶方式：`orderFrontRegardless()` 只抬升聊天面板，随后由该面板单独取得键盘焦点，不再激活整个 Flotis；默认点击取焦点和标题栏原生拖动均保留。自动构建/104+8 tests、Release 安装与来源路径启动已通过；物理 `⌃⌥Q` 的跨 App/Space 层级仍需用户直接确认。这不改变输入法下一目标。

下一目标必须按阶段推进，不能把“接口已构建”直接当成“语音输入法已完成”：

1. 用户自行注销并重新登录；不要由自动化结束当前登录会话。重新登录后确认 Keyboard Settings/Input menu 能发现并启用 `Flotis Voice`，记录 build `3` 的系统发现结果。
2. 仅用输入法自带菜单测试 TextEdit、Notes、浏览器 input/textarea 等客户端：普通键盘输入必须透传，测试文本只进入当前 caret；快速切 app/关窗口/换控件时旧 session 必须拒绝。记录结果但不得记录完整输入文本。
3. 为 `com.Vita0818.FlotisInputMethod` 配置与主 App 一致且稳定的 Apple Development Team/代码身份，并重新验证重复安装、输入源缓存与启动；当前 ad-hoc 身份只证明本机 build `3` 可运行，不等于稳定签名。
4. 在不接触 provider 的前提下设计并审计主 App → 输入法的本地 IPC：versioned payload、调用方认证/同用户边界、active session 获取方式、超时、大小上限、重放与输入法未运行时的错误。不得把 session UUID 误当成身份认证，也不得使用公开 Distributed Notification 携带 transcript。
5. 只有用户确认上述运行态接口方向后，才把 reviewing 的显式确认接到输入法 transport。当前默认行为固定为系统剪贴板复制并返回可见小胶囊；未来接线必须明确输入法可用/不可用时是否保留该复制 fallback，不能静默把文本发往未经核验的新焦点。`ClipboardPasteInjector` 已退出产品路径，仅保留源码兼容，不得当作自动 fallback。
6. 接线后再跑当前全部主 App tests、输入法 8 tests、真实客户端焦点竞态，以及旧注入器的独立安全策略回归；输入法路径不应要求 AX、系统剪贴板或模拟 `⌘V`。

## 当前非目标

- 自定义波形、过渡动画、声纹或复杂视觉效果。
- 在用户确认输入法运行态与 IPC 设计前，把当前复制并返回默认路径替换为输入法 transport。
- 未经授权自动安装/启用输入法、注销登录会话或操作 Keyboard Settings。
- 删除旧 `CommandStore`、`PromptCommand` 或 `commands.json`。
- 在没有新的明确需求时继续修改六个 adapter 的线上协议 payload、adapter ID、runtime route 兼容模型或 canonical config 凭据边界。
- 把当前 recorded-file 对比扩展到 Realtime/Apple 共享捕获、自动评分/合并结果，或默认持久化候选 transcript；这些都需要单独产品与隐私设计。
- 自动读取整个前台文档、剪贴板历史或其他未明确授权的上下文。
- 把 Quick Ask 扩展为 streaming、HTTP localhost/LAN、自动 provider/model fallback、持久化聊天历史、语音直接提问或与输入法互通；这些都需要新的明确产品与隐私决策。

## 完成条件

- 系统发现、普通输入透传、菜单 commit 与焦点竞态矩阵有不含敏感信息的结果。
- IPC 方案明确认证、会话、超时、重放、payload 和 unavailable 行为，并经用户确认后才开始主 App 接线。
- 所有发现的稳定性问题有可复现步骤、修复和回归覆盖。
- `xcodegen generate`、两个 application build、两个 XCTest target 与 `git diff --check` 全部通过。
- 达成后删除本文件，或将其替换为下一项已经确认的具体目标。
