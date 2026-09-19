/** 浮动"+"菜单（M5-4）：扫一扫 / 通用令牌；无障碍（US3）：FAB 动态朗读展开/收起，菜单项整行朗读，emoji 与遮罩不抢焦点 */
import { ResUtil } from '../common/ResUtil';

@Component
export struct AddFabMenu {
  @State expanded: boolean = false;
  onScan: () => void = () => {
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
        Column({ space: 8 }) {
          Row({ space: 8 }) {
            Text('📷')
              .fontSize(16)
              .accessibilityLevel('no')
            Text($r('app.string.add_scan'))
              .fontSize(14)
          }
          .padding({ left: 14, right: 14, top: 10, bottom: 10 })
          .backgroundBlurStyle(BlurStyle.Thin)
          .borderRadius(18)
          .shadow({ radius: 10, color: '#33000000', offsetY: 2 })
          .onClick(() => {
            this.expanded = false;
            this.onScan();
          })
          .accessibilityGroup(true)
          .accessibilityText(ResUtil.str($r('app.string.add_scan')))
          .accessibilityRole(AccessibilityRoleType.BUTTON)
          Row({ space: 8 }) {
            Text('🔑')
              .fontSize(16)
              .accessibilityLevel('no')
            Text($r('app.string.add_manual'))
              .fontSize(14)
          }
          .padding({ left: 14, right: 14, top: 10, bottom: 10 })
          .backgroundBlurStyle(BlurStyle.Thin)
          .borderRadius(18)
          .shadow({ radius: 10, color: '#33000000', offsetY: 2 })
          .onClick(() => {
            this.expanded = false;
            this.onManual();
          })
          .accessibilityGroup(true)
          .accessibilityText(ResUtil.str($r('app.string.add_manual')))
          .accessibilityRole(AccessibilityRoleType.BUTTON)
        }
        .alignItems(HorizontalAlign.End)
        .margin({ right: 12, bottom: 124 })
        .zIndex(2)
      }
      Button() {
        Text(this.expanded ? '×' : '+')
          .fontSize(30)
          .fontWeight(FontWeight.Normal)
          .fontColor($r('app.color.text_primary'))
      }
      .width(56)
      .height(56)
      .borderRadius(28)
      .backgroundColor(Color.Transparent)
      .backgroundBlurStyle(BlurStyle.Thin)
      .shadow({ radius: 12, color: '#44000000', offsetY: 3 })
      .margin({ right: 18, bottom: 74 })
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

  /** FAB 朗读文本：展开态读「收起菜单」、收起态读「添加令牌」 */
  private fabA11yRes(): Resource {
    return this.expanded ? $r('app.string.a11y_fab_close') : $r('app.string.a11y_fab_add');
  }
}