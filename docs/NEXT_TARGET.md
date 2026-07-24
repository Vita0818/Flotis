# NEXT_TARGET

更新日期：2026-07-12

## V0.8 下一目标

在继续设计动画或接入智能改写层之前，先完成 V0.8 小胶囊主链路的真机稳定性验证与必要修复：

1. 使用 `⌘⌥⇧R` 真机验证 idle → recording/streaming → reviewing → injecting → idle，确认快速重复按键不会产生双会话、丢失尾音或重复注入。
2. 验证点击 nonactivating 胶囊编辑文本后，确认动作只回注最近一个有效的非 Flotis 目标；覆盖目标退出、用户切换第三个 app、跨 Space、慢激活、修饰键未释放与 AX 权限撤销。
3. 先真机复测 Apple 累积修复：短句、空 final、两个词中间静音 3–5 秒、同段纠错和重复词；再分别使用本地 mock/connection test 以及可用的真实 provider 账号验证六个 adapter 的 start/stop/cancel/terminal 行为。不得在报告中记录 API key 或完整转写文本。
4. 对注入失败保留文本、重试成功、剪贴板 manager 竞争和复杂剪贴板恢复做真机矩阵。
5. 稳定性通过后，再设计独立的智能文本处理接口；它只能位于最终 transcript 与 reviewing 之间，不得侵入 provider adapter、Keychain 或 `ClipboardPasteInjector` 安全边界。

## 当前非目标

- 自定义波形、过渡动画、声纹或复杂视觉效果。
- 删除旧 `CommandStore`、`PromptCommand` 或 `commands.json`。
- 修改六个 provider 的线上协议 payload、adapter ID、connection v3 schema 或 Keychain 边界。
- 自动读取整个前台文档、剪贴板历史或其他未明确授权的上下文。

## 完成条件

- 完成上述真机矩阵并记录不含敏感信息的结果。
- 所有发现的稳定性问题有可复现步骤、修复和回归覆盖。
- `xcodegen generate`、Debug build、完整 XCTest、`git diff --check` 全部通过。
- 达成后删除本文件，或将其替换为下一项已经确认的具体目标。
