# 插件增强

`Plugin_enhancements.koplugin` 是一个统一管理 KOReader 功能补丁和
SimpleUI 扩展模块的插件。

当前正式版本为 `0.8.0`，保留项目已有的全部功能，并新增
SimpleUI 快捷设置栏双状态图标补丁。当前版本同时适配 SimpleUI
2.1.1 与 2.5.0。插件会自动探测旧版
`desktop_modules/ + sui_*.lua` 和新版 `modules/ + infra/ + screens/`
目录结构，不需要手动选择版本。

组件文件会在 KOReader 启动时加载，以便读取名称、说明和设置菜单；新发现的
模块和补丁初始状态全部为关闭：

- 模块关闭时不会注册到 SimpleUI。
- 补丁关闭时不会执行 `apply()`。
- 在“插件增强”中更改状态后，需要完整重启 KOReader。
- 已经保存过的用户选择不会被版本升级重置。

## 主菜单

```text
工具
└── 插件增强
    ├── SimpleUI
    │   ├── 扩展模块
    │   │   ├── 当前阅读 (With Pace)
    │   │   ├── 当前阅读 (Yanllsama Legacy)
    │   │   ├── 当前阅读 (Hero)
    │   │   ├── 阅读统计
    │   │   ├── 阅读连胜
    │   │   └── 最近阅读统计
    │   └── 功能补丁
    │       ├── 时钟模块：中文日期格式支持
    │       ├── 封面轮播模块：增加书籍简介显示
    │       ├── 封面轮播模块：增加排除路径功能
    │       ├── 模块副本功能
    │       ├── 快捷设置栏：双状态图标（长按进入设置）
    │       ├── 前光灯：滑块样式
    │       ├── 最近书籍模块：增加行数和排除路径功能
    │       ├── 新增屏保：主页屏保
    │       └── 新增屏保：阅读分析屏保
    ├── FileBrowserPlus
    │   └── 功能补丁
    │       └── 二维码增强
    ├── KOReader
    │   └── 功能补丁
    │       └── 擦除渐显翻页动画
    └── 关于
```

启用扩展模块并重启后，还需要在 SimpleUI 的“排列模块”中决定是否把模块
放到首页。所有导入模块自身的 `default_on` 也均为 `false`。

## 扩展模块

| 模块 | 功能 |
|---|---|
| 当前阅读 (With Pace) | 带有每日速度、页速和进度速度的当前阅读卡片 |
| 当前阅读 (Yanllsama Legacy) | 可配置网格、统计项目、字体和进度条的旧版阅读面板 |
| 当前阅读 (Hero) | 大型当前阅读卡片，包含封面、进度、简介和统计 |
| 阅读统计 | 年度阅读统计和月度图表 |
| 阅读连胜 | 当前及最佳连续阅读天数、周数 |
| 最近阅读统计 | 最近阅读书籍的进度、时间和统计卡片 |

模块启用后，其详细外观和内容设置位于：

```text
SimpleUI 首页 → 排列模块 → 对应模块
```

## SimpleUI 补丁

| 补丁 | 功能 |
|---|---|
| 前光灯：滑块样式 | 为前光灯和色温提供原版、细线、圆形三种滑块样式 |
| 快捷设置栏：双状态图标（长按进入设置） | 为已绑定且能读取状态的插件或系统快捷动作分别选择开启、关闭图标；执行后保持快捷设置栏开启并实时刷新状态图标（以 SimpleUI 2.5.0 为目标） |
| 最近书籍模块：增加行数和排除路径功能 | 最近书籍多行布局、行距、路径排除及忽略第一本书 |
| 封面轮播模块：增加排除路径功能 | 从封面书架最近书籍来源中排除指定路径 |
| 封面轮播模块：增加书籍简介显示 | 在封面书架上方或下方显示活动书籍简介 |
| 模块副本功能 | 允许同一模块生成多个副本并放在不同首页页面；2.5.0 同时识别自定义屏幕的独立布局 |
| 时钟模块：中文日期格式支持 | 将 SimpleUI 时钟日期改为“6月3日 周三”格式 |
| 新增屏保：主页屏保 | 将指定或随机 SimpleUI 首页显示为休眠屏 |
| 新增屏保：阅读分析屏保 | 将指定或随机阅读洞察页面显示为休眠屏 |

启用补丁并重启后，具体配置会进入其实际影响的位置，例如：

```text
SimpleUI → 快捷设置栏 → 滑块样式
SimpleUI → 排列模块 → 最近书籍
SimpleUI → 排列模块 → Cover Deck
设置 → 屏幕 → 休眠屏 → 壁纸
```

### 快捷设置栏双状态图标

启用“快捷设置栏：双状态图标（长按进入设置）”并重启 KOReader 后，在该补丁菜单项
上长按进入设置。设置页只列出已经在 SimpleUI 中绑定的插件或系统快捷动作：

```text
插件增强 → SimpleUI → 功能补丁
└── 快捷设置栏：双状态图标（长按进入设置）
    ├── 短按：启用或关闭补丁
    └── 长按：进入双状态图标设置
```

图片继续放在 SimpleUI 原有目录 `koreader/settings/simpleui/sui_icons/`，支持
SVG、PNG 和 Nerd Font 图标，文件名可以任意。开启图标与关闭图标均通过
SimpleUI 自带的 Kindle 图标选择器选取，不会覆盖 SimpleUI 原有的单图标。

当前状态识别规则：

- 插件动作必须已经绑定为 SimpleUI 自定义快捷动作。
- 插件提供 `isRunning()`、`isEnabled()`、`isActive()`、`isOpen()` 或主菜单
  `checked_func` 时可以设置双状态图标。
- 只有 `launch`、没有状态接口的插件会显示为“仅单图标”。
- 系统操作目前识别 FileBrowserPlus 服务开关、Wi-Fi、前光灯和夜间模式；
  其他没有可靠开关状态的系统操作继续使用单图标。
- 只有开启、关闭两张图标都已设置时才启用动态切换；缺少任意一张时自动
  使用 SimpleUI 原有单图标。
- 在 SimpleUI 快捷设置栏中点击已配置双图标的有状态动作后，快捷设置栏保持
  开启并立即重绘；关闭二维码等覆盖窗口后，快捷设置栏仍保留在原处。
- 在双状态图标设置页选取图片后，当前菜单项会立即显示新图片文件名，不需要
  返回上一级再重新进入。

## 其他补丁

### FileBrowserPlus 二维码增强

启用后，在 FileBrowserPlus 设置中增加：

```text
FileBrowserPlus 设置
├── 显示二维码
├── FileBrowserPlus 原有设置……
└── 启动时自动显示二维码
```

### 擦除渐显翻页动画

支持文字排版以及 PDF、DjVu、CBZ 等固定排版文档。启用补丁并重启后，
详细设置为：

```text
工具
└── 插件增强
    └── 翻页动画
        ├── 擦除渐显翻页动画
        └── 翻页动画设置
            ├── 刷新模式
            │   ├── UI 刷新
            │   └── Fast 刷新
            ├── 竖屏动画帧延迟
            ├── 横屏动画帧延迟
            └── 轻度全局刷新
```

该动画面向 KOReader 2026.07.1 及更新版本的 Linux 墨水屏设备，不支持
Android。

## 依赖

- KOReader。
- SimpleUI 2.1.1 或 2.5.0：扩展模块及 SimpleUI 补丁需要。
- Statistics：阅读统计、阅读洞察等功能需要其数据库。
- FileBrowserPlus 1.2.x：二维码增强需要。

没有安装某个目标插件时，相应组件的加载或启用错误会显示在菜单帮助文本中，
不会阻止其他组件继续加载。

## 安装

这是一个完整 KOReader 插件，不是 KOReader 用户补丁。请勿放入
`koreader/patches/`。

1. 将项目目录命名为 `Plugin_enhancements.koplugin`。
2. 将整个目录复制到 KOReader 的 `plugins/` 目录。
3. 完整重启 KOReader。

```text
koreader/
└── plugins/
    └── Plugin_enhancements.koplugin/
        ├── _meta.lua
        ├── main.lua
        ├── plugin_enhancements_i18n.lua
        ├── locale/
        │   └── zh_CN.po
        ├── modules/
        ├── patches/
        ├── utils/
        ├── README.md
        └── LICENSE
```

不要同时安装原始 `simpleui_ext.koplugin`，否则可能重复注册模块或重复包装
SimpleUI/KOReader 函数。

## 开发约定

扩展模块：

```text
modules/module_<id>.lua
```

补丁：

```text
patches/patch_<id>.lua
```

文件返回表中的 `id` 必须与文件名一致。主入口始终将未知组件的初始状态写为
`false`，不会根据组件自己的 `default_enabled` 自动开启。

## 许可与致谢

本项目按照 GNU Affero 通用公共许可证第 3 版发布，完整许可证见
`LICENSE`。

- [SimpleUI](https://github.com/doctorhetfield-cmd/simpleui.koplugin)
- `simpleui_ext.koplugin` 及其模块、补丁和翻译贡献者
- Bookshelf、koreader-user-patches、koreader-frankenpatches-public
- yanllsama 的增强当前阅读模块
- Swipe Animation 原作者及贡献者
