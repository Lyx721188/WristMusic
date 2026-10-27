// 主页 —— 仿华为音乐手表版：首页标题+圆形搜索钮、胶囊播放条、封面横滑卡、功能行
import { NmStore } from '../common/NmStore';
import { NmPlayer } from '../common/NmPlayer';
import { refreshAccount, userPlaylist, likeList } from '../common/NmApi';
import { NmPlaylist, NmPageParam } from '../common/NmTypes';

@Component
export struct HomePage {
  @Consume('nav') pathStack: NavPathStack;
  @State nickname: string = '';
  @State avatarUrl: string = '';
  @State playlists: NmPlaylist[] = [];
  @State loading: boolean = true;
  @State openingLiked: boolean = false;
  @State level: string = 'standard';
  @StorageProp('nmTitle') nowTitle: string = '';
  @StorageProp('nmArtist') nowArtist: string = '';
  @StorageProp('nmCoverUrl') nowCover: string = '';
  @StorageProp('nmPlaying') nowPlaying: boolean = false;
  @StorageProp('nmNeedHomeRefresh') @Watch('onNeedRefresh') needRefresh: boolean = false;

  aboutToAppear(): void {
    this.level = NmStore.level;
    if (!NmStore.isLogged()) {
      this.loading = false;
      this.pathStack.pushPathByName('login', '');
      return;
    }
    this.refresh();
  }

  onNeedRefresh(): void {
    if (this.needRefresh) {
      AppStorage.setOrCreate('nmNeedHomeRefresh', false);
      this.refresh();
    }
  }

  private async refresh(): Promise<void> {
    this.loading = true;
    const ok = await refreshAccount();
    if (!ok) {
      // A temporary network error is not proof that the session expired.
      this.nickname = '';
      this.avatarUrl = '';
      this.loading = false;
      this.pathStack.pushPathByName('login', '');
      return;
    }
    this.nickname = NmStore.nickname;
    this.avatarUrl = NmStore.avatarUrl;
    try {
      this.playlists = await userPlaylist(NmStore.uid, 100, 0);
    } catch (e) {
      this.playlists = [];
    }
    try {
      const ids = await likeList(NmStore.uid);
      const set = new Set<number>();
      for (let i = 0; i < ids.length; i++) {
        set.add(ids[i]);
      }
      NmStore.likedIds = set;
      NmStore.saveLiked();
    } catch (e) {
    }
    this.loading = false;
  }

  private findLikedPlaylist(): NmPlaylist | null {
    for (let i = 0; i < this.playlists.length; i++) {
      const playlist = this.playlists[i];
      if (playlist.specialType === 5 && playlist.ownerId === NmStore.uid) {
        return playlist;
      }
    }
    return null;
  }

  private async openLikedPlaylist(): Promise<void> {
    if (this.openingLiked) { return; }
    this.openingLiked = true;
    try {
      let playlist = this.findLikedPlaylist();
      if (playlist === null && NmStore.uid > 0) {
        this.playlists = await userPlaylist(NmStore.uid, 100, 0);
        playlist = this.findLikedPlaylist();
      }
      if (playlist !== null) {
        const param: NmPageParam = { mode: 'playlist', id: playlist.id, name: playlist.name };
        this.pathStack.pushPathByName('playlist', param);
      } else {
        this.getUIContext().getPromptAction().showToast({ message: '未能获取我喜欢的歌单，请重试', duration: 2000 });
      }
    } catch (e) {
      this.getUIContext().getPromptAction().showToast({ message: '歌单加载失败，请重试', duration: 2000 });
    } finally {
      this.openingLiked = false;
    }
  }

  // 圆形搜索按钮
  @Builder
  searchBtn() {
    Stack() {
      Image($r('app.media.nm_search')).width(21).height(21)
    }
    .width(38)
    .height(38)
    .borderRadius(19)
    .backgroundColor('#1F1F1F')
    .accessibilityText('搜索音乐')
    .onClick(() => {
      this.pathStack.pushPathByName('search', '');
    })
  }

  // 胶囊正在播放条
  @Builder
  playPill() {
    Row({ space: 10 }) {
      if (this.nowCover !== '') {
        Image(this.nowCover + '?param=120y120')
          .width(42)
          .height(42)
          .borderRadius(21)
          .objectFit(ImageFit.Cover)
          .backgroundColor('#141414')
      } else {
        Circle({ width: 42, height: 42 }).fill('#141414')
      }
      Column({ space: 2 }) {
        Text(this.nowTitle)
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor('#FFFFFF')
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(this.nowPlaying ? '正在播放' : '已暂停')
          .fontSize(12)
          .fontColor('#9C9C9C')
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      Stack() {
        if (this.nowPlaying) {
          Image($r('app.media.nm_pause')).width(20).height(20)
        } else {
          Image($r('app.media.nm_play')).width(20).height(20)
        }
      }
      .width(38)
      .height(38)
      .borderRadius(19)
      .backgroundColor('#1F1F1F')
      .alignContent(Alignment.Center)
      .onClick(() => {
        NmPlayer.toggle();
      })
    }
    .width('100%')
    .height(64)
    .padding({ left: 12, right: 12 })
    .borderRadius(32)
    .backgroundColor('#161616')
    .onClick(() => {
      this.pathStack.pushPathByName('player', '');
    })
  }

  // 功能行（图标圆片 + 文案 + 箭头）
  @Builder
  featureRow(icon: Resource, label: string, onTap: () => void) {
    Row({ space: 12 }) {
      Stack() {
        Image(icon).width(22).height(22)
      }
        .width(36)
        .height(36)
        .borderRadius(18)
        .backgroundColor('#1A1A1A')
      Text(label)
        .fontSize(15)
        .fontColor('#FFFFFF')
        .layoutWeight(1)
      Image($r('app.media.nm_chevron')).width(15).height(15)
    }
    .width('100%')
    .height(54)
    .padding({ left: 10, right: 14 })
    .onClick(() => {
      onTap();
    })
  }

  private async setQuality(level: string): Promise<void> {
    this.level = level;
    NmStore.level = level;
    try {
      await NmStore.saveLevel();
    } catch (e) {
      this.getUIContext().getPromptAction().showToast({ message: '音质设置保存失败', duration: 2000 });
    }
  }

  @Builder
  qualityOption(label: string, value: string) {
    Text(label)
      .fontSize(12)
      .fontColor(this.level === value ? '#FFFFFF' : '#C5C5C8')
      .width(52).height(38).textAlign(TextAlign.Center)
      .borderRadius(19)
      .backgroundColor(this.level === value ? '#D93643' : '#252529')
      .accessibilityText(`${label}音质${this.level === value ? '，已选择' : ''}`)
      .onClick(() => { this.setQuality(value); })
  }

  build() {
    Column() {
      Scroll() {
        Column({ space: 12 }) {
          // 标题 + 搜索
          Row({ space: 10 }) {
            Text('音乐')
              .fontSize(20)
              .fontWeight(FontWeight.Bold)
              .fontColor('#FFFFFF')
            this.searchBtn()
          }
          .width('100%')
          .justifyContent(FlexAlign.Center)

          if (this.nowTitle !== '') {
            this.playPill()
          }

          // 我的歌单封面横滑
          if (this.playlists.length > 0) {
            Scroll() {
              Row({ space: 10 }) {
                ForEach(this.playlists, (pl: NmPlaylist) => {
                  Column({ space: 5 }) {
                    if (pl.coverImgUrl !== '') {
                      Image(pl.coverImgUrl + '?param=240y240')
                        .width(104)
                        .height(104)
                        .borderRadius(14)
                        .objectFit(ImageFit.Cover)
                        .backgroundColor('#141414')
                    } else {
                      Circle({ width: 104, height: 104 }).fill('#141414')
                    }
                    Text(pl.name)
                      .fontSize(11)
                      .fontColor('#C9C9C9')
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                      .width(104)
                      .textAlign(TextAlign.Center)
                  }
                  .onClick(() => {
                    const p: NmPageParam = { mode: 'playlist', id: pl.id, name: pl.name };
                    this.pathStack.pushPathByName('playlist', p);
                  })
                }, (pl: NmPlaylist) => `${pl.id}`)
              }
              .padding({ left: 4, right: 4 })
            }
            .scrollable(ScrollDirection.Horizontal)
            .scrollBar(BarState.Off)
            .width('100%')
          }

          // 功能列表
          Column() {
            this.featureRow($r('app.media.nm_daily'), '每日推荐', () => {
              const p1: NmPageParam = { mode: 'daily', id: 0, name: '每日推荐' };
              this.pathStack.pushPathByName('playlist', p1);
            })
            Divider().color('#161616').strokeWidth(1).margin({ left: 58 })
            this.featureRow($r('app.media.nm_radio'), '私人FM', () => {
              NmPlayer.startFm();
              this.pathStack.pushPathByName('player', '');
            })
            Divider().color('#161616').strokeWidth(1).margin({ left: 58 })
            this.featureRow($r('app.media.nm_heart_filled'), '我喜欢的音乐', () => {
              this.openLikedPlaylist();
            })
            Divider().color('#161616').strokeWidth(1).margin({ left: 58 })
            this.featureRow($r('app.media.nm_search'), '搜索音乐', () => {
              this.pathStack.pushPathByName('search', '');
            })
          }
          .width('100%')
          .borderRadius(18)
          .backgroundColor('#121212')
          .padding({ top: 4, bottom: 4 })

          // 音质
          Column({ space: 8 }) {
            Text('音质')
              .fontSize(12)
              .fontColor('#9C9C9C')
            Row({ space: 7 }) {
              this.qualityOption('标准', 'standard')
              this.qualityOption('较高', 'exhigh')
              this.qualityOption('无损', 'lossless')
            }.justifyContent(FlexAlign.Center)
            Text('切歌后生效').fontSize(10).fontColor('#77777D')
          }
          .width('100%')

          if (this.loading) {
            Text('加载中…')
              .fontSize(11)
              .fontColor('#9C9C9C')
          }
          Blank().height(46)
        }
        .padding({ left: 20, right: 20, top: 34, bottom: 16 })
      }
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)
      .id('ncm_home_scroll')
      .focusable(true)
      .focusOnTouch(true)
      .defaultFocus(true)
      .width('100%')
      .height('100%')
      .align(Alignment.Top)
    }
    .width('100%')
    .height('100%')
  }
}
