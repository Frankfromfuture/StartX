#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Rebuild the first booster pack (garage_pack) economy in startx_data.xlsx.

- Clears the card slots of ALL packs (keeps id/name/stage/price/min/max).
- Refills garage_pack with the new 12-card tutorial economy.
- Adds the new cards (fresh p1_* ids to avoid colliding with the 80 legacy
  recipes; only `founder` and `cash` are reused, neither of which appears as
  an all-pack1 input in any legacy recipe).
- Adds the 7 recipes that wire the two production chains + the cash payout.
"""
import openpyxl

XLSX = "data/startx_data.xlsx"

# ---------------------------------------------------------------- new cards
# id, name, type, workTags, salary, capacity, sell, maxUses, workRequired
NEW_CARDS = [
    ("p1_neighborhood", "居住小区", "resource_node", "", "", "", "", "3-5", ""),
    # 小区青年是「客户/被招募对象」而非员工——不能去给节点打工（否则会自己刷自己、还能去批发市场刷产品）
    ("p1_youth",        "小区青年", "resource",      "", "", "", 1, "", 10),
    ("p1_survey",       "市场调研", "resource_node", "", "", "", "", "3-5", ""),
    ("p1_customer",     "靠谱客户", "resource",      "", "", "", 2, "", 15),
    ("p1_university",   "大学",     "resource_node", "", "", "", "", "3-5", ""),
    ("p1_intern",       "实习生",   "employee",      "any", 1, 1, "", "", ""),
    ("p1_wholesale",    "批发市场", "resource_node", "", "", "", "", "3-5", ""),
    ("p1_rawprod",      "裸奔粗糙产品", "resource",  "", "", "", 1, "", 15),
    ("p1_marketing",    "营销策划", "resource_node", "", "", "", "", "3-5", ""),
    ("p1_package",      "带包装粗糙产品", "resource", "", "", "", 2, "", 30),
    ("p1_office",       "办公室",   "facility",      "", 2, "", "", "", ""),
]

# --------------------------------------------------------------- new recipes
# Each: id, name, worker_tags, duration, inputs[(id,count,consume)], outputs[(id,count)]
NEW_RECIPES = [
    ("p1_recruit_youth", "招募小区青年", "any", 10,
     [("p1_neighborhood", 1, False)], [("p1_youth", 1)]),
    ("p1_make_customer", "转化靠谱客户", "", 15,
     [("p1_survey", 1, False), ("p1_youth", 1, True)], [("p1_customer", 1)]),
    ("p1_recruit_intern", "招募实习生", "any", 8,
     [("p1_university", 1, False)], [("p1_intern", 1)]),
    ("p1_make_rawprod", "做出粗糙产品", "any", 15,
     [("p1_wholesale", 1, False)], [("p1_rawprod", 1)]),
    ("p1_package_prod", "包装产品", "", 30,
     [("p1_rawprod", 1, True), ("p1_marketing", 1, False)], [("p1_package", 1)]),
    # 任意产品 + 任意客户 = 现金（数量 = 两者价值之和），现金依次快速跳出
    # 产品: 裸奔粗糙产品(1) / 带包装粗糙产品(2)；客户: 小区青年(1) / 靠谱客户(2)
    ("p1_cash_pkg_cust", "成交：精品×靠谱客户", "", 3,
     [("p1_package", 1, True), ("p1_customer", 1, True)], [("cash", 4)]),   # 2+2
    ("p1_cash_pkg_youth", "成交：精品×小区青年", "", 3,
     [("p1_package", 1, True), ("p1_youth", 1, True)], [("cash", 3)]),      # 2+1
    ("p1_cash_raw_cust", "成交：粗品×靠谱客户", "", 3,
     [("p1_rawprod", 1, True), ("p1_customer", 1, True)], [("cash", 3)]),   # 1+2
    ("p1_cash_raw_youth", "成交：粗品×小区青年", "", 3,
     [("p1_rawprod", 1, True), ("p1_youth", 1, True)], [("cash", 2)]),      # 1+1
]

# ----------------------------------------------- garage_pack slot definition
# four slots, each offers a thematic subset (weights are relative)
GARAGE_SLOTS = [
    [("p1_neighborhood", 40), ("p1_university", 60), ("p1_youth", 25)],
    [("p1_survey", 40), ("p1_customer", 35), ("p1_intern", 25)],
    [("p1_wholesale", 40), ("p1_marketing", 35), ("p1_rawprod", 25)],
    [("p1_package", 34), ("p1_office", 33), ("founder", 33)],
]


def col(ws, name):
    H = [c.value for c in ws[1]]
    return H.index(name) + 1


def set_row(ws, r, name, val):
    ws.cell(row=r, column=col(ws, name)).value = val


def find_row(ws, card_id):
    for r in range(2, ws.max_row + 1):
        if ws.cell(row=r, column=1).value == card_id:
            return r
    return None


def main():
    wb = openpyxl.load_workbook(XLSX)

    # ---- cards ----
    cw = wb["cards"]
    # founder: bump capacity to 5, salary 0
    fr = find_row(cw, "founder")
    set_row(cw, fr, "capacity", 5)
    set_row(cw, fr, "salary", 0)
    # add / overwrite new cards
    for (cid, name, typ, tags, sal, cap, sell, uses, wreq) in NEW_CARDS:
        r = find_row(cw, cid) or (cw.max_row + 1)
        set_row(cw, r, "id", cid)
        set_row(cw, r, "name", name)
        set_row(cw, r, "type", typ)
        set_row(cw, r, "workTags", tags or None)
        set_row(cw, r, "salary", sal if sal != "" else None)
        set_row(cw, r, "capacity", cap if cap != "" else None)
        set_row(cw, r, "sell", sell if sell != "" else None)
        set_row(cw, r, "maxUses", uses if uses != "" else None)
        set_row(cw, r, "workRequired", wreq if wreq != "" else None)

    # ---- recipes ----
    rw = wb["recipes"]
    # clear obsolete/renamed recipe rows (blank the whole row so it's skipped)
    OBSOLETE = {"p1_cash_package", "p1_cash_raw"}
    for r in range(2, rw.max_row + 1):
        if rw.cell(row=r, column=1).value in OBSOLETE:
            for cc in range(1, rw.max_column + 1):
                rw.cell(row=r, column=cc).value = None
    for (rid, name, wtags, dur, inputs, outputs) in NEW_RECIPES:
        r = find_row(rw, rid) or (rw.max_row + 1)
        set_row(rw, r, "id", rid)
        set_row(rw, r, "name", name)
        set_row(rw, r, "requiredIdeaId", None)
        set_row(rw, r, "worker_tags", wtags or None)
        set_row(rw, r, "duration", dur)
        for i in range(5):
            if i < len(inputs):
                cid, cnt, cons = inputs[i]
                set_row(rw, r, "input%d" % (i + 1), cid)
                set_row(rw, r, "input%dCount" % (i + 1), cnt)
                set_row(rw, r, "input%dConsume" % (i + 1), str(cons).lower())
            else:
                set_row(rw, r, "input%d" % (i + 1), None)
                set_row(rw, r, "input%dCount" % (i + 1), None)
                set_row(rw, r, "input%dConsume" % (i + 1), None)
        for i in range(5):
            if i < len(outputs):
                cid, cnt = outputs[i]
                set_row(rw, r, "output%d" % (i + 1), cid)
                set_row(rw, r, "output%dCount" % (i + 1), cnt)
            else:
                set_row(rw, r, "output%d" % (i + 1), None)
                set_row(rw, r, "output%dCount" % (i + 1), None)
        set_row(rw, r, "output_zone", None)

    # ---- packs: clear every pack's slots, then refill garage_pack ----
    pw = wb["packs"]
    slot_cols = [c.value for c in pw[1] if c.value and c.value.startswith("slot")]
    for r in range(2, pw.max_row + 1):
        if pw.cell(row=r, column=1).value is None:
            continue
        for sc in slot_cols:
            pw.cell(row=r, column=col(pw, sc)).value = None
    gr = find_row(pw, "garage_pack")
    for si, cands in enumerate(GARAGE_SLOTS, start=1):
        for ci, (cid, prob) in enumerate(cands, start=1):
            set_row(pw, gr, "slot%dCard%d" % (si, ci), cid)
            set_row(pw, gr, "slot%dProb%d" % (si, ci), prob)

    wb.save(XLSX)
    print("rebuilt:", XLSX)


if __name__ == "__main__":
    main()
