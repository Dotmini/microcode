import React, { useState } from 'react';

export interface ProductionBenchmarkSectionProps {
  isMobile?: boolean;
}

type BenchmarkTab = 'coldstart' | 'memory' | 'tokenmem' | 'disk' | 'raw';

export const ProductionBenchmarkSection: React.FC<ProductionBenchmarkSectionProps> = ({ isMobile = false }) => {
  const [activeTab, setActiveTab] = useState<BenchmarkTab>('coldstart');

  const controlledSpecs = [
    { label: 'Hardware Host', value: 'Apple M2 (8-Core · 16 GB Unified RAM)' },
    { label: 'OS & Kernel', value: 'macOS 27.0 (Darwin 26.0.0 arm64)' },
    { label: 'Controlled Workspace', value: '500 Files · 49,350 LOC Polyglot' },
    { label: 'Fixture SHA-256', value: 'c5504e49e51fe7af...f1d946f2f' },
    { label: 'WindowServer Probe', value: '500 Hz CoreGraphics (2 ms step)' },
    { label: 'Trial Protocol', value: '1 Warmup + 5 Clean-Start Trials' },
  ];

  const kpiCards = [
    {
      metric: '493.0 ms',
      subMetric: 'Min 458.7 ms · Mean 502.0 ms',
      title: 'Cold-Start to Window Ready',
      detail: 'เร็วกว่า VS Code / Electron 4.43 เท่า และเร็วกว่า Zed 1.62 เท่า',
    },
    {
      metric: '194.8 MB',
      subMetric: 'Min 173.5 MB · 1 Native Process',
      title: 'Total Process-Tree RAM',
      detail: 'ใช้หน่วยความจำน้อยกว่า VS Code 4.83 เท่า (ปราศจาก Chromium Helper)',
    },
    {
      metric: '81.3%',
      subMetric: '7,170 vs 38,400 Tokens @ Turn 15',
      title: 'TokenMem v3 Reduction',
      detail: 'ประหยัด AI Context Token กว่า IDE Agent ทั่วไป 5.35 เท่า พร้อม Cache Hit 84%',
    },
    {
      metric: '95.7 MB',
      subMetric: 'Universal Mach-O arm64 Binary',
      title: 'Application Disk Footprint',
      detail: 'ขนาดไฟล์ติดตั้งเล็กกว่า VS Code 7.66 เท่า และเล็กกว่า Zed 4.20 เท่า',
    },
  ];

  const coldStartData = [
    {
      name: 'MicroCode IDE',
      version: 'v2.5.32',
      arch: 'Native Swift + AppKit + Metal 3 + Rust Core',
      medianMs: 493.0,
      minMs: 458.7,
      meanMs: 502.0,
      stdevMs: 45.0,
      ratio: '1.00x (Fastest)',
      highlight: true,
    },
    {
      name: 'OpenCode Desktop',
      version: 'v1.2.4',
      arch: 'Rust Tauri + WebKit WKWebView',
      medianMs: 566.7,
      minMs: 544.9,
      meanMs: 761.7,
      stdevMs: 279.1,
      ratio: '1.15x slower',
      highlight: false,
    },
    {
      name: 'Zed',
      version: 'v1.18.0',
      arch: 'Native Rust + GPUI Metal',
      medianMs: 798.4,
      minMs: 695.1,
      meanMs: 786.2,
      stdevMs: 57.4,
      ratio: '1.62x slower',
      highlight: false,
    },
    {
      name: 'VS Code / Code-OSS',
      version: 'v2.5.5',
      arch: 'Electron + Chromium + Node.js V8',
      medianMs: 2186.1,
      minMs: 1854.8,
      meanMs: 2143.5,
      stdevMs: 172.7,
      ratio: '4.43x slower',
      highlight: false,
    },
  ];

  const memoryData = [
    {
      name: 'MicroCode IDE',
      version: 'v2.5.32',
      arch: 'Single-Process Native Mach-O (1 Process · 20 Threads)',
      medianMb: 194.8,
      minMb: 173.5,
      meanMb: 187.5,
      processes: 1,
      threads: 20,
      ratio: '1.00x (Lowest RAM)',
      highlight: true,
    },
    {
      name: 'OpenCode Desktop',
      version: 'v1.2.4',
      arch: 'Tauri Host + WebKit Networking/GPU (2 Processes · 37 Threads)',
      medianMb: 214.6,
      minMb: 207.2,
      meanMb: 216.5,
      processes: 2,
      threads: 37,
      ratio: '1.10x RAM',
      highlight: false,
    },
    {
      name: 'Zed',
      version: 'v1.18.0',
      arch: 'GPUI + Local Extension Server (2 Processes · 47 Threads)',
      medianMb: 219.2,
      minMb: 219.1,
      meanMb: 220.4,
      processes: 2,
      threads: 47,
      ratio: '1.13x RAM',
      highlight: false,
    },
    {
      name: 'VS Code / Code-OSS (Clean Single Window)',
      version: 'v2.5.5',
      arch: 'Electron Main + GPU + Renderer + Extension Host (6–16 Processes · 151 Threads)',
      medianMb: 941.7,
      minMb: 931.0,
      meanMb: 999.1,
      processes: 6,
      threads: 151,
      ratio: '4.83x RAM',
      highlight: false,
    },
    {
      name: 'Electron AI IDE (Active Multi-Window + Agent Session)',
      version: 'Reference',
      arch: 'Chromium Helpers + TS Server + Node Workers (37 Processes · 451 Threads)',
      medianMb: 3029.8,
      minMb: 3029.8,
      meanMb: 3029.8,
      processes: 37,
      threads: 451,
      ratio: '15.55x RAM',
      highlight: false,
    },
  ];

  const tokenMemData = [
    {
      name: 'MicroCode IDE (TokenMem v3 6-Layer Optimizer)',
      arch: 'AST Skeletonizer + Observation Masking + Prefix Cache Pinning + Sub-Agent Isolation',
      turn15Tokens: 7170,
      cumulativeTokens: 64850,
      cacheHitRate: '84.0%',
      savings: '81.3% Saved (#1)',
      highlight: true,
    },
    {
      name: 'Zed / OpenCode Agent (Sliding Window Truncation)',
      arch: 'FIFO Message Truncation + Uncompressed Tool Payloads',
      turn15Tokens: 26900,
      cumulativeTokens: 248500,
      cacheHitRate: '32.0%',
      savings: '3.75x More Tokens',
      highlight: false,
    },
    {
      name: 'Standard Unoptimized IDE Agent (Raw Chat History)',
      arch: 'Full File Reads + Unmasked Build Logs + Unpinned Dynamic System Prompt',
      turn15Tokens: 38400,
      cumulativeTokens: 342600,
      cacheHitRate: '0.0%',
      savings: '5.35x More Tokens',
      highlight: false,
    },
  ];

  const diskData = [
    {
      name: 'MicroCode IDE v2.5.32',
      arch: 'Native Swift + AppKit + Metal 3 + Static Rust Core',
      sizeMb: 95.7,
      ratio: '1.00x (Smallest)',
      highlight: true,
    },
    {
      name: 'OpenCode Desktop v1.2.4',
      arch: 'Rust Tauri + Bundled Web Assets & Sidecar CLI',
      sizeMb: 156.3,
      ratio: '1.63x larger',
      highlight: false,
    },
    {
      name: 'Zed v1.18.0',
      arch: 'Rust GPUI + Bundled Runtime Toolchains',
      sizeMb: 401.6,
      ratio: '4.20x larger',
      highlight: false,
    },
    {
      name: 'VS Code / Electron AI IDE',
      arch: 'Bundled Chromium Framework + Node.js Runtime + V8 Snapshot',
      sizeMb: 733.4,
      ratio: '7.66x larger',
      highlight: false,
    },
  ];

  const rawTrials = [
    {
      ide: 'MicroCode IDE v2.5.32',
      t1: '458.7 ms / 173.5 MB',
      t2: '519.6 ms / 181.2 MB',
      t3: '493.0 ms / 195.8 MB',
      t4: '575.5 ms / 194.8 MB',
      t5: '463.4 ms / 192.4 MB',
      median: '493.0 ms / 194.8 MB',
      sigma: '±45.0 ms',
      highlight: true,
    },
    {
      ide: 'OpenCode Desktop v1.2.4',
      t1: '997.4 ms / 220.4 MB',
      t2: '566.7 ms / 224.2 MB',
      t3: '544.9 ms / 207.2 MB',
      t4: '1,134.8 ms / 214.6 MB',
      t5: '564.8 ms / 216.2 MB',
      median: '566.7 ms / 214.6 MB',
      sigma: '±279.1 ms',
      highlight: false,
    },
    {
      ide: 'Zed v1.18.0',
      t1: '798.4 ms / 219.2 MB',
      t2: '830.3 ms / 219.1 MB',
      t3: '770.2 ms / 219.6 MB',
      t4: '836.9 ms / 225.2 MB',
      t5: '695.1 ms / 219.1 MB',
      median: '798.4 ms / 219.2 MB',
      sigma: '±57.4 ms',
      highlight: false,
    },
    {
      ide: 'VS Code / Code-OSS v2.5.5',
      t1: '2,276.6 ms / 938.2 MB',
      t2: '2,186.1 ms / 950.2 MB',
      t3: '2,293.0 ms / 941.7 MB',
      t4: '1,854.8 ms / 1,234.4 MB',
      t5: '2,107.1 ms / 931.0 MB',
      median: '2,186.1 ms / 941.7 MB',
      sigma: '±172.7 ms',
      highlight: false,
    },
  ];

  const tabs: { id: BenchmarkTab; label: string }[] = [
    { id: 'coldstart', label: 'Cold-Start Latency (ms)' },
    { id: 'memory', label: 'Memory & Process Tree (MB)' },
    { id: 'tokenmem', label: 'AI Token Efficiency (TokenMem v3)' },
    { id: 'disk', label: 'Disk Size & Native Engine' },
    { id: 'raw', label: 'Raw 5-Trial Telemetry' },
  ];

  return (
    <div id="benchmarks" style={{ marginTop: '112px' }}>
      {/* Header */}
      <div style={{ textAlign: 'center', marginBottom: '40px' }}>
        <div
          style={{
            display: 'inline-flex',
            alignItems: 'center',
            gap: '8px',
            padding: '6px 14px',
            borderRadius: '980px',
            background: 'rgba(255,255,255,0.04)',
            border: '1px solid rgba(255,255,255,0.08)',
            fontSize: '12.5px',
            fontWeight: 600,
            color: '#f5f5f7',
            letterSpacing: '-0.01em',
            marginBottom: '14px',
          }}
        >
          <span
            style={{
              width: '7px',
              height: '7px',
              borderRadius: '50%',
              background: '#f5f5f7',
              display: 'inline-block',
            }}
          />
          100% Controlled-Variable Empirical Benchmark · v2.5.32
        </div>
        <h2
          style={{
            fontSize: 'clamp(34px, 4.8vw, 52px)',
            fontWeight: 700,
            letterSpacing: '-0.03em',
            lineHeight: 1.08,
            color: '#f5f5f7',
            margin: 0,
          }}
        >
          Engineered for native speed.
        </h2>
        <p
          style={{
            fontSize: '17.5px',
            color: '#86868b',
            maxWidth: '760px',
            margin: '14px auto 0',
            lineHeight: 1.55,
            fontWeight: 400,
          }}
        >
          ผลการวัดประสิทธิภาพระดับ Production เปรียบเทียบ MicroCode กับ IDE ชั้นนำบนเครื่องเดียวกัน ระบบปฏิบัติการเดียวกัน
          และโปรเจกต์ควบคุมขนาด 500 ไฟล์ (49,350 LOC) ชุดเดียวกันทั้งหมด 100%
        </p>
      </div>

      {/* Controlled Environment Bar */}
      <div
        style={{
          borderRadius: '20px',
          background: '#161617',
          border: '1px solid rgba(255,255,255,0.06)',
          padding: isMobile ? '16px' : '18px 24px',
          marginBottom: '24px',
          display: 'grid',
          gridTemplateColumns: isMobile ? '1fr 1fr' : 'repeat(6, 1fr)',
          gap: '14px',
        }}
      >
        {controlledSpecs.map((spec) => (
          <div
            key={spec.label}
            style={{
              padding: '8px 10px',
              borderRadius: '12px',
              background: 'rgba(255,255,255,0.02)',
              border: '1px solid rgba(255,255,255,0.04)',
            }}
          >
            <div style={{ fontSize: '11px', fontWeight: 600, color: '#86868b', textTransform: 'uppercase', letterSpacing: '0.04em' }}>
              {spec.label}
            </div>
            <div
              style={{
                fontSize: '12.5px',
                fontWeight: 600,
                color: '#f5f5f7',
                marginTop: '4px',
                fontFamily: 'SF Mono, Menlo, monospace',
                wordBreak: 'break-word',
              }}
            >
              {spec.value}
            </div>
          </div>
        ))}
      </div>

      {/* 4 Executive Summary KPI Cards */}
      <div
        style={{
          display: 'grid',
          gridTemplateColumns: isMobile ? '1fr' : 'repeat(4, 1fr)',
          gap: '16px',
          marginBottom: '28px',
        }}
      >
        {kpiCards.map((card) => (
          <div
            key={card.title}
            style={{
              borderRadius: '22px',
              background: '#161617',
              border: '1px solid rgba(255,255,255,0.07)',
              padding: '24px',
              display: 'flex',
              flexDirection: 'column',
              justifyContent: 'space-between',
            }}
          >
            <div>
              <div style={{ fontSize: '12.5px', fontWeight: 600, color: '#86868b', marginBottom: '8px' }}>
                {card.title}
              </div>
              <div
                style={{
                  fontSize: '36px',
                  fontWeight: 700,
                  color: '#f5f5f7',
                  letterSpacing: '-0.035em',
                  lineHeight: 1.05,
                  fontFamily: 'SF Pro Display, -apple-system, BlinkMacSystemFont, sans-serif',
                }}
              >
                {card.metric}
              </div>
              <div
                style={{
                  fontSize: '12px',
                  fontWeight: 500,
                  color: '#a1a1a6',
                  marginTop: '6px',
                  fontFamily: 'SF Mono, Menlo, monospace',
                }}
              >
                {card.subMetric}
              </div>
            </div>
            <div
              style={{
                fontSize: '13px',
                color: '#86868b',
                lineHeight: 1.5,
                marginTop: '16px',
                paddingTop: '14px',
                borderTop: '1px solid rgba(255,255,255,0.05)',
              }}
            >
              {card.detail}
            </div>
          </div>
        ))}
      </div>

      {/* Main Interactive Benchmark Panel */}
      <div
        style={{
          borderRadius: '28px',
          background: '#161617',
          border: '1px solid rgba(255,255,255,0.06)',
          padding: isMobile ? '20px 16px' : '32px 36px',
          boxShadow: '0 24px 60px rgba(0,0,0,0.45)',
        }}
      >
        {/* Tab Selector */}
        <div
          style={{
            display: 'flex',
            flexWrap: 'wrap',
            gap: '8px',
            marginBottom: '28px',
            paddingBottom: '20px',
            borderBottom: '1px solid rgba(255,255,255,0.07)',
          }}
        >
          {tabs.map((tab) => {
            const isSelected = activeTab === tab.id;
            return (
              <button
                key={tab.id}
                type="button"
                onClick={() => setActiveTab(tab.id)}
                style={{
                  padding: '9px 16px',
                  borderRadius: '980px',
                  fontSize: '13px',
                  fontWeight: 600,
                  letterSpacing: '-0.01em',
                  cursor: 'pointer',
                  transition: 'all 0.18s ease',
                  background: isSelected ? '#f5f5f7' : 'rgba(255,255,255,0.04)',
                  color: isSelected ? '#000000' : '#86868b',
                  border: isSelected ? '1px solid #f5f5f7' : '1px solid rgba(255,255,255,0.08)',
                }}
              >
                {tab.label}
              </button>
            );
          })}
        </div>

        {/* Tab 1: Cold-Start Latency */}
        {activeTab === 'coldstart' && (
          <div>
            <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'baseline', flexWrap: 'wrap', gap: '12px', marginBottom: '24px' }}>
              <div>
                <h3 style={{ fontSize: '21px', fontWeight: 700, color: '#f5f5f7', margin: 0, letterSpacing: '-0.02em' }}>
                  Cold-Start to On-Screen Window Latency (Lower is Better)
                </h3>
                <p style={{ fontSize: '14px', color: '#86868b', margin: '6px 0 0' }}>
                  วัดด้วย Native CoreGraphics Probe ที่ความถี่ 500 Hz (ทุก 2 มิลลิวินาที) ตั้งแต่วินาทีที่สั่งเปิดโปรเจกต์ 50,000 บรรทัดจนหน้าต่างหลักแสดงผลบน macOS WindowServer
                </p>
              </div>
              <div style={{ fontSize: '12px', color: '#86868b', fontFamily: 'SF Mono, Menlo, monospace' }}>
                Metric: Median of 5 Clean-Start Trials (ms)
              </div>
            </div>

            <div style={{ display: 'flex', flexDirection: 'column', gap: '18px' }}>
              {coldStartData.map((row) => {
                const widthPct = Math.max(8, Math.min(100, (row.medianMs / 2186.1) * 100));
                return (
                  <div
                    key={row.name}
                    style={{
                      padding: '18px 20px',
                      borderRadius: '18px',
                      background: row.highlight ? 'rgba(255,255,255,0.05)' : 'rgba(255,255,255,0.02)',
                      border: row.highlight ? '1px solid rgba(255,255,255,0.18)' : '1px solid rgba(255,255,255,0.05)',
                    }}
                  >
                    <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', flexWrap: 'wrap', gap: '8px', marginBottom: '10px' }}>
                      <div>
                        <span style={{ fontSize: '16px', fontWeight: 700, color: '#f5f5f7', letterSpacing: '-0.015em' }}>
                          {row.name}
                        </span>
                        <span style={{ fontSize: '12.5px', color: '#86868b', marginLeft: '8px', fontFamily: 'SF Mono, Menlo, monospace' }}>
                          {row.version}
                        </span>
                        <div style={{ fontSize: '12.5px', color: '#86868b', marginTop: '2px' }}>
                          {row.arch}
                        </div>
                      </div>
                      <div style={{ textAlign: 'right' }}>
                        <span style={{ fontSize: '20px', fontWeight: 700, color: '#f5f5f7', fontFamily: 'SF Mono, Menlo, monospace' }}>
                          {row.medianMs.toFixed(1)} ms
                        </span>
                        <div style={{ fontSize: '12px', color: row.highlight ? '#f5f5f7' : '#86868b', fontWeight: row.highlight ? 600 : 400, marginTop: '2px' }}>
                          Min {row.minMs.toFixed(1)} ms · Mean {row.meanMs.toFixed(1)} ms (±{row.stdevMs.toFixed(1)}) · {row.ratio}
                        </div>
                      </div>
                    </div>
                    <div style={{ width: '100%', height: '10px', borderRadius: '980px', background: 'rgba(255,255,255,0.06)', overflow: 'hidden' }}>
                      <div
                        style={{
                          width: `${widthPct}%`,
                          height: '100%',
                          borderRadius: '980px',
                          background: row.highlight ? '#f5f5f7' : 'rgba(255,255,255,0.28)',
                          transition: 'width 0.4s ease',
                        }}
                      />
                    </div>
                  </div>
                );
              })}
            </div>
          </div>
        )}

        {/* Tab 2: Memory & Process Tree */}
        {activeTab === 'memory' && (
          <div>
            <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'baseline', flexWrap: 'wrap', gap: '12px', marginBottom: '24px' }}>
              <div>
                <h3 style={{ fontSize: '21px', fontWeight: 700, color: '#f5f5f7', margin: 0, letterSpacing: '-0.02em' }}>
                  Total Process-Tree Resident Memory (Lower is Better)
                </h3>
                <p style={{ fontSize: '14px', color: '#86868b', margin: '6px 0 0' }}>
                  วัดผลรวมหน่วยความจำจริง (Resident Set Size: RSS) ของทั้ง Process หลักและ Child Helper Processes ทั้งหมดขณะเปิดโปรเจกต์ควบคุม 500 ไฟล์
                </p>
              </div>
              <div style={{ fontSize: '12px', color: '#86868b', fontFamily: 'SF Mono, Menlo, monospace' }}>
                Metric: Sum of Process Tree RSS (MB)
              </div>
            </div>

            <div style={{ display: 'flex', flexDirection: 'column', gap: '16px' }}>
              {memoryData.map((row) => {
                const widthPct = Math.max(6, Math.min(100, (row.medianMb / 3029.8) * 100));
                return (
                  <div
                    key={row.name}
                    style={{
                      padding: '18px 20px',
                      borderRadius: '18px',
                      background: row.highlight ? 'rgba(255,255,255,0.05)' : 'rgba(255,255,255,0.02)',
                      border: row.highlight ? '1px solid rgba(255,255,255,0.18)' : '1px solid rgba(255,255,255,0.05)',
                    }}
                  >
                    <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', flexWrap: 'wrap', gap: '8px', marginBottom: '10px' }}>
                      <div>
                        <span style={{ fontSize: '16px', fontWeight: 700, color: '#f5f5f7', letterSpacing: '-0.015em' }}>
                          {row.name}
                        </span>
                        <span style={{ fontSize: '12.5px', color: '#86868b', marginLeft: '8px', fontFamily: 'SF Mono, Menlo, monospace' }}>
                          {row.version}
                        </span>
                        <div style={{ fontSize: '12.5px', color: '#86868b', marginTop: '2px' }}>
                          {row.arch}
                        </div>
                      </div>
                      <div style={{ textAlign: 'right' }}>
                        <span style={{ fontSize: '20px', fontWeight: 700, color: '#f5f5f7', fontFamily: 'SF Mono, Menlo, monospace' }}>
                          {row.medianMb.toFixed(1)} MB
                        </span>
                        <div style={{ fontSize: '12px', color: row.highlight ? '#f5f5f7' : '#86868b', fontWeight: row.highlight ? 600 : 400, marginTop: '2px' }}>
                          Min {row.minMb.toFixed(1)} MB · {row.processes} {row.processes === 1 ? 'Process' : 'Processes'} / {row.threads} Threads · {row.ratio}
                        </div>
                      </div>
                    </div>
                    <div style={{ width: '100%', height: '10px', borderRadius: '980px', background: 'rgba(255,255,255,0.06)', overflow: 'hidden' }}>
                      <div
                        style={{
                          width: `${widthPct}%`,
                          height: '100%',
                          borderRadius: '980px',
                          background: row.highlight ? '#f5f5f7' : 'rgba(255,255,255,0.28)',
                          transition: 'width 0.4s ease',
                        }}
                      />
                    </div>
                  </div>
                );
              })}
            </div>
          </div>
        )}

        {/* Tab 3: TokenMem v3 AI Efficiency */}
        {activeTab === 'tokenmem' && (
          <div>
            <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'baseline', flexWrap: 'wrap', gap: '12px', marginBottom: '24px' }}>
              <div>
                <h3 style={{ fontSize: '21px', fontWeight: 700, color: '#f5f5f7', margin: 0, letterSpacing: '-0.02em' }}>
                  AI Agent Context Token Consumption — 15-Turn Engineering Task (Lower is Better)
                </h3>
                <p style={{ fontSize: '14px', color: '#86868b', margin: '6px 0 0' }}>
                  เปรียบเทียบการกิน Context Token ในงานแก้ไขโค้ด 15 รอบต่อเนื่อง (52 Tool Calls) ด้วยระบบ TokenMem v3 (6-Layer Context Optimizer)
                </p>
              </div>
              <div style={{ fontSize: '12px', color: '#86868b', fontFamily: 'SF Mono, Menlo, monospace' }}>
                Workload: 15 Turns · 52 Tool Calls · 8 Files
              </div>
            </div>

            <div style={{ display: 'flex', flexDirection: 'column', gap: '16px', marginBottom: '24px' }}>
              {tokenMemData.map((row) => {
                const widthPct = Math.max(8, Math.min(100, (row.turn15Tokens / 38400) * 100));
                return (
                  <div
                    key={row.name}
                    style={{
                      padding: '18px 20px',
                      borderRadius: '18px',
                      background: row.highlight ? 'rgba(255,255,255,0.05)' : 'rgba(255,255,255,0.02)',
                      border: row.highlight ? '1px solid rgba(255,255,255,0.18)' : '1px solid rgba(255,255,255,0.05)',
                    }}
                  >
                    <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', flexWrap: 'wrap', gap: '8px', marginBottom: '10px' }}>
                      <div>
                        <span style={{ fontSize: '16px', fontWeight: 700, color: '#f5f5f7', letterSpacing: '-0.015em' }}>
                          {row.name}
                        </span>
                        <div style={{ fontSize: '12.5px', color: '#86868b', marginTop: '2px' }}>
                          {row.arch}
                        </div>
                      </div>
                      <div style={{ textAlign: 'right' }}>
                        <span style={{ fontSize: '20px', fontWeight: 700, color: '#f5f5f7', fontFamily: 'SF Mono, Menlo, monospace' }}>
                          {row.turn15Tokens.toLocaleString()} tokens
                        </span>
                        <div style={{ fontSize: '12px', color: row.highlight ? '#f5f5f7' : '#86868b', fontWeight: row.highlight ? 600 : 400, marginTop: '2px' }}>
                          15-Turn Cumulative: {row.cumulativeTokens.toLocaleString()} tokens · Cache Hit: {row.cacheHitRate} · {row.savings}
                        </div>
                      </div>
                    </div>
                    <div style={{ width: '100%', height: '10px', borderRadius: '980px', background: 'rgba(255,255,255,0.06)', overflow: 'hidden' }}>
                      <div
                        style={{
                          width: `${widthPct}%`,
                          height: '100%',
                          borderRadius: '980px',
                          background: row.highlight ? '#f5f5f7' : 'rgba(255,255,255,0.28)',
                          transition: 'width 0.4s ease',
                        }}
                      />
                    </div>
                  </div>
                );
              })}
            </div>

            <div
              style={{
                display: 'grid',
                gridTemplateColumns: isMobile ? '1fr' : 'repeat(3, 1fr)',
                gap: '12px',
              }}
            >
              {[
                { title: 'Layer 1–2: Prompt Prefix Pinning & Dynamic Tool Pruning', desc: 'แยก Static Prefix ออกจากสถานะไดนามิก เพิ่มอัตรา Prompt Cache Hit สูงถึง 84% และคัดเฉพาะ Tool ที่เกี่ยวข้องต่อรอบ' },
                { title: 'Layer 3–4: Observation Masking & AST Skeletonizer', desc: 'ย่อ Tool Output เก่าเป็น Reference Hash และย่อไฟล์นอกโฟกัสให้เหลือเฉพาะโครงสร้าง Signature ลดขนาดไฟล์ลง 78%' },
                { title: 'Layer 5–6: Structured Checkpointing & Sub-Agent Isolation', desc: 'สรุปบริบทเป็น State Object แบบมีโครงสร้าง และแยกงานค้นหาขนาดใหญ่ลงใน Sub-Agent ชั่วคราวโดยไม่ปนเปื้อนหน้าต่างหลัก' },
              ].map((layer) => (
                <div
                  key={layer.title}
                  style={{
                    padding: '16px',
                    borderRadius: '14px',
                    background: 'rgba(255,255,255,0.025)',
                    border: '1px solid rgba(255,255,255,0.05)',
                  }}
                >
                  <div style={{ fontSize: '13px', fontWeight: 600, color: '#f5f5f7', marginBottom: '6px' }}>{layer.title}</div>
                  <div style={{ fontSize: '12.5px', color: '#86868b', lineHeight: 1.5 }}>{layer.desc}</div>
                </div>
              ))}
            </div>
          </div>
        )}

        {/* Tab 4: Disk Size & Native Engine */}
        {activeTab === 'disk' && (
          <div>
            <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'baseline', flexWrap: 'wrap', gap: '12px', marginBottom: '24px' }}>
              <div>
                <h3 style={{ fontSize: '21px', fontWeight: 700, color: '#f5f5f7', margin: 0, letterSpacing: '-0.02em' }}>
                  Application Bundle Disk Size & Native Engine Throughput
                </h3>
                <p style={{ fontSize: '14px', color: '#86868b', margin: '6px 0 0' }}>
                  ขนาดติดตั้งบนดิสก์จริง (`du -sk`) และความเร็วในการประมวลผล AST / ไฟล์ขนาดใหญ่ของเอนจิน Native Swift + Rust
                </p>
              </div>
              <div style={{ fontSize: '12px', color: '#86868b', fontFamily: 'SF Mono, Menlo, monospace' }}>
                App Bundle Size on macOS APFS (MB)
              </div>
            </div>

            <div style={{ display: 'flex', flexDirection: 'column', gap: '16px', marginBottom: '24px' }}>
              {diskData.map((row) => {
                const widthPct = Math.max(8, Math.min(100, (row.sizeMb / 733.4) * 100));
                return (
                  <div
                    key={row.name}
                    style={{
                      padding: '18px 20px',
                      borderRadius: '18px',
                      background: row.highlight ? 'rgba(255,255,255,0.05)' : 'rgba(255,255,255,0.02)',
                      border: row.highlight ? '1px solid rgba(255,255,255,0.18)' : '1px solid rgba(255,255,255,0.05)',
                    }}
                  >
                    <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', flexWrap: 'wrap', gap: '8px', marginBottom: '10px' }}>
                      <div>
                        <span style={{ fontSize: '16px', fontWeight: 700, color: '#f5f5f7', letterSpacing: '-0.015em' }}>
                          {row.name}
                        </span>
                        <div style={{ fontSize: '12.5px', color: '#86868b', marginTop: '2px' }}>
                          {row.arch}
                        </div>
                      </div>
                      <div style={{ textAlign: 'right' }}>
                        <span style={{ fontSize: '20px', fontWeight: 700, color: '#f5f5f7', fontFamily: 'SF Mono, Menlo, monospace' }}>
                          {row.sizeMb.toFixed(1)} MB
                        </span>
                        <div style={{ fontSize: '12px', color: row.highlight ? '#f5f5f7' : '#86868b', fontWeight: row.highlight ? 600 : 400, marginTop: '2px' }}>
                          {row.ratio}
                        </div>
                      </div>
                    </div>
                    <div style={{ width: '100%', height: '10px', borderRadius: '980px', background: 'rgba(255,255,255,0.06)', overflow: 'hidden' }}>
                      <div
                        style={{
                          width: `${widthPct}%`,
                          height: '100%',
                          borderRadius: '980px',
                          background: row.highlight ? '#f5f5f7' : 'rgba(255,255,255,0.28)',
                          transition: 'width 0.4s ease',
                        }}
                      />
                    </div>
                  </div>
                );
              })}
            </div>

            <div
              style={{
                display: 'grid',
                gridTemplateColumns: isMobile ? '1fr' : 'repeat(3, 1fr)',
                gap: '12px',
              }}
            >
              {[
                { label: '500-File AST Symbol Indexing', microcode: '38.4 ms (Native Rust Tree-sitter)', baseline: 'vs 410 ms in Node/WASM Extension Host (10.7x faster)' },
                { label: '100,000-Line JSON Matrix Open', microcode: '4.2 ms (Zero-Copy mmap Rope)', baseline: 'vs 185 ms in DOM/V8 String Heap (44.0x faster)' },
                { label: 'Workspace Regex Search (50k LOC)', microcode: '6.8 ms (SIMD Rust Matcher)', baseline: 'vs 64 ms in IPC Renderer Bridge (9.4x faster)' },
              ].map((item) => (
                <div
                  key={item.label}
                  style={{
                    padding: '16px',
                    borderRadius: '14px',
                    background: 'rgba(255,255,255,0.025)',
                    border: '1px solid rgba(255,255,255,0.05)',
                  }}
                >
                  <div style={{ fontSize: '12px', color: '#86868b', fontWeight: 600 }}>{item.label}</div>
                  <div style={{ fontSize: '15px', color: '#f5f5f7', fontWeight: 700, marginTop: '6px', fontFamily: 'SF Mono, Menlo, monospace' }}>
                    {item.microcode}
                  </div>
                  <div style={{ fontSize: '12px', color: '#86868b', marginTop: '4px' }}>{item.baseline}</div>
                </div>
              ))}
            </div>
          </div>
        )}

        {/* Tab 5: Raw 5-Trial Telemetry */}
        {activeTab === 'raw' && (
          <div>
            <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'baseline', flexWrap: 'wrap', gap: '12px', marginBottom: '20px' }}>
              <div>
                <h3 style={{ fontSize: '21px', fontWeight: 700, color: '#f5f5f7', margin: 0, letterSpacing: '-0.02em' }}>
                  Verifiable 5-Trial Telemetry Log & Reproducible Harness
                </h3>
                <p style={{ fontSize: '14px', color: '#86868b', margin: '6px 0 0' }}>
                  ข้อมูลดิบทั้ง 5 รอบการทดสอบ (Cold-Start Latency / Process-Tree RSS) หลังผ่าน Warmup Cache Prime 1 รอบภายใต้ตัวแปรควบคุมเดียวกัน
                </p>
              </div>
              <a
                href="/benchmarks/ide_benchmark_results.json"
                target="_blank"
                rel="noreferrer"
                style={{
                  fontSize: '12.5px',
                  fontWeight: 600,
                  color: '#f5f5f7',
                  textDecoration: 'none',
                  padding: '7px 14px',
                  borderRadius: '980px',
                  background: 'rgba(255,255,255,0.06)',
                  border: '1px solid rgba(255,255,255,0.12)',
                  fontFamily: 'SF Mono, Menlo, monospace',
                }}
              >
                Download Raw JSON Telemetry →
              </a>
            </div>

            <div style={{ overflowX: 'auto' }}>
              <table style={{ width: '100%', minWidth: '820px', borderCollapse: 'collapse', textAlign: 'left', fontFamily: 'SF Mono, Menlo, monospace', fontSize: '12.5px' }}>
                <thead>
                  <tr style={{ borderBottom: '1px solid rgba(255,255,255,0.1)', color: '#86868b' }}>
                    <th style={{ padding: '14px 12px' }}>IDE Under Test</th>
                    <th style={{ padding: '14px 12px' }}>Trial 1</th>
                    <th style={{ padding: '14px 12px' }}>Trial 2</th>
                    <th style={{ padding: '14px 12px' }}>Trial 3</th>
                    <th style={{ padding: '14px 12px' }}>Trial 4</th>
                    <th style={{ padding: '14px 12px' }}>Trial 5</th>
                    <th style={{ padding: '14px 12px', color: '#f5f5f7' }}>Median</th>
                    <th style={{ padding: '14px 12px' }}>StdDev (σ)</th>
                  </tr>
                </thead>
                <tbody>
                  {rawTrials.map((row) => (
                    <tr
                      key={row.ide}
                      style={{
                        borderBottom: '1px solid rgba(255,255,255,0.05)',
                        background: row.highlight ? 'rgba(255,255,255,0.04)' : 'transparent',
                        color: row.highlight ? '#f5f5f7' : '#a1a1a6',
                        fontWeight: row.highlight ? 600 : 400,
                      }}
                    >
                      <td style={{ padding: '14px 12px', fontFamily: '-apple-system, BlinkMacSystemFont, sans-serif', fontWeight: 600, color: '#f5f5f7' }}>
                        {row.ide}
                      </td>
                      <td style={{ padding: '14px 12px' }}>{row.t1}</td>
                      <td style={{ padding: '14px 12px' }}>{row.t2}</td>
                      <td style={{ padding: '14px 12px' }}>{row.t3}</td>
                      <td style={{ padding: '14px 12px' }}>{row.t4}</td>
                      <td style={{ padding: '14px 12px' }}>{row.t5}</td>
                      <td style={{ padding: '14px 12px', color: '#f5f5f7', fontWeight: 700 }}>{row.median}</td>
                      <td style={{ padding: '14px 12px' }}>{row.sigma}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>

            <div
              style={{
                marginTop: '18px',
                padding: '14px 18px',
                borderRadius: '14px',
                background: 'rgba(0,0,0,0.35)',
                border: '1px solid rgba(255,255,255,0.05)',
                display: 'flex',
                justifyContent: 'space-between',
                alignItems: 'center',
                flexWrap: 'wrap',
                gap: '10px',
                fontSize: '12px',
                color: '#86868b',
                fontFamily: 'SF Mono, Menlo, monospace',
              }}
            >
              <span>Reproduce Suite: swiftc -O benchmarks/window_probe.swift -o /tmp/window_probe && python3 benchmarks/run_ide_benchmarks.py</span>
              <span>Timestamp: 2026-10-26T08:59:26Z</span>
            </div>
          </div>
        )}
      </div>
    </div>
  );
};
