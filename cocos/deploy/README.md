# StartX 网页发布

2026-10-25 发布 `20261025-startx-music-crayon-01`，源码提交 `f5a4347`：开始页循环播放 Theme，开始或继续游戏后切换 BGM1；统一界面蜡笔边框，修复侧边标签接缝，标签与面板描边均为 1.8px；竖屏标签宽 28px、面板占屏宽 2/5。同步当前月末结算和付款动画，移除现金提示中的扣款顺序说明。复用已验证构建，956 个文件逐一校验后原子交换目录；上一版保存在该发布目录的 `previous-startx/`。公网入口、主脚本和三份音乐文件与构建一致，线上音乐和竖屏界面核验通过，官网首页未变。记录见 `review/deployment-music-crayon-verification.json`。

线上地址：https://www.iambrizo.com/startx/ 。`/startx` 自动重定向到带斜线的地址，游戏资源沿子目录加载。

2026-10-25 发布 `20261025-startx-office-crayon-01`，源码提交为 `4a10bf9`：开始页使用办公室望向纽约的手绘窗景，移除人物、金币和星星，按钮改用蜡笔描边与浅灰涂抹阴影；同步卡包曲面、侧栏分组和固定提示字号。复用已验证构建，954 个文件校验后原子切换，上一版保存在该发布目录的 `previous-startx/`。公网入口和主脚本与本地构建一致，官网首页保持原样。发布记录见 `review/deployment-office-crayon-verification.json`。

2026-10-25 按请求重新发布 `20261025-startx-republish-01`：复用提交 `766cfe3` 对应的已验证构建，945 个文件逐一校验后原子切换，保留上一版以便回退。当前游戏功能和浏览器独立存档保持原样，主站首页未改。公网入口、主脚本和卡背网页图标与本地构建一致，记录见 `review/deployment-republish-verification.json`。

2026-10-25 发布 `20261025-startx-operations-logo-01`：文书可零收益回收，供应链组建、交易和生产等经营提示由创始人气泡说出；卡牌属性和 flavor 留在底栏，发展里程碑通知保持独立。同步第二版 Logo、新卡背与翻转投影修复。子站通过相对路径设置卡背 favicon 和 Apple 图标，主站图标不变。945 个文件校验后原子替换，上一版保存在该发布目录的 `previous-startx/`；浏览器存档格式未变。验证记录见 `review/operation-speech-icon-verification.json` 和 `review/deployment-operations-logo-verification.json`。

2026-10-25 发布 `20261025-startx-view-shadows-01`：卡牌、棋盘卡包、创始人气泡、侧边标签和开始页按钮的现有阴影改为共用视角光源，在各自平面投影，随位置、缩放和卡牌抬起、转动更新。顶部一排卡包保持原样。类型检查、完整构建、横竖屏验证通过；944 个文件校验后原子替换，官网首页保持不变，上一版保存在该发布目录的 `previous-startx/`。存档格式和保存位置沿用原有设置。核验记录见 `review/view-shadows-verification.json` 与 `review/deployment-view-shadows-verification.json`。

2026-10-25 发布 `20261025-startx-ui-saves-01`：同步当前卡牌、供应链、奖励礼包和横竖屏界面；奖励礼包使用黑色纹理与 3 颗随机闪星，暂停图案为 38.88 像素，从开始页进入游戏默认运行。复用已验证的最新构建，944 个文件逐一校验后原子替换游戏目录，官网首页哈希保持不变；上一版保存在 `/srv/brizo-landing/releases/20261025-startx-ui-saves-01/previous-startx/`。

存档按浏览器独立保存，无需注册，不上传服务器。已用两个独立浏览器环境验证：分别保留第 7 月／账户 45 和第 3 月／账户 50，刷新后恢复各自进度，互不覆盖。使用相同设备和浏览器可继续；换浏览器、换设备或清除网站数据后使用新的存档。发布核验见 `review/deployment-current-20261025-verification.json`，独立存档核验见 `review/deployment-browser-saves-verification.json`。

运行 `npm run build:web` 会生成 `build/web-mobile/`，并通过 `tools/brand-web.cjs` 应用原游戏的 FrankFromFuture 猫咪启动图，关闭默认 Cocos 启动画面。启动图从网页首次加载显示到游戏资源准备完成，游戏内不再显示原布置桌面的加载文字。

2026-10-23 发布版本为 `20261023-startx-01`，沿用 Brizo 项目已有的服务器身份；本项目不保存登录凭据。游戏位于服务器 `/srv/brizo-landing/current/startx/`，归档和逐文件 SHA-256 清单位于 `/srv/brizo-landing/releases/20261023-startx-01/`。上传后先在临时目录校验全部 780 个文件，再原子移动到游戏目录；未重启网站、订阅和同步服务。

后续更新仅替换 `startx/` 下的游戏文件。若官网切换到新的发布目录，须同时保留这份游戏目录。线上验证记录见 `review/deployment-verification.json`；官网首页哈希与发布前一致，订阅健康端点 GET 仍返回预期的 405。

2026-10-24 修复版本 `20261024-startx-render-01`：修正手机安全区的坐标单位、棋盘与滑动卡牌及战斗区域的遮挡顺序，并在菜单切换或窗口变化前结束上一帧的模糊截图，恢复主相机。保留原存档格式。上一版游戏目录保存在该发布目录的 `previous-startx/`，可用于回滚。Android 浏览器标识、DPR 3 的验证脚本为 `node tests/online-rendering.cjs`；可用 `STARTX_TEST_URL` 指向线上、`STARTX_TEST_LAYOUT=square` 仅运行一个窗口布局。验证记录在 `review/online-rendering-verification.json`。

2026-10-24 视觉版本 `20261024-startx-visual-01`：发布三组淡色卡面、粗蜡笔边框、创始人幻彩外圈与同色侧面，以及边缘卡包的半透明显示。商业模式和公司任务标签使用原细实线边框。复用已验证的网页构建，877 个文件经 SHA-256 校验后原子替换；上一版保存在 `/srv/brizo-landing/releases/20261024-startx-visual-01/previous-startx/`。公网入口和主脚本与本地构建一致，官网首页哈希保持不变。刷新后的效果见 `review/published-startx-visual.png`，发布记录见 `review/deployment-visual-verification.json`。

2026-10-24 分类配色版本 `20261024-startx-palette-01`：按指定的七组颜色更新卡面，标题和圆圈共用强调色；现金、账户和应收尾款增加流动高光，数字贴片与卡面使用相同的高光坐标。保留粗蜡笔边框、创始人幻彩和标签细线边框。产品、其余工具、订单与客户事件暂沿用原底色。877 个文件校验通过后原子替换，上一版保存在该发布目录的 `previous-startx/`。公网入口和主脚本与本地构建一致，线上页面已刷新。发布记录见 `review/deployment-palette-verification.json`，分类与贴片核验见 `review/category-palette-verification.json`。

2026-10-24 完整配色版本 `20261024-startx-palette-02`：补齐产品暖橙、工具／课程棕褐、订单草绿、客户事件粉紫，全部 66 张卡牌均有分类配色。现金与账户的暖金浮光更宽、更亮，并随画面位置变化；黑色笔触和数字贴片保持清晰、同步。固定动画时间后平移画面，已核对浮光产生变化及账户 30 → 29 的贴片衔接。877 个文件校验后原子替换，公开入口与主脚本匹配本地构建，线上页面已刷新并恢复存档。上一版保存在该发布目录的 `previous-startx/`，核验记录见 `review/deployment-complete-palette-verification.json` 与 `review/complete-palette-verification.json`。

2026-10-24 发布 `20261024-startx-founder-speech-01`：新增跟随创始人的立体纸片对话气泡，入场邀请与新达成里程碑祝贺；“公司任务”改为“发展里程碑”。已校验 877 个发布文件，公网入口与主脚本哈希一致，并刷新线上页、继续已有存档确认邀请气泡与新标签可见。原版保留在该发布目录的 `previous-startx/`；核验记录见 `review/deployment-founder-speech-verification.json` 与 `review/founder-speech-verification.json`。

2026-10-24 发布 `20261024-startx-speech-crayon-01`：气泡去掉称呼，按文字自适应大小，从卡面中心圆圈处放大升至上方；使用黑色蜡笔描边、深灰粗糙涂抹阴影，点击外部取消当前和待播台词并保留原点击操作。类型检查和脚本构建通过，入场动画、文字自适应、内外点击、里程碑台词已核对。877 个发布文件校验通过，公网入口和主脚本哈希与本地构建一致，线上刷新后继续存档确认新效果。旧版保留在该发布目录的 `previous-startx/`；核验记录见 `review/deployment-speech-crayon-verification.json` 和 `review/speech-crayon-verification.json`。

2026-10-24 发布 `20261024-startx-speech-compact-01`：气泡字号从 20 调至 18，收紧文字留白，常用台词气泡从 212×59 缩为 187×51；出场起点改到牌面上方，仅轻微上浮。类型检查与脚本构建通过，入场位置及里程碑台词核验通过。877 个发布文件校验通过，公网入口与主脚本哈希一致；已刷新线上并继续已有存档确认效果。旧版保留在发布目录的 `previous-startx/`。记录见 `review/deployment-speech-compact-verification.json` 和 `review/speech-compact-verification.json`。

2026-10-24 发布 `20261024-startx-speech-shadow-01`：气泡阴影偏移由 (6, -8) 缩为 (2.5, -3.5)，基础透明通道由 222 降至 96；外缘采用平稳轮廓，蜡笔涂抹感移至内部的半透明笔触和纸纹。类型检查、脚本构建、入场气泡与开包里程碑气泡的视觉核验通过。877 个文件校验通过，公网入口和主脚本哈希一致，已刷新线上并继续存档确认。旧版保留在发布目录的 `previous-startx/`；记录见 `review/deployment-speech-shadow-verification.json` 和 `review/speech-shadow-verification.json`。

2026-10-24 发布 `20261024-startx-notebook-frame-01`：气泡蜡笔描边由 4.4 调至 3.2，发展里程碑标签加长约 16 像素，内容窗口上下各延伸约 24 像素，右上与右下圆角和标签共用比例。修正窗口同时给两个标签留口、非活跃标签缺少左边线的问题；仅活跃接合处开口，其余边框闭合，端点精确对齐。类型检查与脚本构建通过，里程碑展开和商业模式切换已做几何与视觉核验。877 个发布文件校验通过；公网短暂超时后已恢复，入口和主脚本哈希与构建一致，重新打开线上并继续已有存档确认效果。旧版保留在发布目录的 `previous-startx/`；记录见 `review/deployment-notebook-frame-verification.json` 和 `review/notebook-frame-verification.json`。

2026-10-24 发布 `20261024-startx-blind-backdrop-01`：标签展开、菜单和图鉴的背景改为横向百叶窗样式，浅黑与浅灰半透明条带交错，每条约 28 像素，保留高斯模糊底图。类型检查与完整构建通过，标签展开、切换及图鉴显示核验通过。877 个发布文件校验通过，公网入口、主脚本和编译后的背景着色器哈希与构建一致，已刷新线上并继续已有存档确认新效果。旧版保留在发布目录的 `previous-startx/`；记录见 `review/deployment-blind-backdrop-verification.json` 和 `review/blind-backdrop-verification.json`。

2026-10-24 发布 `20261024-startx-soft-blinds-01`：百叶窗条带由 28 像素收细至 18 像素，深浅条带的染色不透明度由 24%／22% 降至 14%／12%，并拉近黑灰色值。深色边缘改为宽而柔和的过渡，加入细微静止磨砂颗粒；保留高斯模糊，并让浅色叶片透出略多细节。类型检查与完整构建通过，棋盘遮罩渲染捕获、图鉴视觉及线上展开效果已核验。877 个文件校验通过，公网入口、主脚本、编译后的磨砂背景着色器哈希与构建一致。旧版保留在发布目录的 `previous-startx/`；记录见 `review/deployment-soft-blinds-verification.json` 和 `review/soft-blinds-verification.json`。
