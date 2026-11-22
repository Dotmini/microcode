@echo off
rem Builds out-dev\MicroCode.exe, compiles each test program against it and runs its checks (no SDK needed).
rem   PreviewTests        File Preview, Markdown links, PDF, LaTeX
rem   AgentPlatformTests  Consensus Engine + PNS 24/7 (sandbox, real git worktrees, the pnsd daemon)
rem   NotebookTests       Cell Mode: @param, DAG, .ipynb/.py/.mcnb/.mic (LZFSE), warm Python kernel, polyglot cells, cell_* agent tools
rem   McpTests            MCP client: config discovery + trust, stdio (Python) and Streamable HTTP servers, mcp_orchestrator, agent loop
rem   HarnessTests        agent harness: multi-platform rules, hooks + workspace trust, patch / git / web_fetch / find_symbol tools
rem   StudioTests         API Studio (cURL, environments, route scan, .env, real loopback requests) + first-launch onboarding
rem   CollabTests         Team Collaboration: a real host + peer on loopback (join, merge, realtime CRUD, presence, chat, portal, relay, ot1, invite links)
rem   OTTests             ot1 operation algebra, client / host state machines, randomized 3-client convergence
setlocal
set FW=%WINDIR%\Microsoft.NET\Framework64\v4.0.30319
set WPF=%FW%\WPF
set ROOT=%~dp0..
call "%ROOT%\build.cmd" out-dev >nul
if errorlevel 1 (
  echo BUILD FAILED
  exit /b 1
)
set REFS=/r:"%ROOT%\out-dev\MicroCode.exe" /r:"%WPF%\PresentationFramework.dll" /r:"%WPF%\PresentationCore.dll" /r:"%WPF%\WindowsBase.dll" /r:"%FW%\System.Xaml.dll" /r:System.dll /r:System.Core.dll /r:System.Net.Http.dll /r:System.Web.Extensions.dll
set FAILED=0
call :suite PreviewTests
if errorlevel 1 set FAILED=1
call :suite AgentPlatformTests
if errorlevel 1 set FAILED=1
call :suite NotebookTests
if errorlevel 1 set FAILED=1
call :suite StudioTests
if errorlevel 1 set FAILED=1
call :suite HarnessTests
if errorlevel 1 set FAILED=1
call :suite McpTests
if errorlevel 1 set FAILED=1
call :suite CollabTests
if errorlevel 1 set FAILED=1
call :suite OTTests
if errorlevel 1 set FAILED=1
exit /b %FAILED%

rem compile tests\<name>.cs against out-dev\MicroCode.exe and run it; errorlevel 1 when it fails to build or a check fails
:suite
"%FW%\csc.exe" /nologo /target:exe /platform:anycpu /utf8output /codepage:65001 /out:"%ROOT%\out-dev\%1.exe" %REFS% "%ROOT%\tests\%1.cs"
if errorlevel 1 goto :suitebuild
echo.
echo == %1
"%ROOT%\out-dev\%1.exe"
if errorlevel 1 exit /b 1
exit /b 0
:suitebuild
echo TEST BUILD FAILED: %1
exit /b 1
