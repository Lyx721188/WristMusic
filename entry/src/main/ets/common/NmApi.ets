// 接口封装：路径/加密方式/参数与 module/*.js 一一对应
import { nmRequest, NmResponse, mergeCookies } from './NmRequest';
import { NmStore } from './NmStore';
import { md5Hex } from './NcCrypto';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { BusinessError } from '@kit.BasicServicesKit';
import {
  NmSong,
  NmPlaylist,
  normalizeSongs,
  normalizePlaylists
} from './NmTypes';

const LOG_DOMAIN = 0xC0DE;
const LOG_TAG = 'NCM';

function lg(msg: string): void {
  hilog.info(LOG_DOMAIN, LOG_TAG, '%{public}s', msg);
}

function asRecord(v: Object): Record<string, Object> {
  return v as Record<string, Object>;
}

function num(v: Object | undefined): number {
  if (typeof v === 'number') {
    return v as number;
  }
  return 0;
}

// ---------- 登录 / 账号 ----------

export async function loginQrKey(): Promise<string> {
  const data: Record<string, Object> = { 'type': 3 };
  const res = await nmRequest('eapi', '/api/login/qrcode/unikey', data);
  const unikey = asRecord(res.body)['unikey'];
  return typeof unikey === 'string' ? unikey as string : '';
}

// 800 过期 / 801 等待 / 802 已扫 / 803 成功（cookie 已在请求层合并）
export async function loginQrCheck(key: string): Promise<number> {
  const data: Record<string, Object> = { 'key': key, 'type': 3 };
  const res = await nmRequest('eapi', '/api/login/qrcode/client/login', data);
  return num(asRecord(res.body)['code']);
}

export async function loginCellphone(phone: string, password: string,
  countrycode: string): Promise<NmResponse> {
  const md5Pwd = await md5Hex(password);
  const data: Record<string, Object> = {
    'type': '1',
    'https': 'true',
    'phone': phone,
    'countrycode': countrycode,
    'password': md5Pwd,
    'remember': 'true'
  };
  const res = await nmRequest('weapi', '/api/w/login/cellphone', data);
  const cookieVal = asRecord(res.body)['cookie'];
  if (typeof cookieVal === 'string' && (cookieVal as string).includes('MUSIC_U')) {
    mergeCookies([cookieVal as string]);
  }
  return res;
}

export async function userAccount(): Promise<NmResponse> {
  const data: Record<string, Object> = {};
  return nmRequest('weapi', '/api/nuser/account/get', data);
}

// 拉取当前账号信息并写入 NmStore；返回是否登录有效
export async function refreshAccount(): Promise<boolean> {
  if (!NmStore.isLogged()) {
    lg(`refreshAccount: no MUSIC_U (len=${NmStore.musicU.length})`);
    return false;
  }
  try {
    const res = await userAccount();
    const profile = asRecord(res.body)['profile'];
    lg(`refreshAccount: code=${res.status} hasProfile=${profile !== undefined && profile !== null}`);
    if (profile !== undefined && profile !== null) {
      const p = asRecord(profile);
      NmStore.uid = num(p['userId']);
      const nick = p['nickname'];
      const avatar = p['avatarUrl'];
      NmStore.nickname = typeof nick === 'string' ? nick as string : '';
      NmStore.avatarUrl = typeof avatar === 'string' ? avatar as string : '';
      await NmStore.saveAuth();
      return true;
    }
    return false;
  } catch (e) {
    lg(`refreshAccount exception: ${(e as BusinessError).message ?? e}`);
    return false;
  }
}

export async function userPlaylist(uid: number, limit: number,
  offset: number): Promise<NmPlaylist[]> {
  const data: Record<string, Object> = {
    'uid': uid,
    'limit': limit,
    'offset': offset,
    'includeVideo': true
  };
  const res = await nmRequest('weapi', '/api/user/playlist', data);
  return normalizePlaylists(asRecord(res.body)['playlist']);
}

// ---------- 歌单 / 歌曲 ----------

export class TrackPage {
  songs: NmSong[] = [];
  total: number = 0;
}

// 歌单歌曲分页（先取 trackIds 再批量取详情）
export async function playlistTrackPage(id: number, limit: number,
  offset: number): Promise<TrackPage> {
  const out = new TrackPage();
  const data: Record<string, Object> = { 'id': id, 'n': 100000, 's': 8 };
  const res = await nmRequest('eapi', '/api/v6/playlist/detail', data);
  const playlist = asRecord(res.body)['playlist'];
  if (playlist === undefined) {
    return out;
  }
  const trackIds = asRecord(playlist)['trackIds'];
  if (!Array.isArray(trackIds)) {
    return out;
  }
  const ids = trackIds as Array<Object>;
  out.total = ids.length;
  const slice: string[] = [];
  const end = Math.min(offset + limit, ids.length);
  for (let i = offset; i < end; i++) {
    const tid = num(asRecord(ids[i])['id']);
    if (tid > 0) {
      slice.push(`{"id":${tid}}`);
    }
  }
  if (slice.length === 0) {
    return out;
  }
  out.songs = await songDetailByIds('[' + slice.join(',') + ']');
  return out;
}

export async function songDetailByIds(c: string): Promise<NmSong[]> {
  const data: Record<string, Object> = { 'c': c };
  const res = await nmRequest('weapi', '/api/v3/song/detail', data);
  return normalizeSongs(asRecord(res.body)['songs']);
}

export async function songDetail(id: number): Promise<NmSong | null> {
  const songs = await songDetailByIds(`[{"id":${id}}]`);
  return songs.length > 0 ? songs[0] : null;
}

export class SongUrlResult {
  url: string = '';
  type: string = '';
  level: string = '';
  freeTrial: boolean = false;
  fee: number = 0;
}

export async function songUrlV1(id: number, level: string): Promise<SongUrlResult> {
  const data: Record<string, Object> = {
    'ids': `[${id}]`,
    'level': level,
    'encodeType': 'flac'
  };
  const res = await nmRequest('eapi', '/api/song/enhance/player/url/v1', data);
  const out = new SongUrlResult();
  const arr = asRecord(res.body)['data'];
  if (Array.isArray(arr)) {
    const list = arr as Array<Object>;
    if (list.length > 0) {
      const d = asRecord(list[0]);
      const u = d['url'];
      out.url = typeof u === 'string' ? u as string : '';
      out.type = typeof d['type'] === 'string' ? d['type'] as string : '';
      out.level = typeof d['level'] === 'string' ? d['level'] as string : '';
      out.fee = num(d['fee']);
      out.freeTrial = d['freeTrialInfo'] !== undefined && d['freeTrialInfo'] !== null;
    }
  }
  return out;
}

export async function lyricNew(id: number): Promise<string> {
  const data: Record<string, Object> = {
    'id': id,
    'cp': false,
    'tv': 0,
    'lv': 0,
    'rv': 0,
    'kv': 0,
    'yv': 0,
    'ytv': 0,
    'yrv': 0
  };
  const res = await nmRequest('eapi', '/api/song/lyric/v1', data);
  const lrc = asRecord(asRecord(res.body)['lrc'])['lyric'];
  return typeof lrc === 'string' ? lrc as string : '';
}

export async function cloudsearch(keywords: string, limit: number,
  offset: number): Promise<NmSong[]> {
  const data: Record<string, Object> = {
    's': keywords,
    'type': 1,
    'limit': limit,
    'offset': offset,
    'total': true
  };
  const res = await nmRequest('eapi', '/api/cloudsearch/pc', data);
  const result = asRecord(res.body)['result'];
  return result === undefined ? [] : normalizeSongs(asRecord(result)['songs']);
}

// ---------- 推荐与 FM ----------

export async function recommendSongs(): Promise<NmSong[]> {
  const data: Record<string, Object> = {};
  const res = await nmRequest('weapi', '/api/v3/discovery/recommend/songs', data);
  const d = asRecord(res.body)['data'];
  return d === undefined ? [] : normalizeSongs(asRecord(d)['dailySongs']);
}

export async function recommendResource(): Promise<NmPlaylist[]> {
  const data: Record<string, Object> = {};
  const res = await nmRequest('weapi', '/api/v1/discovery/recommend/resource', data);
  return normalizePlaylists(asRecord(res.body)['recommend']);
}

export async function personalFm(): Promise<NmSong[]> {
  const data: Record<string, Object> = {};
  const res = await nmRequest('weapi', '/api/v1/radio/get', data);
  return normalizeSongs(asRecord(res.body)['data']);
}

export async function fmTrash(id: number): Promise<void> {
  const data: Record<string, Object> = { 'songId': id, 'alg': 'RT', 'time': 25 };
  await nmRequest('weapi', '/api/radio/trash/add', data);
}

export async function topPlaylist(cat: string, order: string, limit: number,
  offset: number): Promise<NmPlaylist[]> {
  const data: Record<string, Object> = {
    'cat': cat,
    'order': order,
    'limit': limit,
    'offset': offset,
    'total': true
  };
  const res = await nmRequest('weapi', '/api/playlist/list', data);
  return normalizePlaylists(asRecord(res.body)['playlists']);
}

// ---------- 喜欢 / 签到 ----------

export async function like(id: number, like: boolean): Promise<number> {
  const data: Record<string, Object> = {
    'alg': 'itembased',
    'trackId': id,
    'like': like,
    'time': '3'
  };
  const res = await nmRequest('weapi', '/api/radio/like', data);
  return num(asRecord(res.body)['code']);
}

export async function likeList(uid: number): Promise<number[]> {
  const data: Record<string, Object> = { 'uid': uid };
  const res = await nmRequest('eapi', '/api/song/like/get', data);
  const ids = asRecord(res.body)['ids'];
  const out: number[] = [];
  if (Array.isArray(ids)) {
    const list = ids as Array<Object>;
    for (let i = 0; i < list.length; i++) {
      out.push(num(list[i]));
    }
  }
  return out;
}

export async function dailySignin(): Promise<number> {
  const data: Record<string, Object> = { 'type': 0 };
  const res = await nmRequest('eapi', '/api/point/dailyTask', data);
  return num(asRecord(res.body)['code']);
}
