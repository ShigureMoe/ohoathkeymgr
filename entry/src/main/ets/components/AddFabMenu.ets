/** 浮动"+"菜单（M5-4）：扫一扫 / 通用令牌 */
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
        Column({ space: 8 }) {
          Row({ space: 8 }) {
            Text('📷')
              .fontSize(16)
            Text('扫描二维码')
              .fontSize(14)
          }
          .padding({ left: 14, right: 14, top: 10, bottom: 10 })
          .backgroundColor($r('app.color.surface_sheet'))
          .borderRadius(18)
          .shadow({ radius: 10, color: '#33000000', offsetY: 2 })
          .onClick(() => {
            this.expanded = false;
            this.onScan();
          })
          Row({ space: 8 }) {
            Text('🔑')
              .fontSize(16)
            Text('通用令牌')
              .fontSize(14)
          }
          .padding({ left: 14, right: 14, top: 10, bottom: 10 })
          .backgroundColor($r('app.color.surface_sheet'))
          .borderRadius(18)
          .shadow({ radius: 10, color: '#33000000', offsetY: 2 })
          .onClick(() => {
            this.expanded = false;
            this.onManual();
          })
        }
        .alignItems(HorizontalAlign.End)
        .margin({ right: 12, bottom: 124 })
        .zIndex(2)
      }
      Button() {
        Text(this.expanded ? '×' : '+')
          .fontSize(30)
          .fontWeight(FontWeight.Normal)
          .fontColor($r('app.color.surface_sheet'))
      }
      .width(56)
      .height(56)
      .borderRadius(28)
      .backgroundColor($r('app.color.accent'))
      .shadow({ radius: 12, color: '#44000000', offsetY: 3 })
      .margin({ right: 18, bottom: 74 })
      .zIndex(3)
      .onClick(() => {
        this.expanded = !this.expanded;
      })
    }
    .width('100%')
    .height('100%')
    .hitTestBehavior(this.expanded ? HitTestMode.Default : HitTestMode.Transparent)
  }
}