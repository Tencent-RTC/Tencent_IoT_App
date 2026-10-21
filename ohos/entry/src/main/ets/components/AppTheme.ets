/**
 * AppTheme —— 全局视觉主题
 *
 * ArkTS 严格模式说明：
 * @Extend 不支持跨文件 export。本文件统一使用 AttributeModifier 方案。
 *   所有 export 均可跨文件 import，使用方仍可链式覆盖。
 *
 * 导出清单
 * ── 常量 ──
 *   AppColor / AppFontSize / AppRadius / AppHeight / AppGap / AppShadow
 * ── 按钮 Modifier ──
 *   PrimaryButton / PrimaryHeroButton / DangerButton / SecondaryButton
 *   DangerOutlineButton / CancelButton
 * ── 文字 Modifier ──
 *   PageTitleText / DialogTitleText / SectionTitleText
 *   BodyText / SecondaryText / CaptionText / DangerText / LinkText
 * ── 输入框 Modifier ──
 *   StandardInputField / CompactInputField / DialogInputField / DialogTextAreaField
 * ── 通用组件 ──
 *   DragHandle / MaskOverlay / DividerLine / NavBar
 */

// ============================================================================
// 一、颜色常量
// ============================================================================

export class AppColor {
  // —— 文本 ——
  static readonly TextPrimary: string = '#15161A'
  static readonly TextSecondary: string = '#9DA3B0'
  static readonly TextTertiary: string = '#C9CDD4'
  static readonly TextOnPrimary: string = '#FFFFFF'
  static readonly TextOnDanger: string = '#FFFFFF'
  static readonly TextCancel: string = '#6B7280'
  static readonly TextPlaceholder: string = '#B0B7C3'
  static readonly TextLink: string = '#1890ff'
  // —— 品牌色 ——
  static readonly Brand: string = '#006EFF'
  static readonly BrandStart: string = '#1A73E8'
  static readonly BrandEnd: string = '#006EFF'
  // —— 危险色 ——
  static readonly Danger: string = '#FF4444'
  static readonly DangerStart: string = '#FF6B6B'
  static readonly DangerEnd: string = '#FF4444'
  // —— 成功/在线 ——
  static readonly Success: string = '#52c41a'
  // —— 背景 ——
  static readonly BgPage: string = '#F2F4F8'
  static readonly BgCard: string = '#FFFFFF'
  static readonly BgCancel: string = '#F2F3F5'
  static readonly BgInput: string = '#F7F8FA'
  static readonly BgMask: string = 'rgba(0,0,0,0.5)'
  static readonly BgGray: string = '#f5f5f5'
  // —— 分隔线 / 边框 ——
  static readonly Divider: string = '#F0F0F0'
  static readonly DividerDashed: string = '#d9d9d9'
  static readonly DragIndicator: string = '#E0E4EC'
  static readonly BorderInput: string = '#E7E8EB'
}

// ============================================================================
// 二、字号常量
// ============================================================================

export class AppFontSize {
  static readonly Title: number = 20
  static readonly H1: number = 19
  static readonly H2: number = 17
  static readonly H3: number = 16
  static readonly Input: number = 15
  static readonly Body: number = 14
  static readonly Caption: number = 12
  static readonly Small: number = 11
}

// ============================================================================
// 三、圆角常量
// ============================================================================

export class AppRadius {
  static readonly Card: number = 14
  static readonly Button: number = 14
  static readonly ButtonSmall: number = 12
  static readonly Input: number = 12
  static readonly Tag: number = 8
  static readonly Sheet: number = 24
  static readonly Pill: number = 9999
}

// ============================================================================
// 四、高度常量
// ============================================================================

export class AppHeight {
  static readonly ButtonHero: number = 54
  static readonly Button: number = 46
  static readonly ButtonRegular: number = 48
  static readonly ButtonCompact: number = 44
  static readonly ButtonInline: number = 32
  static readonly ButtonMini: number = 28
  static readonly Input: number = 54
  static readonly InputCompact: number = 44
  static readonly NavBar: number = 56
}

// ============================================================================
// 五、间距常量
// ============================================================================

export class AppGap {
  static readonly XS: number = 4
  static readonly S: number = 8
  static readonly M: number = 12
  static readonly L: number = 16
  static readonly XL: number = 20
  static readonly XXL: number = 24
  static readonly XXXL: number = 32
}

// ============================================================================
// 六、阴影常量
// ============================================================================

export class AppShadow {
  // Shadow constants — use as .shadow({ radius: 4, color: '...', offsetX: 0, offsetY: 2 })
  static readonly Card_Radius: number = 4
  static readonly Card_Color: string = 'rgba(0,0,0,0.08)'
  static readonly NavBar_Radius: number = 4
  static readonly NavBar_Color: string = 'rgba(0,0,0,0.1)'
}

// ============================================================================
// 七、渐变字面量
// ============================================================================

const BRAND_GRADIENT_COLORS: Array<[ResourceColor, number]> = [
  [AppColor.BrandStart, 0],
  [AppColor.BrandEnd, 1]
]

const DANGER_GRADIENT_COLORS: Array<[ResourceColor, number]> = [
  [AppColor.DangerStart, 0],
  [AppColor.DangerEnd, 1]
]

// ============================================================================
// 八、按钮 Modifier
// ============================================================================

class PrimaryButtonModifier implements AttributeModifier<ButtonAttribute> {
  applyNormalAttribute(instance: ButtonAttribute): void {
    instance
      .width('100%')
      .height(AppHeight.Button)
      .fontSize(AppFontSize.H3)
      .fontColor(AppColor.TextOnPrimary)
      .fontWeight(FontWeight.Normal)
      .borderRadius(AppRadius.Button)
      .backgroundColor(Color.Transparent)
      .linearGradient({ angle: 135, colors: BRAND_GRADIENT_COLORS })
  }
}

export const PrimaryButton: AttributeModifier<ButtonAttribute> = new PrimaryButtonModifier()

class PrimaryHeroButtonModifier implements AttributeModifier<ButtonAttribute> {
  applyNormalAttribute(instance: ButtonAttribute): void {
    instance
      .width('100%')
      .height(AppHeight.ButtonHero)
      .fontSize(AppFontSize.H3)
      .fontColor(AppColor.TextOnPrimary)
      .fontWeight(FontWeight.Normal)
      .borderRadius(AppRadius.Button)
      .backgroundColor(Color.Transparent)
      .linearGradient({ angle: 135, colors: BRAND_GRADIENT_COLORS })
  }
}

export const PrimaryHeroButton: AttributeModifier<ButtonAttribute> = new PrimaryHeroButtonModifier()

class DangerButtonModifier implements AttributeModifier<ButtonAttribute> {
  applyNormalAttribute(instance: ButtonAttribute): void {
    instance
      .width('100%')
      .height(AppHeight.Button)
      .fontSize(AppFontSize.H3)
      .fontColor(AppColor.TextOnDanger)
      .fontWeight(FontWeight.Normal)
      .borderRadius(AppRadius.Button)
      .backgroundColor(Color.Transparent)
      .linearGradient({ angle: 135, colors: DANGER_GRADIENT_COLORS })
  }
}

export const DangerButton: AttributeModifier<ButtonAttribute> = new DangerButtonModifier()

class SecondaryButtonModifier implements AttributeModifier<ButtonAttribute> {
  applyNormalAttribute(instance: ButtonAttribute): void {
    instance
      .height(AppHeight.ButtonRegular)
      .fontSize(AppFontSize.Body)
      .fontColor(AppColor.Brand)
      .fontWeight(FontWeight.Normal)
      .backgroundColor(Color.Transparent)
      .border({ width: 1.5, color: AppColor.Brand, radius: AppRadius.Button })
  }
}

export const SecondaryButton: AttributeModifier<ButtonAttribute> = new SecondaryButtonModifier()

class DangerOutlineButtonModifier implements AttributeModifier<ButtonAttribute> {
  applyNormalAttribute(instance: ButtonAttribute): void {
    instance
      .height(AppHeight.ButtonInline)
      .fontSize(AppFontSize.Caption)
      .fontColor(AppColor.Danger)
      .fontWeight(FontWeight.Normal)
      .backgroundColor(Color.Transparent)
      .border({ width: 1.5, color: AppColor.Danger, radius: AppRadius.ButtonSmall })
  }
}

export const DangerOutlineButton: AttributeModifier<ButtonAttribute> = new DangerOutlineButtonModifier()

class CancelButtonModifier implements AttributeModifier<ButtonAttribute> {
  applyNormalAttribute(instance: ButtonAttribute): void {
    instance
      .width('100%')
      .height(AppHeight.Button)
      .fontSize(AppFontSize.H3)
      .fontColor(AppColor.TextCancel)
      .backgroundColor(AppColor.BgCancel)
      .borderRadius(AppRadius.Button)
  }
}

export const CancelButton: AttributeModifier<ButtonAttribute> = new CancelButtonModifier()

// ============================================================================
// 九、文字 Modifier
// ============================================================================

class PageTitleTextModifier implements AttributeModifier<TextAttribute> {
  applyNormalAttribute(instance: TextAttribute): void {
    instance
      .fontSize(AppFontSize.Title)
      .fontWeight(FontWeight.Normal)
      .fontColor(AppColor.TextPrimary)
  }
}

export const PageTitleText: AttributeModifier<TextAttribute> = new PageTitleTextModifier()

class DialogTitleTextModifier implements AttributeModifier<TextAttribute> {
  applyNormalAttribute(instance: TextAttribute): void {
    instance
      .fontSize(AppFontSize.H2)
      .fontWeight(FontWeight.Normal)
      .fontColor(AppColor.TextPrimary)
  }
}

export const DialogTitleText: AttributeModifier<TextAttribute> = new DialogTitleTextModifier()

class SectionTitleTextModifier implements AttributeModifier<TextAttribute> {
  applyNormalAttribute(instance: TextAttribute): void {
    instance
      .fontSize(AppFontSize.H2)
      .fontWeight(FontWeight.Normal)
      .fontColor(AppColor.TextPrimary)
  }
}

export const SectionTitleText: AttributeModifier<TextAttribute> = new SectionTitleTextModifier()

class BodyTextModifier implements AttributeModifier<TextAttribute> {
  applyNormalAttribute(instance: TextAttribute): void {
    instance
      .fontSize(AppFontSize.Body)
      .fontColor(AppColor.TextPrimary)
  }
}

export const BodyText: AttributeModifier<TextAttribute> = new BodyTextModifier()

class SecondaryTextModifier implements AttributeModifier<TextAttribute> {
  applyNormalAttribute(instance: TextAttribute): void {
    instance
      .fontSize(AppFontSize.Body)
      .fontColor(AppColor.TextSecondary)
      .lineHeight(22)
  }
}

export const SecondaryText: AttributeModifier<TextAttribute> = new SecondaryTextModifier()

class CaptionTextModifier implements AttributeModifier<TextAttribute> {
  applyNormalAttribute(instance: TextAttribute): void {
    instance
      .fontSize(AppFontSize.Caption)
      .fontColor(AppColor.TextSecondary)
  }
}

export const CaptionText: AttributeModifier<TextAttribute> = new CaptionTextModifier()

class DangerTextModifier implements AttributeModifier<TextAttribute> {
  applyNormalAttribute(instance: TextAttribute): void {
    instance
      .fontSize(AppFontSize.Body)
      .fontColor(AppColor.Danger)
      .fontWeight(FontWeight.Normal)
  }
}

export const DangerText: AttributeModifier<TextAttribute> = new DangerTextModifier()

class LinkTextModifier implements AttributeModifier<TextAttribute> {
  applyNormalAttribute(instance: TextAttribute): void {
    instance
      .fontSize(AppFontSize.Body)
      .fontColor(AppColor.Brand)
      .fontWeight(FontWeight.Normal)
  }
}

export const LinkText: AttributeModifier<TextAttribute> = new LinkTextModifier()

// ============================================================================
// 十、输入框 Modifier
// ============================================================================

/**
 * 标准输入框 —— 抽屉表单内 TextInput
 * 48px 高 / 15号字 / 浅灰底带边框 / 圆角 12 / 内边距 18
 */
class StandardInputFieldModifier implements AttributeModifier<TextInputAttribute> {
  applyNormalAttribute(instance: TextInputAttribute): void {
    instance
      .width('100%')
      .height(AppHeight.ButtonRegular)
      .fontSize(AppFontSize.Input)
      .fontColor(AppColor.TextPrimary)
      .placeholderColor(AppColor.TextPlaceholder)
      .backgroundColor(AppColor.BgInput)
      .borderRadius(AppRadius.Input)
      .border({ width: 1, color: AppColor.BorderInput, radius: AppRadius.Input })
      .padding({ left: 18, right: 18 })
  }
}

export const StandardInputField: AttributeModifier<TextInputAttribute> = new StandardInputFieldModifier()

/**
 * 紧凑输入框 —— 设置页 / 卡片内小输入框
 * 44px 高 / 15号字 / 圆角 8
 */
class CompactInputFieldModifier implements AttributeModifier<TextInputAttribute> {
  applyNormalAttribute(instance: TextInputAttribute): void {
    instance
      .width('100%')
      .height(AppHeight.InputCompact)
      .fontSize(AppFontSize.Input)
      .fontColor(AppColor.TextPrimary)
      .backgroundColor(AppColor.BgGray)
      .borderRadius(AppRadius.Tag)
  }
}

export const CompactInputField: AttributeModifier<TextInputAttribute> = new CompactInputFieldModifier()

/**
 * 弹窗表单输入框 —— "修改别名"风格 TextInput
 * 48px 高 / 16号字 / 灰底带边框 / 圆角 12 / 内边距 14
 */
class DialogInputFieldModifier implements AttributeModifier<TextInputAttribute> {
  applyNormalAttribute(instance: TextInputAttribute): void {
    instance
      .height(AppHeight.ButtonRegular)
      .fontSize(AppFontSize.H3)
      .backgroundColor(AppColor.BgGray)
      .borderRadius(AppRadius.Input)
      .border({ width: 1, color: AppColor.BorderInput, radius: AppRadius.Input })
      .padding({ left: 14, right: 14 })
  }
}

export const DialogInputField: AttributeModifier<TextInputAttribute> = new DialogInputFieldModifier()

/**
 * 弹窗表单文本域 —— 与 DialogInputField 同风格，适配 TextArea
 */
class DialogTextAreaFieldModifier implements AttributeModifier<TextAreaAttribute> {
  applyNormalAttribute(instance: TextAreaAttribute): void {
    instance
      .height(AppHeight.ButtonRegular)
      .fontSize(AppFontSize.H3)
      .backgroundColor(AppColor.BgGray)
      .borderRadius(AppRadius.Input)
      .border({ width: 1, color: AppColor.BorderInput, radius: AppRadius.Input })
      .padding({ left: 14, right: 14, top: 12 })
  }
}

export const DialogTextAreaField: AttributeModifier<TextAreaAttribute> = new DialogTextAreaFieldModifier()

// ============================================================================
// 十一、通用组件
// ============================================================================

/**
 * 抽屉顶部的拖动指示条（36×4 灰色圆角小块）
 */
@Component
export struct DragHandle {
  build() {
    Column()
      .width(36)
      .height(4)
      .backgroundColor(AppColor.DragIndicator)
      .margin({ top: 14 })
      .borderRadius(2)
  }
}

/**
 * 弹窗蒙层 —— 全屏半透明黑色遮罩
 *
 * @param onClick 点击蒙层时的回调（通常用于关闭弹窗）
 * @param zIndex  层级，默认 100
 *
 * 使用：MaskOverlay({ onMaskClick: () => this.dismissDialog() })
 * 在 Stack 中放最上层（在弹窗内容之后）
 */
@Component
export struct MaskOverlay {
  onMaskClick: () => void = () => {
  }
  maskZIndex: number = 100

  build() {
    Column()
      .width('100%')
      .height('100%')
      .backgroundColor(AppColor.BgMask)
      .onClick(() => this.onMaskClick())
      .transition(TransitionEffect.opacity(0).animation({ duration: 200, curve: Curve.EaseOut }))
  }
}

/**
 * 标准分割线 —— 颜色 #F0F0F0
 *
 * @param margin 外边距（可选，默认无）
 *
 * 使用：DividerLine() 或 DividerLine({ dividerMargin: { left: 16, right: 16 } })
 */
@Component
export struct DividerLine {
  dividerMargin: Margin = {}

  build() {
    Divider()
      .color(AppColor.Divider)
      .margin(this.dividerMargin)
  }
}

/**
 * 通用顶部导航栏（白色背景）
 *
 * @param title    标题文字
 * @param onBack   返回点击回调
 * @param rightBuilder 右侧自定义内容（可选）
 *
 * 使用：
 *   NavBar({ title: '设备设置', onBack: () => router.back() })
 *   NavBar({ title: '消息', onBack: () => this.goBack() }) { Button('清空') }
 */
@Component
export struct NavBar {
  title: string = ''
  onBack: () => void = () => {
  }
  @BuilderParam right: () => void = this.emptyRight

  @Builder
  emptyRight() {
    Column().width(40)
  }

  build() {
    Row() {
      Button() {
        Text('←').fontSize(22).fontColor(AppColor.TextPrimary)
      }
      .width(40).height(40)
      .backgroundColor(Color.Transparent)
      .onClick(() => this.onBack())

      Text(this.title)
        .attributeModifier(PageTitleText)
        .layoutWeight(1).textAlign(TextAlign.Center)

      this.right()
    }
    .width('100%')
    .height(AppHeight.NavBar)
    .padding({ left: 16, right: 16 })
    .backgroundColor(AppColor.BgCard)
    .shadow({
      radius: 4,
      color: 'rgba(0,0,0,0.1)',
      offsetX: 0,
      offsetY: 2
    })
  }
}

/**
 * 渐变顶部导航栏 —— 蓝色渐变背景 + 白色文字 + 状态栏自适应
 *
 * @param title    标题文字
 * @param onBack   返回点击回调
 * @param right    右侧自定义内容（可选，默认 44×44 空占位）
 *
 * 使用：
 *   GradientNavBar({ title: '设备设置', onBack: () => router.back() })
 *   GradientNavBar({ title: '家庭管理', onBack: () => this.goBack() }) { this.moreMenu() }
 */
@Component
export struct GradientNavBar {
  // @Prop 确保父组件动态变更的标题（如家庭重命名后）能实时同步，
  // 避免仅在组件初始化时接收一次值（普通成员变量的局限）
  @Prop title: string = ''
  onBack: () => void = () => {
  }
  @StorageProp('statusBarHeight') statusBarHeight: number = 44
  @BuilderParam right: () => void = this.emptyRight

  @Builder
  emptyRight() {
    Column().width(44).height(44)
  }

  build() {
    Column() {
      Row() {
        Button() {
          // 保留原始 ← 字体的箭头尖，仅通过裁剪缩短横线 1/5
          Stack({ alignContent: Alignment.Start }) {
            Text('←')
              .fontSize(22)
              .fontColor(AppColor.TextOnPrimary)
          }
          .width(17)
          .height(22)
          .clip(true)
        }
        .width(44).height(44)
        .backgroundColor(Color.Transparent)
        .onClick(() => this.onBack())

        Text(this.title)
          .fontSize(18)
          .fontWeight(FontWeight.Normal)
          .fontColor(AppColor.TextOnPrimary)
          .layoutWeight(1)
          .textAlign(TextAlign.Center)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        this.right()
      }
      .width('100%').height(48)
      .padding({ left: 8, right: 8 })
      .margin({ top: px2vp(this.statusBarHeight) })
    }
    .width('100%')
    .linearGradient({ angle: 180, colors: [[AppColor.BrandStart, 0], [AppColor.BrandEnd, 1]] })
  }
}
