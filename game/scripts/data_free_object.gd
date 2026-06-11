extends Resource
class_name DataFreeObject

# 自由布置（不按网格）的物体：记录精确世界坐标与朝向
@export var structure:int       # 对应 structures 数组里的序号（与网格放置同一套 id）
@export var position:Vector3    # 世界坐标（y 一般为 0）
@export var rotation:float      # 绕 Y 轴朝向（弧度）
