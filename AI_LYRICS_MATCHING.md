# LyricsX-Next 自动匹配歌词机制 — 调研交接文档

> 本文自包含，供其他 AI 会话直接使用，不依赖任何先前对话。
> 调研对象：https://github.com/wzk112/LyricsX-Next ，版本锚点 **v2.0.43**，
> commit `204d305`（2026-11-02），MPL-2.0。
> 调研目的：为 fmusic（macOS 本地/WebDAV 播放器）引入"联网搜词 + 自动匹配"能力。
> 调研日期：2026-11-14。

---

## 0. 30 秒结论

- LyricsX Next 的自动匹配 = **读系统 Now Playing 元数据 → 本地缓存/内嵌歌词兜底 → 5 个歌词源并行联网搜索 → 多轮查询扩展 → 统一打分 → 1 秒先显示临时最佳、后台继续补搜 → 24 秒内收敛**。
- 它搜得准的关键不是接口，而是两块纯逻辑：
  1. **查询扩展**：搜索词变体 + iTunes catalog 反查跨语言原生歌名 + 从歌词元数据反推歌手/标题别名；
  2. **打分器 `CandidateRanker`**：标题/歌手/时长三重门槛 + 逐字/双语偏好 + 来源顺序。
- 歌词源全部是**非官方公开接口**（LRCLIB、网易云 eapi、QQ 音乐、酷狗 KRC、Musixmatch），无 SDK、无 API key（Musixmatch 例外，需用户 token，默认不启用）。
- fmusic 现在**没有联网 provider 层**，只读音频同目录的 `.yrc`/`.lrc` 侧车文件。最小接入方式：移植匹配内核 → 联网搜词 → 把结果写成 `.yrc`/`.lrc` 侧车，不碰播放/渲染代码。

---

## 1. 两个项目的关系

| | LyricsX-Next | fmusic |
|---|---|---|
| 定位 | macOS 桌面歌词 App（菜单栏/悬浮窗/Touch Bar） | macOS 本地/WebDAV 音乐播放器（Catalyst） |
| 歌词来源 | 联网搜索 + Apple Music 内嵌/云端 | 仅音频同名 `.yrc` / `.lrc` 侧车（无联网） |
| 歌词模型 | `LyricsDocument` / `LyricLine` / `WordCue` | `StructuredLyrics` / `LyricsLine` / `LyricWord`（Subsonic 风格） |
| 与本文的关系 | 调研对象、借鉴来源 | 目标接入方 |

fmusic 相关事实（截至 2026-11-14）：

- 歌词读取入口：`parseLyrics(relFilePath: URL)` 协议方法。
- WebDAV 索引：`WebDAVLibraryIndexer.fetchLyrics` 按 `.yrc` → `.lrc`（含大写）顺序找同目录侧车。
- 本地索引：`LocalLibraryIndexer.sidecarLyrics` 同样先 `.yrc` 后 `.lrc`，再回退 FLAC/MP3 内嵌歌词。
- 解析：`LyricsTextParser` 先判 YRC（词级 `[lineStart,lineDur](wordStart,wordDur,0)word`）再走 LRC。
- 数据模型：`fmusicKit/Api/BackendApi.swift` 的 `LyricsList` / `StructuredLyrics` / `LyricsLine` / `LyricWord`（时间单位毫秒）。
- 渲染：`LyricsView`、`LyricsOverlayManager`、菜单栏歌词；支持 `StructuredLyrics.offset` 与全局 `lyricsOffsetMs`。
- 已知限制：`StructuredLyrics` 没有独立"翻译行"字段，双语只能拼进 `value` 或按行合并。

---

## 2. 自动匹配全流程（按执行顺序）

### 2.1 触发：识别当前播放歌曲

1. `PlayerBridge` 通过 MediaRemote（`libMediaRemoteAdapter.dylib` + `perl run.pl`）读系统 Now Playing，拿到 `title / artist / album / duration / persistentID`，组装 `Track`。
2. `MusicSourcePolicy` 判定来源是否合法：已知播放器白名单（Apple Music、Spotify、网易云、QQ、酷狗等），或进程 bundle 的 `LSApplicationCategoryType == public.app-category.music`；浏览器一律排除。
3. `LyricsSession.accept()` 判断是否"换歌"：用 `Track.representsSamePlaybackItem` 做身份比较（优先 `persistentID`，否则标题+歌手+专辑兼容），同一首歌元数据逐步补全不算换歌；真换歌才 `reload()`。
4. `reload()` 启动歌词流；若搜索开始时歌手还是空、之后才补上，会取消旧搜索并用新 key 重来。

### 2.2 本地优先（不联网）

`LyricsStore.lyrics(for:forceRefresh:)` 顺序：

1. **磁盘缓存** `~/Music/LyricsX/歌曲 - 歌手.lrcx|.lrc|.txt`
   - 按 `cacheIdentity`（标题+歌手+专辑+整数时长）匹配；
   - 带 `[lxcheckpoint:...]` 头的文件是"搜索未完成时的临时结果"，可立即显示并继续补搜，但不算最终选择。
2. **内嵌歌词**：非 Apple Music 播放器读 `track.embeddedLyrics`，能解析则直接返回（score=999）。
3. **本地旧目录** `.lrcx` / `.lrc`。
4. 以上都空才联网。

### 2.3 联网搜索：多源并行 + 每源独立队列

`LyricsStore.search()` 用 TaskGroup 起三类任务：

- Apple Music worker（内嵌歌词读取，可选云端 TTML）；
- Catalog worker（iTunes API 解析跨语言别名）；
- 每个歌词源一个 worker（LRCLIB / NetEase / QQMusic / Kugou / Musixmatch），各自从 `SearchCollector` 取下一个查询。
  默认启用 LRCLIB、NetEase、QQMusic、Kugou、Apple Music；Musixmatch 只有配置 token 后才进入可用列表。

关键参数（`LyricsStore` 初始化）：

| 参数 | 值 |
|---|---|
| 自动搜索总预算 | 24 秒 |
| 会话级搜索超时 | 28 秒（`LyricsSession.searchTimeout`，到点取消搜索并保留已有结果） |
| 手动精简预算 | 18 秒（`min(24,18)`） |
| 手动完整预算 | 40 秒（`max(24,40)`） |
| 首次提前显示延迟 | 1 秒 |
| 可靠结果后的补搜宽限 | 8 秒 |
| 自动候选上限 | 每源每查询 40 个 |
| 手动精简 / 完整候选上限 | 12 / 80 个 |
| 精简模式每源可见结果 | 12 个 |
| 自动别名上限 | 4 个（精简手动 2 个） |

HTTP 层 `SecureLyricsHTTPClient`：

- 强制 `http → https`；只允许 http/https（防 SSRF）；
- 单请求超时 6s、整资源 9s、每 host 最多 4 连接；
- 仅对 408/500/502/503/504、超时、断连、无法连接重试 **1 次**（350ms 后）；
- 响应 > 8MB 判坏；统一加 `X-Client: LyricsX-Next/2.0 (...)`；
- 特例：QQ 音乐仅为补封面的 `music.pf_song_detail_svr` 请求直接拒绝（macOS 27 上会让 URLSession async 桥崩溃），改用 `dataTask` 回调 API。

### 2.4 查询序列与扩展

每个查询是 `Query(track, keyword)`，两种形态：

- 信息查询 `keyword == nil` → provider 收 `.info(title:artist:)`，文本为 `"标题 歌手"`；
- 关键词查询 → `.keyword(清理后的标题)`。

完整搜索的查询序列 = `[信息查询] + 全部标题变体`；精简手动 = `[信息查询] + 前 2 个变体`；与当前歌曲无关的自由关键词 = 仅该关键词。

**标题变体**（`TrackSearchText.titles`）：

- 去掉 `feat./ft./prod.`；
- 去掉 `（完整版/Full ver/フルバージョン）`；
- 按 `~ ～ 〜` 拆副标题；
- 按 `" - "` 拆双语标题（仅当两段经归一化后等价）。

**跨语言别名**（`TrackAliasResolver`）：

1. iTunes Search：`term = 标题 + 歌手`，`entity=song`，`limit=12`，`country=us` 再 `jp`，`lang=en_us`；
2. 用"种子校验"挑 recording：标题等价 + 歌手等价 + 时长误差 ≤ `max(15s, 8%)`；
3. 用 `trackId` 去 `lookup`，`country=jp` / `tw`，`lang=ja_jp`，得到**原生语言标题+歌手**；
4. 同一 recording 校验：`trackId`、`artistId` 相同且时长差 < 1 秒；
5. 别名插入各源队首，并清空 `successfulAutomaticQueries` 让原生名重新完整搜一轮；
6. 限流：60 秒内最多 18 次请求；空结果缓存 300 秒，非空缓存 24 小时；最多缓存 128 首歌。

**歌词元数据反推别名**：

- `ArtistAliasEvidence.aliases`：若已匹配歌词的歌手字段是 `"本地名 Amala"` 这种"不同文字体系并列"（汉字/假名/谚文/西里尔 vs 拉丁），且标题等价、时长在容差内，则拆出另一端作为歌手别名；
- `ArtistAliasEvidence.searchTitles`：同一条匹配记录里的副标题变体作为标题别名；
- 两者都要求有"已匹配"证据，不凭空假设。

### 2.5 单源内部：token → 二次拉取

每个 provider 统一实现两段式（`_LyricsProvider`）：

1. `search(for:)` 返回轻量 `LyricsToken` 列表；
2. token 截断到 `request.limit`（40/12/80）；
3. 对 token **最多 4 个并发** `fetch(with:)` 拉完整歌词，拉完一个补一个；
4. 按**完成顺序** yield，不按 token 顺序（一个卡住的下载不阻塞其它版本）；
5. 单个 fetch 失败只跳过；只要有一个成功，该源算成功。

### 2.6 结果归一化与去重

provider 返回的 `Lyrics` → `LyricsCodec.convert` → `LyricsDocument`：

- 逐字来自 `line.attachments.timetag`（词/音节/字符 cue）；
- 同一时间戳的两行视为"原文+翻译"合并；
- `hasWordTiming` / `hasTranslation` 由实际内容判定；
- 纯文本永不伪造时间戳；
- 网易 YRC/KLyric/LRC 的时间戳 `[mm:ss:xxx]` 会先修正为 `[mm:ss.xxx]`。

`SearchCollector.add(document)`：

- 入口过滤：必须"同步 / 纯音乐 / 非空纯文本"之一；
- 去重键 = `标题 + 歌手 + 来源 + 歌词行 + 纯文本 + 纯音乐标记 + providerID + 专辑`；
  - 自动搜索和"完整手动搜索"保留 providerID 作为身份；
  - 精简手动搜索不保留，用于合并同源同正文的多个版本；
- 每条候选算分后进入 `candidates`，`yield` 给上层流。

### 2.7 打分与排序

**基础分**（`CandidateRanker.score`，硬门槛在前）：

| 维度 | 计分 |
|---|---|
| 标题 | 等价 60；仅互相包含 38；完全不含 → **0 淘汰** |
| 歌手 | 精确 +25；兼容 +15；对不上 → **0 淘汰** |
| 时长 | `+max(0, 10 - 偏差秒)`；**非精确标题**且偏差 ≥ `max(15s, 8%)` → **0 淘汰** |
| 逐字 | +3 |
| 双语 | +2 |

标题等价 = 归一化（大小写/变音/全半角折叠，只留字母数字）后，用 `toLatin` 罗马化再比较；
所以假名/谚文/西里尔能对上，但**翻译标题不会被当作等价**。

**选择分**（`SourceConfiguration.selectionScore`，仅基础分 ≥ 60 才进入）：

```
60
+ (严格模式 && 标题精确 ? 400 : 0)
+ (同步歌词 ? 200 : 0)
+ 偏好加成 × 25
+ 来源顺序奖励          // (来源总数 - 索引) × 10
+ 基础分 / 100
```

默认来源顺序：`LRCLIB > NetEase > QQMusic > Kugou > Musixmatch > Apple Music`
（6 个来源时奖励依次 60/50/40/30/20/10）。

偏好加成：两项都开时逐字 6、双语 4；只开双语时变为 4/6；只开逐字时仍是 6/4（翻译照常加分）。

**自动选择的额外约束**（`satisfiesAutomaticPreferences`）：

- 必须同步、非纯音乐占位；
- 若开了"逐字优先"或"双语优先"任一，则要求**同时具备逐字和双语**；
- 标题必须等价（严格模式）；
- 选择分 ≥ 60。

> 代码特意避免"中文只有逐字、外语只有双语"时死等不存在的组合，收敛逻辑对此有豁免。

**兜底分**（严格候选全失败后才用）：

- `fallbackSelectionScore`：精确标题 + 歌手兼容，忽略时长（provider 常把最后一句时间当长度）；
- `relaxedSelectionScore`（仅关闭严格匹配时）：标题可包含、精确标题可无视歌手缺失。

### 2.8 提前显示与收敛

`AutomaticSearchResults`：

- 开始 1 秒后，若最佳分 ≥ 60 且比已显示高 9 分，先以 `isProvisional = true` 显示；
- 同时写 checkpoint 到磁盘（分数 ≥ 60 且比已写高 9 分才写）；
- 后台继续搜，后续候选只有高 9 分才替换，避免来回跳。

`SearchCollector` 收敛条件：

- **可靠结果** = 分数 ≥ 60 + 同步 + 非纯音乐占位；
- 若最高优先级源命中"全偏好可靠版本"→ 立即结束；
- 否则各源完成有效轮次（satisfied / 成功查询 ≥ 2 / 队列空且无活跃任务）+ catalog 完成后结束；
- 一旦出现逐字或双语（或两项偏好都关闭），启动 **8 秒补搜宽限**，到期即用当前最佳；
- 新别名会重新打开已 parked 的源并重置补搜；
- 总预算 24 秒兜底；超时保留已有结果并标记为 provisional。

来源状态 `SourceSearchStatus(source, count, isSearching, issue)` 单独上报 UI（数量/搜索中/限流/超时等中文原因）。

### 2.9 缓存格式

- 目录默认 `~/Music/LyricsX`（支持安全书签自定义）。
- 文件名 `"标题 - 歌手"`，`/` 替换为 `:`；超长时 `前缀45字符 + SHA256前8字节`。
- 同步/纯音乐扩展名 `.lrcx`，纯文本 `.txt`；已存在的 `.lrc` 原地更新。
- `.lrcx` 保留逐字时间、翻译、offset、来源附加信息（`[lxrich:...]`）。
- checkpoint 头：`[lxcheckpoint:<base64 JSON>]` 单独一行，记录标题/歌手/专辑/来源/时长/providerID/分数/配置指纹。
- 单文件上限 4MB。

---

## 3. 五个歌词源的接口细节

> 全部为公开但非官方接口，随时可能变更；仅用于兼容实现，不要当作稳定 API 文档。

### 3.1 LRCLIB（无鉴权，最省事）

- 搜索：`GET https://lrclib.net/api/search`
  - 信息查询：`track_name` + `artist_name`
  - 关键词：`q`
- 返回：`id, name, trackName, artistName, albumName, duration(秒), instrumental, plainLyrics, syncedLyrics`
- 取词：搜索结果通常已带 `syncedLyrics`，一次请求即可；App 实际走自定义 `LRCLIBSearch`，只调 `/api/search`。
  Vendor 里的 provider 另有一条 `GET /api/get/{id}` 兜底，但不在 App 搜索路径上。
- 格式：标准 LRC；只有行级，无逐字；无翻译。

### 3.2 NetEase（eapi 加密）

- 搜索：`POST https://interface3.music.163.com/eapi/search/get`
  - payload：`s`=查询词, `type=1`, `limit`, `offset=0`
  - 兜底：`POST https://music.163.com/api/search/pc`（`s/offset/limit`，带 Referer 与 UA）
- eapi 加密流程：
  1. 明文 `nobody{url}use{json}md5forencrypt` → MD5；
  2. 拼接 `{url}-36cd479b6b5-{json}-36cd479b6b5-{digest}`；
  3. **AES-128-ECB**（key `e82ckenh8dichen8`，PKCS7）→ hex → 作为 `params`；
  4. 伪装 Android：`appver=8.0.0`、`os=android`、随机 `requestId`、`Referer: https://music.163.com/`。
- 搜索返回：`result.songs[]`：`name`, `id`, `duration`(毫秒), `artists[].name`, `album.name`, `album.picUrl`
- 取词：`POST https://interface3.music.163.com/eapi/song/lyric/v1`
  - payload：`id, cp=false, lv/kv/tv/rv/yv/ytv/yrv=0`
  - 返回：`yrc`(逐字) / `klyric` / `lrc`，翻译 `tlyric` / `ytlrc`，`.lyric` 为字符串
- 优先级：YRC > KLyric > LRC；翻译优先 `ytlrc`，回退 `tlyric`。
- 格式修正：`[mm:ss:xxx]` → `[mm:ss.xxx]`。

### 3.3 QQMusic（双端点并发）

- 搜索（两路并发，按 id 去重合并）：
  - 快搜：`GET https://c.y.qq.com/splcloud/fcgi-bin/smartbox_new.fcg?key=查询词`
  - 详情：`POST https://u.y.qq.com/cgi-bin/musicu.fcg`
    - body：`req_1.method=DoSearchForQQMusicDesktop`,
      `module=music.search.SearchCgiService`,
      `param={num_per_page:20, page_num, query, search_type:0}`
    - 每页 20 条，按 `limit` 翻页
- 重试：`code 2001` 或详情为空但快搜非空时，等 350ms 重试一次（只一次）。
- 搜索返回：
  - 快搜：`data.song.itemlist[]` → `mid`, `name`, `singer`（单串）, `id`
  - 详情：`req_1.data.body.song.list[]` → `mid`, `name`, `id`, `singer[].name`
- 取词：`POST https://c.y.qq.com/qqmusic/fcgi-bin/lyric_download.fcg`
  - form：`musicid`, `version=15`, `miniversion=82`, `lrctype=4`
  - 返回 XML（需先剥 `<!-- -->`），QRC 解码；`ts` 节点为翻译。
- 封面：`get_song_detail_yqq` 拿 album mid（LyricsX 在搜索阶段会拒绝这个额外请求，见 2.3）。
- 格式：QRC 逐字，可能带假名注音。

### 3.4 Kugou（三步链）

1. 搜索：`GET https://mobiles.kugou.com/api/v3/search/song`
   - `format=json`, `keyword`, `page=1`, `pagesize=min(100,limit)`, `showtype=1`
   - 返回 `data.info[]`：**只有** `hash`, `album_id`, `album_audio_id`, `trans_param.union_cover`（**无标题/歌手/时长**）
2. 换凭据：`GET https://krcs.kugou.com/search`
   - `ver=1`, `man=yes`, `client=mobi`, `hash`, `album_audio_id`
   - 返回 `candidates[]`：`id`, `accesskey`, `song`, `singer`, `duration`(毫秒) —— 标题/歌手/时长在这一跳才出现
3. 下载：`GET http://lyrics.kugou.com/download`
   - `id`, `accesskey`, `fmt=krc`, `charset=utf8`, `client=pc`, `ver=1`
   - 返回 KRC 二进制（需解密），字段 `content`(Data) + `fmt`
- 匹配影响：因为搜索阶段没有元数据，Kugou 的打分实际发生在第二跳拿到 candidate 之后。

### 3.5 Musixmatch（需用户 token）

- 搜索：`GET https://apic-desktop.musixmatch.com/ws/1.1/track.search`
  - `format=json`, `namespace=lyrics_richsynched`, `subtitle_format=mxm`,
    `app_id=web-desktop-app-v1.0`, `f_has_lyrics=1`, `usertoken`
  - 信息查询：`q_track` + `q_artist`；关键词：`q`
  - Header：`authority: apic-desktop.musixmatch.com`, `cookie: x-mxm-token-guid=`
- 搜索返回 `message.body.track_list[].track`：
  `track_id`, `track_name`, `artist_name`, `album_name`, `track_length`(秒),
  `has_subtitles`, `instrumental`, `track_spotify_id`, 各尺寸封面
- 取词：`GET .../ws/1.1/macro.subtitles.get`
  - `q_track`, `q_artist`, `q_album`, `q_duration`, `subtitle_format=mxm`, `usertoken`
  - 需 `has_subtitles != 0` 且 `instrumental != 1`
- 无 token 时该源从可用列表剔除。

### 3.6 Apple Music（不在 providerSearch 内，单独通道）

- **内嵌歌词字段**：通过 AppleScript/JXA 读 Music 当前歌曲的 `lyrics()`，用 `persistentID` 校验没切歌；重试 0/1/3 秒；仅当 `playerID == com.apple.Music`。
- **云端歌词**（默认关闭，需登录）：
  - `GET /v1/me/storefront` → 两位国家码；
  - `GET /v1/catalog/{storefront}/search`：`term = [标题+歌手, 标题]`、`types=songs`、`limit=25`；
  - 校验：标题等价 + 歌手兼容 + 专辑精确 + 时长误差 ≤ `max(5s, 2.5%)`；
  - `GET /v1/catalog/{sf}/songs/{id}/syllable-lyrics`（优先）→ `/lyrics`，
    `extend=ttmlLocalizations`，`l[lyrics]=zh-Hans-CN`；
  - 解析 TTML，保留逐字/逐行。

### 3.7 能力矩阵

| 源 | 逐字 | 双语 | 时长（搜索阶段） | 鉴权 | 加密 |
|---|---|---|---|---|---|
| LRCLIB | ✗ | ✗ | ✓（秒） | 无 | 无 |
| NetEase | ✓ YRC | ✓ tlyric | ✓（毫秒） | 无 | AES-128-ECB + MD5 |
| QQMusic | ✓ QRC | ✓ ts | 详情端点无，快搜无 | 无 | QRC 解码 |
| Kugou | ✓ KRC | 视候选 | 第二跳才有 | 无 | KRC 解密 |
| Musixmatch | 视 track | 视 track | ✓（秒） | usertoken | 无 |
| Apple 云端 | ✓ syllable | TTML 内 | ✓（毫秒） | 网页登录 | 无（TTML） |

---

## 4. 接入 fmusic 的建议路径

### 4.1 推荐方案：独立匹配内核 + 侧车文件输出

不动 fmusic 的播放/渲染代码，按以下顺序落地：

1. 在 `fmusicKit` 新建独立目录（如 `LyricsSearch/`），移植三块纯逻辑：
   - `CandidateRanker`（归一化、等价判断、基础分、选择分）；
   - `TrackSearchText`（标题/歌手变体）；
   - `TrackAliasResolver`（iTunes 反查原生名，可后置）。
2. 实现 2–3 个源起步：**LRCLIB（零鉴权）+ NetEase（逐字+翻译）+ QQ（逐字+翻译）**；Kugou/Musixmatch/Apple 云端按需再加。
3. 搜索编排照抄 `SearchCollector` 的核心：
   - 每源一条队列 + 每源 worker；
   - 首轮信息查询，别名插队首；
   - token 二次拉取，4 并发、完成顺序回流；
   - 1 秒提前显示、8 秒宽限、24 秒总预算可先简化为"取最高分，全部源完成或 15 秒超时"。
4. 结果落地为侧车文件：
   - 有逐字 → 写 `.yrc`（`[lineStart,lineDur](wordStart,wordDur,0)word`）；
   - 只有行级 → 写 `.lrc`；
   - 注意本机规则：测试/验证先用短切片，不拿整库跑。
5. 写回位置与 fmusic 索引器保持一致（音频同目录），索引器已优先 `.yrc`。
6. UI 上只需一个"联网搜索歌词"入口和候选列表；不做自动覆盖前先让用户确认，避免错配。

### 4.2 字段映射

| LyricsX-Next | fmusic `StructuredLyrics` |
|---|---|
| `isSynced`（有 lines） | `synced = true` |
| `LyricLine.time`（秒） | `LyricsLine.start = Int(time * 1000)` |
| `LyricLine.text` | `LyricsLine.value` |
| `WordCue.start / end`（秒） | `LyricWord(start: ms, duration: (end-start)*1000, value:)` |
| `offsetMilliseconds` | `StructuredLyrics.offset` |
| `hasTranslation` | fmusic 无独立字段；只能拼进 `value` 或按双行合并 |
| `source / providerID` | 侧车文件不保存；如需保留写进 LRC 标签或旁路 JSON |

### 4.3 最小可用实现（MVP）建议

1. 只接 **LRCLIB** 拿到行级 LRC，先跑通"搜索→打分→写侧车→fmusic 显示"闭环；
2. 加 **NetEase YRC**，验证逐字高亮和长音光晕（fmusic 现有 `YRCFileParser` 已支持词级 cue）；
3. 加 **iTunes 别名**，专门解决中日文歌用拉丁名搜不到的问题；
4. 最后加 QQ/酷狗，并按需补翻译（fmusic 渲染层需要先决定双语怎么显示）。

---

## 5. 已知坑与注意事项

- **接口非官方**：所有端点都可能改版/限流；务必给每源独立的错误状态和超时，不要因一个源失败阻塞整体。
- **网易 eapi**：加密参数、Android 伪装头缺一不可；`[mm:ss:xxx]` 时间戳必须修正，否则解析失败。
- **QQ**：快搜与详情结果字段不同；详情接口会偶发 `code 2001`，只可重试一次；XML 里夹注释，需先剥。
- **酷狗**：搜索接口不返回歌名/歌手，别在第一步就打分；KRC 需要解密。
- **Musixmatch**：必须用户自带 token；无 token 时应从来源列表移除，而不是报错。
- **时长不是硬过滤**：精确标题+兼容歌手时，时长偏差再大也不能否决（provider 常把最后一句歌词时间当歌曲长度）；时长只用于淘汰"标题也不精确"的模糊候选。
- **自动选择的偏好约束**：开了逐字/双语优先时，自动选择要求两者同时具备；否则会永远停在"临时结果"。中文歌可能只有逐字、外语歌可能只有双语，收敛逻辑对此有豁免，自己实现时别写成死等。
- **翻译标题 ≠ 等价标题**：`toLatin` 只做音译（假名→罗马字等），不做翻译；翻译名只能靠 catalog ID 别名。
- **许可证**：LyricsX-Next 是 MPL-2.0。直接复制其源码文件需保留许可证与文件头；本文只描述机制与接口，重写实现不受影响，但仍建议在 fmusic 内注明参考来源。
- **fmusic 侧车优先级**：`.yrc` 高于 `.lrc`；写错扩展名会导致逐字信息丢失。
- **fmusic 双语限制**：`StructuredLyrics` 无翻译字段，若要双语需先改模型和渲染，不要只在侧车里拼两行导致高亮错位。

---

## 6. 源码索引（便于核对）

clone：

```bash
git clone --depth 1 https://github.com/wzk112/LyricsX-Next.git /tmp/LyricsX-Next
```

| 主题 | 文件 |
|---|---|
| 搜索编排、预算、HTTP 客户端 | `Sources/LyricsXServices/LyricsStore.swift` |
| 每源队列、别名插队、收敛、状态上报 | `Sources/LyricsXServices/SearchCollector.swift` |
| 提前显示、checkpoint | `Sources/LyricsXServices/AutomaticSearchResults.swift` |
| 打分与选择分 | `Sources/LyricsXCore/PlaybackTimeline.swift`（`CandidateRanker`） |
| 来源顺序、偏好、兜底分 | `Sources/LyricsXServices/SourceConfiguration.swift` |
| 标题/歌手变体 | `Sources/LyricsXCore/TrackSearchText.swift` |
| iTunes 跨语言别名 | `Sources/LyricsXServices/TrackAliasResolver.swift` |
| 从歌词元数据反推别名 | `Sources/LyricsXServices/ArtistAliasEvidence.swift` |
| 缓存与 checkpoint | `Sources/LyricsXServices/LyricsCache.swift` |
| LRC/YRC/TTML 解析与导出 | `Sources/LyricsXServices/LyricsCodec.swift` |
| Apple Music 内嵌歌词 | `Sources/LyricsXServices/AppleMusicLyricsSource.swift` |
| Apple Music 云端 TTML | `Sources/LyricsXServices/AppleMusicCloudLyricsSource.swift` |
| 播放器识别 | `Sources/LyricsXServices/MusicSourcePolicy.swift` |
| 会话/换歌/重载 | `Sources/LyricsXCore/LyricsSession.swift` |
| 各源实现 | `Vendor/LyricsKit/Sources/LyricsService/Provider/Services/{LRCLIB,NetEase,QQMusic,Kugou,Musixmatch}/` |
| 源内 token→fetch 并发 | `Vendor/LyricsKit/Sources/LyricsService/Provider/LyricsProvider.swift` |
| 响应模型 | `Vendor/LyricsKit/Sources/LyricsService/Model/{LRCLIB,NetEase,QQMusic,Kugou,Musixmatch}/` |
| 行为回归测试 | `Tests/LyricsXServicesTests/SearchRegressionTests.swift` |

fmusic 侧对照：

| 主题 | 文件 |
|---|---|
| 歌词模型 | `fmusicKit/Api/BackendApi.swift`（`LyricsList` / `StructuredLyrics` / `LyricsLine` / `LyricWord`） |
| YRC/LRC 解析 | `fmusicKit/Api/LibrarySyncerDefaults.swift`（`LyricsTextParser` / `YRCFileParser` / `LRCFileParser`） |
| WebDAV 侧车查找 | `fmusicKit/Api/WebDAV/WebDAVLibraryIndexer.swift`（`fetchLyrics`） |
| 本地侧车查找 | `fmusicKit/Api/Local/LocalLibraryIndexer.swift`（`sidecarLyrics`） |
| 歌词加载调用点 | `fmusic/LyricsOverlay/LyricsOverlayManager.swift`、`fmusic/Screens/Player/LargeCurrentlyPlayingPlayerView.swift`、`fmusic/Screens/ViewController/LyricsVC.swift`、`fmusic/Screens/ViewController/PlainDetailsVC.swift` |

---

## 7. 可直接复用的判断规则（伪代码）

```
func score(doc, track) -> Double {
    guard normalized(doc.title) 非空, normalized(track.title) 非空 else { return 0 }
    guard equivalentTitle(doc.title, track.title)
          || docTitle.contains(trackTitle) || trackTitle.contains(docTitle) else { return 0 }

    exact = equivalentTitle(doc.title, track.title)
    score = exact ? 60 : 38

    if !track.artist.isEmpty {
        guard !doc.artist.isEmpty, compatibleArtists(doc.artist, track) else { return 0 }
        score += equivalent(doc.artist, track.artist) ? 25 : 15
    }
    if track.duration > 0, doc.duration > 0 {
        delta = abs(track.duration - doc.duration)
        if !exact && delta >= max(15, track.duration * 0.08) { return 0 }
        score += max(0, 10 - delta)
    }
    if doc.hasWordTiming { score += 3 }
    if doc.hasTranslation { score += 2 }
    return score
}

func equivalentTitle(a, b) -> Bool {
    TrackSearchText.titles(a).contains { x in
        TrackSearchText.titles(b).contains { y in equivalent(x, y) }
    }
}

func equivalent(a, b) -> Bool {
    // 归一化：caseInsensitive + diacriticInsensitive + widthInsensitive，只留 alphanumerics
    if na == nb { return true }
    // 双方都是纯 ASCII 时到此为止（避免把英文标题互相音译）
    if a 与 b 都只含 ASCII { return false }
    // 否则 toLatin 后再归一化比较，长度 >= 3 且相等
    return latin(na).count >= 3 && latin(na) == latin(nb)
}

func compatibleArtists(candidate, track) -> Bool {
    expected = TrackSearchText.artists(track.artist, title: track.title) // 拆 feat./&/,/、/; 等
    if expected.isEmpty { return true }
    return TrackSearchText.artists(candidate).contains { name in
        expected.contains { other in
            equivalent(name, other) || (min(len) >= 3 && (a.contains(b) || b.contains(a)))
        }
    }
}
```

---

## 8. 一页版总结

| 问题 | 答案 |
|---|---|
| 怎么知道在放哪首歌 | MediaRemote 读系统 Now Playing；白名单/App 类别过滤；`persistentID` 判换歌 |
| 先查什么 | 本地 `.lrcx/.lrc/.txt` 缓存 → 内嵌歌词 → 旧目录 → 才联网 |
| 搜几个源 | 5 个（LRCLIB、网易云、QQ、酷狗、Musixmatch）+ Apple Music 单独通道 |
| 怎么搜 | 每源独立队列；首轮信息查询；标题变体 + iTunes 原生名别名插队首 |
| 怎么拉词 | 先搜索拿 token，再 4 并发二次拉取，完成顺序回流 |
| 怎么选 | 标题/歌手/时长硬门槛 → 基础分 → 精确标题/同步/偏好/来源顺序加权 |
| 什么时候显示 | 1 秒后先显示 ≥60 分的临时最佳；高 9 分才替换 |
| 什么时候停 | 首选源全偏好命中即停；否则各源完成有效轮次；8 秒宽限；24 秒总预算 |
| 缓存是什么 | `~/Music/LyricsX` 的 `.lrcx`，带 `[lxcheckpoint:...]` 临时标记 |
| fmusic 怎么接 | 移植打分器 + 变体/别名 → 联网搜 → 写 `.yrc`/`.lrc` 侧车，不动播放渲染 |
