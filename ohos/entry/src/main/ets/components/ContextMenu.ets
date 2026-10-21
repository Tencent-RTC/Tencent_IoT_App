/**
 * ContextMenu —— 通用 Windows 风格右键菜单 / 更多操作菜单组件
 *
 * 设计要点：
 * 1. VerticalMoreButton：竖直三点按钮（⋮）。透明背景，依靠外层固定尺寸（如 36×36）作为
 *    点击热区，不带任何 backgroundColor / borderRadius 视觉填充。
 *    属性名注意：避开 ArkUI CustomComponent 自带的 size 属性（接收 SizeOptions），
 *    使用 btnSize（number）替代。
 *
 *    重要：菜单弹出必须由组件 *内部* 的原生节点通过 .bindMenu 触发；
 *    若在自定义组件根节点外部链式调用 .bindMenu 不会生效（自定义组件不直接代理 bindMenu）。
 *    因此本组件通过 @BuilderParam menu 把菜单构建器接收进来，并在 Stack 上挂 .bindMenu。
 *
 * 2. ContextMenuBuilder（全局 @Builder）：渲染 Windows 资源管理器风格菜单。
 *    使用 ArkUI 原生 Menu + MenuItem + MenuItemGroup：
 *      - Menu 自带卡片背景 / 圆角 / 阴影 / 弹层尺寸约束（避免文字溢出）；
 *      - MenuItem 自带 hover/press 高亮、固定行高、左右内边距；
 *      - MenuItemGroup 用于"段"，组与组之间会自动产生分隔线，正符合 Windows 右键菜单观感；
 *      - Menu 仅允许 MenuItem / MenuItemGroup / Option 作为直接子节点，
 *        因此分隔线不能用自定义 Row 实现，必须通过 MenuItemGroup 切组。
 *    支持的能力：图标（拼接到 content 文本前缀）、文本、危险红色、禁用、分组分隔线。
 *
 * 使用示例（在 @Component 内）：
 * @Builder
*   private menuBuilder() {
 *     ContextMenuBuilder([
 *       { text: '修改名称', icon: '✎', onAction: () => this.rename() },
 *       { separator: true },
 *       { text: '删除', icon: '🗑', color: '#FF4444', onAction: () => this.delete() },
 *     ])
 *   }
 *
 *   VerticalMoreButton({ color: '#006EFF' }) {
 *     this.menuBuilder()
 *   }
 */

// ---------- 数据结构 ----------

/**
 * 单个菜单项配置
 * - separator: 标记为分割线（其余字段忽略）
 * - disabled : 禁用态（灰显且不响应点击）
 */
export interface ContextMenuItem {
  text?: string
  icon?: string // 左侧符号 / emoji（可选）
  color?: string // 文本颜色，默认 #15161A；危险项常用 #FF4444
  disabled?: boolean
  separator?: boolean // 是否为分组分隔（之前/之后菜单项被切分到不同分组）
  onAction?: () => void // 点击回调
}

// ---------- 竖直三点按钮（透明背景，热区由外层尺寸控制） ----------

/**
 * VerticalMoreButton —— 竖直三点（⋮）按钮
 *
 * - 视觉：仅文字 ⋮，无背景色、无圆角填充。
 * - 热区：由 btnSize 参数控制（默认 36），整个 Stack 都可点击。
 * - 颜色：默认 #006EFF（与原"⋯"按钮一致），可通过 color 覆盖。
 * - 菜单：通过 @BuilderParam menu 传入，在内部 Stack 上直接 .bindMenu 触发。
 *
 * 注意：CustomComponent 的内置属性 size 接收 SizeOptions，不能再被同名 number 字段覆盖；
 * 因此对外暴露的属性名是 btnSize / textSize。
 */
@Component
export struct VerticalMoreButton {
  btnSize: number = 40
  color: string = '#006EFF'
  textSize: number = 24
  /** 菜单内容（必填，由父组件 @Builder 提供） */
  @BuilderParam menu: () => void = this.defaultMenu

  @Builder
  private defaultMenu() {
    // 占位：调用方未提供 menu 时不弹任何内容
  }

  build() {
    Stack() {
      Text('⋮')
        .fontSize(this.textSize)
        .fontColor(this.color)
        .fontWeight(FontWeight.Normal)
    }
    .width(this.btnSize)
    .height(this.btnSize)
    // 不设置 backgroundColor / borderRadius，保持透明无填充
    // bindMenu 必须挂在原生 Stack 上（自定义组件根节点上的 bindMenu 不生效）
    .bindMenu(this.menu)
  }
}

// ---------- 工具：将一维 items 切分为按 separator 分组的二维数组 ----------

/**
 * 把扁平的菜单项数组按 separator 切组：
 * 输入：[A, B, {separator:true}, C, {separator:true}, D]
 * 输出：[[A, B], [C], [D]]
 *
 * 这样可在 Menu 中用 MenuItemGroup 渲染每一组，组间天然形成分隔线，
 * 同时严格满足 Menu 仅接受 MenuItem/MenuItemGroup 作为直接子节点的约束。
 */
function splitItemsBySeparator(items: ContextMenuItem[]): ContextMenuItem[][] {
  const groups: ContextMenuItem[][] = []
  let current: ContextMenuItem[] = []
  for (const it of items) {
    if (it.separator) {
      if (current.length > 0) {
        groups.push(current)
        current = []
      }
    } else {
      current.push(it)
    }
  }
  if (current.length > 0) {
    groups.push(current)
  }
  return groups
}

// ---------- Windows 风格菜单内容 Builder（基于原生 Menu / MenuItemGroup / MenuItem） ----------

/**
 * 全局 @Builder：渲染 Windows 风格菜单。
 *
 * 实现说明：
 * - 用 splitItemsBySeparator 将一维 items 切成多个分组；
 * - 每个分组用 MenuItemGroup 包裹（组间自动分隔线），组内放 MenuItem；
 * - 图标拼接到 content 前缀，避开 startIcon 仅接受 ResourceStr 的限制；
 * - 危险红色 / 禁用灰显通过 contentFontColor 控制。
 */
@Builder
export function ContextMenuBuilder(items: ContextMenuItem[]) {
  Menu() {
    ForEach(splitItemsBySeparator(items), (group: ContextMenuItem[], gIndex: number) => {
      MenuItemGroup() {
        ForEach(group, (item: ContextMenuItem, index: number) => {
          MenuItem({
            content: (item.icon && item.icon.length > 0)
              ? `${item.icon}  ${item.text || ''}`
              : (item.text || '')
          })
            .enabled(!item.disabled)
            .contentFont({ size: 14 })
            .contentFontColor(
              item.disabled ? '#C9CDD4' : (item.color || '#15161A')
            )
            // MenuItem 默认行高约 48vp，对"⋯ 菜单"过高；压到 35vp 更接近 Windows 右键菜单。
            .height(35)
            .onClick(() => {
              if (item.disabled) {
                return
              }
              if (item.onAction) {
                item.onAction()
              }
            })
        }, (item: ContextMenuItem, index: number) => `${gIndex}-${index}-${item.text || ''}`)
      }
    }, (group: ContextMenuItem[], gIndex: number) => `g-${gIndex}-${group.length}`)
  }
  // Menu 自带白底 / 圆角 / 阴影 / 自适应宽度（根据文字内容自动撑开）
}
