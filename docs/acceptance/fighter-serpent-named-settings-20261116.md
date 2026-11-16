# 蛇王 D13：原始动作配置具名恢复

日期：2026-11-16。本批提供刘泉纬改用蛇王套装所需的原始动作配置输入，没有改变 App、资产发布身份或玩法开关。

## 实际恢复范围

新增 `prepare_serpent_named_settings.py` 从已恢复的原始明文配置中读取六个准确成员。它使用已核实的原动画 schema，把字段投射为名称；所有字段保留原值，未提供的值保持 `null`，不套用 D15、D19 或其它角色的默认时序。

| 原始成员 | 原记录数 | 本批选中 |
| --- | ---: | ---: |
| `settings_sets_dynasty.bytes` | 295 | D13 原索引 52–70，共 19 |
| `settings_style_shuangou.bytes` | 31 | 全部 31 |
| `moves_settings.bytes` | 113 | 全部 113 |
| `settings_blocks.bytes` | 149 | 全部 149 |
| `settings_hits.bytes` | 71 | 全部 71 |
| `settings_style_kicks.bytes` | 71 | 全部 71 |

454 条具名记录是可供后续选择的源配置集合，**不是已绑定的 454 个播放动作**。D13 专属集合另存一份 19 条记录，包含专属起势、毒能力、头盔能力、瓶子与云、毒潭、藤蔓、护甲能力及致命醉毒等原 alias。人体与离散 model 记录仍由原 alias / 文件区分，没有混入同一人体骨架。

每条记录保留 `sourceEntry`、原始完整成员 SHA-256、原始 record index 与 `configuration`。顶层 29 个字段及 Intervals / Damage / Sounds / Gender / Floor 使用已审 schema 名称；其它原数组、枚举对象和顺序保留。没有执行 trigger、填充未证伤害或激活蛇王生产状态。

## 严格输入与可逆性

完整 decoded archive 的身份为 17,325,877 bytes / SHA-256 `02bcd31d5b0f3ed992ca1972f2c6da5f59e6495fe3880fec45f8b073fbaa0e7a`；准确 animation split 为 `efe3e5d48819adc1106302dacb2b9e94352d5b6735e79a7018a546b19531ab29`。六个成员分别以完整 bytes / SHA 约束，ZIP 成员不得重复或加密，读取后必须消耗全部 typed-storage bytes。

原 native schema receipt 为 11,577 bytes / `f8687443bcf2da87ff3c9f5d7c2059cb2dbe851a9a33c776655477e750b85111`。本次只复用这份已保存证据，没有新增原生方法读取。helper 保留它对应的 method 16684、原代码摘要与 125 个字段身份。

每条配置实际完成 JSON 写入格式编码、读回、逆投射，并比较类型敏感的完整值：区分 bool / int、保留浮点位样与枚举值、保存数组和字典原顺序。454 条全部相等。此证明约束的是原始数据恢复，不等于证明后续动作播放、碰撞或战斗行为已经实现。

## 本批产物

| 私有派生产物 | Bytes | SHA-256 |
| --- | ---: | --- |
| `serpent-animation-named-v1.json` | 49,609 | `2ff1cca279a4db9bf772c27cd847102d6887e0363905b30616ad5ed54cd4357d` |
| `serpent-shuangou-animation-named-v1.json` | 1,404,057 | `612b85ed595e4a29ab686c00370d0c4bd573d6aaaa62384c769a4abb1f2cf09a` |
| `record-round-trip-audit-private.json` | 222,073 | `a98f6dac51133d50bc4274b20f18398b5e7017848647691da0daf743fb8ff9b6` |
| `receipt-private.json` | 3,668 | `d933ccd2baaa6b030ccfe67fb2f90c8b9798375d3af7d0944b5225b8c4b67d1f` |

这些文件仅是源输入，使用独立 schema 并固定 `sourceOnly=true`、`runtimeBound=false`。它们没有 App 所需的角色 / 模型 manifest 身份，不会被本批 helper 放进发布目录。原始配置与派生内容保存在私有源材料中，公开 Git 仅提交 helper、专项检查和本说明。

## 验证与后续边界

本批只执行新增的四项定向检查：454 条实际记录与六份原始成员逐项 join；实际 crop / null 不被替换；错误 schema / archive 在解析前拒绝；类型与浮点位样保留。四项实际通过（unittest，0.235 秒，无 skip），日志保存在本次私有产物目录的 `four-checks.log`。没有运行旧全套测试、Apple 客户端、GPU 或 TestFlight。

下一阶段从原套装配置与 D13 触发锁恢复等级、资源条、主动能力及状态机制；这批具名动作不会把那些尚未实现的机制标为完成。
