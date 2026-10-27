// 歌单/每日推荐/喜欢列表 —— 仿华为音乐风格：黑底、无卡片行、红色高亮播放行
import { NmPlayer } from '../common/NmPlayer';
import { NmStore } from '../common/NmStore';
import { playlistTrackPage, recommendSongs, songDetailByIds } from '../common/NmApi';
import { NmSong, NmPageParam, fmtTime } from '../common/NmTypes';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { vibrator } from '@kit.SensorServiceKit';

const PAGE_SIZE = 100;

@Component
export struct PlaylistPage {
  @Consume('nav') pathStack: NavPathStack;
  @State songs: NmSong[] = [];
  @State title: string = '';
  @State loading: boolean = true;
  @State err: string = '';
  @StorageProp('nmLoadedId') loadedId: number = 0;
  private mode: string = 'playlist';
  private plId: number = 0;
  private loadedCount: number = 0;
  private totalCount: number = 0;
  private visible: boolean = false;
  private listScroller: Scroller = new Scroller();
  private lastCrownVibration: number = 0;
  private hapticErrorLogged: boolean = false;

  private vibrateCrown(): void {
    const now = Date.now();
    if (now - this.lastCrownVibration < 120) {
      return;
    }
    this.lastCrownVibration = now;
    try {
      vibrator.startVibration({ type: 'time', duration: 10 }, { usage: 'touch' }).catch(() => {
        if (!this.hapticErrorLogged) {
          this.hapticErrorLogged = true;
          hilog.warn(0xC0DE, 'NCM', 'crown vibration unavailable');
        }
      });
    } catch (e) {
      if (!this.hapticErrorLogged) {
        this.hapticErrorLogged = true;
        hilog.warn(0xC0DE, 'NCM', 'crown vibration unavailable');
      }
    }
  }

  private focusList(): void {
    if (this.visible) {
      try {
        this.getUIContext().getFocusController().requestFocus('ncm_playlist_list');
      } catch (e) {}
    }
  }

  build() {
    NavDestination() {
      Column() {
        // 头部作为列表首项（圆表安全：标题随滚动进入中心区，不被表圈裁切）
        List({ space: 2, scroller: this.listScroller }) {
          ListItem() {
            Column({ space: 3 }) {
              Text(this.title)
                .fontSize(16)
                .fontWeight(FontWeight.Bold)
                .fontColor('#FFFFFF')
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .textAlign(TextAlign.Center)
              Text(this.totalCount > 0 ? `共${this.totalCount}首` : (this.mode === 'daily' ? '根据你的口味生成' : ' '))
                .fontSize(11)
                .fontColor('#9C9C9C')
            }
            .width('100%')
            .padding({ top: 30, bottom: 10, left: 50, right: 50 })
          }

          ForEach(this.songs, (song: NmSong, idx: number) => {
            ListItem() {
              Row({ space: 10 }) {
                Text(`${idx + 1}`)
                  .fontSize(12)
                  .fontColor(song.id === this.loadedId ? '#E93B3B' : '#6E6E6E')
                  .width(22)
                  .textAlign(TextAlign.Center)
                Column({ space: 2 }) {
                  Text(song.name)
                    .fontSize(15)
                    .fontWeight(FontWeight.Medium)
                    .fontColor(song.id === this.loadedId ? '#E93B3B' : '#FFFFFF')
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                  Row({ space: 6 }) {
                    Text(`${song.artist}`)
                      .fontSize(11)
                      .fontColor('#9C9C9C')
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                    Text(`· ${fmtTime(song.duration)}`)
                      .fontSize(11)
                      .fontColor('#9C9C9C')
                  }
                }
                .alignItems(HorizontalAlign.Start)
                .layoutWeight(1)
                if (song.fee === 1) {
                  Text('VIP')
                    .fontSize(8)
                    .fontColor('#E93B3B')
                    .border({ width: 1, color: '#E93B3B', radius: 3 })
                    .padding({ left: 3, right: 3, top: 1, bottom: 1 })
                }
              }
              .width('100%')
              .padding({ left: 24, right: 24, top: 8, bottom: 8 })
              .onClick(() => {
                NmPlayer.playSongs(this.songs, idx);
                this.pathStack.pushPathByName('player', '');
              })
            }
          }, (song: NmSong) => `${song.id}_${song.name}`)

          ListItem() {
            Column({ space: 8 }) {
              if (this.err !== '') {
                Text(this.err)
                  .fontSize(12)
                  .fontColor('#E93B3B')
              }
              if (this.loading) {
                Text('加载中…')
                  .fontSize(11)
                  .fontColor('#9C9C9C')
              }
              if (this.mode === 'playlist' && !this.loading && this.loadedCount < this.totalCount) {
                Text(`加载更多 (${this.loadedCount}/${this.totalCount})`)
                  .fontSize(12)
                  .fontColor('#E93B3B')
                  .onClick(() => {
                    this.loadMore();
                  })
              }
            }
            .width('100%')
            .padding({ top: 10, bottom: 110 })
          }
        }
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring)
        .id('ncm_playlist_list')
        .focusable(true)
        .focusOnTouch(true)
        .defaultFocus(true)
        .digitalCrownSensitivity(CrownSensitivity.MEDIUM)
        .onDigitalCrown((event: CrownEvent) => {
          event.stopPropagation();
          if (event.action !== CrownAction.END && Number.isFinite(event.degree)) {
            const delta = Math.max(-160, Math.min(160, -event.degree * 2));
            if (delta !== 0) {
              this.listScroller.scrollBy(0, delta);
              this.vibrateCrown();
            }
          }
        })
        .width('100%')
        .height('100%')
      }
      .width('100%')
      .height('100%')
      .focusable(true)
    }
    .hideTitleBar(true)
    .focusable(true)
    .backgroundColor('#000000')
    .onShown(() => {
      this.visible = true;
      setTimeout(() => { this.focusList(); }, 200);
    })
    .onHidden(() => { this.visible = false; })
    .onReady((ctx: NavDestinationContext) => {
      const param = ctx.pathInfo.param as NmPageParam;
      if (param !== null && param !== undefined) {
        this.mode = param.mode;
        this.plId = param.id;
        this.title = param.name;
      }
      this.load();
    })
  }

  private async load(): Promise<void> {
    this.loading = true;
    this.err = '';
    try {
      if (this.mode === 'playlist') {
        const page = await playlistTrackPage(this.plId, PAGE_SIZE, 0);
        this.songs = page.songs;
        this.loadedCount = page.songs.length;
        this.totalCount = page.total;
      } else if (this.mode === 'daily') {
        this.songs = await recommendSongs();
        this.loadedCount = this.songs.length;
        this.totalCount = this.songs.length;
      } else {
        // 我喜欢的音乐
        const ids: number[] = [];
        NmStore.likedIds.forEach((v: number) => {
          ids.push(v);
        });
        this.songs = [];
        this.loadedCount = 0;
        this.totalCount = ids.length;
        if (ids.length > 0) {
          const songs = await this.fetchLikedPage(ids, 0, Math.min(PAGE_SIZE, ids.length));
          this.songs = songs;
          this.loadedCount = songs.length;
        }
      }
    } catch (e) {
      this.err = '加载失败，请返回重试';
    }
    this.loading = false;
    setTimeout(() => { this.focusList(); }, 100);
  }

  private async fetchLikedPage(ids: number[], offset: number,
    limit: number): Promise<NmSong[]> {
    const slice: string[] = [];
    const end = Math.min(offset + limit, ids.length);
    for (let i = offset; i < end; i++) {
      slice.push(`{"id":${ids[i]}}`);
    }
    if (slice.length === 0) {
      return [];
    }
    return songDetailByIds('[' + slice.join(',') + ']');
  }

  private async loadMore(): Promise<void> {
    if (this.loading || this.mode !== 'playlist') {
      return;
    }
    this.loading = true;
    try {
      const page = await playlistTrackPage(this.plId, PAGE_SIZE, this.loadedCount);
      this.songs = this.songs.concat(page.songs);
      this.loadedCount += page.songs.length;
    } catch (e) {
      this.err = '加载失败';
    }
    this.loading = false;
  }
}
