// 播放服务：AVPlayer 流播放 + AVSession 播控 + audioPlayback 长时任务 + 私人FM续播
import { media } from '@kit.MediaKit';
import { avSession } from '@kit.AVSessionKit';
import { backgroundTaskManager } from '@kit.BackgroundTasksKit';
import { wantAgent, WantAgent, common } from '@kit.AbilityKit';
import { image } from '@kit.ImageKit';
import { http } from '@kit.NetworkKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { NmSong, LrcLine, parseLrc } from './NmTypes';
import {
  songUrlV1,
  lyricNew,
  personalFm,
  like as apiLike,
  fmTrash as apiFmTrash
} from './NmApi';
import { NmStore } from './NmStore';

export class NmPlayer {
  static queue: NmSong[] = [];
  static index: number = -1;
  static fmMode: boolean = false;
  static lyric: LrcLine[] = [];
  static context: common.UIAbilityContext | null = null;

  private static player: media.AVPlayer | null = null;
  private static session: avSession.AVSession | null = null;
  private static sessionReady: boolean = false;
  private static bgTaskRunning: boolean = false;
  private static bgTaskBusy: boolean = false;
  private static timerId: number = -1;
  private static skipGuard: number = 0;
  private static wantAgentObj: WantAgent | null = null;
  private static pendingUrl: string = '';
  private static seekPending: boolean = false;
  private static seekTimer: number = -1;
  private static lastClockTick: number = 0;

  static currentSong(): NmSong | null {
    if (NmPlayer.index >= 0 && NmPlayer.index < NmPlayer.queue.length) {
      return NmPlayer.queue[NmPlayer.index];
    }
    return null;
  }

  static init(context: common.UIAbilityContext): void {
    NmPlayer.context = context;
    AppStorage.setOrCreate('nmTitle', '');
    AppStorage.setOrCreate('nmArtist', '');
    AppStorage.setOrCreate('nmPlaying', false);
    AppStorage.setOrCreate('nmPosition', 0);
    AppStorage.setOrCreate('nmDuration', 0);
    AppStorage.setOrCreate('nmFav', false);
    AppStorage.setOrCreate('nmFmMode', false);
    AppStorage.setOrCreate('nmLyricIdx', -1);
    AppStorage.setOrCreate('nmLyricCount', 0);
    AppStorage.setOrCreate('nmCoverUrl', '');
    AppStorage.setOrCreate('nmMsg', '');
    AppStorage.setOrCreate('nmLoadedId', 0);
  }

  static setMsg(msg: string): void {
    AppStorage.setOrCreate('nmMsg', msg);
  }

  static clearMsg(): void {
    AppStorage.setOrCreate('nmMsg', '');
  }

  // ---------- 播放控制 ----------

  static playSongs(songs: NmSong[], start: number): void {
    if (songs.length === 0) {
      NmPlayer.setMsg('没有可播放的歌曲');
      return;
    }
    NmPlayer.queue = songs;
    NmPlayer.fmMode = false;
    AppStorage.setOrCreate('nmFmMode', false);
    NmPlayer.skipGuard = 0;
    NmPlayer.playIndex(start);
  }

  static async startFm(): Promise<void> {
    NmPlayer.setMsg('私人FM加载中…');
    const songs = await personalFm();
    if (songs.length === 0) {
      NmPlayer.setMsg('FM 获取失败');
      return;
    }
    NmPlayer.queue = songs;
    NmPlayer.fmMode = true;
    AppStorage.setOrCreate('nmFmMode', true);
    NmPlayer.skipGuard = 0;
    NmPlayer.clearMsg();
    NmPlayer.playIndex(0);
  }

  private static async refillFm(): Promise<boolean> {
    try {
      const songs = await personalFm();
      if (songs.length === 0) {
        return false;
      }
      NmPlayer.queue = NmPlayer.queue.concat(songs);
      return true;
    } catch (e) {
      return false;
    }
  }

  static async playIndex(i: number): Promise<void> {
    if (i < 0 || i >= NmPlayer.queue.length) {
      return;
    }
    NmPlayer.clearSeekPending();
    NmPlayer.lastClockTick = Date.now();
    NmPlayer.index = i;
    const song = NmPlayer.queue[i];
    AppStorage.setOrCreate('nmLoadedId', song.id);
    AppStorage.setOrCreate('nmTitle', song.name);
    AppStorage.setOrCreate('nmArtist', song.artist);
    AppStorage.setOrCreate('nmCoverUrl', song.cover);
    AppStorage.setOrCreate('nmPosition', 0);
    AppStorage.setOrCreate('nmDuration', song.duration);
    AppStorage.setOrCreate('nmFav', NmStore.likedIds.has(song.id));
    AppStorage.setOrCreate('nmLyricIdx', -1);
    AppStorage.setOrCreate('nmLyricCount', 0);
    NmPlayer.lyric = [];
    NmPlayer.fetchLyric(song.id);
    NmPlayer.updateSessionMetadata(song);
    await NmPlayer.loadSong(song, true);
  }

  private static async loadSong(song: NmSong, allowAutoSkip: boolean): Promise<void> {
    let url = '';
    try {
      const r = await songUrlV1(song.id, NmStore.level);
      url = r.url;
    } catch (e) {
      url = '';
    }
    if (url === '') {
      NmPlayer.setMsg('无法播放：版权或VIP限制');
      if (allowAutoSkip) {
        NmPlayer.skipGuard++;
        if (NmPlayer.skipGuard < 5) {
          NmPlayer.next(true);
        }
      }
      return;
    }
    NmPlayer.skipGuard = 0;
    NmPlayer.clearMsg();
    await NmPlayer.ensurePlayer();
    const p = NmPlayer.player;
    if (p === null) {
      return;
    }
    try {
      p.reset();
      if (p.state === 'idle') {
        p.url = url;
      } else {
        NmPlayer.pendingUrl = url;
      }
    } catch (e) {
      NmPlayer.setMsg('播放器加载失败');
    }
  }

  private static async fetchLyric(id: number): Promise<void> {
    try {
      const lrc = await lyricNew(id);
      NmPlayer.lyric = parseLrc(lrc);
    } catch (e) {
      NmPlayer.lyric = [];
    }
    AppStorage.setOrCreate('nmLyricCount', NmPlayer.lyric.length);
  }

  static toggle(): void {
    const p = NmPlayer.player;
    if (p === null) {
      if (NmPlayer.queue.length > 0) {
        NmPlayer.playIndex(Math.max(0, NmPlayer.index));
      }
      return;
    }
    try {
      if (p.state === 'playing') {
        p.pause();
      } else if (p.state === 'paused' || p.state === 'prepared' || p.state === 'completed') {
        p.play();
      }
    } catch (e) {
      // 状态切换竞争时忽略
    }
  }

  static next(auto: boolean): void {
    const i = NmPlayer.index + 1;
    if (NmPlayer.fmMode && i >= NmPlayer.queue.length) {
      NmPlayer.refillFm().then((ok: boolean) => {
        if (ok) {
          NmPlayer.playIndex(NmPlayer.index + 1);
        } else {
          NmPlayer.setMsg('FM 获取失败');
        }
      });
      return;
    }
    if (i >= NmPlayer.queue.length) {
      if (NmPlayer.queue.length > 0) {
        NmPlayer.playIndex(0); // 列表循环
      }
      return;
    }
    NmPlayer.playIndex(i);
    if (!auto) {
      NmPlayer.skipGuard = 0;
    }
  }

  static prev(): void {
    const i = NmPlayer.index - 1;
    if (i >= 0) {
      NmPlayer.playIndex(i);
    } else if (NmPlayer.queue.length > 0) {
      NmPlayer.playIndex(NmPlayer.queue.length - 1);
    }
  }

  static seek(ms: number): void {
    const p = NmPlayer.player;
    if (p === null || !['prepared', 'playing', 'paused', 'completed'].includes(p.state)) {
      NmPlayer.setMsg('播放器尚未准备好');
      return;
    }
    const duration = p.duration > 0 ? p.duration : (AppStorage.get<number>('nmDuration') ?? 0);
    const target = Math.max(0, Math.min(Math.round(ms), duration));
    try {
      NmPlayer.clearSeekPending();
      NmPlayer.seekPending = true;
      p.seek(target);
      AppStorage.setOrCreate('nmPosition', target);
      NmPlayer.seekTimer = setTimeout(() => {
        NmPlayer.clearSeekPending();
        if (p.currentTime >= 0) {
          AppStorage.setOrCreate('nmPosition', p.currentTime);
        }
        NmPlayer.lastClockTick = Date.now();
      }, 2000);
    } catch (e) {
      NmPlayer.clearSeekPending();
      NmPlayer.setMsg('进度调整失败');
    }
  }

  private static clearSeekPending(): void {
    NmPlayer.seekPending = false;
    if (NmPlayer.seekTimer >= 0) {
      clearTimeout(NmPlayer.seekTimer);
      NmPlayer.seekTimer = -1;
    }
  }

  static async likeCurrent(): Promise<void> {
    const song = NmPlayer.currentSong();
    if (song === null) {
      return;
    }
    const fav = !NmStore.likedIds.has(song.id);
    const code = await apiLike(song.id, fav);
    if (code === 200) {
      if (fav) {
        NmStore.likedIds.add(song.id);
      } else {
        NmStore.likedIds.delete(song.id);
      }
      NmStore.saveLiked();
      AppStorage.setOrCreate('nmFav', fav);
    } else {
      NmPlayer.setMsg(fav ? '收藏失败' : '取消收藏失败');
    }
  }

  static async trashCurrent(): Promise<void> {
    const song = NmPlayer.currentSong();
    if (song !== null && NmPlayer.fmMode) {
      try {
        await apiFmTrash(song.id);
      } catch (e) {
      }
    }
    NmPlayer.next(false);
  }

  // ---------- AVPlayer ----------

  private static async ensurePlayer(): Promise<void> {
    if (NmPlayer.player !== null) {
      return;
    }
    const p = await media.createAVPlayer();
    p.on('stateChange', (state: string) => {
      NmPlayer.onState(state);
    });
    p.on('timeUpdate', (time: number) => {
      if (!NmPlayer.seekPending && time >= 0) {
        AppStorage.setOrCreate('nmPosition', time);
        NmPlayer.updateLyricIndex(time);
        NmPlayer.lastClockTick = Date.now();
      }
    });
    p.on('seekDone', (time: number) => {
      if (NmPlayer.seekPending) {
        NmPlayer.clearSeekPending();
        if (time >= 0) {
          AppStorage.setOrCreate('nmPosition', time);
          NmPlayer.updateLyricIndex(time);
        }
        NmPlayer.lastClockTick = Date.now();
      }
    });
    p.on('error', (err: BusinessError) => {
      NmPlayer.setMsg(`播放出错(${err.code})`);
      NmPlayer.skipGuard++;
      if (NmPlayer.skipGuard < 5) {
        NmPlayer.next(true);
      }
    });
    NmPlayer.player = p;
  }

  private static onState(state: string): void {
    if (state === 'idle') {
      const p = NmPlayer.player;
      if (p !== null && NmPlayer.pendingUrl !== '') {
        try {
          p.url = NmPlayer.pendingUrl;
        } catch (e) {
        }
        NmPlayer.pendingUrl = '';
      }
      AppStorage.setOrCreate('nmPlaying', false);
    } else if (state === 'initialized') {
      const p = NmPlayer.player;
      if (p !== null) {
        p.prepare().catch((err: BusinessError) => {
          NmPlayer.setMsg('缓冲失败');
        });
      }
    } else if (state === 'prepared') {
      const p = NmPlayer.player;
      if (p !== null) {
        if (p.duration > 0) {
          AppStorage.setOrCreate('nmDuration', p.duration);
        }
        p.play();
      }
    } else if (state === 'playing') {
      NmPlayer.lastClockTick = Date.now();
      AppStorage.setOrCreate('nmPlaying', true);
      NmPlayer.startTimer();
      NmPlayer.ensureBgTask();
      NmPlayer.updateSessionState(true);
    } else if (state === 'paused') {
      AppStorage.setOrCreate('nmPlaying', false);
      NmPlayer.updateSessionState(false);
    } else if (state === 'completed') {
      AppStorage.setOrCreate('nmPlaying', false);
      NmPlayer.updateSessionState(false);
      NmPlayer.next(true);
    } else if (state === 'stopped' || state === 'idle') {
      AppStorage.setOrCreate('nmPlaying', false);
    }
  }

  private static startTimer(): void {
    if (NmPlayer.timerId >= 0) {
      return;
    }
    NmPlayer.timerId = setInterval(() => {
      const p = NmPlayer.player;
      if (p !== null && p.state === 'playing' && !NmPlayer.seekPending) {
        const now = Date.now();
        const t = p.currentTime;
        if (t >= 0) {
          AppStorage.setOrCreate('nmPosition', t);
          NmPlayer.updateLyricIndex(t);
        } else if (NmPlayer.lastClockTick > 0) {
          // Some wearable players report -1 and never emit timeUpdate.
          // Estimate while playing, and return to the player clock when available.
          const elapsed = Math.max(0, now - NmPlayer.lastClockTick);
          const previous = AppStorage.get<number>('nmPosition') ?? 0;
          const duration = AppStorage.get<number>('nmDuration') ?? 0;
          const next = duration > 0 ? Math.min(duration, previous + elapsed) : previous + elapsed;
          AppStorage.setOrCreate('nmPosition', next);
          NmPlayer.updateLyricIndex(next);
        }
        NmPlayer.lastClockTick = now;
      }
    }, 500);
  }

  private static updateLyricIndex(time: number): void {
    if (NmPlayer.lyric.length === 0) {
      return;
    }
    let idx = -1;
    for (let i = 0; i < NmPlayer.lyric.length; i++) {
      if (NmPlayer.lyric[i].time <= time) {
        idx = i;
      } else {
        break;
      }
    }
    if (idx !== AppStorage.get<number>('nmLyricIdx')) {
      AppStorage.setOrCreate('nmLyricIdx', idx);
    }
  }

  // ---------- AVSession 播控中心 ----------

  static async ensureSession(): Promise<void> {
    if (NmPlayer.sessionReady || NmPlayer.context === null) {
      return;
    }
    NmPlayer.sessionReady = true;
    try {
      const session = await avSession.createAVSession(NmPlayer.context, 'ncm_watch', 'audio');
      NmPlayer.session = session;
      session.on('play', () => {
        NmPlayer.ensurePlay();
      });
      session.on('pause', () => {
        NmPlayer.toggle();
      });
      session.on('playNext', () => {
        NmPlayer.next(false);
      });
      session.on('playPrevious', () => {
        NmPlayer.prev();
      });
      session.on('seek', (time: number) => {
        NmPlayer.seek(time);
      });
      await session.activate();
    } catch (e) {
      NmPlayer.sessionReady = false;
    }
  }

  // 播控中心点“播放”时，若播放器尚未创建则从头开始当前队列
  private static ensurePlay(): void {
    const p = NmPlayer.player;
    if (p === null) {
      if (NmPlayer.queue.length > 0) {
        NmPlayer.playIndex(Math.max(0, NmPlayer.index));
      }
      return;
    }
    try {
      if (p.state === 'paused' || p.state === 'prepared' || p.state === 'completed') {
        p.play();
      }
    } catch (e) {
    }
  }

  private static updateSessionMetadata(song: NmSong): void {
    NmPlayer.ensureSession().then(() => {
      const s = NmPlayer.session;
      if (s === null) {
        return;
      }
      const meta: avSession.AVMetadata = {
        assetId: `${song.id}`,
        title: song.name,
        artist: song.artist,
        album: song.album
      };
      s.setAVMetadata(meta).catch(() => {
      });
      if (song.cover !== '') {
        NmPlayer.fetchCoverPixelMap(song.cover).then((pm: image.PixelMap | null) => {
          const sess = NmPlayer.session;
          if (sess !== null && pm !== null) {
            const meta2: avSession.AVMetadata = {
              assetId: `${song.id}`,
              title: song.name,
              artist: song.artist,
              album: song.album,
              mediaImage: pm
            };
            sess.setAVMetadata(meta2).catch(() => {
            });
          }
        });
      }
    });
  }

  private static async fetchCoverPixelMap(coverUrl: string): Promise<image.PixelMap | null> {
    const req = http.createHttp();
    try {
      const resp = await req.request(coverUrl + '?param=300y300', {
        method: http.RequestMethod.GET,
        expectDataType: http.HttpDataType.ARRAY_BUFFER,
        connectTimeout: 10000,
        readTimeout: 20000,
        usingCache: true
      });
      const buf = resp.result as ArrayBuffer;
      const source = image.createImageSource(buf);
      const pm = await source.createPixelMap({ desiredSize: { width: 240, height: 240 } });
      return pm;
    } catch (e) {
      return null;
    } finally {
      req.destroy();
    }
  }

  private static updateSessionState(playing: boolean): void {
    const s = NmPlayer.session;
    if (s === null) {
      return;
    }
    const pos = AppStorage.get<number>('nmPosition') ?? 0;
    const dur = AppStorage.get<number>('nmDuration') ?? 0;
    const st: avSession.AVPlaybackState = {
      state: playing ? avSession.PlaybackState.PLAYBACK_STATE_PLAY : avSession.PlaybackState.PLAYBACK_STATE_PAUSE,
      position: { elapsedTime: pos, updateTime: Date.now() },
      duration: dur
    };
    s.setAVPlaybackState(st).catch(() => {
    });
  }

  // ---------- 长时任务（后台播放） ----------

  private static async ensureBgTask(): Promise<void> {
    if (NmPlayer.bgTaskRunning || NmPlayer.bgTaskBusy || NmPlayer.context === null) {
      return;
    }
    NmPlayer.bgTaskBusy = true;
    try {
      if (NmPlayer.wantAgentObj === null) {
        const info: wantAgent.WantAgentInfo = {
          wants: [
            {
              bundleName: 'com.ncm.watch',
              abilityName: 'EntryAbility'
            }
          ],
          actionType: wantAgent.OperationType.START_ABILITY,
          requestCode: 0,
          actionFlags: [wantAgent.WantAgentFlags.UPDATE_PRESENT_FLAG]
        };
        NmPlayer.wantAgentObj = await wantAgent.getWantAgent(info);
      }
      if (NmPlayer.wantAgentObj !== null) {
        await backgroundTaskManager.startBackgroundRunning(
          NmPlayer.context as common.UIAbilityContext,
          ['audioPlayback'],
          NmPlayer.wantAgentObj
        );
        NmPlayer.bgTaskRunning = true;
      }
    } catch (e) {
      // 申请失败仅影响后台播放
    } finally {
      NmPlayer.bgTaskBusy = false;
    }
  }

  static stopBgTask(): void {
    if (!NmPlayer.bgTaskRunning || NmPlayer.context === null) {
      return;
    }
    backgroundTaskManager.stopBackgroundRunning(NmPlayer.context as common.UIAbilityContext)
      .then(() => {
        NmPlayer.bgTaskRunning = false;
      })
      .catch(() => {
      });
  }
}
