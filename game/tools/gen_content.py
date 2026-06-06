#!/usr/bin/env python3
"""Generate the full multi-stage business economy -> cards.json / recipes.json / packs.json.
Original business-themed crafting tree (not a transliteration). Production model:
  recipe.duration = 产能槽(工作量); recipe.worker_tags = 对口工种;
  card.capacity = 产能 = 每秒工作速率 + 商战攻击力(双用).
Preserves ids the engine hardcodes: cash/revenue/founder/office/business_school/patent/
research_bench/lead/data/prd/training.
"""
import json, os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DATA = os.path.join(ROOT, "data")

cards = {}
recipes = []
packs = {}


def C(cid, name, ctype, cap=0, sal=0, sell=0, tags=None, maxUses=None, hp=None, atk=None):
    d = {"name": name, "type": ctype, "salary": sal, "capacity": cap, "sell": sell}
    if tags:
        d["workTags"] = tags
    if maxUses is not None:
        d["maxUses"] = maxUses
    if hp is not None:
        d["hp"] = hp
    if atk is not None:
        d["attack"] = atk
    cards[cid] = d


def R(rid, name, inp, out, dur, tags=None, idea=None):
    # inp/out: list of (id, count, consume?) ; out consume ignored
    rc = {"id": rid, "name": name, "worker_tags": tags or ["any"], "duration": float(dur),
          "inputs": [{"id": i[0], "count": i[1], "consume": (i[2] if len(i) > 2 else True)} for i in inp],
          "outputs": [{"id": o[0], "count": o[1]} for o in out]}
    if idea:
        rc["requiredIdeaId"] = idea
    recipes.append(rc)


def P(pid, name, stage, price, mn, mx, slots):
    packs[pid] = {"name": name, "stage": stage, "price": price,
                  "minCards": mn, "maxCards": mx,
                  "slots": [[{"id": s[0], "w": s[1]} for s in slot] for slot in slots]}


# ======================================================== 人（员工，产能=攻击）
C("founder", "创始人", "employee", cap=3, sal=1, tags=["sales", "dev", "admin", "market", "data", "finance", "any"])
C("intern", "实习生", "employee", cap=1, sal=1, tags=["any"])
C("grad", "毕业生", "employee", cap=2, sal=1, tags=["any"])
C("sales_mgr", "销售经理", "employee", cap=3, sal=2, tags=["sales", "any"])
C("market_mgr", "市场经理", "employee", cap=3, sal=2, tags=["market", "any"])
C("dev_mgr", "研发经理", "employee", cap=3, sal=2, tags=["dev", "any"])
C("admin_mgr", "行政经理", "employee", cap=3, sal=2, tags=["admin", "any"])
C("data_mgr", "数据经理", "employee", cap=4, sal=2, tags=["data", "any"])
C("finance_mgr", "财务经理", "employee", cap=3, sal=2, tags=["finance", "any"])
C("sales_dir", "销售总监", "employee", cap=6, sal=4, tags=["sales", "any"])
C("market_dir", "市场总监", "employee", cap=6, sal=4, tags=["market", "any"])
C("dev_dir", "研发总监", "employee", cap=6, sal=4, tags=["dev", "any"])
C("admin_dir", "行政总监", "employee", cap=6, sal=4, tags=["admin", "any"])
C("data_dir", "数据总监", "employee", cap=7, sal=4, tags=["data", "any"])
C("cto", "首席技术官", "employee", cap=10, sal=7, tags=["dev", "any"])
C("cmo", "首席营销官", "employee", cap=10, sal=7, tags=["market", "any"])
C("coo", "首席运营官", "employee", cap=10, sal=7, tags=["admin", "any"])
C("cfo", "首席财务官", "employee", cap=10, sal=7, tags=["finance", "any"])
C("growth_hacker", "增长黑客", "employee", cap=5, sal=3, tags=["market", "data", "any"])
C("architect", "架构师", "employee", cap=7, sal=5, tags=["dev", "any"])
C("legal", "法务", "employee", cap=4, sal=3, tags=["admin", "any"])
C("pr", "公关", "employee", cap=4, sal=3, tags=["market", "any"])
C("consultant", "顾问", "employee", cap=5, sal=4, tags=["any"])

# ======================================================== 技能包 / 课程（装上→经理）
C("sales_kit", "销售技能包", "skill")
C("market_kit", "市场技能包", "skill")
C("dev_kit", "研发技能包", "skill")
C("admin_kit", "行政技能包", "skill")
C("data_kit", "数据技能包", "skill")
C("finance_kit", "财务技能包", "skill")
C("exec_course", "高管课程", "skill")
C("growth_course", "增长课程", "skill")
C("architect_course", "架构课程", "skill")
C("resilience_course", "抗压课", "skill")
C("network", "人脉", "skill")

# ======================================================== 基础资源
C("cash", "现金", "resource", sell=0)
C("lead", "线索", "resource", sell=1)
C("customer_list", "客户名单", "resource", sell=2)
C("order", "订单", "resource", sell=3)
C("bigdeal", "大单", "resource", sell=8)
C("revenue", "营收", "resource", sell=12)
C("doc", "资料", "resource", sell=1)
C("code", "代码", "resource", sell=2)
C("module", "模块", "resource", sell=4)
C("prd", "技术方案", "resource", sell=2)
C("product", "产品", "resource", sell=8)
C("data", "数据", "resource", sell=1)
C("insight", "洞察", "resource", sell=3)
C("traffic", "流量", "resource", sell=1)
C("user", "用户", "resource", sell=2)
C("report", "报告", "resource", sell=4)
C("contract", "合同", "resource", sell=5)
C("proposal", "方案", "resource", sell=0)
C("patent", "专利", "resource", sell=0)
C("brand", "品牌", "resource", sell=0)
C("license", "牌照", "resource", sell=0)
C("training", "培训", "resource", sell=1)
C("market_report", "行业报告", "resource", sell=3)
C("equity", "股权", "resource", sell=0)

# ======================================================== 资源节点（深耕对象）
C("customer_pool", "客户资源", "resource_node", maxUses=4)
C("expo_booth", "展会摊位", "resource_node", maxUses=3)
C("app_store", "应用商店", "resource_node", maxUses=5)
C("oss_repo", "开源代码库", "resource_node", maxUses=6)
C("hot_topic", "热点话题", "resource_node", maxUses=3)
C("data_source", "数据源", "resource_node", maxUses=5)
C("archive", "文档库", "resource_node", maxUses=5)
C("capital_market", "资本市场", "resource_node", maxUses=4)
C("overseas", "海外市场", "resource_node", maxUses=4)
C("talent_pool", "人才市场", "resource_node", maxUses=3)
C("university", "大学", "resource_node", maxUses=4)
C("research_bench", "研发台", "resource_node")

# ======================================================== 设施
C("desk", "工位", "facility", sal=0)
C("office", "办公室", "facility", sal=1)
C("warehouse", "仓库", "facility", sal=1)
C("meeting_room", "会议室", "facility", sal=1)
C("training_center", "培训中心", "facility", sal=1)
C("pantry", "茶水间", "facility", sal=1)
C("biz_hall", "商务大厅", "facility", sal=1)
C("crm", "CRM系统", "facility", sal=1)
C("server", "服务器", "facility", sal=1)
C("data_center", "数据中心", "facility", sal=2)
C("business_school", "商学院", "facility", sal=2)
C("hq", "总部大楼", "facility", sal=3)

# ======================================================== 竞争对手（hp/攻击，商战为阶段3代码）
C("r_teashop", "巷口奶茶店", "rival", hp=3, atk=1)
C("r_printshop", "老李打印铺", "rival", hp=4, atk=1)
C("r_usedpc", "二手电脑城", "rival", hp=5, atk=2)
C("r_orange", "橙子科技", "rival", hp=8, atk=3)
C("r_whale", "蓝鲸网络", "rival", hp=10, atk=4)
C("r_elephant", "大象搬家", "rival", hp=9, atk=3)
C("r_headhunter", "猎头老张", "rival", hp=6, atk=2)
C("r_shadow", "影子公司", "rival", hp=7, atk=3)
C("r_trolls", "键盘侠联盟", "rival", hp=5, atk=2)
C("r_cosmos", "宇宙集团", "rival", hp=20, atk=7)
C("r_titan", "巨无霸控股", "rival", hp=25, atk=8)
C("r_devour", "吞天资本", "rival", hp=30, atk=10)

# ======================================================== 配方
# —— 招人 / 育人 ——
R("recruit_intern", "校招·招实习生", [("university", 1, False), ("cash", 1)], [("intern", 1)], 4, ["any"])
R("build_university", "拉母校关系", [("intern", 1)], [("university", 1)], 5, ["any"])
R("train_grad", "带教·转正", [("intern", 1), ("meeting_room", 1, False)], [("grad", 1)], 5, ["any"])
R("hire_grad", "人才市场·挖毕业生", [("talent_pool", 1, False), ("cash", 2)], [("grad", 1)], 4, ["admin", "any"])
# —— 毕业生 + 技能包 → 经理 ——
R("make_sales_mgr", "上岗·销售经理", [("grad", 1), ("sales_kit", 1)], [("sales_mgr", 1)], 3, ["any"])
R("make_market_mgr", "上岗·市场经理", [("grad", 1), ("market_kit", 1)], [("market_mgr", 1)], 3, ["any"])
R("make_dev_mgr", "上岗·研发经理", [("grad", 1), ("dev_kit", 1)], [("dev_mgr", 1)], 3, ["any"])
R("make_admin_mgr", "上岗·行政经理", [("grad", 1), ("admin_kit", 1)], [("admin_mgr", 1)], 3, ["any"])
R("make_data_mgr", "上岗·数据经理", [("grad", 1), ("data_kit", 1)], [("data_mgr", 1)], 3, ["any"])
R("make_finance_mgr", "上岗·财务经理", [("grad", 1), ("finance_kit", 1)], [("finance_mgr", 1)], 3, ["any"])
# —— 经理晋升总监 / C级 ——
R("promote_sales_dir", "晋升·销售总监", [("sales_mgr", 1), ("training", 1)], [("sales_dir", 1)], 6, ["any"])
R("promote_market_dir", "晋升·市场总监", [("market_mgr", 1), ("training", 1)], [("market_dir", 1)], 6, ["any"])
R("promote_dev_dir", "晋升·研发总监", [("dev_mgr", 1), ("training", 1)], [("dev_dir", 1)], 6, ["any"])
R("promote_admin_dir", "晋升·行政总监", [("admin_mgr", 1), ("training", 1)], [("admin_dir", 1)], 6, ["any"])
R("promote_data_dir", "晋升·数据总监", [("data_mgr", 1), ("training", 1)], [("data_dir", 1)], 6, ["any"])
R("make_cto", "聘任·CTO", [("dev_dir", 1), ("exec_course", 1)], [("cto", 1)], 10, ["any"])
R("make_cmo", "聘任·CMO", [("market_dir", 1), ("exec_course", 1)], [("cmo", 1)], 10, ["any"])
R("make_coo", "聘任·COO", [("admin_dir", 1), ("exec_course", 1)], [("coo", 1)], 10, ["any"])
R("make_cfo", "聘任·CFO", [("finance_mgr", 1), ("exec_course", 1)], [("cfo", 1)], 10, ["any"])
R("make_growth", "培养·增长黑客", [("market_mgr", 1), ("growth_course", 1)], [("growth_hacker", 1)], 7, ["any"])
R("make_architect", "培养·架构师", [("dev_mgr", 1), ("architect_course", 1)], [("architect", 1)], 8, ["any"])
R("make_legal", "招聘·法务", [("grad", 1), ("resilience_course", 1)], [("legal", 1)], 5, ["any"])
R("make_pr", "招聘·公关", [("market_mgr", 1), ("network", 1)], [("pr", 1)], 5, ["any"])
# —— 培训中心产技能包；商学院产高管课程 ——
R("make_sales_kit", "做销售技能包", [("training_center", 1, False), ("cash", 1)], [("sales_kit", 1)], 4, ["admin", "any"])
R("make_market_kit", "做市场技能包", [("training_center", 1, False), ("cash", 1)], [("market_kit", 1)], 4, ["admin", "any"])
R("make_dev_kit", "做研发技能包", [("training_center", 1, False), ("code", 1)], [("dev_kit", 1)], 4, ["admin", "any"])
R("make_admin_kit", "做行政技能包", [("training_center", 1, False), ("doc", 1)], [("admin_kit", 1)], 4, ["admin", "any"])
R("make_data_kit", "做数据技能包", [("training_center", 1, False), ("data", 1)], [("data_kit", 1)], 4, ["admin", "any"])
R("make_finance_kit", "做财务技能包", [("training_center", 1, False), ("report", 1)], [("finance_kit", 1)], 4, ["admin", "any"])
R("make_exec_course", "商学院·高管课程", [("business_school", 1, False), ("cash", 2), ("report", 1)], [("exec_course", 1)], 8, ["any"])
R("make_growth_course", "商学院·增长课程", [("business_school", 1, False), ("data", 2)], [("growth_course", 1)], 7, ["any"])
R("make_arch_course", "商学院·架构课程", [("business_school", 1, False), ("code", 2)], [("architect_course", 1)], 7, ["any"])
R("make_training", "组织内训", [("training_center", 1, False), ("doc", 1)], [("training", 1)], 4, ["admin", "any"])
R("make_resilience", "商学院·抗压课", [("business_school", 1, False), ("cash", 1)], [("resilience_course", 1)], 5, ["any"])
R("make_network", "攒人脉", [("expo_booth", 1, False), ("cash", 1)], [("network", 1)], 5, ["sales", "market", "any"])
# —— 经理深耕节点 → 资源（对口工种）——
R("gather_lead", "深耕·客户资源", [("customer_pool", 1, False)], [("lead", 1)], 3, ["sales", "any"])
R("gather_expo", "跑展会", [("expo_booth", 1, False)], [("lead", 1)], 3, ["sales", "any"])
R("gather_customer", "应用商店·拉新", [("app_store", 1, False)], [("customer_list", 1)], 4, ["market", "any"])
R("gather_traffic", "蹭热点·搞流量", [("hot_topic", 1, False)], [("traffic", 1)], 3, ["market", "any"])
R("gather_code", "开源社区·写代码", [("oss_repo", 1, False)], [("code", 1)], 3, ["dev", "any"])
R("gather_data", "数据源·采集", [("data_source", 1, False)], [("data", 1)], 3, ["data", "any"])
R("gather_doc", "文档库·整理资料", [("archive", 1, False)], [("doc", 1)], 3, ["admin", "any"])
R("gather_overseas", "出海·拿订单", [("overseas", 1, False)], [("order", 1)], 6, ["sales", "any"])
R("gather_capital", "资本市场·融资", [("capital_market", 1, False)], [("cash", 3)], 6, ["finance", "any"])
R("gather_report", "买行业报告", [("market_report", 1, False)] if False else [("data", 1), ("doc", 1)], [("market_report", 1)], 4, ["data", "admin", "any"])
# —— 食物链：线索→订单→大单→现金/营收 ——
R("make_order", "跟进成单", [("lead", 2)], [("order", 1)], 3, ["sales", "any"])
R("contract_deal", "签合同", [("order", 1), ("customer_list", 1)], [("contract", 1)], 4, ["sales", "any"])
R("make_bigdeal", "凑大单", [("order", 3)], [("bigdeal", 1)], 5, ["sales", "any"])
R("close_deal", "成交·现金", [("order", 1), ("biz_hall", 1, False)], [("cash", 2)], 3, ["sales", "any"])
R("close_big", "大单·回款", [("bigdeal", 1), ("biz_hall", 1, False)], [("revenue", 1)], 4, ["sales", "any"])
R("deliver", "交付·回款", [("contract", 1), ("product", 1)], [("revenue", 1)], 5, ["sales", "any"])
# —— 产品链：代码→模块→产品 ——
R("make_prd", "出技术方案", [("code", 1), ("data", 1)], [("prd", 1)], 4, ["dev", "any"])
R("make_module", "封装模块", [("code", 3)], [("module", 1)], 4, ["dev", "any"])
R("make_product", "做产品", [("module", 2), ("data", 1)], [("product", 1)], 8, ["dev", "any"])
R("make_insight", "数据→洞察", [("data", 2)], [("insight", 1)], 4, ["data", "any"])
R("make_user", "拉新增长", [("traffic", 1), ("product", 1)], [("user", 1)], 4, ["market", "any"])
R("make_report", "出报告", [("data", 1), ("doc", 1)], [("report", 1)], 4, ["data", "admin", "any"])
R("make_proposal", "写方案", [("prd", 1), ("insight", 1)], [("proposal", 1)], 5, ["sales", "dev", "any"])
R("win_bid", "投标·赢大单", [("proposal", 1), ("order", 1)], [("contract", 2)], 5, ["sales", "any"])
R("make_patent", "申请专利", [("product", 1), ("insight", 1)], [("patent", 1)], 8, ["dev", "any"])
R("make_brand", "打品牌", [("product", 1), ("user", 2)], [("brand", 1)], 8, ["market", "any"])
R("make_license", "办牌照", [("cash", 1), ("report", 1)], [("license", 1)], 4, ["admin", "any"])
R("make_equity", "释放股权", [("brand", 1), ("revenue", 1), ("license", 1)], [("equity", 1)], 10, ["finance", "any"])
# —— 盖设施（用材料建造）——
R("build_desk", "添工位", [("cash", 1), ("doc", 1)], [("desk", 1)], 3, ["admin", "any"])
R("build_office", "扩租办公室", [("desk", 2), ("cash", 1)], [("office", 1)], 5, ["admin", "any"])
R("build_warehouse", "建仓库", [("cash", 1), ("doc", 2)], [("warehouse", 1)], 5, ["admin", "any"])
R("build_meeting", "建会议室", [("desk", 1), ("cash", 1)], [("meeting_room", 1)], 4, ["admin", "any"])
R("build_pantry", "建茶水间", [("cash", 1), ("doc", 1)], [("pantry", 1)], 3, ["admin", "any"])
R("build_training", "建培训中心", [("cash", 2), ("doc", 1)], [("training_center", 1)], 6, ["admin", "any"])
R("build_bizhall", "建商务大厅", [("cash", 1), ("contract", 1)], [("biz_hall", 1)], 5, ["admin", "any"])
R("build_crm", "上CRM系统", [("code", 1), ("data", 1)], [("crm", 1)], 5, ["dev", "any"])
R("build_server", "买服务器", [("cash", 1), ("code", 1)], [("server", 1)], 5, ["dev", "any"])
R("build_datacenter", "建数据中心", [("server", 2), ("cash", 1)], [("data_center", 1)], 8, ["dev", "any"])
R("build_school", "建商学院", [("cash", 2), ("report", 2)], [("business_school", 1)], 10, ["admin", "any"])
R("build_hq", "盖总部大楼", [("office", 2), ("brand", 1)], [("hq", 1)], 12, ["admin", "any"])
# —— 节点开拓 ——
R("open_customer", "开拓客户资源", [("cash", 1), ("lead", 1)], [("customer_pool", 1)], 4, ["sales", "any"])
R("open_appstore", "上架应用商店", [("product", 1)], [("app_store", 1)], 5, ["market", "any"])
R("open_overseas", "拓展海外市场", [("cash", 2), ("brand", 1)], [("overseas", 1)], 8, ["sales", "any"])
R("open_datasource", "接入数据源", [("crm", 1, False), ("cash", 1)], [("data_source", 1)], 5, ["data", "any"])

# ======================================================== 卡包（分阶段）
P("garage_pack", "车库创业包", 0, 3, 3, 4, [
    [("intern", 50), ("grad", 30), ("cash", 20)],
    [("customer_pool", 40), ("oss_repo", 35), ("archive", 25)],
    [("sales_kit", 35), ("dev_kit", 35), ("doc", 30)],
    [("lead", 60), ("cash", 40)]])
P("hiring_fair", "招聘会包", 1, 5, 3, 5, [
    [("grad", 45), ("intern", 35), ("university", 20)],
    [("sales_kit", 25), ("market_kit", 25), ("dev_kit", 25), ("admin_kit", 25)],
    [("talent_pool", 40), ("meeting_room", 30), ("grad", 30)],
    [("data_kit", 50), ("finance_kit", 50)]])
P("channel_pack", "获客渠道包", 1, 6, 3, 5, [
    [("customer_pool", 30), ("app_store", 30), ("expo_booth", 40)],
    [("hot_topic", 40), ("lead", 60)],
    [("customer_list", 50), ("traffic", 50)],
    [("lead", 70), ("order", 30)]])
P("product_pack", "产品研发包", 2, 10, 3, 5, [
    [("oss_repo", 40), ("data_source", 35), ("research_bench", 25)],
    [("code", 50), ("data", 50)],
    [("module", 40), ("prd", 30), ("server", 30)],
    [("code", 60), ("product", 20), ("data", 20)]])
P("office_pack", "办公装修包", 2, 8, 3, 5, [
    [("desk", 50), ("office", 30), ("warehouse", 20)],
    [("meeting_room", 35), ("pantry", 35), ("training_center", 30)],
    [("crm", 50), ("server", 50)],
    [("doc", 60), ("cash", 40)]])
P("rival_pack", "商战来袭包", 3, 12, 3, 5, [
    [("r_teashop", 35), ("r_printshop", 35), ("r_usedpc", 30)],
    [("r_orange", 40), ("r_elephant", 35), ("r_headhunter", 25)],
    [("resilience_course", 40), ("legal", 30), ("pr", 30)],
    [("r_whale", 40), ("r_shadow", 35), ("r_trolls", 25)]])
P("data_pack", "数据增长包", 4, 16, 3, 5, [
    [("data_source", 40), ("data_mgr", 30), ("data_kit", 30)],
    [("data", 40), ("insight", 35), ("user", 25)],
    [("traffic", 40), ("growth_course", 30), ("growth_hacker", 30)],
    [("report", 50), ("crm", 50)]])
P("scale_pack", "规模扩张包", 5, 24, 4, 5, [
    [("sales_dir", 30), ("dev_dir", 30), ("market_dir", 40)],
    [("product", 40), ("brand", 30), ("hq", 30)],
    [("overseas", 50), ("data_center", 50)],
    [("exec_course", 40), ("architect", 30), ("consultant", 30)],
    [("module", 45), ("product", 45), ("r_cosmos", 10)]])
P("funding_pack", "融资轮包", 5, 34, 4, 5, [
    [("capital_market", 40), ("finance_mgr", 30), ("cfo", 30)],
    [("cash", 50), ("report", 50)],
    [("license", 40), ("market_report", 30), ("contract", 30)],
    [("equity", 45), ("brand", 45), ("r_titan", 10)]])
P("ipo_pack", "上市包", 6, 50, 4, 5, [
    [("hq", 30), ("brand", 35), ("equity", 35)],
    [("patent", 40), ("license", 30), ("market_report", 30)],
    [("cto", 25), ("cmo", 25), ("coo", 25), ("cfo", 25)],
    [("revenue", 45), ("product", 45), ("r_devour", 10)]])


# ======================================================== 校验
def validate():
    ids = set(cards.keys())
    errs = []
    produced = set()
    consumed = set()
    for r in recipes:
        for io in r["inputs"]:
            if io["id"] not in ids:
                errs.append("recipe %s input %s missing" % (r["id"], io["id"]))
            if io.get("consume", True):
                consumed.add(io["id"])
        for o in r["outputs"]:
            if o["id"] not in ids:
                errs.append("recipe %s output %s missing" % (r["id"], o["id"]))
            produced.add(o["id"])
    for pid, p in packs.items():
        for slot in p["slots"]:
            for s in slot:
                if s["id"] not in ids:
                    errs.append("pack %s slot id %s missing" % (pid, s["id"]))
    pack_ids = set()
    for p in packs.values():
        for slot in p["slots"]:
            for s in slot:
                pack_ids.add(s["id"])
    # resources consumed but never produced nor pack-dropped (excl. nodes/people/skills makeable)
    for cid in consumed:
        if cid in produced or cid in pack_ids:
            continue
        errs.append("DANGLING consumed-but-no-source: %s" % cid)
    return errs


errs = validate()
if errs:
    print("VALIDATION ERRORS:")
    for e in errs:
        print("  -", e)
else:
    json.dump(cards, open(os.path.join(DATA, "cards.json"), "w", encoding="utf-8"), ensure_ascii=False, indent=2)
    json.dump(recipes, open(os.path.join(DATA, "recipes.json"), "w", encoding="utf-8"), ensure_ascii=False, indent=2)
    json.dump(packs, open(os.path.join(DATA, "packs.json"), "w", encoding="utf-8"), ensure_ascii=False, indent=2)
    print("OK  cards=%d  recipes=%d  packs=%d" % (len(cards), len(recipes), len(packs)))
