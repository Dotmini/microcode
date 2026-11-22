@echo off
rem MicroCode for Windows - native WPF build using the C# compiler that ships with Windows (.NET Framework 4.8).
rem No SDK, NuGet or admin rights required. PDF preview uses the Windows Runtime metadata that ships in System32\WinMetadata.  Output: out\MicroCode.exe  (or: build.cmd <outdir>)
setlocal
set FW=%WINDIR%\Microsoft.NET\Framework64\v4.0.30319
set WPF=%FW%\WPF
cd /d "%~dp0"
set OUT=%~1
if "%OUT%"=="" set OUT=out
if not exist "%OUT%" mkdir "%OUT%"
set ICON=
if exist assets\MicroCode.ico (
  set ICON=/win32icon:assets\MicroCode.ico
  copy /y assets\MicroCode.ico "%OUT%\MicroCode.ico" >nul
)
"%FW%\csc.exe" /nologo /target:winexe /platform:anycpu /optimize+ /utf8output /codepage:65001 /out:"%OUT%\MicroCode.exe" ^
  /win32manifest:app.manifest %ICON% ^
  /r:"%WPF%\PresentationFramework.dll" /r:"%WPF%\PresentationCore.dll" /r:"%WPF%\WindowsBase.dll" /r:"%FW%\System.Xaml.dll" ^
  /r:System.dll /r:System.Core.dll /r:System.Xml.dll /r:System.Net.Http.dll /r:System.Web.Extensions.dll /r:System.Security.dll ^
  /r:Microsoft.VisualBasic.dll /r:Microsoft.CSharp.dll ^
  /r:"%WINDIR%\System32\WinMetadata\Windows.Data.winmd" /r:"%WINDIR%\System32\WinMetadata\Windows.Foundation.winmd" /r:"%WINDIR%\System32\WinMetadata\Windows.Storage.winmd" ^
  /r:"%FW%\System.Runtime.dll" /r:"%FW%\System.Runtime.WindowsRuntime.dll" /r:"%FW%\System.Threading.Tasks.dll" ^
  /recurse:src\*.cs
if errorlevel 1 (
  echo BUILD FAILED
  exit /b 1
)
(
  echo ^<?xml version="1.0" encoding="utf-8"?^>
  echo ^<configuration^>
  echo   ^<startup^>^<supportedRuntime version="v4.0" sku=".NETFramework,Version=v4.8" /^>^</startup^>
  echo   ^<runtime^>
  echo     ^<AppContextSwitchOverrides value="Switch.System.Net.DontEnableSystemDefaultTlsVersions=false;Switch.System.ServiceModel.DisableUsingServicePointManagerSecurityProtocols=false" /^>
  echo   ^</runtime^>
  echo ^</configuration^>
) > "%OUT%\MicroCode.exe.config"
echo Built %OUT%\MicroCode.exe
endlocal
