// Huawei Music inspired circular watch playback layout.
import { NmPlayer } from '../common/NmPlayer';
import { fmtTime } from '../common/NmTypes';
import { audio, AVVolumePanel } from '@kit.AudioKit';
import { vibrator } from '@kit.SensorServiceKit';

const RED = '#FF214C';

@Component
export struct PlayerPage {
  @State showLyric: boolean = false;
  @State showSeek: boolean = false;
  @State seeking: boolean = false;
  @State seekPosition: number = 0;
  @State volumeLevel: number = 0;
  @State volumeReady: boolean = false;
  @State showVolume: boolean = false;
  private minVolume: number = 0;
  private maxVolume: number = 15;
  private crownDegrees: number = 0;
  private volumeTimer: number = -1;
  private visible: boolean = false;
  private lastVibration: number = 0;
  private volumeManager: audio.AudioVolumeManager | null = null;
  private volumeCallback: (event: audio.VolumeEvent) => void = (event: audio.VolumeEvent) => {
    if (event.volumeType === audio.AudioVolumeType.MEDIA) {
      this.volumeLevel = event.volume;
    }
  };
  @StorageProp('nmTitle') title: string = '';
  @StorageProp('nmArtist') artist: string = '';
  @StorageProp('nmPlaying') playing: boolean = false;
  @StorageProp('nmPosition') pos: number = 0;
  @StorageProp('nmDuration') dur: number = 0;
  @StorageProp('nmFav') fav: boolean = false;
  @StorageProp('nmFmMode') fmMode: boolean = false;
  @StorageProp('nmLyricIdx') lyricIdx: number = -1;
  @StorageProp('nmLyricCount') lyricCount: number = 0;
  @StorageProp('nmCoverUrl') coverUrl: string = '';
  @StorageProp('nmMsg') @Watch('onMsg') msg: string = '';

  aboutToAppear(): void {
    try {
      const manager = audio.getAudioManager().getVolumeManager();
      const group = manager.getVolumeGroupManagerSync(audio.DEFAULT_VOLUME_GROUP_ID);
      this.minVolume = group.getMinVolumeSync(audio.AudioVolumeType.MEDIA);
      this.maxVolume = group.getMaxVolumeSync(audio.AudioVolumeType.MEDIA);
      this.volumeLevel = group.getVolumeSync(audio.AudioVolumeType.MEDIA);
      this.volumeManager = manager;
      manager.on('volumeChange', this.volumeCallback);
      this.volumeReady = true;
    } catch (e) {
      this.volumeReady = false;
    }
  }

  aboutToDisappear(): void {
    if (this.volumeTimer >= 0) { clearTimeout(this.volumeTimer); }
    if (this.volumeManager !== null) {
      try { this.volumeManager.off('volumeChange', this.volumeCallback); } catch (e) {}
    }
  }

  private focusControls(): void {
    if (this.visible && !this.showSeek) {
      try { this.getUIContext().getFocusController().requestFocus('ncm_player_controls'); } catch (e) {}
    }
  }

  private onCrown(event: CrownEvent): void {
    event.stopPropagation();
    if (!this.volumeReady || event.action === CrownAction.END || !Number.isFinite(event.degree)) { return; }
    this.crownDegrees -= event.degree;
    const steps = Math.trunc(this.crownDegrees / 8);
    if (steps === 0) { return; }
    this.crownDegrees -= steps * 8;
    const next = Math.max(this.minVolume, Math.min(this.maxVolume, this.volumeLevel + steps));
    if (next === this.volumeLevel) { return; }
    this.volumeLevel = next;
    this.showVolume = true;
    if (this.volumeTimer >= 0) { clearTimeout(this.volumeTimer); }
    this.volumeTimer = setTimeout(() => { this.showVolume = false; }, 1600);
    const now = Date.now();
    if (now - this.lastVibration >= 120) {
      this.lastVibration = now;
      try { vibrator.startVibration({ type: 'time', duration: 10 }, { usage: 'touch' }).catch(() => {}); } catch (e) {}
    }
  }

  onMsg(): void {
    if (this.msg !== '') {
      this.getUIContext().getPromptAction().showToast({ message: this.msg, duration: 2000 });
      NmPlayer.clearMsg();
    }
  }

  private lyricText(): string {
    const lines = NmPlayer.lyric;
    if (this.lyricIdx >= 0 && this.lyricIdx < lines.length) {
      return lines[this.lyricIdx].text;
    }
    return this.lyricCount > 0 ? '等待歌词…' : '暂无歌词';
  }

  @Builder
  playIcon() {
    if (this.playing) {
      Image($r('app.media.nm_pause')).width(32).height(32)
    } else {
      Image($r('app.media.nm_play')).width(32).height(32)
    }
  }

  @Builder
  skipIcon(previous: boolean) {
    if (previous) {
      Image($r('app.media.nm_previous')).width(31).height(31)
    } else {
      Image($r('app.media.nm_next')).width(31).height(31)
    }
  }

  @Builder
  playback() {
    Column({ space: 4 }) {
      Text(this.title === '' ? '未在播放' : this.title)
        .fontSize(18).fontWeight(FontWeight.Bold).fontColor('#FFFFFF')
        .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
        .textAlign(TextAlign.Center).width(165)
      Text(this.artist === '' ? '选择一首歌曲' : this.artist)
        .fontSize(13).fontColor('#A6A6A6').maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .textAlign(TextAlign.Center).width(160)

      Row({ space: 9 }) {
        Stack() { this.skipIcon(true) }
          .width(42).height(48).accessibilityText('上一首')
          .onClick(() => { NmPlayer.prev(); })
        Stack() {
          if (this.coverUrl !== '') {
            Image(this.coverUrl + '?param=180y180')
              .width(76).height(76).borderRadius(38).objectFit(ImageFit.Cover)
          } else {
            Circle({ width: 76, height: 76 }).fill('#252525')
          }
          Circle({ width: 76, height: 76 }).fill('#000000').fillOpacity(0.38)
          if (this.showLyric) {
            Text(this.lyricText()).fontSize(10).fontColor('#FFFFFF')
              .maxLines(3).textOverflow({ overflow: TextOverflow.Ellipsis })
              .textAlign(TextAlign.Center).width(68)
          } else {
            this.playIcon()
          }
        }
        .width(76).height(76)
        .accessibilityText(this.playing ? '暂停' : '播放')
        .onClick(() => { NmPlayer.toggle(); })
        Stack() { this.skipIcon(false) }
          .width(42).height(48).accessibilityText('下一首')
          .onClick(() => { NmPlayer.next(false); })
      }.justifyContent(FlexAlign.Center).margin({ top: 7, bottom: 7 })

      Row({ space: this.fmMode ? 3 : 16 }) {
        Stack() {
          if (this.fav) {
            Image($r('app.media.nm_heart_filled')).width(29).height(29)
          } else {
            Image($r('app.media.nm_heart')).width(29).height(29)
          }
        }
          .width(44).height(44)
          .accessibilityText(this.fav ? '取消喜欢' : '喜欢')
          .onClick(() => { NmPlayer.likeCurrent(); })
        Stack() { Image($r('app.media.nm_lyrics')).width(27).height(27) }
          .width(44).height(44).accessibilityText(this.showLyric ? '显示封面' : '显示歌词')
          .onClick(() => { this.showLyric = !this.showLyric; })
        Stack() { Image($r('app.media.nm_progress')).width(27).height(27) }
          .width(44).height(44).accessibilityText('调整播放进度')
          .onClick(() => { this.showSeek = true; })
        if (this.fmMode) {
          Stack() { Image($r('app.media.nm_trash')).width(27).height(27) }
            .width(44).height(44).accessibilityText('不喜欢这首歌')
            .onClick(() => { NmPlayer.trashCurrent(); })
        }
      }.justifyContent(FlexAlign.Center)
    }
    .width('100%').height('100%').justifyContent(FlexAlign.Center)
    .id('ncm_player_controls').focusable(true).focusOnTouch(true).defaultFocus(true)
    .onDigitalCrown((event: CrownEvent) => { this.onCrown(event); })
  }

  @Builder
  seekView() {
    Column({ space: 12 }) {
      Text('播放进度').fontSize(17).fontWeight(FontWeight.Bold).fontColor('#FFFFFF')
      Text(`${fmtTime(this.seeking ? this.seekPosition : this.pos)} / ${fmtTime(this.dur)}`)
        .fontSize(13).fontColor('#B5B5B5')
      Slider({ value: this.seeking ? this.seekPosition : this.pos,
        min: 0, max: Math.max(this.dur, 1), step: 1000, style: SliderStyle.OutSet })
        .width(165).height(30).blockColor('#FFFFFF').selectedColor(RED).trackColor('#3B3B40')
        .enabled(this.dur > 0 && this.title !== '')
        .accessibilityText('播放进度')
        .onChange((value: number, mode: SliderChangeMode) => {
          if (mode === SliderChangeMode.Begin || mode === SliderChangeMode.Moving) {
            this.seeking = true;
            this.seekPosition = value;
          } else if (mode === SliderChangeMode.Click || (mode === SliderChangeMode.End && this.seeking)) {
            this.seeking = false;
            NmPlayer.seek(value);
          }
        })
      Button('返回播放').fontSize(13).height(38).backgroundColor('#292929')
        .onClick(() => { this.showSeek = false; setTimeout(() => { this.focusControls(); }, 100); })
    }.width('100%').height('100%').justifyContent(FlexAlign.Center)
  }

  build() {
    NavDestination() {
      Stack() {
        if (this.showSeek) { this.seekView() } else { this.playback() }
        if (this.volumeReady) {
          AVVolumePanel({ volumeLevel: this.volumeLevel, volumeParameter: { position: { x: 0, y: 0 } } })
            .width(1).height(1).position({ x: 0, y: 0 }).hitTestBehavior(HitTestMode.None)
        }
        if (this.showVolume && !this.showSeek) {
          Row({ space: 5 }) {
            Image($r('app.media.nm_volume')).width(16).height(16)
            Text(`${Math.round((this.volumeLevel - this.minVolume) * 100 / Math.max(1, this.maxVolume - this.minVolume))}%`)
              .fontSize(12).fontColor('#FFFFFF')
          }.padding({ left: 8, right: 8, top: 5, bottom: 5 }).borderRadius(14)
            .backgroundColor('#B32A2A2A').position({ x: '64%', y: '25%' })
            .hitTestBehavior(HitTestMode.None)
        }
      }.width('100%').height('100%')
    }
    .hideTitleBar(true).backgroundColor('#000000').focusable(true)
    .onShown(() => { this.visible = true; setTimeout(() => { this.focusControls(); }, 300); })
    .onHidden(() => { this.visible = false; })
    .onBackPressed(() => {
      if (this.showSeek) { this.showSeek = false; setTimeout(() => { this.focusControls(); }, 100); return true; }
      return false;
    })
  }
}
