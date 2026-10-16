> 历史设计快照（2026-10-14）。2026-10-16已统一为current-minus-baseline，并等价迁移演示C/前向模型；下文原约定与初始测试数量仅留设计历史。当前行为、范围和验证以项目README及仓库修正结果为准。

# Integrated Thermal Lab Prototype Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Deliver a usable simulated integrated acquisition prototype with MATLAB source and a directly runnable browser preview.

**Architecture:** One shared communication owner and two business modules under an experiment state machine. MATLAB and browser deliverables are independent implementations of the same workflow, with no hardware I/O.

**Tech Stack:** MATLAB R2021b base GUI; dependency-free JavaScript/HTML/CSS; Node test; Playwright.

**Spec:** ../specs/2026-10-14-integrated-lab-design.md

## Global Constraints

- simulation-only; no real serial open, hardware writes, or silent mode fallback.
- A bed/B columns/C beam; 18 temperatures, 3 probes, 6 branches.
- single serialized communication owner; actual UTC and wall elapsed recorded separately from simulated thermal time.
- one baseline per experiment; confirmed stopped/positioned/oriented effective windows only; errors and overrange retained as invalid.
- demo 1-second interval, 2-second settle, 5 points, 120x thermal clock; C and range as spec, clearly illustrative.
- exports raw, event, window and metadata records; fixed group while experiment active.

## Review Focus

1. Early start or repeated baseline: reject without changing baseline.
2. Lost pose confirmation during waiting/measurement: invalidate, never append valid XYZ.
3. Communications error/cancelled partial window: preserve provenance and error; recovery keeps baseline and resets pose.
4. Reentrant polling or queued valve writes: no concurrent transport execution.
5. Export before valid heat window or after fault: preserve headers and empty/invalid semantics, not fake zeros.

### Task 1: MATLAB standalone prototype

**Files:** matlab/IntegratedThermalLab.m; matlab/+itl/{defaultConfig,LabEngine,SerialScheduler,SimTransport,exportSession}.m; matlab/run_core_tests.m.
**Interfaces:** LabEngine owns config/state/logs/transport; GUI calls public methods defined by implementer and documented; no cross-dependency on browser source.
- [ ] Write behavioral assertions for baseline gates, immutable baseline, pose invalidation, overrange, fault/recovery, queue serialization and cancellation before core code.
- [ ] Implement core, simulated transport and serial scheduler; provide substantive MATLAB tests.
- [ ] Implement Chinese GUI with automatic demo, group, three pose checks, run/return/window, fault buttons, live views and export.
- [ ] Parse all MATLAB files and self-review R2021b APIs. Report unavailable MATLAB runtime explicitly.
- [ ] Review against spec with independent reviewer and resolve Important/Critical findings.

### Task 2: Browser preview and executable regression suite

**Files:** preview/lab-engine.js; preview/index.html; preview/ui.js; preview/style.css; preview/tests/lab-engine.test.js; preview/tests/browser-smoke.cjs.
**Interfaces:** public engine snapshot/action/tick/export functions shared with browser view; no external dependency in preview.
- [ ] Write tests and observe missing-feature failures: baseline, timing, pose gating, frozen group, invalid range, fault/cancel, FIFO single-owner transport and export.
- [ ] Implement minimal model and pass the entire Node suite.
- [ ] Build Chinese dashboard and automatic demo using public engine methods.
- [ ] Run Playwright manual/automatic workflows, export downloads, error paths, console checks and screenshot inspection.
- [ ] Independently review the entire prototype and fix findings.

### Task 3: Packaging and reviewable delivery

**Files:** README.md; config/device_map_template.csv; config/hardware_readiness.md; preview.png; ZIP bundle generated outside source root.
- [ ] Document exact MATLAB and browser launch steps, demo parameters, data meaning, tests and unverified hardware/runtime.
- [ ] Verify bundle contains all launch dependencies and opens offline.
- [ ] Publish verified files to an isolated GitHub prototype branch; keep existing programs intact and create a reviewable draft PR if supported.
- [ ] Read back file SHAs and update current conversation archive per archive-repository instructions.
