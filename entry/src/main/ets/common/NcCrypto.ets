// 网易云音乐接口加密实现（移植自 NeteaseCloudMusicApiEnhanced util/crypto.js）
// weapi: 双层 AES-128-CBC + RSA 无填充
// eapi: AES-128-ECB + MD5
import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { util } from '@kit.ArkTS';

const WEAPI_IV: string = '0102030405060708';
const WEAPI_PRESET_KEY: string = '0CoJUm6Qyw8W8jud';
const EAPI_KEY: string = 'e82ckenh8dichen8';
const BASE62: string =
  'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
// NetEase 官方 RSA-1024 公钥的模数与指数（原仓库 PEM 解码结果）
const RSA_N_HEX: string =
  'e0b509f6259df8642dbc35662901477df22677ec152b5ff68ace615bb7b725152b3ab17a876aea8a5aa76d2e417629ec4ee341f56135fccf695280104e0312ecbda92557c93870114af6c9d05c4f7f0c3685b7a46bee255932575cce10b424d813cfe4875d3e82047b97ddef52741d546b8e289dc6935b3ece0462db0a22b8e7';
const RSA_N: bigint = BigInt('0x' + RSA_N_HEX);
const RSA_E: bigint = BigInt(0x10001);

export function utf8(text: string): Uint8Array {
  return new util.TextEncoder().encodeInto(text);
}

export function bytesToHex(bytes: Uint8Array, upper: boolean): string {
  let s = '';
  for (let i = 0; i < bytes.length; i++) {
    let h = bytes[i].toString(16);
    if (h.length < 2) {
      h = '0' + h;
    }
    s += h;
  }
  return upper ? s.toUpperCase() : s;
}

export function randomHex(byteLen: number): string {
  let s = '';
  for (let i = 0; i < byteLen; i++) {
    let h = Math.floor(Math.random() * 256).toString(16);
    if (h.length < 2) {
      h = '0' + h;
    }
    s += h;
  }
  return s;
}

export function randomBase62(len: number): string {
  let s = '';
  for (let i = 0; i < len; i++) {
    s += BASE62.charAt(Math.floor(Math.random() * 62));
  }
  return s;
}

export function base64Encode(bytes: Uint8Array): string {
  return new util.Base64Helper().encodeToStringSync(bytes);
}

export async function md5Hex(text: string): Promise<string> {
  const md = cryptoFramework.createMd('MD5');
  await md.update({ data: utf8(text) });
  const blob = await md.digest();
  return bytesToHex(blob.data, false);
}

export async function md5Bytes(text: string): Promise<Uint8Array> {
  const md = cryptoFramework.createMd('MD5');
  await md.update({ data: utf8(text) });
  const blob = await md.digest();
  return blob.data;
}

async function aesEncryptPkcs7(data: Uint8Array, key: Uint8Array,
  iv: Uint8Array | null): Promise<Uint8Array> {
  const algName = iv === null ? 'AES128|ECB|PKCS7' : 'AES128|CBC|PKCS7';
  const cipher = cryptoFramework.createCipher(algName);
  const gen = cryptoFramework.createSymKeyGenerator('AES128');
  const symKey = await gen.convertKey({ data: key });
  if (iv === null) {
    await cipher.init(cryptoFramework.CryptoMode.ENCRYPT_MODE, symKey, null);
  } else {
    const spec: cryptoFramework.IvParamsSpec = {
      algName: 'IvParamsSpec',
      iv: { data: iv }
    };
    await cipher.init(cryptoFramework.CryptoMode.ENCRYPT_MODE, symKey, spec);
  }
  const part1 = await cipher.update({ data: data });
  const part2 = await cipher.doFinal({ data: new Uint8Array(0) });
  const out = new Uint8Array(part1.data.length + part2.data.length);
  out.set(part1.data, 0);
  out.set(part2.data, part1.data.length);
  return out;
}

function bigIntFromBytes(bytes: Uint8Array): bigint {
  let v = BigInt(0);
  for (let i = 0; i < bytes.length; i++) {
    v = (v << BigInt(8)) | BigInt(bytes[i]);
  }
  return v;
}

function modPow(base: bigint, exp: bigint, mod: bigint): bigint {
  const one = BigInt(1);
  const two = BigInt(2);
  const zero = BigInt(0);
  let result = one;
  let b = base % mod;
  let e = exp;
  while (e > zero) {
    if ((e & one) === one) {
      result = (result * b) % mod;
    }
    b = (b * b) % mod;
    e = e / two;
  }
  return result;
}

// RSA 无填充加密（weapi encSecKey），输出定长 256 位十六进制
function rsaNoPadHex(bytes: Uint8Array): string {
  const c = modPow(bigIntFromBytes(bytes), RSA_E, RSA_N);
  let hex = c.toString(16);
  while (hex.length < 256) {
    hex = '0' + hex;
  }
  return hex.toUpperCase();
}

export class WeapiParams {
  params: string = '';
  encSecKey: string = '';
}

export async function weapiEncrypt(obj: Record<string, Object>): Promise<WeapiParams> {
  const text = JSON.stringify(obj);
  const secretKey = randomBase62(16);
  const pass1 = await aesEncryptPkcs7(utf8(text), utf8(WEAPI_PRESET_KEY), utf8(WEAPI_IV));
  const pass2 = await aesEncryptPkcs7(pass1, utf8(secretKey), utf8(WEAPI_IV));
  const p = new WeapiParams();
  p.params = base64Encode(pass2);
  let rev = '';
  for (let i = secretKey.length - 1; i >= 0; i--) {
    rev += secretKey.charAt(i);
  }
  p.encSecKey = rsaNoPadHex(utf8(rev));
  return p;
}

export class EapiParams {
  params: string = '';
}

export async function eapiEncrypt(url: string,
  obj: Record<string, Object>): Promise<EapiParams> {
  const text = JSON.stringify(obj);
  const message = `nobody${url}use${text}md5forencrypt`;
  const digest = await md5Hex(message);
  const plain = `${url}-36cd479b6b5-${text}-36cd479b6b5-${digest}`;
  const enc = await aesEncryptPkcs7(utf8(plain), utf8(EAPI_KEY), null);
  const p = new EapiParams();
  p.params = bytesToHex(enc, true);
  return p;
}
