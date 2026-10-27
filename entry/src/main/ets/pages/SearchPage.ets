// 搜索页 —— 仿华为音乐风格：黑底、胶囊输入框、无卡片结果行
import { NmPlayer } from '../common/NmPlayer';
import { cloudsearch } from '../common/NmApi';
import { NmSong, fmtTime } from '../common/NmTypes';

@Component
export struct SearchPage {
  @Consume('nav') pathStack: NavPathStack;
  @State kw: string = '';
  @State songs: NmSong[] = [];
  @State searching: boolean = false;
  @State err: string = '';
  @StorageProp('nmLoadedId') loadedId: number = 0;

  private async doSearch(): Promise<void> {
    if (this.kw.trim() === '') {
      return;
    }
    this.searching = true;
    this.err = '';
    try {
      this.songs = await cloudsearch(this.kw.trim(), 30, 0);
      if (this.songs.length === 0) {
        this.err = '没有找到相关歌曲';
      }
    } catch (e) {
      this.err = '搜索失败，请重试';
    }
    this.searching = false;
  }

  build() {
    NavDestination() {
      Column({ space: 8 }) {
        Row({ space: 8 }) {
          TextInput({ placeholder: '搜索歌曲、歌手', text: this.kw })
            .fontSize(13)
            .fontColor('#FFFFFF')
            .placeholderColor('#6E6E6E')
            .backgroundColor('#1A1A1A')
            .borderRadius(19)
            .height(38)
            .layoutWeight(1)
            .onChange((v: string) => {
              this.kw = v;
            })
            .onSubmit(() => {
              this.doSearch();
            })
            .onBlur(() => {
              try {
                this.getUIContext().getFocusController().requestFocus('ncm_search_results');
              } catch (e) {
                // Focus may be unavailable while navigating away.
              }
            })
          Stack() {
            Image($r('app.media.nm_search')).width(20).height(20)
          }
          .width(38)
          .height(38)
          .borderRadius(19)
          .backgroundColor('#1F1F1F')
          .onClick(() => {
            this.doSearch();
          })
        }
        .width('100%')
        .padding({ top: 40 })

        if (this.searching) {
          Text('搜索中…')
            .fontSize(12)
            .fontColor('#9C9C9C')
        }
        if (this.err !== '') {
          Text(this.err)
            .fontSize(12)
            .fontColor('#9C9C9C')
        }

        List({ space: 2 }) {
          ForEach(this.songs, (song: NmSong, idx: number) => {
            ListItem() {
              Row({ space: 10 }) {
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
            Row().height(90).width('100%')
          }
        }
        .layoutWeight(1)
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring)
        .id('ncm_search_results')
        .focusable(true)
        .focusOnTouch(true)
        .defaultFocus(true)
        .width('100%')
      }
      .padding({ left: 16, right: 16, bottom: 10 })
      .width('100%')
      .height('100%')
    }
    .hideTitleBar(true)
    .backgroundColor('#000000')
  }
}
