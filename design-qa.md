# Workspace 文件管理 Design QA

- source visual truth path: `/Users/heart/Desktop/Screenshot 2026-10-22 at 18.34.14.png`
- implementation screenshot path: `/Users/heart/Documents/workspace/githubs/workspace/Courses/Forma/.agents/test/workspace-file-menu.png`
- viewport: source 为 684 × 1238 px 的侧栏局部；实现为 1920 × 1280 px 的完整 macOS 窗口
- density normalization: 两者均按屏幕像素查看；由于源图是窄幅局部，重点对齐文件树和菜单区域，不比较窗口总宽度
- state: 浅色模式，工作空间文件列表可见，图文件操作菜单展开

**Findings**

- 无 P0/P1/P2 问题。实现保留 Forma 的橙色强调色与宽屏资料库布局，同时覆盖参考图的核心文件菜单能力。
- 字体与排版：使用系统 SF 字体；菜单层级、字重和行高符合原生 macOS 菜单，中文没有截断。
- 间距与布局：侧栏、列表和菜单留白稳定；菜单未超出窗口，操作分组清楚。
- 颜色与视觉令牌：继续使用 `FormaTheme.accent`，选中、收藏及危险操作使用语义色。
- 图像与图标：全部使用 SF Symbols 和现有 Forma 图形标识，无模糊位图或占位资源。
- 文案：打开、重命名、创建副本、收藏、Finder 定位、移动和回收箱均与参考交互一致，并已提供中英文。

**Focused Region Comparison**

- 重点比较源图右键菜单与实现菜单。实现菜单已显示“打开 / 重命名 / 创建副本 / 添加到收藏 / 在 Finder 中显示 / 移动到 / 移入回收箱”。
- 文件层级继续沿用 Forma 已有拖拽层级；拥有子项的图文件显示为文件夹样式并显示直接子项数量。

**Comparison History**

- 初始实现缺少创建副本、收藏和 Finder 定位。
- 本轮补齐上述操作，增加收藏快捷区、层级文件夹视觉及独立多 Sheet 副本逻辑。
- 修订后通过真实 Release 应用截图复核，未发现需要继续修复的 P0/P1/P2 问题。

**Implementation Checklist**

- [x] 工作空间在 Finder 中显示
- [x] 图文件创建独立副本
- [x] 添加到收藏／从收藏移除
- [x] 图文件在 Finder 中显示
- [x] 多 Sheet 副本保持页面数量并更新页面 ID
- [x] 中英文文案与原生菜单状态

**Follow-up Polish**

- P3：未来可在引入独立 Folder 领域模型后，为目录增加折叠状态和文件夹级右键菜单。

final result: passed
