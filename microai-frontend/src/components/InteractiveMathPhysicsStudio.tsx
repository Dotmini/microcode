import React, { useState, useEffect, useRef } from 'react';
import {
  Activity,
  Calculator,
  Compass,
  Play,
  Pause,
  RotateCcw,
  Sliders,
  TrendingUp,
  Maximize2,
  HelpCircle,
  Sparkles,
  Layers,
  ArrowRight,
  Info
} from 'lucide-react';
import katex from 'katex';

export type MathMode = 'parabola' | 'trig' | 'calculus';
export type PhysicsMode = 'kinematics' | 'projectile' | 'shm';

export const InteractiveMathPhysicsStudio: React.FC = () => {
  const [activeTab, setActiveTab] = useState<'math' | 'physics'>('math');

  // Math Lab State
  const [mathMode, setMathMode] = useState<MathMode>('parabola');
  const [paramA, setParamA] = useState<number>(1);
  const [paramB, setParamB] = useState<number>(-2);
  const [paramC, setParamC] = useState<number>(-3);
  const [probeX, setProbeX] = useState<number>(1);

  // Physics Lab State
  const [physicsMode, setPhysicsMode] = useState<PhysicsMode>('projectile');
  const [velocityU, setVelocityU] = useState<number>(25);
  const [angleDeg, setAngleDeg] = useState<number>(45);
  const [gravityG, setGravityG] = useState<number>(9.8);
  const [isSimRunning, setIsSimRunning] = useState<boolean>(true);
  const [simTime, setSimTime] = useState<number>(0);

  // Kinematics State
  const [kinematicsAcc, setKinematicsAcc] = useState<number>(2);
  const [kinematicsV0, setKinematicsV0] = useState<number>(0);

  // Canvas Refs
  const mathCanvasRef = useRef<HTMLCanvasElement>(null);
  const physicsCanvasRef = useRef<HTMLCanvasElement>(null);
  const animationFrameRef = useRef<number | null>(null);

  // LaTeX helper
  const renderLatex = (latex: string) => {
    try {
      return { __html: katex.renderToString(latex, { throwOnError: false, displayMode: false }) };
    } catch {
      return { __html: latex };
    }
  };

  // Math Calculations for Parabola
  const vertexH = -paramB / (2 * (paramA || 0.001));
  const vertexK = paramC - (paramB * paramB) / (4 * (paramA || 0.001));
  const discriminant = paramB * paramB - 4 * paramA * paramC;
  const root1 = discriminant >= 0 ? (-paramB + Math.sqrt(discriminant)) / (2 * paramA) : null;
  const root2 = discriminant >= 0 ? (-paramB - Math.sqrt(discriminant)) / (2 * paramA) : null;
  const probeY = paramA * probeX * probeX + paramB * probeX + paramC;
  const probeSlope = 2 * paramA * probeX + paramB;

  // Projectile Calculations
  const angleRad = (angleDeg * Math.PI) / 180;
  const totalFlightTime = (2 * velocityU * Math.sin(angleRad)) / gravityG;
  const maxRange = (velocityU * velocityU * Math.sin(2 * angleRad)) / gravityG;
  const maxHeight = (velocityU * velocityU * Math.sin(angleRad) * Math.sin(angleRad)) / (2 * gravityG);

  // ── Math Canvas Renderer ──
  useEffect(() => {
    const canvas = mathCanvasRef.current;
    if (!canvas) return;
    const ctx = canvas.getContext('2d');
    if (!ctx) return;

    const width = canvas.parentElement?.clientWidth || 600;
    const height = 360;
    const dpr = window.devicePixelRatio || 1;
    canvas.width = width * dpr;
    canvas.height = height * dpr;
    canvas.style.width = `${width}px`;
    canvas.style.height = `${height}px`;
    ctx.scale(dpr, dpr);

    // Background
    ctx.fillStyle = '#0a0c14';
    ctx.fillRect(0, 0, width, height);

    // Coordinate System Setup
    const originX = width / 2;
    const originY = height / 2;
    const scale = 26; // pixels per unit

    // Grid lines
    ctx.strokeStyle = 'rgba(255, 255, 255, 0.06)';
    ctx.lineWidth = 1;
    for (let x = originX % scale; x < width; x += scale) {
      ctx.beginPath();
      ctx.moveTo(x, 0);
      ctx.lineTo(x, height);
      ctx.stroke();
    }
    for (let y = originY % scale; y < height; y += scale) {
      ctx.beginPath();
      ctx.moveTo(0, y);
      ctx.lineTo(width, y);
      ctx.stroke();
    }

    // Axes
    ctx.strokeStyle = 'rgba(255, 255, 255, 0.3)';
    ctx.lineWidth = 1.5;
    ctx.beginPath();
    ctx.moveTo(0, originY);
    ctx.lineTo(width, originY);
    ctx.moveTo(originX, 0);
    ctx.lineTo(originX, height);
    ctx.stroke();

    // Axis Labels
    ctx.fillStyle = 'rgba(255, 255, 255, 0.4)';
    ctx.font = '10px -apple-system, BlinkMacSystemFont, "SF Pro Text", sans-serif';
    ctx.fillText('X', width - 16, originY - 6);
    ctx.fillText('Y', originX + 6, 14);

    // Draw Function Curve
    ctx.beginPath();
    ctx.strokeStyle = '#6366f1';
    ctx.lineWidth = 3;
    let started = false;

    for (let px = 0; px < width; px += 2) {
      const x = (px - originX) / scale;
      let y = 0;

      if (mathMode === 'parabola') {
        y = paramA * x * x + paramB * x + paramC;
      } else if (mathMode === 'trig') {
        y = paramA * Math.sin(paramB * x + paramC);
      } else if (mathMode === 'calculus') {
        y = 0.2 * (x * x * x - 3 * x * x + 5);
      }

      const py = originY - y * scale;
      if (py >= -100 && py <= height + 100) {
        if (!started) {
          ctx.moveTo(px, py);
          started = true;
        } else {
          ctx.lineTo(px, py);
        }
      }
    }
    ctx.stroke();

    // If Parabola, draw Vertex and Tangent at Probe
    if (mathMode === 'parabola') {
      // Vertex point
      const vx = originX + vertexH * scale;
      const vy = originY - vertexK * scale;
      if (vx >= 0 && vx <= width && vy >= 0 && vy <= height) {
        ctx.fillStyle = '#f59e0b';
        ctx.beginPath();
        ctx.arc(vx, vy, 5, 0, Math.PI * 2);
        ctx.fill();

        ctx.fillStyle = '#fbbf24';
        ctx.font = 'bold 10px monospace';
        ctx.fillText(`V(${vertexH.toFixed(1)}, ${vertexK.toFixed(1)})`, vx + 8, vy - 4);
      }

      // Probe Point & Tangent Line
      const ppx = originX + probeX * scale;
      const ppy = originY - probeY * scale;

      // Tangent line: y - y0 = m*(x - x0)
      ctx.strokeStyle = '#ec4899';
      ctx.lineWidth = 1.5;
      ctx.setLineDash([4, 4]);
      ctx.beginPath();
      const xSpan = 4;
      const xLeft = probeX - xSpan;
      const yLeft = probeY - probeSlope * xSpan;
      const xRight = probeX + xSpan;
      const yRight = probeY + probeSlope * xSpan;
      ctx.moveTo(originX + xLeft * scale, originY - yLeft * scale);
      ctx.lineTo(originX + xRight * scale, originY - yRight * scale);
      ctx.stroke();
      ctx.setLineDash([]);

      // Probe circle
      ctx.fillStyle = '#ec4899';
      ctx.beginPath();
      ctx.arc(ppx, ppy, 6, 0, Math.PI * 2);
      ctx.fill();
      ctx.strokeStyle = '#ffffff';
      ctx.lineWidth = 2;
      ctx.stroke();
    }
  }, [mathMode, paramA, paramB, paramC, probeX, vertexH, vertexK, probeY, probeSlope]);

  // ── Physics Simulation Loop ──
  useEffect(() => {
    let lastTime = performance.now();

    const loop = (time: number) => {
      const delta = (time - lastTime) / 1000;
      lastTime = time;

      if (isSimRunning) {
        setSimTime((prev) => {
          const next = prev + delta * 1.2;
          if (physicsMode === 'projectile' && next > totalFlightTime + 0.5) {
            return 0; // loop simulation
          }
          return next;
        });
      }

      // Draw Physics Canvas
      const canvas = physicsCanvasRef.current;
      if (canvas) {
        const ctx = canvas.getContext('2d');
        if (ctx) {
          const width = canvas.parentElement?.clientWidth || 600;
          const height = 360;
          const dpr = window.devicePixelRatio || 1;
          canvas.width = width * dpr;
          canvas.height = height * dpr;
          canvas.style.width = `${width}px`;
          canvas.style.height = `${height}px`;
          ctx.scale(dpr, dpr);

          // Dark Sci-Fi Canvas Background
          ctx.fillStyle = '#090b12';
          ctx.fillRect(0, 0, width, height);

          // Grid
          ctx.strokeStyle = 'rgba(255, 255, 255, 0.05)';
          ctx.lineWidth = 1;
          for (let x = 0; x < width; x += 30) {
            ctx.beginPath();
            ctx.moveTo(x, 0);
            ctx.lineTo(x, height);
            ctx.stroke();
          }
          for (let y = 0; y < height; y += 30) {
            ctx.beginPath();
            ctx.moveTo(0, y);
            ctx.lineTo(width, y);
            ctx.stroke();
          }

          if (physicsMode === 'projectile') {
            // Ground line
            const groundY = height - 40;
            ctx.strokeStyle = '#3b82f6';
            ctx.lineWidth = 2;
            ctx.beginPath();
            ctx.moveTo(0, groundY);
            ctx.lineTo(width, groundY);
            ctx.stroke();

            // Ground hash marks
            ctx.strokeStyle = 'rgba(59, 130, 246, 0.3)';
            for (let x = 0; x < width; x += 20) {
              ctx.beginPath();
              ctx.moveTo(x, groundY);
              ctx.lineTo(x - 10, groundY + 10);
              ctx.stroke();
            }

            const originX = 50;
            const meterScale = Math.min((width - 100) / (maxRange || 1), (groundY - 50) / (maxHeight || 1));

            // Draw Full Parabolic Path
            ctx.beginPath();
            ctx.strokeStyle = 'rgba(99, 102, 241, 0.4)';
            ctx.lineWidth = 2;
            ctx.setLineDash([5, 5]);
            for (let t = 0; t <= totalFlightTime; t += 0.05) {
              const xPos = originX + velocityU * Math.cos(angleRad) * t * meterScale;
              const yPos = groundY - (velocityU * Math.sin(angleRad) * t - 0.5 * gravityG * t * t) * meterScale;
              if (t === 0) ctx.moveTo(xPos, yPos);
              else ctx.lineTo(xPos, yPos);
            }
            ctx.stroke();
            ctx.setLineDash([]);

            // Current Projectile Position
            const tCur = Math.min(simTime, totalFlightTime);
            const curX = originX + velocityU * Math.cos(angleRad) * tCur * meterScale;
            const curY = groundY - Math.max(0, velocityU * Math.sin(angleRad) * tCur - 0.5 * gravityG * tCur * tCur) * meterScale;

            // Velocity Vector Arrow
            const curVx = velocityU * Math.cos(angleRad);
            const curVy = velocityU * Math.sin(angleRad) - gravityG * tCur;
            const arrowLen = 20;

            ctx.strokeStyle = '#10b981';
            ctx.lineWidth = 2;
            ctx.beginPath();
            ctx.moveTo(curX, curY);
            ctx.lineTo(curX + curVx * 1.5, curY - curVy * 1.5);
            ctx.stroke();

            // Projectile Glow & Sphere
            const gradient = ctx.createRadialGradient(curX, curY, 2, curX, curY, 14);
            gradient.addColorStop(0, '#a855f7');
            gradient.addColorStop(0.5, '#6366f1');
            gradient.addColorStop(1, 'transparent');
            ctx.fillStyle = gradient;
            ctx.beginPath();
            ctx.arc(curX, curY, 14, 0, Math.PI * 2);
            ctx.fill();

            ctx.fillStyle = '#ffffff';
            ctx.beginPath();
            ctx.arc(curX, curY, 5, 0, Math.PI * 2);
            ctx.fill();

            // Stats Callout
            ctx.fillStyle = '#e0e7ff';
            ctx.font = '11px -apple-system, BlinkMacSystemFont, monospace';
            ctx.fillText(`t = ${tCur.toFixed(2)} s`, curX + 12, curY - 12);
            ctx.fillText(`h = ${(Math.max(0, velocityU * Math.sin(angleRad) * tCur - 0.5 * gravityG * tCur * tCur)).toFixed(1)} m`, curX + 12, curY + 2);
          } else if (physicsMode === 'kinematics') {
            // Kinematics v-t Graph
            const originX = 50;
            const originY = height - 50;
            const tMax = 10;
            const vMax = 20;
            const scaleX = (width - 100) / tMax;
            const scaleY = (height - 100) / vMax;

            // Axes
            ctx.strokeStyle = 'rgba(255, 255, 255, 0.4)';
            ctx.lineWidth = 1.5;
            ctx.beginPath();
            ctx.moveTo(originX, 30);
            ctx.lineTo(originX, originY);
            ctx.lineTo(width - 30, originY);
            ctx.stroke();

            // Fill Area Under Curve (Displacement s)
            ctx.fillStyle = 'rgba(99, 102, 241, 0.2)';
            ctx.beginPath();
            ctx.moveTo(originX, originY);
            for (let t = 0; t <= tMax; t += 0.2) {
              const v = kinematicsV0 + kinematicsAcc * t;
              const px = originX + t * scaleX;
              const py = originY - Math.min(vMax, v) * scaleY;
              ctx.lineTo(px, py);
            }
            ctx.lineTo(originX + tMax * scaleX, originY);
            ctx.closePath();
            ctx.fill();

            // v-t Line
            ctx.strokeStyle = '#6366f1';
            ctx.lineWidth = 3;
            ctx.beginPath();
            for (let t = 0; t <= tMax; t += 0.2) {
              const v = kinematicsV0 + kinematicsAcc * t;
              const px = originX + t * scaleX;
              const py = originY - Math.min(vMax, v) * scaleY;
              if (t === 0) ctx.moveTo(px, py);
              else ctx.lineTo(px, py);
            }
            ctx.stroke();

            // Labeling
            ctx.fillStyle = '#a5b4fc';
            ctx.font = 'bold 11px -apple-system, sans-serif';
            ctx.fillText('v (m/s)', originX - 10, 20);
            ctx.fillText('t (s)', width - 20, originY + 20);
            ctx.fillText(`Area = Distance s = ${(0.5 * kinematicsAcc * 100 + kinematicsV0 * 10).toFixed(1)} m`, originX + 60, originY - 30);
          }
        }
      }

      animationFrameRef.current = requestAnimationFrame(loop);
    };

    animationFrameRef.current = requestAnimationFrame(loop);
    return () => {
      if (animationFrameRef.current) cancelAnimationFrame(animationFrameRef.current);
    };
  }, [physicsMode, velocityU, angleRad, gravityG, isSimRunning, simTime, totalFlightTime, maxRange, maxHeight, kinematicsAcc, kinematicsV0]);

  return (
    <div className="bg-[#12141e]/90 border border-white/10 rounded-3xl p-6 sm:p-8 backdrop-blur-2xl shadow-2xl space-y-6">
      {/* ── Header with Apple iOS Pro Segmented Control ── */}
      <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-4 border-b border-white/10 pb-5">
        <div>
          <div className="flex items-center gap-2">
            <span className="px-2.5 py-0.5 rounded-full bg-indigo-500/10 text-indigo-400 text-[10px] font-bold uppercase tracking-wider border border-indigo-500/20">
              Interactive Exam Lab
            </span>
            <span className="text-xs text-zinc-400 font-mono">TGAT & A-Level Visualizer Engine</span>
          </div>
          <h2 className="text-xl sm:text-2xl font-bold text-white tracking-tight mt-1 flex items-center gap-2">
            <Activity className="w-6 h-6 text-indigo-400" />
            <span>Interactive Graphing Studio (กราฟคณิตศาสตร์ & ฟิสิกส์ประยุกต์)</span>
          </h2>
        </div>

        {/* iOS Mode Segmented Switcher */}
        <div className="flex p-1 bg-white/5 border border-white/10 rounded-2xl">
          <button
            type="button"
            onClick={() => setActiveTab('math')}
            className={`px-4 py-2 rounded-xl text-xs font-bold transition-all cursor-pointer flex items-center gap-2 ${
              activeTab === 'math'
                ? 'bg-indigo-600 text-white shadow-md'
                : 'text-zinc-400 hover:text-white'
            }`}
          >
            <Calculator className="w-4 h-4" />
            <span>คณิตศาสตร์ประยุกต์ (Math)</span>
          </button>
          <button
            type="button"
            onClick={() => setActiveTab('physics')}
            className={`px-4 py-2 rounded-xl text-xs font-bold transition-all cursor-pointer flex items-center gap-2 ${
              activeTab === 'physics'
                ? 'bg-indigo-600 text-white shadow-md'
                : 'text-zinc-400 hover:text-white'
            }`}
          >
            <TrendingUp className="w-4 h-4" />
            <span>ฟิสิกส์ประยุกต์ (Physics)</span>
          </button>
        </div>
      </div>

      {/* ═══════════ MATHEMATICS STUDIO ═══════════ */}
      {activeTab === 'math' && (
        <div className="grid grid-cols-1 lg:grid-cols-12 gap-6 items-start">
          {/* Math Canvas Graph */}
          <div className="lg:col-span-8 space-y-3">
            <div className="flex items-center justify-between">
              <div className="flex items-center gap-2">
                <span className="text-xs font-bold text-indigo-300 uppercase tracking-wider">
                  {mathMode === 'parabola' && 'พาราโบลา & ฟังก์ชันกำลังสอง'}
                  {mathMode === 'trig' && 'คลื่นตรีโกณมิติ Sine Wave'}
                  {mathMode === 'calculus' && 'แคลคูลัส & สมการเส้นสัมผัสเส้นโค้ง'}
                </span>
              </div>
              <div className="flex gap-1.5">
                {(['parabola', 'trig', 'calculus'] as MathMode[]).map((m) => (
                  <button
                    key={m}
                    type="button"
                    onClick={() => setMathMode(m)}
                    className={`px-2.5 py-1 rounded-lg text-[11px] font-semibold transition-all cursor-pointer border ${
                      mathMode === m
                        ? 'bg-indigo-500/20 text-indigo-300 border-indigo-500/40'
                        : 'bg-white/5 hover:bg-white/10 text-zinc-400 border-white/5'
                    }`}
                  >
                    {m === 'parabola' ? 'Parabola' : m === 'trig' ? 'Trig Wave' : 'Calculus'}
                  </button>
                ))}
              </div>
            </div>

            <div className="w-full h-[360px] rounded-2xl overflow-hidden border border-white/10 relative bg-[#0a0c14] shadow-inner">
              <canvas ref={mathCanvasRef} className="w-full h-full block" />

              <div className="absolute bottom-3 left-3 bg-black/70 backdrop-blur-md px-3 py-1.5 rounded-xl border border-white/10 text-[11px] font-mono text-zinc-300">
                {mathMode === 'parabola' && `f(x) = ${paramA}x² + (${paramB})x + (${paramC})`}
                {mathMode === 'trig' && `f(x) = ${paramA} sin(${paramB}x + ${paramC})`}
                {mathMode === 'calculus' && `f(x) = 0.2(x³ - 3x² + 5)`}
              </div>
            </div>
          </div>

          {/* Math Sliders & Interactive Controls */}
          <div className="lg:col-span-4 space-y-4">
            <div className="bg-white/5 border border-white/10 rounded-2xl p-4 space-y-4">
              <h3 className="text-xs font-bold text-white uppercase tracking-wider flex items-center gap-1.5">
                <Sliders className="w-4 h-4 text-indigo-400" />
                <span>พารามิเตอร์ของสมการ (Parameters)</span>
              </h3>

              {/* Slider A */}
              <div className="space-y-1">
                <div className="flex justify-between text-xs">
                  <span className="text-zinc-300 font-medium">สัมประสิทธิ์ a (ความโค้ง):</span>
                  <span className="font-mono text-indigo-400 font-bold">{paramA}</span>
                </div>
                <input
                  type="range"
                  min="-3"
                  max="3"
                  step="0.5"
                  value={paramA}
                  onChange={(e) => setParamA(parseFloat(e.target.value) || 0.1)}
                  className="w-full accent-indigo-500 cursor-pointer"
                />
              </div>

              {/* Slider B */}
              <div className="space-y-1">
                <div className="flex justify-between text-xs">
                  <span className="text-zinc-300 font-medium">สัมประสิทธิ์ b (แกนสมมาตร):</span>
                  <span className="font-mono text-indigo-400 font-bold">{paramB}</span>
                </div>
                <input
                  type="range"
                  min="-6"
                  max="6"
                  step="0.5"
                  value={paramB}
                  onChange={(e) => setParamB(parseFloat(e.target.value))}
                  className="w-full accent-indigo-500 cursor-pointer"
                />
              </div>

              {/* Slider C */}
              <div className="space-y-1">
                <div className="flex justify-between text-xs">
                  <span className="text-zinc-300 font-medium">สัมประสิทธิ์ c (จุดตัดแกน Y):</span>
                  <span className="font-mono text-indigo-400 font-bold">{paramC}</span>
                </div>
                <input
                  type="range"
                  min="-6"
                  max="6"
                  step="0.5"
                  value={paramC}
                  onChange={(e) => setParamC(parseFloat(e.target.value))}
                  className="w-full accent-indigo-500 cursor-pointer"
                />
              </div>

              {/* Probe X */}
              <div className="space-y-1 pt-2 border-t border-white/10">
                <div className="flex justify-between text-xs">
                  <span className="text-pink-300 font-medium">จุด Probe x₀ (ความชันเส้นสัมผัส):</span>
                  <span className="font-mono text-pink-400 font-bold">{probeX}</span>
                </div>
                <input
                  type="range"
                  min="-4"
                  max="4"
                  step="0.2"
                  value={probeX}
                  onChange={(e) => setProbeX(parseFloat(e.target.value))}
                  className="w-full accent-pink-500 cursor-pointer"
                />
              </div>
            </div>

            {/* Real-time Math Diagnostics */}
            <div className="bg-indigo-950/30 border border-indigo-500/20 rounded-2xl p-4 space-y-2.5 text-xs">
              <div className="font-bold text-indigo-300 flex items-center gap-1.5">
                <Sparkles className="w-4 h-4" />
                <span>การวิเคราะห์คุณสมบัติเชิงวิชาการ (TCAS & A-Level)</span>
              </div>
              <div className="grid grid-cols-2 gap-2 font-mono text-[11px]">
                <div className="bg-black/30 p-2 rounded-lg border border-white/5">
                  <span className="text-zinc-400 block text-[10px]">จุดยอด (Vertex):</span>
                  <span className="text-amber-300 font-bold">({vertexH.toFixed(2)}, {vertexK.toFixed(2)})</span>
                </div>
                <div className="bg-black/30 p-2 rounded-lg border border-white/5">
                  <span className="text-zinc-400 block text-[10px]">ดิสคริมิแนนท์ (Δ):</span>
                  <span className={discriminant >= 0 ? 'text-emerald-300 font-bold' : 'text-red-300 font-bold'}>
                    {discriminant.toFixed(1)} {discriminant >= 0 ? '(มีรากจริง)' : '(รากเชิงซ้อน)'}
                  </span>
                </div>
                <div className="bg-black/30 p-2 rounded-lg border border-white/5 col-span-2">
                  <span className="text-zinc-400 block text-[10px]">ความชันเส้นสัมผัส ณ x₀={probeX}:</span>
                  <span className="text-pink-300 font-bold">m = f'({probeX}) = {probeSlope.toFixed(2)}</span>
                </div>
              </div>
            </div>
          </div>
        </div>
      )}

      {/* ═══════════ APPLIED PHYSICS STUDIO ═══════════ */}
      {activeTab === 'physics' && (
        <div className="grid grid-cols-1 lg:grid-cols-12 gap-6 items-start">
          {/* Physics Canvas Simulator */}
          <div className="lg:col-span-8 space-y-3">
            <div className="flex items-center justify-between">
              <div className="flex items-center gap-2">
                <span className="text-xs font-bold text-indigo-300 uppercase tracking-wider">
                  {physicsMode === 'projectile' && 'การเคลื่อนที่แบบโปรเจกไทล์ (2D Projectile Trajectory)'}
                  {physicsMode === 'kinematics' && 'กราฟการเคลื่อนที่แนวตรง (v-t Velocity-Time Curve)'}
                  {physicsMode === 'shm' && 'การแกว่งฮาร์มอนิกอย่างง่าย & การอนุรักษ์พลังงาน (SHM)'}
                </span>
              </div>
              <div className="flex gap-1.5">
                {(['projectile', 'kinematics'] as PhysicsMode[]).map((pm) => (
                  <button
                    key={pm}
                    type="button"
                    onClick={() => setPhysicsMode(pm)}
                    className={`px-2.5 py-1 rounded-lg text-[11px] font-semibold transition-all cursor-pointer border ${
                      physicsMode === pm
                        ? 'bg-indigo-500/20 text-indigo-300 border-indigo-500/40'
                        : 'bg-white/5 hover:bg-white/10 text-zinc-400 border-white/5'
                    }`}
                  >
                    {pm === 'projectile' ? 'Projectile' : 'Kinematics v-t'}
                  </button>
                ))}
              </div>
            </div>

            <div className="w-full h-[360px] rounded-2xl overflow-hidden border border-white/10 relative bg-[#090b12] shadow-inner">
              <canvas ref={physicsCanvasRef} className="w-full h-full block" />

              {/* Simulation Play/Pause Bar */}
              <div className="absolute top-3 right-3 flex items-center gap-1.5 bg-black/60 backdrop-blur-md px-2.5 py-1 rounded-xl border border-white/10">
                <button
                  type="button"
                  onClick={() => setIsSimRunning(!isSimRunning)}
                  className="p-1 rounded-lg bg-indigo-600 hover:bg-indigo-500 text-white transition-all cursor-pointer"
                >
                  {isSimRunning ? <Pause className="w-3.5 h-3.5" /> : <Play className="w-3.5 h-3.5" />}
                </button>
                <button
                  type="button"
                  onClick={() => setSimTime(0)}
                  className="p-1 rounded-lg bg-white/10 hover:bg-white/20 text-zinc-300 transition-all cursor-pointer"
                >
                  <RotateCcw className="w-3.5 h-3.5" />
                </button>
              </div>
            </div>
          </div>

          {/* Physics Sliders & Controls */}
          <div className="lg:col-span-4 space-y-4">
            <div className="bg-white/5 border border-white/10 rounded-2xl p-4 space-y-4">
              <h3 className="text-xs font-bold text-white uppercase tracking-wider flex items-center gap-1.5">
                <Sliders className="w-4 h-4 text-indigo-400" />
                <span>ตัวแปรฟิสิกส์ (Physics Controls)</span>
              </h3>

              {physicsMode === 'projectile' ? (
                <>
                  <div className="space-y-1">
                    <div className="flex justify-between text-xs">
                      <span className="text-zinc-300 font-medium">ความเร็วต้น u (m/s):</span>
                      <span className="font-mono text-indigo-400 font-bold">{velocityU} m/s</span>
                    </div>
                    <input
                      type="range"
                      min="5"
                      max="45"
                      step="1"
                      value={velocityU}
                      onChange={(e) => setVelocityU(parseFloat(e.target.value))}
                      className="w-full accent-indigo-500 cursor-pointer"
                    />
                  </div>

                  <div className="space-y-1">
                    <div className="flex justify-between text-xs">
                      <span className="text-zinc-300 font-medium">มุมยิง θ (องศา):</span>
                      <span className="font-mono text-indigo-400 font-bold">{angleDeg}°</span>
                    </div>
                    <input
                      type="range"
                      min="10"
                      max="85"
                      step="1"
                      value={angleDeg}
                      onChange={(e) => setAngleDeg(parseFloat(e.target.value))}
                      className="w-full accent-indigo-500 cursor-pointer"
                    />
                  </div>

                  <div className="space-y-1">
                    <div className="flex justify-between text-xs">
                      <span className="text-zinc-300 font-medium">ความเร่งโน้มถ่วง g (m/s²):</span>
                      <span className="font-mono text-indigo-400 font-bold">{gravityG} m/s²</span>
                    </div>
                    <input
                      type="range"
                      min="1.6"
                      max="20"
                      step="0.2"
                      value={gravityG}
                      onChange={(e) => setGravityG(parseFloat(e.target.value))}
                      className="w-full accent-indigo-500 cursor-pointer"
                    />
                  </div>
                </>
              ) : (
                <>
                  <div className="space-y-1">
                    <div className="flex justify-between text-xs">
                      <span className="text-zinc-300 font-medium">ความเร่ง a (m/s²):</span>
                      <span className="font-mono text-indigo-400 font-bold">{kinematicsAcc} m/s²</span>
                    </div>
                    <input
                      type="range"
                      min="-4"
                      max="4"
                      step="0.5"
                      value={kinematicsAcc}
                      onChange={(e) => setKinematicsAcc(parseFloat(e.target.value))}
                      className="w-full accent-indigo-500 cursor-pointer"
                    />
                  </div>
                  <div className="space-y-1">
                    <div className="flex justify-between text-xs">
                      <span className="text-zinc-300 font-medium">ความเร็วเริ่มต้น v₀ (m/s):</span>
                      <span className="font-mono text-indigo-400 font-bold">{kinematicsV0} m/s</span>
                    </div>
                    <input
                      type="range"
                      min="0"
                      max="15"
                      step="1"
                      value={kinematicsV0}
                      onChange={(e) => setKinematicsV0(parseFloat(e.target.value))}
                      className="w-full accent-indigo-500 cursor-pointer"
                    />
                  </div>
                </>
              )}
            </div>

            {/* Physics Analytics */}
            <div className="bg-emerald-950/30 border border-emerald-500/20 rounded-2xl p-4 space-y-2.5 text-xs">
              <div className="font-bold text-emerald-300 flex items-center gap-1.5">
                <Sparkles className="w-4 h-4" />
                <span>ผลลัพธ์คำนวณตามสูตร A-Level Physics</span>
              </div>
              <div className="grid grid-cols-2 gap-2 font-mono text-[11px]">
                <div className="bg-black/30 p-2 rounded-lg border border-white/5">
                  <span className="text-zinc-400 block text-[10px]">ระยะไกลสุด (Range R):</span>
                  <span className="text-emerald-300 font-bold">{maxRange.toFixed(1)} m</span>
                </div>
                <div className="bg-black/30 p-2 rounded-lg border border-white/5">
                  <span className="text-zinc-400 block text-[10px]">ความสูงสูงสุด (H_max):</span>
                  <span className="text-indigo-300 font-bold">{maxHeight.toFixed(1)} m</span>
                </div>
                <div className="bg-black/30 p-2 rounded-lg border border-white/5 col-span-2">
                  <span className="text-zinc-400 block text-[10px]">เวลาลอยในอากาศทั้งหมด (Flight Time T):</span>
                  <span className="text-amber-300 font-bold">{totalFlightTime.toFixed(2)} วินาที</span>
                </div>
              </div>
            </div>
          </div>
        </div>
      )}
    </div>
  );
};
