/** 浮动"+"菜单（fab-menu-ux）：等宽菜单项（@Builder 参数化同构）+ 自绘 SVG 线性图标（fillColor 主题色，与全站 icon_* 体系同源）+ 右缘与 FAB 对齐；扫一扫 / 从链接添加 / 通用令牌 */
import { ResUtil } from '../common/ResUtil';

/** 菜单项统一宽度（等宽保证；按中英最长文案校准，176 容纳 "Add from URI" 不截断） */
const MENU_ITEM_WIDTH = 176;
/** 菜单项统一高度 */
const MENU_ITEM_HEIGHT = 44;
/** 菜单项垂直间距 */
const MENU_ITEM_SPACE = 12;
/** FAB 尺寸与位置（保持现状不动） */
const FAB_SIZE = 56;
const FAB_RIGHT = 18;
const FAB_BOTTOM = 74;
/** 菜单容器 bottom = FAB bottom(74) + FAB 高(56) + 菜单-FAB 间距(16) */
const MENU_BOTTOM = FAB_BOTTOM + FAB_SIZE + 16;

@Component
export struct AddFabMenu {
  @State expanded: boolean = false;
  onScan: () => void = () => {
  };
  onUri: () => void = () => {
  };
  onManual: () => void = () => {
  };

  build() {
    Stack({ alignContent: Alignment.BottomEnd }) {
      if (this.expanded) {
        // 遮罩先声明（z 序在下），菜单后声明（z 序在上）——避免遮罩拦截菜单点击
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor($r('app.color.mask'))
          .onClick(() => {
            this.expanded = false;
          })
          .accessibilityLevel('no')
        Column({ space: MENU_ITEM_SPACE }) {
          this.menuItem($r('app.string.add_scan'), $r('app.media.icon_scan'), this.onScan)
          this.menuItem($r('app.string.add_by_uri_title'), $r('app.media.icon_link'), this.onUri)
          this.menuItem($r('app.string.add_manual'), $r('app.media.key_horizontal'), this.onManual)
        }
        .alignItems(HorizontalAlign.End)
        .margin({ right: FAB_RIGHT, bottom: MENU_BOTTOM })
        .zIndex(2)
      }
      Button() {
        Image(this.expanded ? $r('app.media.icon_xmark') : $r('app.media.icon_plus'))
          .width(22)
          .height(22)
          .fillColor($r('app.color.text_primary'))
          .accessibilityLevel('no')
      }
      .width(FAB_SIZE)
      .height(FAB_SIZE)
      .borderRadius(28)
      .backgroundColor(Color.Transparent)
      .backgroundBlurStyle(BlurStyle.Thin)
      .shadow({ radius: 12, color: '#44000000', offsetY: 3 })
      .margin({ right: FAB_RIGHT, bottom: FAB_BOTTOM })
      .zIndex(3)
      .onClick(() => {
        this.expanded = !this.expanded;
      })
      .accessibilityText(ResUtil.str(this.fabA11yRes()))
    }
    .width('100%')
    .height('100%')
    .hitTestBehavior(this.expanded ? HitTestMode.Default : HitTestMode.Transparent)
  }

  /** 等宽菜单项：SVG 线性图标（fillColor 主题色）+ 文案，固定宽高/毛玻璃/阴影，点击先收起再回调；整行朗读 + BUTTON 角色 */
  @Builder
  menuItem(label: Resource, iconRes: Resource, onTap: () => void) {
    Row({ space: 10 }) {
      Image(iconRes)
        .width(20)
        .height(20)
        .fillColor($r('app.color.text_primary'))
        .accessibilityLevel('no')
      Text(label)
        .fontSize(14)
    }
    .width(MENU_ITEM_WIDTH)
    .height(MENU_ITEM_HEIGHT)
    .padding({ left: 14, right: 14 })
    .backgroundBlurStyle(BlurStyle.Thin)
    .borderRadius(MENU_ITEM_HEIGHT / 2)
    .shadow({ radius: 10, color: '#33000000', offsetY: 2 })
    .onClick(() => {
      this.expanded = false;
      onTap();
    })
    .accessibilityGroup(true)
    .accessibilityText(ResUtil.str(label))
    .accessibilityRole(AccessibilityRoleType.BUTTON)
  }

  /** FAB 朗读文本：展开态读「收起菜单」、收起态读「添加令牌」 */
  private fabA11yRes(): Resource {
    return this.expanded ? $r('app.string.a11y_fab_close') : $r('app.string.a11y_fab_add');
  }
}
