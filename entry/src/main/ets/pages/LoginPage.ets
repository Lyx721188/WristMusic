import { NmStore } from '../common/NmStore';
import { loginQrKey, loginQrCheck, loginCellphone, refreshAccount } from '../common/NmApi';

@Component
export struct LoginPage {
  @Consume('nav') pathStack: NavPathStack;
  @State mode: number = 0; // 0 二维码 1 手机号
  @State qrUrl: string = '';
  @State qrStatus: string = '';
  @State phone: string = '';
  @State pwd: string = '';
  @State busy: boolean = false;
  @State msg: string = '';
  private qrKey: string = '';
  private pollId: number = -1;
  private polling: boolean = false;
  private generation: number = 0;

  aboutToAppear(): void {
    if (NmStore.isLogged()) {
      refreshAccount().then((ok: boolean) => {
        if (ok) {
          AppStorage.setOrCreate('nmNeedHomeRefresh', true);
          this.pathStack.pop();
        }
      });
    }
  }

  aboutToDisappear(): void {
    this.stopPoll();
  }

  private stopPoll(): void {
    this.generation++;
    if (this.pollId >= 0) {
      clearInterval(this.pollId);
      this.pollId = -1;
    }
  }

  private async finalizeLogin(): Promise<void> {
    let ok = await refreshAccount();
    if (!ok) {
      // 803 后立刻查账号偶发未生效，稍候重试一次
      await new Promise<void>((resolve: () => void) => setTimeout(resolve, 1500));
      ok = await refreshAccount();
    }
    if (ok) {
      AppStorage.setOrCreate('nmNeedHomeRefresh', true);
      this.msg = '';
      this.pathStack.pop();
    } else {
      this.msg = '登录成功但获取账号失败，请重试';
    }
  }

  private async startQr(): Promise<void> {
    if (this.busy) {
      return;
    }
    this.stopPoll();
    const generation = this.generation;
    this.qrUrl = '';
    this.msg = '';
    this.busy = true;
    this.qrStatus = '获取二维码…';
    try {
      this.qrKey = await loginQrKey();
    } catch (e) {
      this.qrKey = '';
    }
    if (generation !== this.generation) {
      this.busy = false;
      return;
    }
    this.busy = false;
    if (this.qrKey === '') {
      this.qrStatus = '';
      this.msg = '二维码获取失败，请检查网络';
      return;
    }
    this.qrUrl = `https://music.163.com/login?codekey=${this.qrKey}`;
    this.qrStatus = '等待扫码…';
    this.pollId = setInterval(() => {
      this.pollOnce();
    }, 2000);
  }

  private async pollOnce(): Promise<void> {
    if (this.qrKey === '' || this.polling || this.mode !== 0) {
      return;
    }
    const key = this.qrKey;
    const generation = this.generation;
    this.polling = true;
    let code = 0;
    try {
      code = await loginQrCheck(key);
    } catch (e) {
      this.polling = false;
      return;
    }
    this.polling = false;
    if (generation !== this.generation || this.mode !== 0) {
      return;
    }
    if (code === 800) {
      this.stopPoll();
      this.qrStatus = '二维码已过期，请点击刷新';
    } else if (code === 802) {
      this.qrStatus = '已扫码，请在手机上确认';
    } else if (code === 803) {
      this.stopPoll();
      this.qrStatus = '登录成功';
      this.finalizeLogin();
    } else if (code === 801) {
      this.qrStatus = '等待扫码…';
    } else {
      this.qrStatus = '连接异常，正在重试…';
    }
  }

  private async doPhoneLogin(): Promise<void> {
    if (this.phone === '' || this.pwd === '') {
      this.msg = '请输入手机号和密码';
      return;
    }
    this.busy = true;
    this.msg = '登录中…';
    try {
      const res = await loginCellphone(this.phone, this.pwd, '86');
      const code = res.body['code'];
      if (typeof code === 'number' && (code as number) === 200) {
        this.msg = '';
        await this.finalizeLogin();
      } else {
        const m = res.body['message'];
        this.msg = typeof m === 'string' ? m as string : `登录失败(${res.status})`;
      }
    } catch (e) {
      this.msg = '网络错误，请重试';
    }
    this.busy = false;
  }

  build() {
    NavDestination() {
      Column({ space: 10 }) {
        // 模式切换
        Row({ space: 8 }) {
          Text('扫码登录')
            .fontSize(12)
            .fontColor(this.mode === 0 ? $r('app.color.nm_accent') : $r('app.color.nm_sub'))
            .padding({ left: 10, right: 10, top: 5, bottom: 5 })
            .borderRadius(10)
            .backgroundColor($r('app.color.nm_card'))
            .onClick(() => {
              this.mode = 0;
            })
          Text('手机号登录')
            .fontSize(12)
            .fontColor(this.mode === 1 ? $r('app.color.nm_accent') : $r('app.color.nm_sub'))
            .padding({ left: 10, right: 10, top: 5, bottom: 5 })
            .borderRadius(10)
            .backgroundColor($r('app.color.nm_card'))
            .onClick(() => {
              this.stopPoll();
              this.mode = 1;
            })
        }

        if (this.mode === 0) {
          if (this.qrUrl === '') {
            Column({ space: 10 }) {
              Text('用手机网易云音乐\n扫码登录')
                .fontSize(13)
                .fontColor($r('app.color.nm_text'))
                .textAlign(TextAlign.Center)
              Button(this.busy ? '获取中…' : '生成二维码')
                .fontSize(13)
                .backgroundColor($r('app.color.nm_accent'))
                .onClick(() => {
                  this.startQr();
                })
            }
          } else {
            QRCode(this.qrUrl)
              .width(150)
              .height(150)
              .color('#101014')
              .backgroundColor('#FFFFFF')
            Text(this.qrStatus)
              .fontSize(11)
              .fontColor($r('app.color.nm_sub'))
              .maxLines(1)
            if (this.qrStatus.includes('过期')) {
              Button('刷新二维码')
                .fontSize(12)
                .backgroundColor($r('app.color.nm_card'))
                .onClick(() => {
                  this.startQr();
                })
            }
          }
        } else {
          TextInput({ placeholder: '手机号', text: this.phone })
            .type(InputType.PhoneNumber)
            .fontSize(13)
            .height(38)
            .width('82%')
            .onChange((v: string) => {
              this.phone = v;
            })
          TextInput({ placeholder: '密码', text: this.pwd })
            .type(InputType.Password)
            .fontSize(13)
            .height(38)
            .width('82%')
            .onChange((v: string) => {
              this.pwd = v;
            })
          Button(this.busy ? '登录中…' : '登录')
            .fontSize(13)
            .backgroundColor($r('app.color.nm_accent'))
            .onClick(() => {
              this.doPhoneLogin();
            })
        }

        if (this.msg !== '') {
          Text(this.msg)
            .fontSize(11)
            .fontColor($r('app.color.nm_accent'))
            .maxLines(2)
            .textAlign(TextAlign.Center)
        }
      }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.Center)
    }
    .hideTitleBar(true)
    .backgroundColor($r('app.color.nm_bg'))
    .onBackPressed(() => {
      this.stopPoll();
      return false;
    })
  }
}
