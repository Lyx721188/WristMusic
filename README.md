# WristMusic（腕上音乐）

> 第三方、非官方的鸿蒙（HarmonyOS）手表网易云音乐客户端，与网易公司无任何关联。
> “网易云音乐”等商标及音乐内容版权归网易所有，本项目仅供学习交流。

独立的鸿蒙（HarmonyOS）手表网易云音乐客户端，**API 已完整集成进应用**：把
[NeteaseCloudMusicApiEnhanced](https://github.com/NeteaseCloudMusicApiEnhanced/api-enhanced) 的加密与请求层（eapi/weapi、cookie、匿名注册）移植为 ArkTS，
直连网易服务器，**无需部署任何 API 服务端**。

适配设备：HUAWEI WATCH 5（出厂 HarmonyOS 5.1.1 / API 19，固件更新后 HarmonyOS 6.0.x / API 20），
圆形表盘 466×466 设计，`deviceTypes: ["wearable"]`，`compatibleSdkVersion: 5.1.1(19)`。

## 功能

| 模块 | 说明 |
|---|---|
| 登录 | 二维码扫码登录（手表显示二维码，手机网易云 App 扫码确认）/ 手机号+密码登录，游客自动匿名注册 |
| 主页 | “音乐”标题+圆形搜索钮、胶囊正在播放条、歌单封面横滑卡、每日推荐/私人FM/我喜欢的/搜索、音质切换（标准/较高/无损） |
| 歌单 | 歌单歌曲分页加载（100/页）、每日推荐、喜欢列表（歌曲详情批量拉取），标题随列表滚动（圆表安全区） |
| 播放 | 参考华为音乐的圆屏布局：中央封面播放/暂停、左右切歌、SVG 快捷图标、歌词与进度调整、播放页表冠调节媒体音量，VIP/版权歌曲自动跳过 |
| 私人FM | FM 流自动续播、“弃”（fm_trash）切歌 |
| 搜索 | 关键词云搜索（cloudsearch），点按即播 |
| 后台 | audioPlayback 长时任务 + AVSession 播控中心（表盘媒体卡片可 播放/暂停/切歌），熄屏续播 |

UI 整体仿华为音乐 HarmonyOS 手表版（纯黑底、白色实心图标、红色点缀），全部控件按圆形表盘安全区排布。

## 网络通路说明（重要）

手表直连 `music.163.com` 时，火山 DCDN 边缘节点会对部分请求返回 **HTTP 200 空响应体**
（`server: volc-dcdn`，实测定版）。请求层因此实现了多通路自动回退：

```
weapi@music.163.com → weapi@interface.music.163.com → eapi@interfacepc.music.163.com
```

一旦某次回退到 eapi 成功，后续 weapi 请求会优先直接走 eapi（官方 PC 客户端同款通道），
避免每次都浪费 4 个空请求。日志（hilog tag `NCM`）会输出每次实际使用的通路。

## 目录结构

```
entry/src/main/ets/
  common/
    NcCrypto.ets    weapi(双层AES-CBC+RSA无填充)/eapi(AES-ECB+MD5) 加密，移植自 util/crypto.js
    NmRequest.ets   HTTP 层：cookie 组装、set-cookie 回写、匿名注册(weapi)，对应 util/request.js
    NmApi.ets       接口封装（与 module/*.js 一一对应：login_qr_*、song_url_v1、personal_fm 等 20 个）
    NmStore.ets     持久化（preferences）：deviceId/MUSIC_U/MUSIC_A/__csrf/NMTID/喜欢列表/音质
    NmTypes.ets     新旧字段归一化(ar/artists、al/album)、LRC 歌词解析
    NmPlayer.ets    播放服务：AVPlayer + AVSession + 长时任务 + FM 续播
  pages/            Index(Navigation) + Home / Login / Playlist / Search / Player
```

## 构建与安装

```bash
cd WristMusic
devecocli build                 # 产出 entry/build/default/outputs/default/entry-default-unsigned.hap
```

真机安装需要签名（首次）：

```bash
devecocli auth login                          # 浏览器登录华为开发者账号（一次性）
# 连接手表（开发者模式 + USB/无线调试授权）
devecocli signature generate --product default   # 自动生成证书并写入 build-profile.json5
devecocli run                                  # 构建+签名+安装+启动
```

若报 `error:install sign info inconsistent`：`devecocli run --uninstall` 后重装。
也可以用 DevEco Studio 打开本目录，配置签名后直接 Run。

仓库内不包含任何签名证书和密码：`build-profile.json5` 已移除 `signingConfigs`，首次真机运行请在本机执行上面的 `devecocli signature generate`。

## 手表上使用

1. 打开应用 → 首页提示未登录 → 进入登录页。
2. **推荐扫码登录**：手表上点“生成二维码”，打开手机网易云音乐 App 扫码并确认。
   （也可切换为手机号+密码登录。）
3. 登录后从主页进入 每日推荐 / 歌单 / 私人FM / 搜索，点歌曲即播；播放页底部图标依次为喜欢、歌词、进度，点击封面播放或暂停。播放页转动表冠可调节媒体音量；歌单页转动表冠可滚动列表。
4. 在首页选择音质后，从下一首歌曲开始使用新设置；实际音质取决于歌曲和账号权限。
5. 音质在主页切换；VIP 歌曲需账号本身有权益，否则自动跳下一首。

## 已知限制

- 需要手表独立联网（eSIM/蓝牙网络）；未做离线缓存。
- 个别手表播放时不返回有效的播放器时间，界面会按播放时长估算进度；网络缓冲或系统挂起可能导致估算与声音有偏差，播放器恢复提供时间后会重新同步。
- 匿名注册走 weapi（原仓库走 xeapi），已实测网易侧仍接受该方式。
- 歌单每次加载 100 首，可在列表末尾选择“加载更多”。
- 部分老歌单/电台接口未移植；只接入了手表场景需要的 20 个端点。
- 未配置签名前构建产物为 `*-unsigned.hap`，不可直接安装。

## 许可与致谢

- 本项目以 MIT 许可发布，详见 [LICENSE](LICENSE)。
- weapi/eapi 加密与请求层移植自 [NeteaseCloudMusicApiEnhanced](https://github.com/NeteaseCloudMusicApiEnhanced/api-enhanced)（MIT，Copyright (c) 2013-2022 Binaryify）。
- 应用图标基于网易云音乐官方 `og:image` 提取，仅用于标识所连接的服务；相关商标归网易所有。
- 请使用自己的账号，遵守网易云音乐服务条款；不要用于商业分发或大规模请求。
