# StartX · Cocos 卡牌棋盘

工程使用 Cocos Creator 3.8.8。打开本目录，进入 `assets/scenes/CardSample.scene`。卡牌数据源是 `data/startx_data.xlsx`；Excel、原始插画、字体和构建工具均保存在本工程内。

## 构建与数据修改

首次安装依赖后，直接构建即可自动同步 Excel 和卡面：

```sh
npm install
npm run build:web
npm run preview
```

访问 http://127.0.0.1:4173/ 。微信小游戏使用 `npm run build:wechat`，正式 AppID 可通过 `WECHAT_APPID` 环境变量传入。Creator 安装位置不同时，将 `COCOS_CREATOR` 设为编辑器可执行文件路径。

`build:web` 和 `build:wechat` 都先读取 Excel 的 `cards`、`recipes`、`packs`、`tasks`，校验引用后生成 `assets/content/catalog.json`、全部卡面、卡包封面、数字贴片和配方图标。字体使用随工程提供的完整得意黑，新增中文名称也能显示。未修改的数据会复用已有产物。指定 `--scripts-only` 时，如果同步产生了资源修改，会自动改为完整构建。

Creator 项目扩展 `extensions/startx-data` 将同一同步入口接入编辑器构建。重新打开工程后，普通构建会先同步并刷新资源。扩展配置见 [Cocos 构建扩展文档](https://docs.cocos.com/creator/3.8/manual/en/editor/publish/custom-build-plugin.html)。命令行构建独立执行同步，即使未打开编辑器也能使用。

数据位置与字段用法见 [数据说明](data/README.md)。只想更新编辑器预览中的卡面时，可运行 `npm run sync:data`。新增卡牌插画放到 `data/art/cards/<id>.png`，新增卡包插画放到 `data/art/packs/<id>.png`，也支持 SVG。商业模式卡随配方自动生成。

Excel 中的卡牌数值、名称、说明、配方和卡包配置由构建同步。特殊能力和交互逻辑在 `assets/scripts/GameModel.ts` 等脚本中修改。

## 游戏与资源

游戏包含可平移、缩放的 30×30 格棋盘，外围为城市背景。支持触屏拖放、双指缩放、卡包抽取、生产配方、账户、供应链、月末结算和商战。默认测试模式提供一个余额为 50 的账户；在设置中关闭后重新开始，使用普通开局。月末先扣散装现金，再扣账户余额。

进度定时保存到浏览器本机存储，并在操作完成、页面隐藏及退出时补存。重新进入后点击“继续创业”，恢复棋盘、卡牌、账户和进行中的生产或战斗。数据更新沿用现有存档格式；新增卡牌使用新的唯一 id。

长按卡牌打开可翻转的立体预览，资料区展示功能、说明、产出配方和来源卡包。配方图标可继续进入对应卡牌预览。图鉴展示已解锁卡面和未解锁卡背，支持稀有度、类型、名称排序。设置与图鉴使用模糊背景，深夜加班模式会保留创始人周围的柔边光圈。

`assets/` 是 Creator 资源，`data/` 是编辑用数据和素材，`tools/` 是构建工具。生成卡面沿用黑色圆角框、分类色、原插画和数字角标；卡牌厚度、光照与现金玻璃效果由运行时材质处理。网页启动显示 FrankFromFuture 猫咪 Logo。

## 验证与发布

```sh
npm run typecheck
npm run test:data
npm run test:rules
npm run test:progress
# 预览服务器启动后：
node tests/online-rendering.cjs
```

`test:data` 在临时副本中修改 Excel，核对数据和图片一起更新、新卡牌资源生成、重复构建复用资源，以及无效引用停止构建。不会修改正式表格。

网页地址：https://www.iambrizo.com/startx/ 。本地构建不会自动发布，发布方式见 [部署说明](deploy/README.md)。
