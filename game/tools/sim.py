#!/usr/bin/env python3
"""StartX 卡牌经济模拟器 / Bug 扫描器（瞬时完成，不计工时与月份）。
忠实复现游戏的员工匹配规则（_recipe_matches）：配方 worker_tags 含 'any' 且有任意员工即通过，
否则需员工 workTags 命中。按阶段逐渐解锁卡包，做可达性推演，报告：
  - 永远拿不到的卡（孤儿）
  - 永远触发不了的配方（死配方，附缺失原因）
  - 没有任何员工能干的配方（工种缺口）
  - 创始人百搭性检查
  - 拿得到但无法与任何东西交互的卡（死胡同）
"""
import json, os

DATA = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "data")
cards = json.load(open(os.path.join(DATA, "cards.json"), encoding="utf-8"))
recipes = json.load(open(os.path.join(DATA, "recipes.json"), encoding="utf-8"))
packs = json.load(open(os.path.join(DATA, "packs.json"), encoding="utf-8"))

START = ["founder", "intern", "university", "office", "meeting_room",
         "customer_pool", "oss_repo", "sales_kit", "dev_kit", "cash"]

employees = [cid for cid, c in cards.items() if c.get("type") == "employee"]
nm = lambda cid: cards.get(cid, {}).get("name", cid) if cid in cards else f"<缺:{cid}>"


def emp_can_work(emp_id, r):
    rtags = r.get("worker_tags", [])
    if "any" in rtags:
        return True
    etags = cards.get(emp_id, {}).get("workTags", [])
    return any(t in rtags for t in etags)


def recipe_has_worker(r, reach):
    return any(e in reach and emp_can_work(e, r) for e in employees)


# ---------- 阶段逐渐解锁的可达性推演 ----------
reach = set(START)
unlock_log = []
for stage in range(7):
    for pid, p in packs.items():
        if int(p.get("stage", 0)) <= stage:
            for slot in p.get("slots", []):
                for opt in slot:
                    reach.add(opt["id"])
    changed = True
    while changed:
        changed = False
        for r in recipes:
            if not recipe_has_worker(r, reach):
                continue
            if all(inp["id"] in reach for inp in r.get("inputs", [])):
                for o in r.get("outputs", []):
                    if o["id"] not in reach:
                        reach.add(o["id"])
                        unlock_log.append((stage, r["id"], o["id"]))
                        changed = True

fired = []
dead = []
for r in recipes:
    has_w = recipe_has_worker(r, reach)
    miss_in = [inp["id"] for inp in r.get("inputs", []) if inp["id"] not in reach]
    if has_w and not miss_in:
        fired.append(r)
    else:
        reason = []
        if not has_w:
            reason.append("无任何对口员工(worker_tags=%s)" % r.get("worker_tags"))
        if miss_in:
            reason.append("缺输入: " + ", ".join("%s(%s)" % (nm(x), x) for x in miss_in))
        dead.append((r, " / ".join(reason)))

all_ids = set(cards.keys())
unreachable = sorted(all_ids - reach)

# 工种缺口：任何员工都干不了的配方（连"任意员工"都不行）
worker_gap = [r for r in recipes if not any(emp_can_work(e, r) for e in employees)]

# 创始人百搭检查
founder_tags = set(cards.get("founder", {}).get("workTags", []))
all_rtags = set()
for r in recipes:
    for t in r.get("worker_tags", []):
        all_rtags.add(t)
founder_missing_tags = sorted(t for t in all_rtags if t != "any" and t not in founder_tags)
# 哪些配方"若没有 any 兜底"创始人会干不了（=强依赖 any 的工种专属配方）
founder_blocked_if_no_any = []
for r in recipes:
    rt = r.get("worker_tags", [])
    if "any" in rt and not (founder_tags & set(t for t in rt if t != "any")):
        founder_blocked_if_no_any.append(r)

# 死胡同：拿得到但无法交互的卡（非员工/非对手；不作任何配方输入、不是任何配方的工位非消耗输入、不可卖）
used_as_input = set()
used_as_station = set()
for r in recipes:
    for inp in r.get("inputs", []):
        used_as_input.add(inp["id"])
        if not inp.get("consume", True):
            used_as_station.add(inp["id"])
deadend = []
for cid in sorted(reach):
    c = cards.get(cid, {})
    t = c.get("type")
    if t in ("employee", "rival"):
        continue
    sellable = int(c.get("sell", 0)) > 0
    if cid not in used_as_input and not sellable:
        deadend.append(cid)

rivals = [cid for cid, c in cards.items() if c.get("type") == "rival"]

# ---------------- 报告 ----------------
print("=" * 64)
print("StartX 模拟器报告  | 卡 %d  配方 %d  卡包 %d" % (len(cards), len(recipes), len(packs)))
print("可达卡: %d / %d   可触发配方: %d / %d" % (len(reach), len(cards), len(fired), len(recipes)))
print("=" * 64)

print("\n■ 永远拿不到的卡（孤儿，%d）" % len(unreachable))
for cid in unreachable:
    print("   - %s (%s)  type=%s" % (nm(cid), cid, cards[cid].get("type")))

print("\n■ 永远触发不了的配方（死配方，%d）" % len(dead))
for r, why in dead:
    print("   - %s [%s] → %s" % (r.get("name"), r["id"],
          ",".join(nm(o["id"]) for o in r.get("outputs", []))))
    print("       因: %s" % why)

print("\n■ 工种缺口·没有任何员工能干的配方（%d）" % len(worker_gap))
for r in worker_gap:
    print("   - %s [%s] worker_tags=%s" % (r.get("name"), r["id"], r.get("worker_tags")))

print("\n■ 创始人百搭检查")
print("   创始人 workTags = %s" % sorted(founder_tags))
print("   配方用到的全部工种 = %s" % sorted(all_rtags))
print("   创始人缺失的工种 = %s" % (founder_missing_tags or "无（已覆盖全部具体工种）"))
print("   依赖 'any' 兜底、否则创始人干不了的配方（%d）:" % len(founder_blocked_if_no_any))
for r in founder_blocked_if_no_any:
    print("       - %s [%s] worker_tags=%s" % (r.get("name"), r["id"], r.get("worker_tags")))

print("\n■ 死胡同·拿得到但无法交互的卡（%d）" % len(deadend))
for cid in deadend:
    print("   - %s (%s)  type=%s sell=%s" % (nm(cid), cid, cards[cid].get("type"), cards[cid].get("sell")))

print("\n■ 对手公司（商战未实现，暂无交互，%d）" % len(rivals))
print("   " + ", ".join(nm(c) for c in rivals))

print("\n■ 解锁进度（前 40 条：阶段→配方→产物）")
for stage, rid, oid in unlock_log[:40]:
    print("   S%d  %-18s → %s" % (stage, rid, nm(oid)))
print("\n(完)")
