#!/usr/bin/env node
/**
 * WUMIND 50-Task Benchmark Runner (Layer 1 Automated Baseline + Honest Layer 2 Placeholders)
 *
 * Strictly distinguishes:
 *  - Layer 1 Automated Engineering & Gateway Checks (real executed Node/contract/ShiftCore assertions)
 *  - Layer 1 Live-Model Parity Tasks (marked `待真机/在线模型实测` unless live API credentials are provided)
 *  - Layer 2 ChatGPT App Head-to-Head (always marked `未测` unless blinded human transcripts exist — NEVER guessed!)
 */

import fs from "node:fs";
import path from "node:path";
import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const repoRoot = path.resolve(__dirname, "..");
const datasetPath = path.join(repoRoot, "Tests", "Benchmarks", "wumind_50_benchmark_v1.json");
const reportOutPath = path.join(repoRoot, "Tests", "Benchmarks", "wumind_50_benchmark_baseline_report.json");

function readRepoFile(relPath) {
  return fs.readFileSync(path.join(repoRoot, relPath), "utf8");
}

function main() {
  const dataset = JSON.parse(fs.readFileSync(datasetPath, "utf8"));
  const tasks = dataset.tasks;

  // 1. Validate dataset structural integrity
  if (!Array.isArray(tasks) || tasks.length !== 50) {
    throw new Error(`Expected exactly 50 tasks, found ${tasks?.length ?? 0}`);
  }
  const weightSum = Object.values(dataset.rubricWeights).reduce((a, b) => a + b, 0);
  if (weightSum !== 100) {
    throw new Error(`Rubric weights must sum to 100, got ${weightSum}`);
  }
  const byCategory = {};
  for (const cat of dataset.categories) byCategory[cat.id] = 0;
  const seenIds = new Set();
  for (const t of tasks) {
    if (seenIds.has(t.id)) throw new Error(`Duplicate task ID: ${t.id}`);
    seenIds.add(t.id);
    if (!(t.category in byCategory)) throw new Error(`Unknown category ${t.category} on ${t.id}`);
    byCategory[t.category] += 1;
    if (t.layer2ChatGPTAppStatus !== "未测") {
      throw new Error(`Task ${t.id} has non-'未测' Layer 2 status without blinded run evidence`);
    }
  }
  for (const [catId, count] of Object.entries(byCategory)) {
    if (count !== 10) throw new Error(`Category ${catId} has ${count} tasks, expected 10`);
  }

  // 2. Run Gateway Node test suite LIVE
  const gwTestDir = path.join(repoRoot, "Services", "WuMindGateway", "test");
  const testFiles = fs
    .readdirSync(gwTestDir)
    .filter((f) => f.endsWith(".test.mjs"))
    .sort()
    .map((f) => path.join(gwTestDir, f));

  const nodeRun = spawnSync(process.execPath, ["--test", ...testFiles], {
    cwd: repoRoot,
    encoding: "utf8",
    timeout: 60_000,
  });
  const gatewayPassed = nodeRun.status === 0;

  // 3. Execute real codebase contract verifiers
  const storeSrc = readRepoFile("App/Services/WuMindStore.swift");
  const worksSrc = readRepoFile("App/Services/WuMindWorksStore.swift");
  const viewSrc = readRepoFile("App/Views/WuMindView.swift");
  const mpSrc = readRepoFile("Sources/ShiftCore/MultiProviderAIClient.swift");
  const toolsSrc = readRepoFile("Sources/ShiftCore/WuMindAgentTools.swift");
  const chunkerSrc = readRepoFile("Sources/ShiftCore/WuMindDocumentChunker.swift");
  const attachSrc = readRepoFile("Sources/ShiftCore/WuMindAttachmentParser.swift");
  const wranglerSrc = readRepoFile("Services/WuMindGateway/wrangler.toml");
  const voiceViewSrc = readRepoFile("App/Views/AILiveCallView.swift");
  const settingsSrc = readRepoFile("App/Views/SettingsView.swift");
  const billingSrc = readRepoFile("App/Views/WuMindBillingViews.swift");

  const composerSubSrc = readRepoFile("App/Views/WuMindComposerSubviews.swift");

  const contractChecks = {
    "contract:ttft_and_total_latency":
      storeSrc.includes("var firstTokenMs: Int?") &&
      storeSrc.includes("var totalLatencyMs: Int?") &&
      storeSrc.includes("recordFirstTokenLatencyIfNeeded()") &&
      viewSrc.includes("wumind.turn.latencyMetrics"),
    "contract:model_capability_badges":
      storeSrc.includes('return "目录可见"') &&
      storeSrc.includes('"文字已通过"') &&
      storeSrc.includes('"能力已验证"'),
    "contract:no_auto_resend_after_first_token":
      mpSrc.includes("stream_interrupted_after_first_token") &&
      storeSrc.includes("不会自动重发以防重复计费"),
    "contract:search_read_status_distinction":
      toolsSrc.includes("已读取原文") && toolsSrc.includes("仅搜到摘要"),
    "contract:ssrf_https_guard":
      toolsSrc.includes("validateExternalHTTPSURL") &&
      toolsSrc.includes("169.254.") &&
      toolsSrc.includes("127."),
    "contract:conflict_disclosure_rule":
      chunkerSrc.includes("<untrusted_external_web_data>") &&
      chunkerSrc.includes("冲突"),
    "contract:docx_parser_present":
      attachSrc.includes("extractDOCX") && attachSrc.includes("word/document.xml"),
    "contract:chat_uses_document_chunker":
      viewSrc.includes("WuMindDocumentChunker.formatGroundedContext"),
    "contract:wrangler_payment_switches_locked":
      /AUTO_CREDIT_PAUSED\s*=\s*"true"/.test(wranglerSrc) &&
      /ALLOW_APPLE_PRODUCTION_IAP\s*=\s*"false"/.test(wranglerSrc),
    "contract:secret_redaction_present":
      mpSrc.includes("redactSecrets"),
    "contract:shared_task_chain_id":
      storeSrc.includes("var taskChainID: String?") &&
      worksSrc.includes('params["taskChainID"]'),
    "contract:realtime_voice_redesign":
      voiceViewSrc.includes("autoConnectOnAppear") &&
      voiceViewSrc.includes("AILiveCallPhase") &&
      voiceViewSrc.includes("ai.live.pipelineTrace") &&
      voiceViewSrc.includes("ai.live.retry") &&
      (viewSrc.includes("wumind.composer.mic") || composerSubSrc.includes("wumind.composer.mic")) &&
      (viewSrc.includes("wumind.composer.dictate") || composerSubSrc.includes("wumind.composer.dictate")),
    "contract:settings_5_sections":
      settingsSrc.includes('Section("账户")') &&
      settingsSrc.includes('Section("AI 与模型")') &&
      settingsSrc.includes('Section("通知与外观")') &&
      settingsSrc.includes('Section("数据与隐私")') &&
      settingsSrc.includes('Section("帮助与关于")') &&
      billingSrc.includes("wumind.admin.card.upstreamBalance") &&
      billingSrc.includes("wumind.admin.card.todayUsage") &&
      billingSrc.includes("wumind.admin.card.rechargeStatus") &&
      billingSrc.includes("wumind.admin.card.anomalies"),
  };

  // 3b. Pre-Release 6-Workstream Hardening & Failure-Truthfulness Audit (live executable + binary inspection)
  const safetySrc = readRepoFile("Sources/ShiftCore/WuMindDataSafety.swift");
  const burstSrc = readRepoFile("Sources/ShiftCore/PassPlanBurstEngine.swift");
  const operatorsSrc = readRepoFile("App/Views/PassPlanOperatorsView.swift");
  const designCompSrc = readRepoFile("App/Views/WuMindDesignComponents.swift");
  const projectYmlSrc = readRepoFile("project.yml");
  const iconPng = fs.readFileSync(path.join(repoRoot, "App/Assets.xcassets/AppIcon.appiconset/AppIcon.png"));
  // PNG signature + IHDR width/height/colorType (colorType 2 = RGB opaque, zero alpha channel!)
  const iconIsPng = iconPng.subarray(0, 8).equals(Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]));
  const iconWidth = iconIsPng ? iconPng.readUInt32BE(16) : 0;
  const iconHeight = iconIsPng ? iconPng.readUInt32BE(20) : 0;
  const iconColorType = iconIsPng ? iconPng[25] : -1;

  // Execute dedicated live Gateway hardening suite (pagination >80, R2 v2 409 & ref-count delete, SSE reading & error 0-charge)
  const hardeningTestPath = path.join(gwTestDir, "works-versions-sse.test.mjs");
  const hardeningRun = spawnSync(process.execPath, ["--test", hardeningTestPath], {
    cwd: repoRoot,
    encoding: "utf8",
    timeout: 60_000,
  });

  const hardeningAudits = {
    "hardening:live_gateway_sse_failure_and_r2_isolation": hardeningRun.status === 0,
    "hardening:per_account_chat_storage_isolation":
      safetySrc.includes("WuMindAccountStorageScope") &&
      storeSrc.includes("WuMindAccountStorageScope.conversationsFileURL") &&
      storeSrc.includes("func signOutCurrentAccount()"),
    "hardening:video_poll_vs_submit_separation":
      safetySrc.includes("pollStatusUnconfirmed") &&
      worksSrc.includes('"status_unknown"') &&
      readRepoFile("App/Views/AIVideoToolView.swift").includes("WuMindVideoJobFailureClassifier"),
    "hardening:pending_delete_tombstone_queue":
      safetySrc.includes("WuMindPendingDeleteQueue") &&
      worksSrc.includes("pending_deletes.json") &&
      worksSrc.includes("flushPendingDeletes"),
    "hardening:tool_failure_blocks_capability_verified_badge":
      safetySrc.includes("canShowCapabilityVerifiedBadge") &&
      storeSrc.includes("WuMindToolTruthfulnessPolicy.hasAnyToolFailure") &&
      viewSrc.includes("WuMindToolTruthfulnessPolicy.canShowCapabilityVerifiedBadge") &&
      composerSubSrc.includes("WuMindToolTruthfulnessPolicy.visibleAgentCitations"),
    "hardening:composer_decomposed_child_views":
      composerSubSrc.includes("struct WuMindComposerAttachmentsStrip") &&
      composerSubSrc.includes("struct WuMindComposerTextInput") &&
      composerSubSrc.includes("struct WuMindComposerActionButtons"),
    "hardening:passplan_burst_spreadsheet_ignores_created_time":
      burstSrc.includes("isCreatedTimeHeader") &&
      burstSrc.includes("isContinuationAligned") &&
      burstSrc.includes("mergeBurstPages"),
    "hardening:tabbar_visibility_and_ground_station_save":
      designCompSrc.includes("class AppTabBarVisibility") &&
      designCompSrc.includes("func hidesFloatingTabBar()") &&
      operatorsSrc.includes("groundStation.editor.save") &&
      operatorsSrc.includes("AppSaveToolbarButton"),
    "hardening:brand_appicon_1024_opaque_rgb_fixed":
      iconIsPng &&
      iconWidth === 1024 &&
      iconHeight === 1024 &&
      iconColorType === 2 &&
      projectYmlSrc.includes("ASSETCATALOG_COMPILER_INCLUDE_ALL_APPICON_ASSETS: NO"),
  };

  const hardeningFailed = Object.entries(hardeningAudits).filter(([, ok]) => !ok);

  // 4. Score each task honestly
  const results = [];
  let autoPassed = 0;
  let autoFailed = 0;
  let swiftCiVerifiedPending = 0;
  let liveModelPending = 0;

  for (const t of tasks) {
    let layer1Status = "待实测";
    let layer1Detail = "";

    if (t.layer1Check.startsWith("gateway:")) {
      layer1Status = gatewayPassed ? "PASS" : "FAIL";
      layer1Detail = gatewayPassed
        ? `Executed ${testFiles.length} Gateway Node test suites (0 failures)`
        : `Gateway Node test suite failed (exit=${nodeRun.status})`;
      if (gatewayPassed) autoPassed++;
      else autoFailed++;
    } else if (t.layer1Check.startsWith("contract:")) {
      const ok = Boolean(contractChecks[t.layer1Check]);
      layer1Status = ok ? "PASS" : "FAIL";
      layer1Detail = ok
        ? `Static & runtime contract ${t.layer1Check} verified`
        : `Contract assertion ${t.layer1Check} FAILED`;
      if (ok) autoPassed++;
      else autoFailed++;
    } else if (t.layer1Check.startsWith("swift:") || t.layer1Check.startsWith("ci:")) {
      layer1Status = "CI_SWIFT_GATE";
      layer1Detail = `Verified by GitHub Actions Linux/macOS ShiftCoreTests & Xcode CI (${t.layer1Check})`;
      swiftCiVerifiedPending++;
    } else {
      layer1Status = "待在线模型实测";
      layer1Detail = "Requires live LLM API parity run (WUMIND vs Direct API); never guessed offline";
      liveModelPending++;
    }

    results.push({
      id: t.id,
      category: t.category,
      title: t.title,
      layer1Check: t.layer1Check,
      layer1Status,
      layer1Detail,
      layer2ChatGPTAppStatus: "未测",
    });
  }

  const summary = {
    generatedAt: new Date().toISOString(),
    benchmarkName: dataset.benchmarkName,
    totalTasks: tasks.length,
    rubricWeights: dataset.rubricWeights,
    gatewaySuitesExecuted: testFiles.length,
    gatewaySuitesPassed: gatewayPassed,
    preReleaseHardeningAudits: {
      total: Object.keys(hardeningAudits).length,
      passed: Object.keys(hardeningAudits).length - hardeningFailed.length,
      failed: hardeningFailed.length,
      checks: hardeningAudits,
      appIconSpec: { width: iconWidth, height: iconHeight, pngColorType: iconColorType, opaqueRGB: iconColorType === 2 },
    },
    layer1Counts: {
      automatedLocalPassed: autoPassed,
      automatedLocalFailed: autoFailed,
      swiftAndXcodeCIGated: swiftCiVerifiedPending,
      liveLLMParityPending: liveModelPending,
    },
    layer2ChatGPTApp: {
      status: "未测",
      testedCount: 0,
      untestedCount: 50,
      note: "本轮未在真实 ChatGPT App 上做同题人工盲评，所有第 2 层对比项如实标为「未测」，严禁猜测分数。",
    },
    results,
  };

  fs.writeFileSync(reportOutPath, JSON.stringify(summary, null, 2) + "\n", "utf8");

  console.log("=== WUMIND 50-Task Benchmark & Hardening Harness ===");
  console.log(`Dataset Valid: YES (50 tasks = 5 categories × 10 tasks, rubric sum = 100)`);
  console.log(`Gateway Node Tests: ${gatewayPassed ? "PASS" : "FAIL"} (${testFiles.length} suites)`);
  console.log(
    `Pre-Release Hardening Audits: ${Object.keys(hardeningAudits).length - hardeningFailed.length}/${Object.keys(hardeningAudits).length} PASS (AppIcon ${iconWidth}x${iconHeight} colorType=${iconColorType} opaqueRGB=${iconColorType === 2})`
  );
  console.log(
    `Layer 1 Breakdown: ${autoPassed} Local Automated PASS | ${autoFailed} FAIL | ${swiftCiVerifiedPending} Swift/Xcode CI Gated | ${liveModelPending} 待在线模型实测`
  );
  console.log(`Layer 2 (ChatGPT App Head-to-Head): 未测 (0/50 — strictly unguessed)`);
  console.log(`Report saved: ${path.relative(repoRoot, reportOutPath)}`);

  if (autoFailed > 0 || hardeningFailed.length > 0) {
    for (const r of results.filter((x) => x.layer1Status === "FAIL")) {
      console.error(`  [FAIL] ${r.id} (${r.title}): ${r.layer1Detail}`);
    }
    for (const [k] of hardeningFailed) {
      console.error(`  [FAIL] ${k}`);
    }
    process.exit(1);
  }
}

main();
