// 数据模型与归一化工具
// NetEase 不同端点返回新旧两种字段（ar/artists、al/album、dt/duration），统一归一化
export interface NmSong {
  id: number;
  name: string;
  artist: string;
  album: string;
  cover: string;
  duration: number; // 毫秒
  fee: number; // 0 免费 1 VIP 4 购买专辑 8 低音质免费
}

export interface NmPlaylist {
  id: number;
  name: string;
  trackCount: number;
  coverImgUrl: string;
  specialType: number;
  ownerId: number;
}

export interface LrcLine {
  time: number; // 毫秒
  text: string;
}

export interface NmPageParam {
  mode: string; // 'playlist' | 'daily' | 'liked'
  id: number;
  name: string;
}

function asRecord(v: Object): Record<string, Object> {
  return v as Record<string, Object>;
}

function str(v: Object | undefined): string {
  if (typeof v === 'string') {
    return v as string;
  }
  return '';
}

function num(v: Object | undefined): number {
  if (typeof v === 'number') {
    return v as number;
  }
  return 0;
}

function namesOf(arr: Object | undefined): string {
  if (Array.isArray(arr)) {
    const list = arr as Array<Object>;
    const names: string[] = [];
    for (let i = 0; i < list.length; i++) {
      names.push(str(asRecord(list[i])['name']));
    }
    return names.join('/');
  }
  return '';
}

export function normalizeSong(raw: Object): NmSong {
  const r = asRecord(raw);
  const al = r['al'] !== undefined ? asRecord(r['al']) : (r['album'] !== undefined ? asRecord(r['album']) : undefined);
  const song: NmSong = {
    id: num(r['id']),
    name: str(r['name']),
    artist: namesOf(r['ar'] !== undefined ? r['ar'] : r['artists']),
    album: al !== undefined ? str(al['name']) : '',
    cover: al !== undefined ? (str(al['picUrl']) !== '' ? str(al['picUrl']) : str(al['blurPicUrl'])) : '',
    duration: num(r['dt'] !== undefined ? r['dt'] : r['duration']),
    fee: num(r['fee'])
  };
  return song;
}

export function normalizeSongs(arr: Object | undefined): NmSong[] {
  const out: NmSong[] = [];
  if (Array.isArray(arr)) {
    const list = arr as Array<Object>;
    for (let i = 0; i < list.length; i++) {
      const s = normalizeSong(list[i]);
      if (s.id > 0) {
        out.push(s);
      }
    }
  }
  return out;
}

export function normalizePlaylists(arr: Object | undefined): NmPlaylist[] {
  const out: NmPlaylist[] = [];
  if (Array.isArray(arr)) {
    const list = arr as Array<Object>;
    for (let i = 0; i < list.length; i++) {
      const r = asRecord(list[i]);
      const creator = r['creator'];
      const creatorId = creator !== undefined && creator !== null ? num(asRecord(creator)['userId']) : 0;
      const pl: NmPlaylist = {
        id: num(r['id']),
        name: str(r['name']),
        trackCount: num(r['trackCount']),
        coverImgUrl: str(r['coverImgUrl']),
        specialType: num(r['specialType']),
        ownerId: num(r['userId']) || creatorId
      };
      if (pl.id > 0) {
        out.push(pl);
      }
    }
  }
  return out;
}

// 解析 [mm:ss.xxx] 形式的 LRC 歌词
export function parseLrc(lrc: string): LrcLine[] {
  const lines: LrcLine[] = [];
  if (lrc === '') {
    return lines;
  }
  const rows = lrc.split('\n');
  for (let i = 0; i < rows.length; i++) {
    const row = rows[i];
    const matches = row.match(/\[\d{1,3}:\d{1,2}(?:[.:]\d{1,3})?\]/g);
    if (matches === null || matches.length === 0) {
      continue;
    }
    let text = row;
    for (let m = 0; m < matches.length; m++) {
      text = text.replace(matches[m], '');
    }
    text = text.trim();
    if (text === '') {
      continue;
    }
    for (let m = 0; m < matches.length; m++) {
      const tag = matches[m].substring(1, matches[m].length - 1);
      const sep = tag.indexOf(':');
      if (sep < 0) {
        continue;
      }
      const min = parseInt(tag.substring(0, sep));
      const secStr = tag.substring(sep + 1).replace(':', '.');
      const sec = parseFloat(secStr);
      if (isNaN(min) || isNaN(sec)) {
        continue;
      }
      lines.push({ time: Math.round((min * 60 + sec) * 1000), text: text });
    }
  }
  lines.sort((a: LrcLine, b: LrcLine) => a.time - b.time);
  return lines;
}

export function fmtTime(ms: number): string {
  const total = Math.max(0, Math.floor(ms / 1000));
  const m = Math.floor(total / 60);
  const s = total % 60;
  return `${m}:${s < 10 ? '0' : ''}${s}`;
}
