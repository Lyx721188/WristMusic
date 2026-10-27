// HTTP 层：cookie 组装、eapi/weapi 加密请求、set-cookie 回写
// 移植自 NeteaseCloudMusicApiEnhanced util/request.js（默认 encrypt=true → eapi）
import { http } from '@kit.NetworkKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { NmStore } from './NmStore';
import {
  eapiEncrypt,
  weapiEncrypt,
  md5Bytes,
  base64Encode,
  utf8,
  randomHex
} from './NcCrypto';

const LOG_DOMAIN = 0xC0DE;
const LOG_TAG = 'NCM';

function lg(msg: string): void {
  hilog.info(LOG_DOMAIN, LOG_TAG, '%{public}s', msg);
}

const DOMAIN = 'https://music.163.com';
const API_DOMAIN = 'https://interface.music.163.com';
const EAPI_DOMAIN = 'https://interfacepc.music.163.com';

// 一旦发现 eapi 通路可用，后续 weapi 请求优先走 eapi（手表网络下 volc-dcdn 边缘常回空体）
let preferEapi = false;
const PC_OSVER = 'Microsoft-Windows-10-Professional-build-19045-64bit';
const PC_APPVER = '3.1.17.204416';
const UA_WEAPI =
  'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36 Edg/124.0.0.0';
const UA_API = 'NeteaseMusic 9.0.90/5038 (iPhone; iOS 16.2; zh_CN)';
const ID_XOR_KEY = '3go8&$8*3*3h0k(2)2';

export class NmResponse {
  status: number = 0;
  body: Record<string, Object> = {};
  cookies: string[] = [];
}

function cookieToString(map: Record<string, string>): string {
  const keys = Object.keys(map);
  const parts: string[] = [];
  for (let i = 0; i < keys.length; i++) {
    const k = keys[i];
    parts.push(`${encodeURIComponent(k)}=${encodeURIComponent(map[k])}`);
  }
  return parts.join('; ');
}

function fullCookieMap(): Record<string, string> {
  const map: Record<string, string> = {};
  map['os'] = 'pc';
  map['appver'] = PC_APPVER;
  map['osver'] = PC_OSVER;
  map['channel'] = 'netease';
  map['deviceId'] = NmStore.deviceId;
  map['__remember_me'] = 'true';
  map['ntes_kaola_ad'] = '1';
  map['_ntes_nuid'] = NmStore.nuid;
  map['_ntes_nnid'] = NmStore.nnid;
  map['WNMCID'] = NmStore.wnmcid;
  map['WEVNSM'] = '1.0.0';
  if (NmStore.nmtid !== '') {
    map['NMTID'] = NmStore.nmtid;
  } else {
    map['NMTID'] = '00O' + randomHex(19);
  }
  if (NmStore.musicU !== '') {
    map['MUSIC_U'] = NmStore.musicU;
  } else if (NmStore.musicA !== '') {
    map['MUSIC_A'] = NmStore.musicA;
  }
  if (NmStore.csrf !== '') {
    map['__csrf'] = NmStore.csrf;
  }
  return map;
}

// eapi 请求体的 header 字段，同时作为 HTTP Cookie 头
function eapiHeaderMap(): Record<string, string> {
  const map: Record<string, string> = {};
  map['osver'] = PC_OSVER;
  map['deviceId'] = NmStore.deviceId;
  map['os'] = 'pc';
  map['appver'] = PC_APPVER;
  map['versioncode'] = '140';
  map['mobilename'] = '';
  map['buildver'] = Math.floor(Date.now() / 1000).toString();
  map['resolution'] = '1920x1080';
  map['__csrf'] = NmStore.csrf;
  map['channel'] = 'netease';
  map['requestId'] = `${Date.now()}_${Math.floor(Math.random() * 1000).toString().padStart(4, '0')}`;
  if (NmStore.musicU !== '') {
    map['MUSIC_U'] = NmStore.musicU;
  } else if (NmStore.musicA !== '') {
    map['MUSIC_A'] = NmStore.musicA;
  }
  return map;
}

function extractSetCookies(header: Object): string[] {
  const out: string[] = [];
  const h = header as Record<string, Object>;
  const keys = Object.keys(h);
  const lowerKeys: string[] = [];
  for (let i = 0; i < keys.length; i++) {
    lowerKeys.push(keys[i].toLowerCase());
  }
  let raw: Object | undefined = undefined;
  for (let i = 0; i < keys.length; i++) {
    if (lowerKeys[i] === 'set-cookie') {
      raw = h[keys[i]];
      break;
    }
  }
  lg(`set-cookie present=${raw !== undefined} headerKeys=${lowerKeys.join('|')}`);
  if (raw === undefined) {
    return out;
  }
  if (Array.isArray(raw)) {
    const arr = raw as Array<Object>;
    for (let i = 0; i < arr.length; i++) {
      if (typeof arr[i] === 'string') {
        out.push(arr[i] as string);
      }
    }
  } else if (typeof raw === 'string') {
    out.push(raw as string);
  }
  lg(`set-cookie count=${out.length}`);
  return out;
}

function stripDomain(c: string): string {
  const idx = c.indexOf('Domain=');
  if (idx < 0) {
    return c;
  }
  const end = c.indexOf(';', idx);
  if (end < 0) {
    return c.substring(0, idx).trim() + (idx > 0 && c[idx - 1] === ';' ? ';' : '');
  }
  return c.substring(0, idx) + c.substring(end + 1);
}

// 把响应 set-cookie / 登录返回的 cookie 字符串合并进本地存储
export function mergeCookies(cookieStrList: string[]): void {
  let changed = false;
  const mergedKeys: string[] = [];
  for (let i = 0; i < cookieStrList.length; i++) {
    // NetworkKit may combine Set-Cookie headers with commas. Do not split
    // Expires dates on commas; split only before another cookie assignment.
    const segments = cookieStrList[i].split(/;|,(?=\s*[A-Za-z_][A-Za-z0-9_]*=)/);
    for (let j = 0; j < segments.length; j++) {
      const seg = segments[j].trim();
      if (seg === '') {
        continue;
      }
      const eq = seg.indexOf('=');
      if (eq <= 0) {
        continue;
      }
      // 逗号拼接的多条 set-cookie 会让键带前导逗号/空白，统一去掉
      const k = seg.substring(0, eq).trim().replace(/^[,;\s]+/, '');
      const v = seg.substring(eq + 1).trim();
      if (k === 'MUSIC_U' && NmStore.musicU !== v) {
        NmStore.musicU = v;
        changed = true;
        mergedKeys.push('MUSIC_U');
      } else if (k === 'MUSIC_A' && NmStore.musicA !== v) {
        NmStore.musicA = v;
        changed = true;
        mergedKeys.push('MUSIC_A');
      } else if (k === '__csrf' && NmStore.csrf !== v) {
        NmStore.csrf = v;
        changed = true;
        mergedKeys.push('__csrf');
      } else if (k === 'NMTID' && NmStore.nmtid !== v) {
        NmStore.nmtid = v;
        changed = true;
        mergedKeys.push('NMTID');
      }
    }
  }
  if (mergedKeys.length > 0) {
    lg(`cookie merged: ${mergedKeys.join(',')} musicULen=${NmStore.musicU.length}`);
  }
  if (changed) {
    NmStore.saveAuth();
  }
}

let anonRegistering: boolean = false;

// 无 MUSIC_U 时注册游客 cookie（MUSIC_A），移植自 register_anonimous（走 weapi）
export async function ensureGuestToken(): Promise<void> {
  if (NmStore.musicU !== '' || NmStore.musicA !== '') {
    return;
  }
  // 注册请求自身会再进 nmRequest→ensureGuestToken，重入时直接放行（注册本身无需 cookie）
  if (anonRegistering) {
    return;
  }
  anonRegistering = true;
  try {
    const xorKey = ID_XOR_KEY;
    let xored = '';
    for (let i = 0; i < NmStore.deviceId.length; i++) {
      const code =
        NmStore.deviceId.charCodeAt(i) ^ xorKey.charCodeAt(i % xorKey.length);
      xored += String.fromCharCode(code);
    }
    const encId = base64Encode(await md5Bytes(xored));
    const username = base64Encode(utf8(`${NmStore.deviceId} ${encId}`));
    const data: Record<string, Object> = { 'username': username };
    const res = await nmRequest('weapi', '/api/register/anonimous', data);
    if (res.cookies.length > 0) {
      mergeCookies(res.cookies);
    }
  } catch (e) {
    // 注册失败不阻塞，继续无 MUSIC_A 请求
  } finally {
    anonRegistering = false;
  }
}

class RequestVariant {
  url: string = '';
  cookie: string = '';
  ua: string = '';
  referer: boolean = false;
  body: string = '';
  tag: string = '';
}

export async function nmRequest(crypto: string, uri: string,
  data: Record<string, Object>): Promise<NmResponse> {
  // Login endpoints do not need a guest session. A failed guest registration
  // must not delay each QR polling request.
  if (!uri.startsWith('/api/login/') && !uri.startsWith('/api/w/login/')) {
    await ensureGuestToken();
  }
  const req = http.createHttp();
  const res = new NmResponse();
  try {
    // 同一接口的多条通路：weapi 主域 → weapi 备域 → eapi（官方 PC 同款）
    // 手表直连 music.163.com 偶发 200 空体（DSA 边缘异常），空体时自动切换
    const variants: RequestVariant[] = [];
    if (crypto === 'eapi') {
      data['e_r'] = false;
      const headerMap = eapiHeaderMap();
      data['header'] = headerMap;
      const enc = await eapiEncrypt(uri, data);
      const va = new RequestVariant();
      va.url = EAPI_DOMAIN + '/eapi/' + uri.substring(5);
      va.cookie = cookieToString(headerMap);
      va.ua = UA_API;
      va.body = 'params=' + enc.params;
      va.tag = 'eapi@interfacepc';
      variants.push(va);
    } else {
      data['e_r'] = false;
      data['csrf_token'] = NmStore.csrf;
      const enc = await weapiEncrypt(data);
      const weapiBody = `params=${encodeURIComponent(enc.params)}&encSecKey=${enc.encSecKey}`;
      const cookieFull = cookieToString(fullCookieMap());
      const v1 = new RequestVariant();
      v1.url = DOMAIN + '/weapi/' + uri.substring(5);
      v1.cookie = cookieFull;
      v1.ua = UA_WEAPI;
      v1.referer = true;
      v1.body = weapiBody;
      v1.tag = 'weapi@music';
      const v2 = new RequestVariant();
      v2.url = API_DOMAIN + '/weapi/' + uri.substring(5);
      v2.cookie = cookieFull;
      v2.ua = UA_WEAPI;
      v2.referer = true;
      v2.body = weapiBody;
      v2.tag = 'weapi@interface';
      const headerMap = eapiHeaderMap();
      data['header'] = headerMap;
      const encEapi = await eapiEncrypt(uri, data);
      const v3 = new RequestVariant();
      v3.url = EAPI_DOMAIN + '/eapi/' + uri.substring(5);
      v3.cookie = cookieToString(headerMap);
      v3.ua = UA_API;
      v3.body = 'params=' + encEapi.params;
      v3.tag = 'eapi@interfacepc';
      if (preferEapi) {
        variants.push(v3, v1, v2);
      } else {
        variants.push(v1, v2, v3);
      }
    }
    let text = '';
    let lastResp: http.HttpResponse | null = null;
    let usedVariant = -1;
    for (let v = 0; v < variants.length; v++) {
      const va = variants[v];
      for (let attempt = 0; attempt < 2; attempt++) {
        const headers: Record<string, string> = {};
        headers['Cookie'] = va.cookie;
        headers['User-Agent'] = va.ua;
        if (va.referer) {
          headers['Referer'] = DOMAIN;
        }
        headers['Content-Type'] = 'application/x-www-form-urlencoded;charset=UTF-8';
        let resp: http.HttpResponse;
        try {
          resp = await req.request(va.url, {
          method: http.RequestMethod.POST,
          header: headers,
          extraData: va.body,
          connectTimeout: 15000,
          readTimeout: 30000,
          expectDataType: http.HttpDataType.STRING,
          usingCache: false
          });
        } catch (e) {
          lg(`request failed variant=${va.tag} attempt=${attempt}`);
          continue;
        }
        text = typeof resp.result === 'string' ? resp.result as string : '';
        lastResp = resp;
        if (text.length > 0) {
          usedVariant = v;
          break;
        }
        const h = resp.header as Record<string, Object>;
        lg(`empty body variant=${va.tag} attempt=${attempt} status=${resp.responseCode} originStatus=${h['x-dsa-origin-status']} server=${h['server']}`);
        await new Promise<void>((resolve: () => void) => setTimeout(resolve, 500));
      }
      if (text.length > 0) {
        if (v > 0) {
          lg(`recovered via ${va.tag}`);
          if (va.tag === 'eapi@interfacepc') {
            preferEapi = true;
          }
        }
        break;
      }
    }
    if (lastResp === null) {
      return res;
    }
    try {
      res.body = JSON.parse(text) as Record<string, Object>;
    } catch (e) {
      lg(`json parse failed uri=${uri} len=${text.length} prefix=${text.substring(0, 48)}`);
      res.body = {};
    }
    res.cookies = extractSetCookies(lastResp.header);
    mergeCookies(res.cookies);
    res.status = lastResp.responseCode;
    const codeVal = res.body['code'];
    if (typeof codeVal === 'number') {
      res.status = codeVal as number;
    }
    lg(`${crypto} ${uri} -> httpStatus=${lastResp.responseCode} code=${res.status} bodyLen=${text.length}`);
    return res;
  } finally {
    req.destroy();
  }
}
