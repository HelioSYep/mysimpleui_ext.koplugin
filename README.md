# 我的 SimpleUI 增强插件

这是一个用于集中管理个人 SimpleUI 易用性改进的 KOReader 插件，结构参考
`simpleui_ext.koplugin`，但去掉了与当前目标无关的统计模块和补丁。

## 当前包含的补丁

### `patch_qs_slider_style.lua`：快捷设置栏滑块样式

- 默认状态：开启。
- 在 SimpleUI 快捷设置栏设置中增加“原版”和“细线”两种样式。
- 细线样式仅修改 SimpleUI 快捷设置面板，不影响 KOReader 原生前光灯窗口。
- 自动适配仅亮度设备。
- 在支持自然光/色温的设备上同时处理亮度和色温滑块。
- 兼容 SimpleUI 2.1.x 的平铺模块结构和 2.5.x 的分目录结构。

补丁开关位于：

```text
工具 → 我的 SimpleUI 增强 → 增强功能 → 快捷设置栏：滑块样式
```

启用补丁后，具体样式选择位于：

```text
SimpleUI → 快捷设置栏 → 滑块样式
```

## 安装

1. 将项目目录命名为 `mysimpleui_ext.koplugin`。
2. 复制到 KOReader 的 `plugins/` 目录。
3. 确保 SimpleUI 插件已启用，然后完全重启 KOReader。

插件入口位于：

```text
工具 → 我的 SimpleUI 增强
```

## 开发约定

新的增强补丁放入 `patches/`，文件名采用：

```text
patch_<id>.lua
```

文件返回：

```lua
return {
    id = "<id>",
    name = "菜单名称",
    description = "功能说明",
    default_enabled = false,
    apply = function()
        -- 安装增强
        return true
    end,
}
```

`id` 必须与文件名中的 `<id>` 一致。启停增强后需要重启 KOReader。

## 许可

本项目结构参考 `simpleui_ext.koplugin`，按照 GNU Affero 通用公共许可证
第 3 版发布。完整许可证见 `LICENSE`。

## 致谢

- [doctorhetfield-cmd/simpleui.koplugin](https://github.com/doctorhetfield-cmd/simpleui.koplugin)
- `simpleui_ext.koplugin`：本项目的补丁发现与启停菜单以其结构为参考。
