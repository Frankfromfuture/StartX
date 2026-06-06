#!/usr/bin/env python3
"""Generate startx_data.xlsx (cards / recipes / packs sheets) from the current JSON.
Run once to seed the workbook; afterwards the .xlsx is the single source of truth.

Cell encodings (kept human-editable in Excel):
  cards.workTags / recipes.worker_tags : comma list   e.g. "sales,dev,any"
  recipes.inputs  : "id:count:consume" items joined by "|"  e.g. "lead:1:false|prd:2:true"
  recipes.outputs : "id:count" items joined by "|"          e.g. "lead:2|cash:1"
  packs.slots     : slot = "id:w,id:w"; slots joined by "|"
                    e.g. "sales_rep:40,market_lead_pool:60|lead:100"
"""
import json, os, zipfile, html

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DATA = os.path.join(ROOT, "data")
OUT = os.path.join(DATA, "startx_data.xlsx")


def load(name):
    with open(os.path.join(DATA, name), encoding="utf-8") as f:
        return json.load(f)


# ---- build sheet rows (list of rows; each cell is str or number) ----
def cards_rows():
    d = load("cards.json")
    head = ["id", "name", "type", "workTags", "salary", "capacity", "sell", "maxUses", "hp", "attack", "workRequired"]
    rows = [head]
    for cid, c in d.items():
        rows.append([
            cid, c.get("name", ""), c.get("type", ""),
            ",".join(c.get("workTags", [])),
            c.get("salary", 0), c.get("capacity", 0), c.get("sell", 0),
            c.get("maxUses", "") if "maxUses" in c else "",
            c.get("hp", "") if "hp" in c else "",
            c.get("attack", "") if "attack" in c else "",
            c.get("workRequired", "") if "workRequired" in c else "",
        ])
    return rows


def recipes_rows():
    d = load("recipes.json")
    input_head = []
    for i in range(1, 6):
        input_head += ["input%d" % i, "input%dCount" % i, "input%dConsume" % i]
    output_head = []
    for i in range(1, 6):
        output_head += ["output%d" % i, "output%dCount" % i]
    head = ["id", "name", "requiredIdeaId", "worker_tags", "duration"] + input_head + output_head + ["output_zone"]
    rows = [head]
    for r in d:
        inputs = []
        for i in r.get("inputs", [])[:5]:
            inputs += [i["id"], int(i.get("count", 1)), str(bool(i.get("consume", False))).lower()]
        while len(inputs) < 15:
            inputs.append("")
        outputs = []
        for o in r.get("outputs", [])[:5]:
            outputs += [o["id"], int(o.get("count", 1))]
        while len(outputs) < 10:
            outputs.append("")
        rows.append([
            r.get("id", ""), r.get("name", ""), r.get("requiredIdeaId", ""),
            ",".join(r.get("worker_tags", [])),
            float(r.get("duration", 0)),
        ] + inputs + outputs + [r.get("output_zone", "")])
    return rows


def packs_rows():
    d = load("packs.json")
    slot_head = []
    for s in range(1, 6):
        for o in range(1, 5):
            slot_head += ["slot%dCard%d" % (s, o), "slot%dProb%d" % (s, o)]
    head = ["id", "name", "stage", "price", "minCards", "maxCards"] + slot_head
    rows = [head]
    for pid, p in d.items():
        slots = []
        for slot in p.get("slots", [])[:5]:
            opts = []
            for opt in slot[:4]:
                opts += [opt["id"], int(opt.get("w", 0))]
            while len(opts) < 8:
                opts.append("")
            slots += opts
        while len(slots) < 40:
            slots.append("")
        rows.append([
            pid, p.get("name", ""), p.get("stage", 0), p.get("price", 0),
            p.get("minCards", 0), p.get("maxCards", 0),
        ] + slots)
    return rows


# ---- minimal OOXML writer ----
def col_letter(n):  # 0 -> A
    s = ""
    n += 1
    while n:
        n, r = divmod(n - 1, 26)
        s = chr(65 + r) + s
    return s


def build_xlsx(sheets):
    # sheets: list of (name, rows). Collect shared strings.
    shared = {}
    shared_list = []

    def sid(text):
        if text not in shared:
            shared[text] = len(shared_list)
            shared_list.append(text)
        return shared[text]

    sheet_xmls = []
    for name, rows in sheets:
        out = ['<?xml version="1.0" encoding="UTF-8" standalone="yes"?>',
               '<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">',
               '<sheetData>']
        for ri, row in enumerate(rows, start=1):
            out.append('<row r="%d">' % ri)
            for ci, val in enumerate(row):
                ref = "%s%d" % (col_letter(ci), ri)
                if val == "" or val is None:
                    continue
                if isinstance(val, bool):
                    val = str(val).lower()
                    out.append('<c r="%s" t="s"><v>%d</v></c>' % (ref, sid(val)))
                elif isinstance(val, (int, float)):
                    out.append('<c r="%s"><v>%s</v></c>' % (ref, repr(val) if isinstance(val, float) else val))
                else:
                    out.append('<c r="%s" t="s"><v>%d</v></c>' % (ref, sid(str(val))))
            out.append('</row>')
        out.append('</sheetData></worksheet>')
        sheet_xmls.append("".join(out))

    # sharedStrings.xml
    ss = ['<?xml version="1.0" encoding="UTF-8" standalone="yes"?>',
          '<sst xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" count="%d" uniqueCount="%d">'
          % (len(shared_list), len(shared_list))]
    for s in shared_list:
        ss.append('<si><t xml:space="preserve">%s</t></si>' % html.escape(s))
    ss.append('</sst>')
    shared_xml = "".join(ss)

    # workbook.xml
    wb = ['<?xml version="1.0" encoding="UTF-8" standalone="yes"?>',
          '<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" '
          'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets>']
    for i, (name, _) in enumerate(sheets, start=1):
        wb.append('<sheet name="%s" sheetId="%d" r:id="rId%d"/>' % (html.escape(name), i, i))
    wb.append('</sheets></workbook>')
    workbook_xml = "".join(wb)

    # workbook rels
    rels = ['<?xml version="1.0" encoding="UTF-8" standalone="yes"?>',
            '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">']
    for i in range(1, len(sheets) + 1):
        rels.append('<Relationship Id="rId%d" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet%d.xml"/>' % (i, i))
    ssid = len(sheets) + 1
    rels.append('<Relationship Id="rId%d" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/sharedStrings" Target="sharedStrings.xml"/>' % ssid)
    rels.append('</Relationships>')
    workbook_rels = "".join(rels)

    # content types
    ct = ['<?xml version="1.0" encoding="UTF-8" standalone="yes"?>',
          '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">',
          '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>',
          '<Default Extension="xml" ContentType="application/xml"/>',
          '<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>',
          '<Override PartName="/xl/sharedStrings.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sharedStrings+xml"/>']
    for i in range(1, len(sheets) + 1):
        ct.append('<Override PartName="/xl/worksheets/sheet%d.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>' % i)
    ct.append('</Types>')
    content_types = "".join(ct)

    root_rels = ('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
                 '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
                 '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>'
                 '</Relationships>')

    with zipfile.ZipFile(OUT, "w", zipfile.ZIP_DEFLATED) as z:
        z.writestr("[Content_Types].xml", content_types)
        z.writestr("_rels/.rels", root_rels)
        z.writestr("xl/workbook.xml", workbook_xml)
        z.writestr("xl/_rels/workbook.xml.rels", workbook_rels)
        z.writestr("xl/sharedStrings.xml", shared_xml)
        for i, xml in enumerate(sheet_xmls, start=1):
            z.writestr("xl/worksheets/sheet%d.xml" % i, xml)


build_xlsx([("cards", cards_rows()), ("recipes", recipes_rows()), ("packs", packs_rows())])
print("wrote", OUT)
