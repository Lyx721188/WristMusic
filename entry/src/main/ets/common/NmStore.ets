// 持久化：设备标识、cookie（MUSIC_U/MUSIC_A/__csrf/NMTID 等）、用户信息、偏好
import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { randomHex } from './NcCrypto';

export class NmStore {
  static deviceId: string = '';
  static musicU: string = '';
  static musicA: string = '';
  static csrf: string = '';
  static nmtid: string = '';
  static nuid: string = '';
  static nnid: string = '';
  static wnmcid: string = '';
  static uid: number = 0;
  static nickname: string = '';
  static avatarUrl: string = '';
  static likedIds: Set<number> = new Set<number>();
  static level: string = 'standard'; // standard | exhigh | lossless

  private static store: preferences.Preferences | null = null;

  static randomDeviceId(): string {
    return randomHex(26).toUpperCase(); // 52 个十六进制字符
  }

  static async init(context: common.UIAbilityContext): Promise<void> {
    const store = await preferences.getPreferences(context, 'ncm_watch');
    NmStore.store = store;
    NmStore.deviceId = (await store.get('deviceId', '')) as string;
    if (NmStore.deviceId === '') {
      NmStore.deviceId = NmStore.randomDeviceId();
      await store.put('deviceId', NmStore.deviceId);
    }
    NmStore.musicU = (await store.get('musicU', '')) as string;
    NmStore.musicA = (await store.get('musicA', '')) as string;
    NmStore.csrf = (await store.get('csrf', '')) as string;
    NmStore.nmtid = (await store.get('nmtid', '')) as string;
    NmStore.nuid = (await store.get('nuid', '')) as string;
    NmStore.nnid = (await store.get('nnid', '')) as string;
    NmStore.wnmcid = (await store.get('wnmcid', '')) as string;
    NmStore.uid = (await store.get('uid', 0)) as number;
    NmStore.nickname = (await store.get('nickname', '')) as string;
    NmStore.avatarUrl = (await store.get('avatarUrl', '')) as string;
    NmStore.level = (await store.get('level', 'standard')) as string;
    if (NmStore.nuid === '') {
      NmStore.nuid = randomHex(32);
    }
    if (NmStore.nnid === '') {
      NmStore.nnid = `${NmStore.nuid},${Date.now()}`;
    }
    if (NmStore.wnmcid === '') {
      let rs = '';
      const chars = 'abcdefghijklmnopqrstuvwxyz';
      for (let i = 0; i < 6; i++) {
        rs += chars.charAt(Math.floor(Math.random() * chars.length));
      }
      NmStore.wnmcid = `${rs}.${Date.now()}.01.0`;
    }
    const likedStr = (await store.get('likedIds', '')) as string;
    if (likedStr !== '') {
      const parts = likedStr.split(',');
      for (let i = 0; i < parts.length; i++) {
        const v = parseInt(parts[i]);
        if (!isNaN(v)) {
          NmStore.likedIds.add(v);
        }
      }
    }
    await store.flush();
  }

  static clearUser(): void {
    NmStore.musicU = '';
    NmStore.csrf = '';
    NmStore.uid = 0;
    NmStore.nickname = '';
    NmStore.avatarUrl = '';
    NmStore.likedIds.clear();
  }

  static async saveAuth(): Promise<void> {
    const store = NmStore.store;
    if (store === null) {
      return;
    }
    await store.put('musicU', NmStore.musicU);
    await store.put('musicA', NmStore.musicA);
    await store.put('csrf', NmStore.csrf);
    await store.put('nmtid', NmStore.nmtid);
    await store.put('nuid', NmStore.nuid);
    await store.put('nnid', NmStore.nnid);
    await store.put('wnmcid', NmStore.wnmcid);
    await store.put('uid', NmStore.uid);
    await store.put('nickname', NmStore.nickname);
    await store.put('avatarUrl', NmStore.avatarUrl);
    await store.flush();
  }

  static async saveLiked(): Promise<void> {
    const store = NmStore.store;
    if (store === null) {
      return;
    }
    let s = '';
    NmStore.likedIds.forEach((id: number) => {
      s = s === '' ? `${id}` : `${s},${id}`;
    });
    await store.put('likedIds', s);
    await store.flush();
  }

  static async saveLevel(): Promise<void> {
    const store = NmStore.store;
    if (store === null) {
      return;
    }
    await store.put('level', NmStore.level);
    await store.flush();
  }

  static isLogged(): boolean {
    return NmStore.musicU !== '';
  }
}
