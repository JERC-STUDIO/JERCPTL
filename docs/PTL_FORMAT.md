# PTL 规则文件格式（Packet Translation Language）

规则文件位于 `PTL/`，一个**版本对**一个 JSON，文件名即版本对：`2193-2225.json`。
文件内同时表达两个方向，不需要按方向分文件。构建时全部内嵌进 `JERCPLD.PTL.dll`。

## 文件身份

```json
{
  "ptlApi": 1,
  "pair": [2193, 2225],
  "serverVersions": ["1.26.50", "1.26.51"],
  "packets": { }
}
```

| 字段 | 含义 |
| --- | --- |
| `ptlApi` | 规则 API 版本。当前只接受 `1`，不匹配直接拒绝加载。 |
| `pair` | `[较旧协议号, 较新协议号]`，构建期用作规则对名字。 |
| `serverVersions` | 仅供人读与文档核对，不参与路由。 |
| `note` | 可选备注。 |
| `packets` | `"<包 ID>": { "name": ..., "rules": [...] }` 或 `overrides`。 |

## 双向推导

对本质对称的差异只声明一条事实：

```json
"13": { "name": "add_actor", "rules": [
  { "type": "appendBytes", "addedIn": 2225, "bytes": "00" }
] }
```

含义：2225 比 2193 多 1 字节。引擎在 `2193 -> 2225` 时追加，在 `2225 -> 2193` 时校验并删除。

不对称的差异写在 `overrides`，必须分方向明写：

```json
"12": { "name": "add_player", "overrides": {
  "olderToNewer": [ { "type": "builtin", "name": "add_player_passenger" } ],
  "newerToOlder": []
} }
```

## 规则类型

| type | 字段 | 语义 |
| --- | --- | --- |
| `appendBytes` | `addedIn`, `bytes`(hex) | 尾部追加；反向校验后删除 |
| `insertField` | `addedIn`, `skip`(程序), `bytes` | 游标处插入；反向校验后删除 |
| `enumRemap` | `skip`, `map` | 游标处 1 字节查表替换（只影响命中的值） |
| `zeroFixed` | `skip`, `zeros` | 游标处连续 N 字节清零 |
| `builtin` | `name` | 引用引擎内置的结构性重写（加载期校验名字） |
| `drop` | — | 该包在该方向直接丢弃（未实现安全翻译前） |

### 游标程序（`skip`）

按顺序把游标从包载荷起点移到目标字段，全程越界检查：

`var`、`u8`、`u16`、`i32`、`lf32`、`str`、`nbt`、`optionalVar`、`skip:N`、`marker:<text>`

`marker:<text>` 用于定位带长度前缀的字符串（如 StartGame 的 `multiplayer_correlation_id`）：
引擎找到文本后按前置长度字节跳到字符串末尾，再继续后续 token。

## builtin

以下必须重新解析/重编码整包，由引擎实现；规则里只写名字，名字拼错会在**加载期**被拒绝。

| name | 说明 |
| --- | --- |
| `start_game_editor_checksum` | StartGame 中间插入/删除 `editor_level_migration_version`，并把 `block_pallette_checksum` 清 0 |
| `start_game_zero_checksum` | 仅清 `block_pallette_checksum` |
| `add_player_passenger` | AddPlayer 在 `device_id` 前插入/删除 `passenger_of_block` |
| `level_chunk_skeleton` | LevelChunk 切换 skeleton 模式 / 删除尾部 `client_biome_update` |
| `player_list_fab` | PlayerList 的 `play_fab_id` 迁移 |
| `client_cache_force_off` | c2s `client_cache_status` 强制 false |
| `camera_presets_strip` | 为 2169 及更老客户端裁掉 CameraPresets 尾部字段 |
| `boss_event_to_2169` / `boss_event_to_2193` | boss_event 的 `player_id`（仅 add/remove 事件带） |
| `play_sound_to_2169` / `play_sound_to_2193` | play_sound 尾部新增字段（`bypass` / `playback_position`） |
| `pack_setting_change_guard` | serverbound_packet_setting_change type=3 的 string_list 守卫 |
| `transaction_to_2169` / `transaction_to_2193` | inventory_transaction 内层 item descriptor 重排 |
| `player_auth_input_to_2193` | 2169 `input_data` 列表 → 2193 数组，deprecated 2/54/55 过滤 |
| `item_stack_response_to_2169` | item_stack_response 容器结果/物品栈字段重排 |
| `subchunk_to_2169` | 子区块高度图行格式 + 子区块版本 |
| `move_entity_delta_strip_ticks` | 删除尾部 `ticks` varint |
| `dimension_data_to_2169` / `dimension_data_to_2193` | 维度字段差异 |

## 安全

- 加载期校验：`ptlApi`、`pair`、包 ID、规则类型、hex、`skip` token、builtin 名字，任一失败拒绝该模块。
- 运行期每条规则都做偏移/长度边界检查；失败即**丢弃该包**（fail-closed），并记日志，
  不把服务端格式原样发给对端客户端（否则对端会以 BadPacket / InitialConnection-90 断开）。
- 对称规则首次命中做 A→B→A 往返自检，失败即禁用该包规则并丢包。
- 所有解析都在 `try` 内，异常退化为「不翻译」。

## 新增一个版本对

1. 新建 `PTL/<a>-<b>.json`，写 `ptlApi: 1` 与 `pair`。
2. 对称差异用 `rules` + `addedIn`；不对称差异用 `overrides` 分方向。
3. 需要整包重编码时用 `builtin`，且必须先在引擎里实现并登记名字。
4. `build.bat` 重建 `JERCPLD.PTL.dll`。
5. 用引擎仓 `tools/verify-client` 的模拟客户端跑该版本回归，并抓包核对字段。
