# 卡牌数据源

修改 `startx_data.xlsx` 后，在 `cocos/` 目录执行 `npm run build:web` 或 `npm run build:wechat`。构建会先校验表格，再生成游戏数据、卡面、数字贴片和配方图标。Excel 内容没有变化时复用已有文件。

| 工作表 | 内容 |
| --- | --- |
| `cards` | 卡牌名称、类型、工资、产能、价值、成本、次数、生产时间和说明 |
| `recipes` | 配方输入、消耗数量、产出数量、员工条件、卡包归属 |
| `packs` | 卡包名称、价格、阶段、抽取数量和各候选卡牌的权重 |
| `tasks` | 任务名称、说明、目标、分组、排序和解锁卡包 |

`id` 用来关联卡牌、配方、卡包和存档，修改名称时保留原来的 `id`。`recipes` 每行会自动生成一张 `bm_<配方 id>` 商业模式卡。`maxUses` 支持固定值和 `3-5` 这样的范围；留空表示无限次。表内计算公式使用 Excel 保存的计算结果，修改后先让 Excel 完成计算再保存。

新增卡牌时，把透明插画放到 `art/cards/<卡牌 id>.png`，也支持 `.svg`；PNG 优先。新增卡包的插画放到 `art/packs/<卡包 id>.png`。商业模式卡共用 `art/cards/business_model.png`。生成的卡面在 `../assets/content/faces/`，卡包封面在 `../assets/content/packs/`，这两处会由构建更新。

`balance.json` 保存月末结算等全局数值，`research.json` 保存研发配置，`idea_pools.json` 保存想法池。字体、猫咪启动图和卡包纹理也保存在本目录，构建不依赖项目外的素材或字体安装。

Creator 编辑器内的普通构建通过项目扩展 `startx-data` 执行同样的同步。表格引用不存在的卡牌、重复 id、无效数量或缺少插画时，构建会给出具体位置并停止，保留上一份完整资源。
