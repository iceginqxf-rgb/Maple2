# Maple2 社区模拟器修复手册

## 环境

- 服务器: g1n (Windows)
- 客户端: MapleStory2 (Xml.m2d / Xml.m2h)
- 数据库: maple-data (MySQL)
- 工具: Orion2-CLI

---

## 修复 1: 消耗品无法使用

### 问题
双击消耗品（经验增幅券、攻击力药剂、速度药剂等）无反应。只有 HP 药水可以正常使用。

### 根因
消耗品使用链: item -> skill (客户端本地校验) -> conditionSkill -> AdditionalEffect
客户端在发送使用包之前会本地校验 skill XML 属性。非血药 skill 的 immediateActive, subType, useItem, beginCondition 等与血药不同，导致客户端拒绝使用。

### 修复
将非血药消耗品的 skill XML 完整替换为 HP 药水模板 (90000032)，只保留 skillID 不变。
效果不变: conditionSkill skillID 被替换为原值，触发的 AdditionalEffect 保持原效果。

### 工具
Orion2-CLI patch-copy-potion-skill <m2h> <m2d> <idlist.txt> <out.m2h> <out.m2d>

---

## 修复 2: 经验倍率未生效

### 问题
使用经验增幅券后 buff 图标和持续时间正常，但打怪经验没有翻倍。

### 根因
StatsManager.AddBuffs() 正确将 buff SpecialRates[Experience] 存入 Values[SpecialAttribute.Experience].Rate，
但 ExperienceManager 的 OnKill() 和 AddExp() 从未读取该值。

### 修复
在 ExperienceManager.cs 添加 GetExpRate() 方法返回 (1 + Rate)，并在 OnKill 和 AddExp 中应用。

| 券类型 | Rate | 倍率 (1+Rate) |
|--------|------|---------------|
| 1.5倍券 | 0.5  | 1.5x          |
| 2倍券   | 1.0  | 2x            |
| 3倍券   | 2.0  | 3x            |

### 修改文件
- Maple2.Server.Game/Manager/ExperienceManager.cs

---

## 修复 3: 蓝蘑菇商店只显示2个分类

### 问题
蓝蘑菇商店只显示功能(40300)和乐器(40600)两个分类。

### 根因
客户端 table/na/meratmarketcategory.xml 末尾有 environment 标签:
<environment feature="MeratMarketNewBM"> 覆盖 category 100000 只保留 2 个 tab。

### 修复
删除 environment 标签，恢复完整 category (22 个 tab)。

### 工具
Orion2-CLI patch-meret-category <m2h> <m2d> <out.m2h> <out.m2d>

---

## 服务端代码修改清单

| 文件 | 修改 |
|------|------|
| PacketRouter.cs | RECVDUMP 调试日志 |
| GameServer.cs | premiumMarketCache 统计日志 |
| ExperienceManager.cs | GetExpRate() 经验倍率 |
| ItemUseHandler.cs | 优先 ItemFunction 路径 |
| MeretMarketHandler.cs | MERET DEBUG 日志 + null SubTabIds 处理 |
| SkillHandler.cs | SKILL USE 日志 |

---

## Orion2-CLI 补丁命令

| 命令 | 说明 |
|------|------|
| patch-copy-potion-skill | 整体替换非血药 skill 为血药模板 |
| patch-meret-category | 删除 meratmarketcategory 的 environment 覆盖 |
