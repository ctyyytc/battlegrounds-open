# 外部内容包 v2

主菜单点击“资源包”→“安装资源包…”，选择包目录中的 `pack.json`。系统校验并复制 JSON 和引用图片到当前应用的私人资源目录，成功后立即更新菜单与描述。点击“卸载并恢复默认”即可恢复默认名称、文字、数值和占位图；安装副本被移除，导入来源目录保留，可重新安装。无须手动改工程配置。安装失败会保留此前内容。切换仅能在主菜单进行，旧存档保留并继续核对数值身份。

程序把安装内容放在独立的 `user://resource_packs/`，与对局存档分开；卸载不会删除 `open_save.json` 或来源包。本工程没有默认随附包；未安装时使用中性占位内容。命令行 `--resource-pack` 优先级最高，使用该参数时界面会提示先移除参数再切换。

默认不读取源码目录中的任何资源包。推荐在游戏内选择工程外的 `pack.json` 安装；高级用法可启动时在 `--` 后传入 `--resource-pack=绝对路径`。只加载 JSON 和本地图片；通过界面安装/卸载立即生效；直接修改包文件后需重启或重新安装。

未提供包时仍可开局：英雄30血/0甲，酒馆法术2币，大小饰品均2币，普通随从1/1，明确定义的金色随从2/2；6个未实现依赖仅把既有非空基础属性设为1/1，空值保留。编号、效果、英雄技能费用、本数、资格、卡池、任务目标和全局规则由代码负责。

```json
{
  "schema_version": 2,
  "definitions": {
    "BG20_HERO_101": {"name": "示例英雄", "health": 35, "armor": 4},
    "BG28_503": {"name": "示例法术", "text": "自行撰写的说明", "cost": 3},
    "BG25_001": {"attack": 2, "health": 3}
  },
  "assets": {"BG20_HERO_101:portrait:normal:neutral": "images/portrait.svg"},
  "templates": {"content.BG28_503.body": "{name}：当前费用 {effective_cost}；{status}"},
  "phrases": {},
  "ui": {},
  "terms": {}
}
```

图片与资源包单独提供或自行准备；本工程不附示例包、原版图文、原值还原包或下载地址。

| 区域 | 可填写内容 | 契约 |
| --- | --- | --- |
| definitions | 名称、静态说明、允许的基础数值 | `resource_contract/fields.json`，按ID逐字段白名单 |
| assets | 肖像、卡面、边框及其它界面图片的包内相对路径 | `resource_contract/images.json` |
| templates | 按ID的body/compact/status/condition动态模板 | `resource_contract/fields.json` |
| phrases | 已有计算分支使用的说明片段 | `resource_contract/phrases.json` |
| ui | 通用按钮、提示、状态格式 | `content/packs/resource_schema.json` 的ui |
| terms | 逻辑种族/关键词编号对应的显示用语 | 同上terms；不会更改机制编号 |

数值必须为范围内整数，0是合法的费用/攻击/护甲，生命必须大于0；布尔、字符串和小数不作为整数。英雄生命1～1000、护甲0～1000，价格0～100，随从攻击0～1000000、生命1～1000000。未填写字段使用默认值；非法定义整行忽略并给出诊断，其它合法行仍可用。非法根结构整包回退。`schema_version: 1` 继续支持原有名称/文字/图片/片段，不能导入基础数值。

图片只接受PNG/JPG/WebP/SVG；路径相对pack.json，不接受网络、绝对路径、上级路径或符号链接。缺图使用自制占位；存在但无法解码的图像同样回退。

动态模板使用 `{参数名}`，字面大括号写 `{{`、`}}`。常用参数为 `name`、`attack`、`health`、`base_attack`、`base_health`、`base_cost`、`effective_cost`、`progress`、`threshold`、`remaining`、`round`、`used`、`status`、`generated`；`card.<字段>`、`player.<字段>`、`effect.<序号>.<字段>` 的允许名称见契约。参数来自实际局面；费用折扣不由文字计算。`generated` 是现有计算分支输出，可用phrases定制其措辞。

只提供静态text时，计算分支及独立状态仍保留。提供body模板时，未放入`{status}`会自动补状态；需要完整原有计算信息时加`{generated}`。`content.<ID>.status`可定制状态行。`beetle.summon`使用count/attack/health，`status.remaining`使用remaining。无法解析、含未知参数或当前场景缺少参数时，使用计算回退。模板是单次代入，名称中的大括号不会再次解释。

phrases/ui/terms使用契约规定的格式参数，保留`%d`、`%s`等顺序和类型；不匹配则回退。空白模板与片段保留默认显示。不要从说明文字反推属性、效果或进度。

需要自行制作包时，先运行 `python tools/resource_pack.py template --output 工程外的私人目录`，得到默认数值、空文字键及图片/字段需求；填写后运行 `python tools/resource_pack.py check --pack 私人目录/pack.json`。工具只做本地读写，不下载资源，不覆盖已有模板。检查结果列出错误及已填写覆盖数，不要求一次填齐全部资源。模板只在指定的外部目录生成，不随本源码分发。

数值包会影响对局身份：只改文字/图片可继续同数值档；改变任何允许的基础数值后，旧档返回`NUMERIC_PROFILE_MISMATCH`，请新开局。旧版没有数值身份的档仍按内容哈希检查，不冒险套用。

资源包、安装副本与玩家档均不应复制到源码目录或源码归档中。

## 空文字与留空图片

v2中未提供text字段沿用默认说明；显式text为空字符串会保留空说明，null按空字符串显示。生成模板不预填text，避免无意清空。v1空文字仍按原兼容规则回退。assets的值可以为null，表示这一项故意不提供纹理，使用原有程序绘制或留空；省略键则继续使用内置占位。安装时null图片不复制文件，其它路径仍严格校验。

资源包始终保存在本工程外；安装副本和来源包均不进入PUBLIC_FILES或公开副本。资源包目录包含相对路径图片即可独立迁移，不依赖原工程仍在原位置。


## 内置界面与资源覆盖

`assets/` 仅包含项目自制占位图、按钮、面板、图标和特效，不是可安装资源包，不含原版卡图。图片和文字包通过既有资源键覆盖；显式null停用相应图片，省略键保持内置占位。`assets/ui/runtime21/CONSUMER_MAP.json` 列出特效组件的consumer_key；资源包只改变展示或白名单基础数值，不导入脚本和玩法实现。
