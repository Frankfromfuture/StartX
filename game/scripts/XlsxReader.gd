extends RefCounted
## 运行时读取 .xlsx（zip + OOXML）。返回 { 工作表名 : [ [行内每个单元格字符串], ... ] }。
## 通过 preload 引用（不用 class_name，避免 autoload 解析顺序问题）。
## 支持 sharedStrings / inlineStr / 数字单元格，兼容 Excel 重新保存后的标准结构。
## 仅在游戏启动时调用一次，开销可忽略。

static func read(path: String) -> Dictionary:
	var zip := ZIPReader.new()
	var err := zip.open(path)
	if err != OK:
		# 退回到全局路径（导出环境）
		err = zip.open(ProjectSettings.globalize_path(path))
		if err != OK:
			push_error("XlsxReader: 无法打开 " + path)
			return {}
	var files := zip.get_files()
	var shared := _parse_shared_strings(zip, files)
	var name_to_file := _sheet_map(zip, files)
	var out := {}
	for sheet_name in name_to_file:
		var fp: String = name_to_file[sheet_name]
		if files.has(fp):
			out[sheet_name] = _parse_sheet(zip.read_file(fp), shared)
	zip.close()
	return out

# 工作表名 → 文件路径（通过 workbook.xml + rels）
static func _sheet_map(zip: ZIPReader, files: PackedStringArray) -> Dictionary:
	var rid_to_target := {}
	if files.has("xl/_rels/workbook.xml.rels"):
		var p := XMLParser.new()
		p.open_buffer(zip.read_file("xl/_rels/workbook.xml.rels"))
		while p.read() == OK:
			if p.get_node_type() == XMLParser.NODE_ELEMENT and p.get_node_name() == "Relationship":
				var rid := _attr(p, "Id")
				var target := _attr(p, "Target")
				if target.begins_with("/"):
					target = target.substr(1)
				elif not target.begins_with("xl/"):
					target = "xl/" + target
				rid_to_target[rid] = target
	var out := {}
	if files.has("xl/workbook.xml"):
		var p := XMLParser.new()
		p.open_buffer(zip.read_file("xl/workbook.xml"))
		var idx := 0
		while p.read() == OK:
			if p.get_node_type() == XMLParser.NODE_ELEMENT and p.get_node_name() == "sheet":
				idx += 1
				var nm := _attr(p, "name")
				var rid := _attr(p, "r:id")
				if rid == "":
					rid = _attr(p, "id")
				var target: String = rid_to_target.get(rid, "xl/worksheets/sheet%d.xml" % idx)
				out[nm] = target
	return out

static func _parse_shared_strings(zip: ZIPReader, files: PackedStringArray) -> PackedStringArray:
	var out := PackedStringArray()
	if not files.has("xl/sharedStrings.xml"):
		return out
	var p := XMLParser.new()
	p.open_buffer(zip.read_file("xl/sharedStrings.xml"))
	var cur := ""
	var in_t := false
	while p.read() == OK:
		var t := p.get_node_type()
		if t == XMLParser.NODE_ELEMENT:
			var n := p.get_node_name()
			if n == "si":
				cur = ""
			elif n == "t":
				in_t = not p.is_empty()
		elif t == XMLParser.NODE_TEXT and in_t:
			cur += p.get_node_data()
		elif t == XMLParser.NODE_ELEMENT_END:
			var n := p.get_node_name()
			if n == "t":
				in_t = false
			elif n == "si":
				out.append(cur)
	return out

static func _parse_sheet(bytes: PackedByteArray, shared: PackedStringArray) -> Array:
	var rows: Array = []
	var p := XMLParser.new()
	p.open_buffer(bytes)
	var cells := {}            # col_index -> String
	var maxcol := -1
	var cell_type := ""
	var cell_col := 0
	var in_v := false
	var in_t := false
	var val := ""
	while p.read() == OK:
		var t := p.get_node_type()
		if t == XMLParser.NODE_ELEMENT:
			var n := p.get_node_name()
			if n == "row":
				cells = {}
				maxcol = -1
			elif n == "c":
				cell_type = _attr(p, "t")
				cell_col = _col_index(_attr(p, "r"))
				val = ""
				if p.is_empty():
					cells[cell_col] = ""
					maxcol = maxi(maxcol, cell_col)
			elif n == "v":
				in_v = not p.is_empty()
				val = ""
			elif n == "t":
				in_t = not p.is_empty()
		elif t == XMLParser.NODE_TEXT:
			if in_v or in_t:
				val += p.get_node_data()
		elif t == XMLParser.NODE_ELEMENT_END:
			var n := p.get_node_name()
			if n == "v":
				in_v = false
			elif n == "t":
				in_t = false
			elif n == "c":
				var out_val := val
				if cell_type == "s":
					var idx := val.to_int()
					out_val = shared[idx] if idx >= 0 and idx < shared.size() else ""
				cells[cell_col] = out_val
				maxcol = maxi(maxcol, cell_col)
			elif n == "row":
				var arr: Array = []
				for i in range(maxcol + 1):
					arr.append(String(cells.get(i, "")))
				rows.append(arr)
	return rows

static func _col_index(ref: String) -> int:
	var n := 0
	for i in range(ref.length()):
		var ch := ref.unicode_at(i)
		if ch >= 65 and ch <= 90:
			n = n * 26 + (ch - 64)
		elif ch >= 97 and ch <= 122:
			n = n * 26 + (ch - 96)
		else:
			break
	return n - 1

static func _attr(p: XMLParser, name: String) -> String:
	for i in range(p.get_attribute_count()):
		if p.get_attribute_name(i) == name:
			return p.get_attribute_value(i)
	return ""
