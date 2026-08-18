# Simple UI 增强插件

这是一个用于集中管理个人 SimpleUI 易用性改进的 KOReader 插件，结构参考
`simpleui_ext.koplugin`，但去掉了与当前目标无关的统计模块和补丁。

## 当前包含的补丁

### `patch_qs_slider_style.lua`：前光灯滑块样式

- 默认状态：开启。
- 在 SimpleUI 快捷设置栏设置中增加“原版”“细线”和“圆形”三种样式。
- 同一个样式选项同时作用于 SimpleUI 快捷设置面板和 KOReader 原生前光灯窗口。
- KOReader 原生窗口同步亮度和色温的滑轨、滑块及配套控制格式；设备特有的开关、配置等功能按钮保持不变。
- 原版和细线样式会同时保留亮度、色温的 `Max`；圆形样式会同时隐藏并禁用两者的 `Max`，与 SimpleUI 面板保持一致。
- 圆形样式参考墨水屏系统滑块：细轨道搭配白底黑边的圆形滑块。
- 在 SimpleUI 面板中，圆形样式的加减按钮使用无边框纯符号，并移除 `Max` 最大值按钮。
- 在 SimpleUI 面板中，圆形样式缩小左右加减按钮的占位，让符号更靠近面板边缘；释放的空间补给滑轨，滑轨不会越过加号。
- 自动适配仅亮度设备。
- 在支持自然光/色温的设备上同时处理亮度和色温滑块。
- 兼容 SimpleUI 2.1.x 的平铺模块结构和 2.5.x 的分目录结构。

补丁开关位于：

```text
工具 → Simple UI 增强 → 增强功能 → 前光灯：滑块样式
```

启用补丁后，具体样式选择位于：

```text
SimpleUI → 快捷设置栏 → 滑块样式
```

### `patch_filebrowserplus_qr.lua`：FileBrowserPlus 二维码增强

- 默认状态：开启；直接补丁 FileBrowserPlus 1.2.x，不依赖 SimpleUI 快捷操作。
- 保留 FileBrowserPlus 1.2.x 原层级：短按顶层项目启动/停止服务器，长按进入设置。
- 在长按设置页中保留原版端口、路径、密码、自动启动和自动停止等项目，并增加“显示二维码”和“启动时自动显示二维码”。
- 默认在服务器启动后显示二维码；关闭二维码不会停止服务器。
- 停止服务器时自动关闭二维码。

补丁开关位于：

```text
工具 → Simple UI 增强 → 增强功能 → FileBrowserPlus：二维码增强
```

## 安装

这是一个完整的 KOReader 插件，不是 KOReader 用户补丁。请勿放入
`koreader/patches/`。

1. 将整个项目目录命名为 `mysimpleui_ext.koplugin`。
2. 把该目录复制到 KOReader 的 `plugins/` 目录。
3. 确保 SimpleUI 插件已启用，然后完全重启 KOReader。

正确的安装结构如下：

```text
koreader/
└── plugins/
    └── mysimpleui_ext.koplugin/
        ├── _meta.lua
        ├── main.lua
        ├── LICENSE
        ├── README.md
        └── patches/
            ├── patch_filebrowserplus_qr.lua
            └── patch_qs_slider_style.lua
```

插件入口位于：

```text
工具 → Simple UI 增强
```

## 插件内部开发约定

下面提到的 `patches/` 是
`koreader/plugins/mysimpleui_ext.koplugin/patches/`，不是 KOReader 根目录下的
`koreader/patches/`。

新的增强功能补丁放入本插件自己的 `patches/` 子目录，文件名采用：

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
