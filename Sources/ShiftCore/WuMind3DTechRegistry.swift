import Foundation

/// Authoritative, continuously maintained 3D technology registry for WUMIND「AI 3D 空间工坊」.
/// Strictly separates maturity statuses (`研究候选` / `样例跑通` / `已接入验收`) so research notes,
/// standalone verified samples, and live in-app integrations are NEVER conflated.

public enum WuMind3DTechCategory: String, Codable, CaseIterable, Identifiable, Sendable {
    case cadMechanical = "cad_mechanical"
    case architectureBIM = "architecture_bim"
    case worldGameScene = "world_game_scene"
    case singleAssetImageTo3D = "single_asset_image_to_3d"
    case characterRigAnimation = "character_rig_animation"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .cadMechanical: return "1. CAD 绘图与机械建模"
        case .architectureBIM: return "2. 建筑与室内设计（BIM）"
        case .worldGameScene: return "3. 大型环境与游戏场景"
        case .singleAssetImageTo3D: return "4. 单物体与参考图生成 3D"
        case .characterRigAnimation: return "5. 角色、服装、骨骼与动画"
        }
    }

    public var shortTitle: String {
        switch self {
        case .cadMechanical: return "CAD 机械"
        case .architectureBIM: return "建筑 BIM"
        case .worldGameScene: return "场景关卡"
        case .singleAssetImageTo3D: return "单物体 3D"
        case .characterRigAnimation: return "角色动画"
        }
    }

    public var iconName: String {
        switch self {
        case .cadMechanical: return "gearshape.2.fill"
        case .architectureBIM: return "building.2.fill"
        case .worldGameScene: return "map.fill"
        case .singleAssetImageTo3D: return "cube.transparent.fill"
        case .characterRigAnimation: return "figure.walk"
        }
    }
}

/// Strictly non-conflatable readiness status for every 3D tool / pipeline.
public enum WuMind3DTechStatus: String, Codable, CaseIterable, Sendable {
    case researchCandidate = "研究候选"
    case sampleVerified = "样例跑通"
    case integratedAccepted = "已接入验收"

    public var badgeText: String { rawValue }
}

/// Single clean mobile entry: user picks "我要做什么" first, and WUMIND selects the appropriate route.
public enum WuMind3DTaskIntent: String, Codable, CaseIterable, Identifiable, Sendable {
    case gameTownWorld = "game_town_world"
    case interiorBIM = "interior_bim"
    case cadPartDrawing = "cad_part_drawing"
    case singlePropPhoto3D = "single_prop_photo_3d"
    case characterRigAnim = "character_rig_anim"

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .gameTownWorld: return "游戏小镇 / 大型场景"
        case .interiorBIM: return "户型 / 建筑室内"
        case .cadPartDrawing: return "CAD 零件 / 工程图"
        case .singlePropPhoto3D: return "参考图做单物体 3D"
        case .characterRigAnim: return "角色与骨骼动画"
        }
    }

    public var subtitle: String {
        switch self {
        case .gameTownWorld: return "独立可编辑地标 + 可走主街 + 本地导出 GLB / Godot 工程"
        case .interiorBIM: return "区分标注/扫描/估算尺寸，独立移动门窗与墙洞联动"
        case .cadPartDrawing: return "参数化实体（保留原生脚本）+ 二维 DXF + STEP 校验"
        case .singlePropPhoto3D: return "单物体参考图 3D 路线（需云端 24GB+ GPU，先验网格可编辑性）"
        case .characterRigAnim: return "标准人形骨骼 + 蒙皮权重 + 动作导出（遵守素材再分发许可）"
        }
    }

    public var iconName: String {
        switch self {
        case .gameTownWorld: return "map.fill"
        case .interiorBIM: return "house.lodge.fill"
        case .cadPartDrawing: return "wrench.and.screwdriver.fill"
        case .singlePropPhoto3D: return "camera.viewfinder"
        case .characterRigAnim: return "figure.run"
        }
    }

    public var category: WuMind3DTechCategory {
        switch self {
        case .gameTownWorld: return .worldGameScene
        case .interiorBIM: return .architectureBIM
        case .cadPartDrawing: return .cadMechanical
        case .singlePropPhoto3D: return .singleAssetImageTo3D
        case .characterRigAnim: return .characterRigAnimation
        }
    }

    public var recommendedRouteSummary: String {
        switch self {
        case .gameTownWorld:
            return "自动路线：WuMind 参数化场景引擎（已接入验收）→ 独立可编辑 .wumind3d.json + 校验 .glb + Godot 4 .tscn（离线本地导出）"
        case .interiorBIM:
            return "自动路线：WuMind 建筑室内引擎（已接入验收）+ IfcOpenShell IFC4（样例跑通）→ 保留楼层/墙/门洞关联与尺寸来源标注"
        case .cadPartDrawing:
            return "自动路线：WuMind 参数化安装板预览 + ezdxf DXF / CadQuery STEP（样例跑通）→ 原生参数代码单独保留，STEP 不冒充建模历史"
        case .singlePropPhoto3D:
            return "自动路线：TRELLIS.2（MIT，需 24GB+ NVIDIA GPU，当前研究候选）→ 仅接受带贴图可编辑网格，绝不把 Gaussian Splat 标成可编辑模型"
        case .characterRigAnim:
            return "自动路线：已验收自有绑骨人形 GLB 管线 + MPFB2/Blender（研究候选）→ 严格核对 Mixamo 地区与不可再分发原始文件限制"
        }
    }

    public var defaultPromptPlaceholder: String {
        switch self {
        case .gameTownWorld:
            return "例如：生成一个叫「赤河镇」的西部小镇，有河流、木石桥梁、火车站、西部酒馆，主街可从酒馆过桥走到火车站…"
        case .interiorBIM:
            return "例如：导入户型图，北墙 5200mm、进深 4400mm，把南墙门向右移动 600mm 并联动墙洞与尺寸标注…"
        case .cadPartDrawing:
            return "例如：生成一块 160×120×10mm 带四个 Ø10 安装孔的金属安装板，孔距 120×80mm，支持改孔距重生成…"
        case .singlePropPhoto3D:
            return "例如：上传一张单物体参考图（如复古煤油灯或木椅），评估云端网格生成路线与导出格式…"
        case .characterRigAnim:
            return "例如：查看当前已绑骨人形角色的骨骼、蒙皮与待机/行走/重击动画检查结果…"
        }
    }
}

/// Dimension source tag required for BIM / Floorplan / CAD accuracy honesty.
public enum WuMindDimensionSource: String, Codable, Equatable, Sendable {
    case annotated = "标注尺寸"
    case scanned = "扫描值"
    case estimated = "估算值"
}

public struct WuMind3DTechEntry: Codable, Identifiable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let category: WuMind3DTechCategory
    public let status: WuMind3DTechStatus
    public let officialURL: String
    public let pinnedVersion: String
    public let supportedInputs: [String]
    public let supportedOutputs: [String]
    public let hardwareAndCost: String
    public let codeLicense: String
    public let weightsOrAssetLicense: String
    public let commercialUseAllowed: Bool
    public let redistributionAllowed: Bool
    public let complianceNotes: String
    public let testedSampleSummary: String
    public let lastVerifiedDate: String
}

public enum WuMind3DTechRegistry {
    public static let lastUpdatedDate = "2026-11-26"

    public static let entries: [WuMind3DTechEntry] = [
        // 1. CAD & Mechanical Modeling
        WuMind3DTechEntry(
            id: "cad.ezdxf",
            name: "ezdxf",
            category: .cadMechanical,
            status: .sampleVerified,
            officialURL: "https://ezdxf.readthedocs.io/en/stable/",
            pinnedVersion: "1.4.5",
            supportedInputs: ["Python 参数脚本", "DXF (R12–R2018)"],
            supportedOutputs: ["二维 DXF（图层/轮廓/中心线/尺寸标注）"],
            hardwareAndCost: "纯 CPU（开源免费，毫秒级运行，零 GPU 依赖）",
            codeLicense: "MIT",
            weightsOrAssetLicense: "无模型权重（纯几何库）",
            commercialUseAllowed: true,
            redistributionAllowed: true,
            complianceNotes: "仅原生处理 DXF，不直接读写专有 DWG；DWG 兼容须通过 ODA File Converter 或 LibreDWG 单独验证。",
            testedSampleSummary: "已跑通 160×120mm 四孔安装板 DXF（OUTLINE/HOLES/DIMENSIONS 分层），孔距由 120×80mm 改至 130×90mm 重生成并用独立 ezdxf.readfile 校验圆心与半径精确无误。",
            lastVerifiedDate: "2026-11-26"
        ),
        WuMind3DTechEntry(
            id: "cad.cadquery",
            name: "CadQuery",
            category: .cadMechanical,
            status: .sampleVerified,
            officialURL: "https://cadquery.readthedocs.io/en/latest/",
            pinnedVersion: "2.8.0 (OCP 7.9.x)",
            supportedInputs: ["Python 参数化实体脚本 (.py)", "STEP", "BREP"],
            supportedOutputs: ["ISO-10303-21 STEP", "STL", "AMF", "VRML", "DXF", "SVG"],
            hardwareAndCost: "纯 CPU（开源免费，单零件 <1s 生成，可部署服务端无头节点）",
            codeLicense: "Apache-2.0（底层 Open CASCADE 共享库为 LGPL-2.1 + OCCT Exception）",
            weightsOrAssetLicense: "无模型权重；原生参数工程为 .py 源文件",
            commercialUseAllowed: true,
            redistributionAllowed: true,
            complianceNotes: "必须保留原生 .py 参数脚本作为可编辑源工程；STEP/GLB 导出仅为边界几何/网格，绝不宣称保留完整建模历史。动态链接 OCCT 遵循 LGPL-2.1 例外条款。",
            testedSampleSummary: "已跑通四孔安装板参数化实体与 ISO STEP 导出；修改孔距 120×80→130×90mm 重新导出后，以独立 importStep() 重新读入校验外框 160×120×10mm、4 孔圆心坐标及精确净体积。",
            lastVerifiedDate: "2026-11-26"
        ),
        WuMind3DTechEntry(
            id: "cad.freecad",
            name: "FreeCAD",
            category: .cadMechanical,
            status: .researchCandidate,
            officialURL: "https://www.freecad.org/",
            pinnedVersion: "1.1.4",
            supportedInputs: ["FCStd 原生参数工程", "STEP", "IGES", "DXF", "BREP"],
            supportedOutputs: ["FCStd（保留特征树历史）", "STEP", "STL", "OBJ", "DXF", "TechDraw PDF"],
            hardwareAndCost: "桌面 / Linux 无头服务 CPU（开源免费；AppImage/容器体量约 600MB）",
            codeLicense: "LGPL-2.1-or-later",
            weightsOrAssetLicense: "无模型权重；FCStd 保留完整参数特征树",
            commercialUseAllowed: true,
            redistributionAllowed: true,
            complianceNotes: "只有原生 .FCStd 保存完整参数建模历史，STEP/GLB 不保留历史；DWG 导入导出依赖外部转换器，需单独验证。",
            testedSampleSummary: "已核对 1.1.4 官方发布与 LGPL-2.1 许可，当前作为桌面/服务端全功能 CAD 候选，零件级参数化与 STEP 样例已先由轻量 CadQuery 2.8.0 跑通。",
            lastVerifiedDate: "2026-11-26"
        ),

        // 2. Architecture & Interior Design (BIM)
        WuMind3DTechEntry(
            id: "bim.ifcopenshell",
            name: "IfcOpenShell",
            category: .architectureBIM,
            status: .sampleVerified,
            officialURL: "https://ifcopenshell.org/",
            pinnedVersion: "0.9.0.post1",
            supportedInputs: ["IFC2x3", "IFC4", "IFC4x3", "Python BIM 构件脚本"],
            supportedOutputs: ["标准 IFC4 / IFC4x3（保留楼层/墙/门洞/门窗语义与属性集）", "OBJ/glTF（经转换器）"],
            hardwareAndCost: "纯 CPU（开源免费，Python 服务端即可无头读写与校验 IFC）",
            codeLicense: "LGPL-3.0-or-later",
            weightsOrAssetLicense: "无模型权重（BIM 工程内核）",
            commercialUseAllowed: true,
            redistributionAllowed: true,
            complianceNotes: "图纸尺寸须显式区分「标注尺寸 / 扫描值 / 估算值」（通过自定义 Pset 属性集持久化）；服务端动态调用遵循 LGPL-3.0。",
            testedSampleSummary: "已跑通 IFC4 户型楼层/4 面墙/开洞/门构件生成；单独移动门 X=1800mm→2400mm 时联动更新 IfcOpeningElement 墙洞与尺寸标注，重新用 ifcopenshell.open() 外部校验通过。",
            lastVerifiedDate: "2026-11-26"
        ),
        WuMind3DTechEntry(
            id: "bim.bonsai",
            name: "Bonsai (原 BlenderBIM)",
            category: .architectureBIM,
            status: .researchCandidate,
            officialURL: "https://bonsaibim.org/",
            pinnedVersion: "0.8.x (IfcOpenShell 内置)",
            supportedInputs: ["IFC2x3 / IFC4 / IFC4x3", "Blender 场景"],
            supportedOutputs: ["原生编辑 IFC", "BIM 施工平面/立面 SVG 与 PDF"],
            hardwareAndCost: "桌面 Blender + CPU/GPU（开源免费，适合桌面专业端而非 iOS 移动端）",
            codeLicense: "GPL-3.0-or-later",
            weightsOrAssetLicense: "无模型权重",
            commercialUseAllowed: true,
            redistributionAllowed: true,
            complianceNotes: "GPL-3.0 强传染性仅适用于与 Bonsai/Blender 进程内链接的代码；若由云端独立子进程调用并通过 IFC 文件交换，不污染 iOS App 主工程。",
            testedSampleSummary: "已核对官方定位与 GPL-3.0 许可；作为桌面深度 BIM 复核工具候选，核心 IFC4 读写与门洞联动已先由 IfcOpenShell 0.9.0.post1 跑通。",
            lastVerifiedDate: "2026-11-26"
        ),
        WuMind3DTechEntry(
            id: "bim.roomplan",
            name: "Apple RoomPlan",
            category: .architectureBIM,
            status: .researchCandidate,
            officialURL: "https://developer.apple.com/augmented-reality/roomplan/",
            pinnedVersion: "iOS 16+ / iOS 17+ Multi-Room",
            supportedInputs: ["iPhone Pro / iPad Pro LiDAR 实时摄像头扫描"],
            supportedOutputs: ["CapturedRoom JSON（墙/门/窗/家具语义）", "参数化 USDZ"],
            hardwareAndCost: "端侧免费（仅支持带 LiDAR 激光雷达的 iPhone/iPad Pro，无云端推理费用）",
            codeLicense: "Apple SDK Terms（专有系统框架）",
            weightsOrAssetLicense: "端侧系统内置（不可提取）",
            commercialUseAllowed: true,
            redistributionAllowed: false,
            complianceNotes: "RoomPlan 测量结果为厘米级「扫描值」，严禁冒充施工图精确毫米「标注尺寸」；无 LiDAR 机型必须自动降级隐藏并改走图纸叠图路线。",
            testedSampleSummary: "当前 Linux/CI 模拟器无 LiDAR 硬件，暂列「研究候选」；需真机 iPhone/iPad Pro 实扫验收后再升级状态。",
            lastVerifiedDate: "2026-11-26"
        ),

        // 3. Large Environments & Game Scenes
        WuMind3DTechEntry(
            id: "world.godot",
            name: "Godot Engine (含 WuMind 场景导出链路)",
            category: .worldGameScene,
            status: .integratedAccepted,
            officialURL: "https://godotengine.org/",
            pinnedVersion: "4.7.2 (glTF 2.0 + .tscn)",
            supportedInputs: ["glTF 2.0 / .glb", ".tscn 文本场景树", "PBR 材质与碰撞体"],
            supportedOutputs: ["可运行 3D 关卡与实时漫游（桌面/移动/Web）"],
            hardwareAndCost: "开源免费、零分成（MIT）；移动端场景导出纯本地零成本",
            codeLicense: "MIT",
            weightsOrAssetLicense: "用户导出场景归属用户",
            commercialUseAllowed: true,
            redistributionAllowed: true,
            complianceNotes: "推荐以标准 glTF 2.0 (.glb) + 独立 .tscn 碰撞场景文件导入 Godot 4；保留 .wumind3d.json 作为可重开编辑源工程。",
            testedSampleSummary: "已接入验收「赤河镇」：修复西部描述变故宫路由问题，独立可编辑河流/主桥/火车站/酒馆，主街过桥连续可行走碰撞校验通过，离线本地导出 .wumind3d.json + 校验 .glb + Godot 4 .tscn（含 StaticBody3D 碰撞体）。",
            lastVerifiedDate: "2026-11-26"
        ),
        WuMind3DTechEntry(
            id: "world.polyhaven",
            name: "Poly Haven",
            category: .worldGameScene,
            status: .researchCandidate,
            officialURL: "https://polyhaven.com/license",
            pinnedVersion: "Public REST API v2 (CC0)",
            supportedInputs: ["关键词/分类检索（HDRI / PBR 贴图 / 3D 模型）"],
            supportedOutputs: ["EXR/HDR 环境光", "1K–8K PBR 贴图", "glTF / Blend / FBX 资产"],
            hardwareAndCost: "资产全部免费（CC0），仅需遵守官方 API 合理速率限制",
            codeLicense: "API 使用条款（网站源码/渲染图受网站条款约束）",
            weightsOrAssetLicense: "CC0 1.0 Universal（全部 HDRI、材质与 3D 模型）",
            commercialUseAllowed: true,
            redistributionAllowed: true,
            complianceNotes: "CC0 资产可商用、可随作品再分发且免署名；注意仅下载资产文件本身，勿批量抓取网站界面或违反 API 速率规范。",
            testedSampleSummary: "已核对 CC0 1.0 许可与 API 规范，列为真实 PBR 贴图与环境 HDRI 资产库首选候选。",
            lastVerifiedDate: "2026-11-26"
        ),
        WuMind3DTechEntry(
            id: "world.infinigen",
            name: "Infinigen",
            category: .worldGameScene,
            status: .researchCandidate,
            officialURL: "https://infinigen.org/",
            pinnedVersion: "2.0.0a4 (princeton-vl/infinigen)",
            supportedInputs: ["程序化自然/室内配置参数（Python + Blender）"],
            supportedOutputs: ["高细节程序化自然地形/植被/室内 Blender 场景与导出网格"],
            hardwareAndCost: "Linux 多核 CPU + NVIDIA GPU 渲染（开源免费，但单场景生成需分钟级算力，仅适合云端批处理节点）",
            codeLicense: "BSD-3-Clause（部分脚本 CC0；运行依赖 Blender GPL-3.0）",
            weightsOrAssetLicense: "程序化生成几何归属使用者",
            commercialUseAllowed: true,
            redistributionAllowed: true,
            complianceNotes: "必须作为独立云端工作节点运行（通过队列返回 GLB/Blend），不可在移动端本地运行。",
            testedSampleSummary: "已核对仓库许可与 Blender 运行依赖，列为云端高精度自然地形与室内程序化生成候选。",
            lastVerifiedDate: "2026-11-26"
        ),
        WuMind3DTechEntry(
            id: "world.unreal_pcg",
            name: "Unreal Engine PCG",
            category: .worldGameScene,
            status: .researchCandidate,
            officialURL: "https://dev.epicgames.com/documentation/en-us/unreal-engine/procedural-content-generation-overview",
            pinnedVersion: "Unreal Engine 5.x PCG Framework",
            supportedInputs: ["样条线/地形/建筑占位体/点云规则图"],
            supportedOutputs: ["大规模实时开放世界关卡（Nanite/Lumen）"],
            hardwareAndCost: "桌面级高性能 GPU（单品总收入 \$1M 以下免分成，超 \$1M 收 5% 分成）",
            codeLicense: "Unreal Engine EULA（专有商业许可）",
            weightsOrAssetLicense: "取决于引入的 Fab/第三方资产许可",
            commercialUseAllowed: true,
            redistributionAllowed: false,
            complianceNotes: "不得再分发引擎编辑器本身；移动端 WUMIND 仅导出开放标准 GLB/JSON 供桌面端 UE 导入，不绑定 UE 运行时。",
            testedSampleSummary: "已核对 UE 5.x PCG 文档与 5% 分成门槛，列为桌面端影视/AAA 级大场景外部衔接目标。",
            lastVerifiedDate: "2026-11-26"
        ),

        // 4. Single Asset & Reference-Image-to-3D
        WuMind3DTechEntry(
            id: "asset.trellis2",
            name: "Microsoft TRELLIS.2",
            category: .singleAssetImageTo3D,
            status: .researchCandidate,
            officialURL: "https://github.com/microsoft/TRELLIS.2",
            pinnedVersion: "TRELLIS.2-4B",
            supportedInputs: ["单张清晰物体参考图（去背效果最佳）"],
            supportedOutputs: ["带 PBR 材质（Albedo/Roughness/Metallic）的可编辑三角网格 GLB"],
            hardwareAndCost: "需云端 NVIDIA CUDA GPU ≥ 24GB 显存（约 3–60 秒/件，按云 GPU 时长计费；不可跑在 iPhone 本地）",
            codeLicense: "MIT",
            weightsOrAssetLicense: "主权重 MIT（注意部分辅助编码器如 DINOv3 在 Hugging Face 有独立门控许可，部署前需逐项核对）",
            commercialUseAllowed: true,
            redistributionAllowed: true,
            complianceNotes: "输出须经网格拓扑与 PBR 贴图解码校验后才能标记可用；绝不把点云或 3D Gaussian Splat 冒充为可编辑网格。",
            testedSampleSummary: "当前环境无 24GB NVIDIA GPU，诚实标为「研究候选」；已列为云端单物体参考图转 PBR GLB 的第一顺位接入方案。",
            lastVerifiedDate: "2026-11-26"
        ),
        WuMind3DTechEntry(
            id: "asset.hunyuan3d",
            name: "Tencent Hunyuan3D 2.1",
            category: .singleAssetImageTo3D,
            status: .researchCandidate,
            officialURL: "https://github.com/Tencent-Hunyuan/Hunyuan3D-2.1",
            pinnedVersion: "2.1 (Shape + PBR Paint)",
            supportedInputs: ["单张/多视角参考图"],
            supportedOutputs: ["白模网格（10GB 显存）+ PBR 贴图网格 GLB/OBJ（21–29GB 显存）"],
            hardwareAndCost: "需云端 NVIDIA GPU（仅白模 10GB / 含 PBR 贴图 21–29GB 显存）",
            codeLicense: "Tencent Hunyuan 3D 2.1 Community License（非 OSI 宽松许可）",
            weightsOrAssetLicense: "Tencent Hunyuan 3D 2.1 Community License",
            commercialUseAllowed: true,
            redistributionAllowed: false,
            complianceNotes: "重要合规红线：社区许可排除欧盟、英国、韩国地区商业使用；月活超 100 万须另购商业授权；生成结果不得用于训练其他 AI 模型。",
            testedSampleSummary: "已核对显存需求与地域/MAU 许可红线；因无 GPU 环境暂列「研究候选」，上线前须按目标发行地区确认合规性。",
            lastVerifiedDate: "2026-11-26"
        ),
        WuMind3DTechEntry(
            id: "asset.sam3d",
            name: "Meta SAM 3D Objects",
            category: .singleAssetImageTo3D,
            status: .researchCandidate,
            officialURL: "https://github.com/facebookresearch/sam-3d-objects",
            pinnedVersion: "2025/2026 Release",
            supportedInputs: ["单张自然场景图 + 目标物体 Mask 分割"],
            supportedOutputs: ["3D Gaussian Splat / 转换后带纹理网格（需实测网格质量）"],
            hardwareAndCost: "需云端 NVIDIA GPU（先分割再重建，输出转换网格需额外耗时）",
            codeLicense: "SAM License（允许商用生成，衍生模型须保留 SAM License，禁止军事及违禁用途）",
            weightsOrAssetLicense: "SAM License（需通过 Hugging Face 门控申请）",
            commercialUseAllowed: true,
            redistributionAllowed: false,
            complianceNotes: "严格红线：SAM 3D 原生 Gaussian Splat 预览仅供观看，绝不可标注为「可编辑网格模型」；仅在导出并校验带贴图封闭网格后方可进入编辑管线。",
            testedSampleSummary: "已核对 SAM License 与 Splat/Mesh 边界；当前环境无 GPU 与门控权重，诚实标为「研究候选」。",
            lastVerifiedDate: "2026-11-26"
        ),

        // 5. Character, Clothing, Rigging & Animation
        WuMind3DTechEntry(
            id: "char.blender",
            name: "Blender（含现有绑骨人形 GLB 管线验证）",
            category: .characterRigAnimation,
            status: .sampleVerified,
            officialURL: "https://www.blender.org/",
            pinnedVersion: "4.x (glTF 2.0 Armature + Skinning)",
            supportedInputs: ["人形网格", "Armature 骨骼", "动作关键帧", "GLB/FBX/Blend"],
            supportedOutputs: ["带标准骨骼、蒙皮权重与多段动画轨道的 GLB"],
            hardwareAndCost: "开源免费（Linux 无头 CLI 可批处理导出与体检）",
            codeLicense: "GPL-3.0-or-later（创作出的模型与导出 GLB 归创作者所有，不受 GPL 传染）",
            weightsOrAssetLicense: "导出资产归创作者（须单独核对第三方贴图/基础人体许可）",
            commercialUseAllowed: true,
            redistributionAllowed: true,
            complianceNotes: "Blender 导出作品不受 GPL 传染；但任何打包进 App 的插件脚本或内置基础网格须独立留存许可证明。",
            testedSampleSummary: "已实测校验仓库内置绑骨人形资产 DuelChar_wuYong.glb（骨骼节点、蒙皮权重、待机/移动/攻击多段动画轨道及标准人形身高均通过独立解析脚本核验）。",
            lastVerifiedDate: "2026-11-26"
        ),
        WuMind3DTechEntry(
            id: "char.mpfb2",
            name: "MPFB2 (MakeHuman for Blender 2)",
            category: .characterRigAnimation,
            status: .researchCandidate,
            officialURL: "https://static.makehumancommunity.org/mpfb.html",
            pinnedVersion: "2.0.x",
            supportedInputs: ["参数化身高/体型/性别/服装滑块（Blender 插件）"],
            supportedOutputs: ["带 Rigify/GameEngine 骨骼的写实人形网格 + 服装资产"],
            hardwareAndCost: "桌面/无头 Blender CPU 即可生成（开源免费）",
            codeLicense: "AGPL-3.0（核心插件代码）",
            weightsOrAssetLicense: "MakeHuman 官方基础人体与核心资产为 CC0（第三方社区服装包须逐包核对许可！）",
            commercialUseAllowed: true,
            redistributionAllowed: true,
            complianceNotes: "核心代码为 AGPL-3.0（若通过网络服务对外提供插件改造版需注意 AGPL 源码公开义务）；但 CC0 基础网格生成出的角色模型可自由商用。",
            testedSampleSummary: "已核对 AGPL-3.0 代码与 CC0 资产双许可边界，列为参数化可定制角色与服装生成候选。",
            lastVerifiedDate: "2026-11-26"
        ),
        WuMind3DTechEntry(
            id: "char.mixamo",
            name: "Adobe Mixamo",
            category: .characterRigAnimation,
            status: .researchCandidate,
            officialURL: "https://www.mixamo.com/",
            pinnedVersion: "Web Service (Auto-Rig + Mocap FBX)",
            supportedInputs: ["无绑骨 T-Pose / A-Pose 人形 OBJ/FBX"],
            supportedOutputs: ["自动绑骨人形 FBX + 待机/行走/跑跳动作库"],
            hardwareAndCost: "个人免费 Adobe ID 可用（无官方公开商用 API，仅人工网页端使用）",
            codeLicense: "Adobe Terms of Use / Mixamo FAQ（专有在线服务）",
            weightsOrAssetLicense: "免版税用于成品游戏/影视项目，严禁作为独立素材包再分发原始 FBX/动画文件，严禁用于 ML/AI 训练",
            commercialUseAllowed: true,
            redistributionAllowed: false,
            complianceNotes: "重要限制：① 不可再分发原始 Mixamo 角色或动作文件给第三方用户下载；② 不支持中国大陆区号 Adobe ID 及企业/联合账号；③ 无服务端 API，绝不可集成到自动后端流水线。",
            testedSampleSummary: "已核对 Adobe 官方条款、地区限制与不可再分发红线，仅列为人工桌面原型参考「研究候选」，严禁作为 WUMIND 服务端自动分发资产源。",
            lastVerifiedDate: "2026-11-26"
        ),
    ]

    public static func entries(for category: WuMind3DTechCategory) -> [WuMind3DTechEntry] {
        entries.filter { $0.category == category }
    }

    public static func count(with status: WuMind3DTechStatus) -> Int {
        entries.filter { $0.status == status }.count
    }
}
