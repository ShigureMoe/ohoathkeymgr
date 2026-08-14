/** 环形倒计时（TOTP）：圆环 + 中央剩余秒数 */
@Component
export struct CountdownArc {
  @Prop remaining: number = 30;
  @Prop total: number = 30;
  @Prop stale: boolean = false;

  build() {
    Stack({ alignContent: Alignment.Center }) {
      Progress({
        value: this.stale ? 0 : this.remaining,
        total: this.total,
        type: ProgressType.Ring
      })
        .width(36)
        .height(36)
        .color(this.stale ? $r('app.color.text_secondary') : $r('app.color.accent'))
        .backgroundColor($r('app.color.ring_track'))
        .style({ strokeWidth: 3 })
      Text(this.stale ? '--' : String(this.remaining))
        .fontSize(11)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.stale ? $r('app.color.text_secondary') : $r('app.color.accent'))
    }
    .width(44)
    .height(44)
  }
}