# StartX 网页发布

线上地址：https://www.iambrizo.com/startx/ 。`/startx` 自动重定向到带斜线的地址，游戏资源沿子目录加载。

运行 `npm run build:web` 会生成 `build/web-mobile/`，并通过 `tools/brand-web.cjs` 应用原游戏的 FrankFromFuture 猫咪启动图，关闭默认 Cocos 启动画面。启动图从网页首次加载显示到游戏资源准备完成，游戏内不再显示原布置桌面的加载文字。

2026-10-23 发布版本为 `20261023-startx-01`，沿用 Brizo 项目已有的服务器身份；本项目不保存登录凭据。游戏位于服务器 `/srv/brizo-landing/current/startx/`，归档和逐文件 SHA-256 清单位于 `/srv/brizo-landing/releases/20261023-startx-01/`。上传后先在临时目录校验全部 780 个文件，再原子移动到游戏目录；未重启网站、订阅和同步服务。

后续更新仅替换 `startx/` 下的游戏文件。若官网切换到新的发布目录，须同时保留这份游戏目录。线上验证记录见 `review/deployment-verification.json`；官网首页哈希与发布前一致，订阅健康端点 GET 仍返回预期的 405。

2026-10-24 修复版本 `20261024-startx-render-01`：修正手机安全区的坐标单位、棋盘与滑动卡牌及战斗区域的遮挡顺序，并在菜单切换或窗口变化前结束上一帧的模糊截图，恢复主相机。保留原存档格式。上一版游戏目录保存在该发布目录的 `previous-startx/`，可用于回滚。Android 浏览器标识、DPR 3 的验证脚本为 `node tests/online-rendering.cjs`；可用 `STARTX_TEST_URL` 指向线上、`STARTX_TEST_LAYOUT=square` 仅运行一个窗口布局。验证记录在 `review/online-rendering-verification.json`。
