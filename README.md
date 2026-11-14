# JERCPTL

JERCPLD 的 **PTL 规则模块**（Packet Translation Language）独立仓库。

本仓只产出一个文件：`JERCPLD.PTL.dll`。它是纯数据模块——内嵌 `PTL/*.json` 规则，经 5 个 C ABI
导出交给引擎（[JERC-STUDIO/JERCPLD](https://github.com/JERC-STUDIO/JERCPLD)）。翻译执行、边界检查、
越界回滚、A→B→A 自检、链式路由、连接调度全部在引擎里，本仓不链接 LeviLamina / BDS。

## 目录

```
build.bat                 MSVC 构建入口（只需 VS Build Tools，无需 LeviLamina）
gen-ptl-header.ps1        把 PTL/*.json 内嵌成 build/generated/ptl_rules_generated.h
src/JERCPLD.PTL.cpp       仅包含 5 个 extern "C" 导出
PTL/2168-2169.json        2168 ↔ 2169（两版包集合一致，只用于链式路由）
PTL/2169-2193.json        2169 ↔ 2193
PTL/2193-2225.json        2193 ↔ 2225（26.50/26.51 服务端 ↔ 26.60–26.62 客户端）
docs/PTL_FORMAT.md        规则 JSON 格式（ptlApi / pair / rules / overrides / builtin）
```

## 构建

```bat
build.bat
```

产物：`build\JERCPLD.PTL.dll`。

- 不需要 LeviLamina 头文件或导入库；
- 新增规则文件后重跑即可，`gen-ptl-header.ps1` 会按文件名重新内嵌全部 `PTL/*.json`；
- 构建期校验：缺 `pair`、规则里出现 `)PTLJSON"` 终止符、`PTL/` 为空，直接失败。

## 安装

由引擎仓的安装脚本带上本模块：

```powershell
<JERCPLD>\mod\JERCPLD.Mod\install.ps1 -ServerDir <服务器目录> -PtlDll <本仓>\build\JERCPLD.PTL.dll
```

安装位置：`plugins/JERCPLD/PTL/JERCPLD.PTL.dll`。引擎启动时加载、解析后立即 `FreeLibrary`；
模块缺失或无效时退回读取同目录 `PTL/*.json`（兼容模式），两者都不可用则翻译能力为空、服务端继续运行。

## C ABI（固定 5 个导出，全部 `extern "C"`）

```c
uint32_t    jercpld_ptl_api_version(void);          // 当前为 1
uint32_t    jercpld_ptl_pair_count(void);
const char* jercpld_ptl_pair_name(uint32_t index);  // "2193-2225"
const char* jercpld_ptl_pair_rules(uint32_t index); // NUL 结尾的 JSON
int         jercpld_ptl_self_check(void);           // 0 = OK
```

不导出 C++ 类、不跨边界传 STL。引擎只接受 `api_version == 1` 的模块。

## 内置能力（builtin）

结构性重写（重新解析/编码整包）由引擎实现，规则文件只能按名字引用，名字写错会在加载期被拒绝。
名单以引擎 `isKnownBuiltin()` 为准，见 [docs/PTL_FORMAT.md](docs/PTL_FORMAT.md#builtin)。

## 支持范围

| 客户端 | 协议 | 服务端 26.50/26.51（协议 2193） |
| --- | --- | --- |
| 26.40 / 26.43 / 26.44 | 2168 | 两跳 2168→2169→2193 |
| 26.45 | 2169 | 一跳 2169↔2193 |
| 26.60 – 26.62 | 2225 | 一跳 2193↔2225 |

26.30 及更老客户端只支持 RakNet 传输，与本服务端的 NetherNet 互斥，不在支持范围。

## 许可

Apache License 2.0，见 [LICENSE](LICENSE)。
