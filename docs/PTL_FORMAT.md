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
| `ptlApi` | 规则 API 版本。当前接受 `1` / `2`；`2` 用于 `insertConst` / `deleteField` / `stripTrailing` / `arrayTransform` / `when`。不匹配直接拒绝加载。 |
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
| `insertField` | `addedIn`, `skip`(程序), `bytes` | 游标处插入；反向校验后删除（适合 `rules` 对称规则） |
| `insertConst` | `skip`(程序), `bytes` | 游标处**无条件**插入常量（适合 `overrides` 单向规则） |
| `deleteField` | `skip`(程序), `field` | 游标处删除一个指定类型的字段 |
| `stripTrailing` | `field`, `range` | 从包尾回扫一个值并删除；`range` 越界即失败 |
| `arrayTransform` | `count`, `element`, `requireEnd` | 读取长度前缀数组，按元素 read/drop/emit 重编码 |
| `enumRemap` | `skip`, `map` | 游标处 1 字节查表替换（只影响命中的值） |
| `zeroFixed` | `skip`, `zeros` | 游标处连续 N 字节清零 |
| `builtin` | `name` | 引用引擎内置的结构性重写（加载期校验名字） |
| `drop` | — | 该包在该方向直接丢弃（未实现安全翻译前） |

### 条件（`when`）

任意规则可加守卫，先按 `skip` 定位并读取一个字段，再判断谓词：

```json
"when": { "skip": ["var"], "field": "u8", "op": "in", "in": [0, 1] }
```

`op` 支持 `eq` / `ne` / `in` / `min` / `max`（`eq`/`ne`/`min`/`max` 用 `value`）。
谓词不满足时跳过该规则；守卫本身读失败则按规则失败处理（fail-closed）。

### 数组变换（`arrayTransform`）

```json
{
  "type": "arrayTransform", "count": "var", "requireEnd": true,
  "element": [
    { "op": "read", "name": "min_y", "type": "zigzag" },
    { "op": "drop", "type": "str" },
    { "op": "emit", "type": "zigzag", "expr": "min_y + height_range" },
    { "op": "emit", "type": "str", "ref": "generator",
      "map": { "3": "minecraft:nether_wastes" }, "default": "minecraft:plains" }
  ]
}
```

- `read` 绑定变量；`drop` 丢弃一个字段；`emit` 用 `const` / `ref` / `expr` / `map` 写出。
- 表达式只支持 int64 的 `+ - * /` 和括号，加载期校验变量引用。
- 字段类型：`var`、`u8`、`u16`、`i32`、`lf32`、`zigzag`、`str`、`nbt`、`optionalVar`、`fixed:N`；`emit` 另支持 `bytes`。

### 游标程序（`skip`）

按顺序把游标从包载荷起点移到目标字段，全程越界检查：

`var`、`u8`、`u16`、`i32`、`lf32`、`str`、`nbt`、`optionalVar`、`skip:N`、`marker:<text>`、`markerAny:<a>|<b>`

`marker:<text>` 用于定位带长度前缀的字符串（如 StartGame 的 `multiplayer_correlation_id`）：
引擎找到文本后按前置长度字节跳到字符串末尾，再继续后续 token。
`markerAny` 依次尝试多个 needle，用于同一包在不同传输层下的 marker（`<nethernet>` / `<raknet>`）。

## builtin

以下必须重新解析/重编码整包，由引擎实现；规则里只写名字，名字拼错会在**加载期**被拒绝。

| name | 说明 |
| --- | --- |
| `add_player_passenger` | AddPlayer 在 `device_id` 前插入/删除 `passenger_of_block`（双向） |
| `level_chunk_skeleton` | LevelChunk 切换 skeleton 模式 / 删除尾部 `client_biome_update` |
| `player_list_fab` | PlayerList 的 `play_fab_id` 双向迁移（record 级 ↔ Skin 内） |
| `player_skin_fab` | player_skin 的 Skin 内 `play_fab_id` 双向插入/删除 |
| `client_cache_force_off` | c2s `client_cache_status` 强制 false |
| `camera_presets_strip` | 为 2169 及更老客户端裁掉 CameraPresets 尾部字段 |
| `play_sound_to_2169` / `play_sound_to_2193` | play_sound 尾部新增字段（`bypass` / `playback_position`） |
| `pack_setting_change_guard` | serverbound_packet_setting_change type=3 的 string_list 守卫 |
| `transaction_to_2169` / `transaction_to_2193` | inventory_transaction 内层 item descriptor 重排 |
| `player_auth_input_to_2193` | 2169 `input_data` 列表 → 2193 数组，deprecated 2/54/55 过滤 |
| `item_stack_response_to_2169` | item_stack_response 容器结果/物品栈字段重排 |
| `subchunk_to_2169` | 子区块高度图行格式 + 子区块版本 |

> 2026-11-14 起，`start_game_editor_checksum`、`start_game_zero_checksum`、`boss_event_to_*`、
> `move_entity_delta_strip_ticks`、`dimension_data_to_*` 已迁出引擎，改由 schema v2 原语在 JSON 中表达。

## 安全

- 加载期校验：`ptlApi`、`pair`、包 ID、规则类型、hex、`skip` token、builtin 名字，任一失败拒绝该模块。
- 运行期每条规则都做偏移/长度边界检查；失败即**丢弃该包**（fail-closed），并记日志，
  不把服务端格式原样发给对端客户端（否则对端会以 BadPacket / InitialConnection-90 断开）。
- 对称规则首次命中做 A→B→A 往返自检，失败即禁用该包规则并丢包。
- 所有解析都在 `try` 内，异常退化为「不翻译」。

## 新增一个版本对

1. 新建 `PTL/<a>-<b>.json`，写 `ptlApi: 2` 与 `pair`。
2. 对称差异用 `rules` + `addedIn`；不对称差异用 `overrides` 分方向。
3. 优先用通用原语（`insertConst` / `deleteField` / `stripTrailing` / `arrayTransform` / `zeroFixed` / `when`）；
   需要整包重编码时才用 `builtin`，且必须先在引擎里实现并登记名字。
4. `build.bat` 重建 `JERCPLD.PTL.dll`。
5. 用引擎仓 `tools/verify-client` 的模拟客户端跑该版本回归，并抓包核对字段。

## 路由与跳数

- 引擎按已加载版本对自动建无向图，BFS 取最短链，**不设固定跳数上限**。
  新增一档只需注册相邻版本对，例如再注册 `2225-2240` 后，`2168 -> 2240` 会自动走 4 跳。
- 防环：BFS 的 `seen` 集合保证每个版本节点最多入队一次，路径长度天然 ≤ 节点数-1；
  同一版本对重复注册不会被采用为更短路径。
- 开销：每多一跳就多一次整包规则匹配（命中规则时才改写），
  每包成本约 `O(跳数 × 该包规则数)`；[CONN] 行与启动日志会打印实际路由链，
  `perfStatsEnabled` 打开后 PERF 汇总会给出每包平均跳数，便于评估新增档位的代价。

