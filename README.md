# Simple UI 增强插件

这是一个用于集中管理个人 SimpleUI 易用性改进的 KOReader 插件，结构参考
`simpleui_ext.koplugin`，但去掉了与当前目标无关的统计模块和补丁。

## 当前包含的补丁

### `patch_qs_slider_style.lua`：快捷设置栏滑块样式

- 默认状态：开启。
- 在 SimpleUI 快捷设置栏设置中增加“原版”“细线”和“圆形”三种样式。
- 细线和圆形样式仅修改 SimpleUI 快捷设置面板，不影响 KOReader 原生前光灯窗口。
- 圆形样式参考墨水屏系统滑块：细轨道搭配白底黑边的圆形滑块。
- 圆形样式的加减按钮使用无边框纯符号，并移除 `Max` 最大值按钮。
- 圆形样式缩小左右加减按钮的占位，让符号更靠近面板边缘；释放的空间补给滑轨，滑轨不会越过加号。
- 自动适配仅亮度设备。
- 在支持自然光/色温的设备上同时处理亮度和色温滑块。
- 兼容 SimpleUI 2.1.x 的平铺模块结构和 2.5.x 的分目录结构。

补丁开关位于：

```text
工具 → Simple UI 增强 → 增强功能 → 快捷设置栏：滑块样式
```

启用补丁后，具体样式选择位于：

```text
SimpleUI → 快捷设置栏 → 滑块样式
```

### `patch_filebrowserplus_qr.lua`：FileBrowserPlus 文件管理快捷操作

- 默认状态：开启；需要已安装并启用 [FileBrowserPlus](https://github.com/patelneeraj/filebrowserplus.koplugin)。
- 在 `SimpleUI → 快捷设置栏 → 快捷操作` 中增加“文件管理 / FileBrowserPlus”。
- 单击快捷操作可以切换 FileBrowserPlus：未运行时启动并居中显示二维码，运行中再次单击会停止服务；二维码下方同时显示 `IP:port`。
- 关闭二维码只关闭弹窗，不会停止文件管理服务；长按快捷操作会再次显示正在运行的服务二维码。
- KOReader 不支持二维码组件时，会提示使用 `IP:port` 连接。

补丁开关位于：

```text
工具 → Simple UI 增强 → 增强功能 → 文件管理：FileBrowserPlus
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
