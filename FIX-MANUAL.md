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


---

## 修复 4: 全部消耗品批量修复 (645个)

### 问题
之前只修复了用户背包里的 11 个消耗品，新获得的消耗品仍然无法使用。

### 修复
从 `maple-data.item` 表提取所有 20000000-20000999 范围且有 Skill 的物品 (645个)，
排除 4 个 HP 药水 (20000004, 20000022, 20000028, 20000443)，
对其余 641 个的 skill XML 全部替换为血药模板。

### 操作
1. 从 DB 提取所有需要修复的物品 ID:
   ```sql
   SELECT DISTINCT Id FROM item
   WHERE Id BETWEEN 20000000 AND 20000999
   AND Skill IS NOT NULL AND JSON_LENGTH(Skill) > 0
   AND Id NOT IN (20000004, 20000022, 20000028, 20000443)
   ```
2. 使用 Orion2-CLI:
   ```
   Orion2-CLI.exe patch-copy-potion-skill <m2h> <m2d> <all_ids.txt> <out.m2h> <out.m2d>
   ```

### 消耗品分类 (645个)

| 分类 | 数量 | 示例 |
|------|------|------|
| 经验加成 | 21 | 20000073 (3倍经验券), 20000441 (毒菌烤串) |
| 攻击力提升 | ~30 | 20000017 (战士药水), 20000018 (法师药水) |
| 防御/生命提升 | ~25 | 20000019 (生命药水), 20000020 (防御药水) |
| 速度提升 | ~20 | 20000305 (疾风药水), 20000552 (攻速药水) |
| 暴击/命中/闪避 | ~15 | 20000543 (暴击率药水), 20000253 (仙泉之水) |
| 精灵/四维 | ~10 | 20000043 (蜂蜜罐), 20000542 (精神药水) |
| 生产/采集奖励 | ~40 | 20000343-350 (各种皮袋), 20000413-418 (各种水晶) |
| Meso/金币 | ~5 | 20000117 (金币眼药水) |
| 伤害加成 | ~15 | 20000544 (不稳定伤害提升药水) |
| 其他/食物/烟花 | ~464 | 20000065 (弹面), 20000092 (烤五花肉) |

---

## 修复 5: 创建全新自定义消耗品 (5倍经验券)

### 需求
创建一个全新的 5 倍经验券，持续 1 小时，不影响任何现有物品。

### 实现方案

创建 3 个组件: AdditionalEffect (AE) + Skill + Item

#### 1. AE (AdditionalEffect)
- ID: 90000999
- SpecialRates.Experience = 4 (1+4 = 5倍)
- DurationTick = 3600000 (1小时 = 3600秒)
- 同时加成 FishingExp 和 PlayInstrumentExp

```sql
INSERT INTO `additional-effect` (Id, Level, Property, Status, Recovery) VALUES
(90000999, 1,
 '{"Type": 1, "Group": 25, "MaxCount": 1, "KeepOnDeath": true, "DurationTick": 3600000, "UseInGameTime": true, "KeepOnEnterPvpZone": true}',
 '{"Rates": {}, "Values": {}, "Resistances": {}, "SpecialRates": {"Experience": 4, "FishingExp": 4, "PlayInstrumentExp": 4}, "SpecialValues": {}}',
 NULL);
```

#### 2. Skill
- 复用已有 skill 文件路径 skill/90/90000050.xml (原 Experimental Potion 的 skill)
- 验证: DB 中没有其他物品使用 skillId 90000050，覆盖安全
- 客户端 XML: 替换 skill/90/90000050.xml 内容为血药模板，conditionSkill 指向 AE 90000999
- DB skill 表: 更新 skill 90000050 的 conditionSkill.Id = 90000999，清除 Health 条件

```xml
<skill id="90000999" name="90000999" feature="Season1">
    <template><consume money="0" useItem="1" /></template>
    <levels>
        <level value="1" immediateActive="1" cooldownTime="5000">
            <beginCondition><owner><stat hp="1" /></owner></beginCondition>
            <conditionSkill><jump skillID="90000999" level="1" /></conditionSkill>
        </level>
    </levels>
</skill>
```

#### 3. Item
- ID: 20001011 (已存在于客户端 Xml.m2d 中，替换内容即可)
- DB: 从 20000073 (3倍经验券) 复制结构，改 SkillId = 90000050
- 客户端 XML: 替换 item/2/00/20001011.xml，skill 指向 90000050，function 指向 AE 90000999

```xml
<item id="20001011" optionType="9">
    <slot name="ETC" />
    <property type="2" itemGroup="1" usePeriod="0" transferType="0" />
    <skill id="90000050" />
    <function name="AddAdditionalEffect" parameter="90000999" />
    <AdditionalEffects><AdditionalEffect id="90000999" level="1" /></AdditionalEffects>
</item>
```

#### 4. 中文名称
- 修改 string/cn/itemname.xml 中 id=20001011 的 name 属性
- 改为 "定制五倍经验券(1小时)"

### 部署流程 (从 orig 干净备份完整重建)

```
1. patch-copy-potion-skill (627个消耗品 skill 替换)
2. patch-meret-category (蓝蘑菇商店修复)
3. replace skill/90/90000050.xml (自定义5倍经验 skill)
4. replace item/2/00/20001011.xml (自定义5倍经验 item)
5. replace string/cn/itemname.xml (中文名称)
```

### 使用
游戏内输入 `/item 20001011` 获取，双击使用。

### 关键注意事项
- 不要覆盖有用的现有物品 (需检查 DB 中哪些物品使用该 skillId)
- AE 的 Experience rate=4 表示 1+4=5倍 (ExperienceManager 使用 1+Rate 公式)
- Skill 文件路径必须和 skillId 匹配 (skill/90/90000050.xml 对应 skillId 90000050)
- conditionSkill 的 skillID 决定触发哪个 AE
- 客户端 skill XML 的 immediateActive, subType, useItem 等属性必须和血药模板一致才能使用
- DB skill 表的 conditionSkill 也要同步更新 (服务端用 DB 数据，不用客户端 XML)
- 物品中文名在 string/cn/itemname.xml 中，用 class="consume" 标记

---

## 新增 Orion2-CLI 命令

| 命令 | 说明 |
|------|------|
| patch-inject | 注入新文件到 m2d 归档 (有 bug，FileHeader 处理不完善) |
| replace | 替换归档中已有文件 (推荐使用) |

### 创建自定义消耗品检查清单

1. [ ] 确定 AE ID (在 90000999+ 范围，避免冲突)
2. [ ] 确定 Skill ID (复用已有文件路径或创建新的)
3. [ ] 确定 Item ID (在 20001000+ 范围，检查 DB 和客户端是否已存在)
4. [ ] 检查 DB 中是否有其他物品使用相同 SkillId (避免影响)
5. [ ] 创建 AE 记录 (additional-effect 表)
6. [ ] 创建/更新 Skill 记录 (skill 表，conditionSkill 指向新 AE)
7. [ ] 创建/更新 Item 记录 (item 表，Skill 指向新 skillId)
8. [ ] 创建客户端 skill XML (血药模板 + conditionSkill 指向新 AE)
9. [ ] 创建客户端 item XML (property itemGroup=1, skill, function, AE)
10. [ ] 修改 string/cn/itemname.xml 添加中文名称
11. [ ] 从 orig 干净备份完整重建 Xml.m2d (避免残留脏数据)
12. [ ] 重启服务端
13. [ ] 测试 /item 获取并使用
