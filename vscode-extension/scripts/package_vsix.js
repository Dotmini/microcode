#!/usr/bin/env node
/**
 * Deterministic VSIX Packager for MicroCode VS Code Extension (`dotmini.microcode-vscode`)
 */

const fs = require('fs');
const path = require('path');
const cp = require('child_process');
const os = require('os');

const extDir = path.resolve(__dirname, '..');
const pkg = JSON.parse(fs.readFileSync(path.join(extDir, 'package.json'), 'utf8'));

const stageRoot = fs.mkdtempSync(path.join(os.tmpdir(), 'microcode-vsix-'));
const stageExt = path.join(stageRoot, 'extension');
fs.mkdirSync(stageExt, { recursive: true });

const contentTypesXml = `<?xml version="1.0" encoding="utf-8"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
  <Default Extension=".json" ContentType="application/json"/>
  <Default Extension=".js" ContentType="application/javascript"/>
  <Default Extension=".map" ContentType="application/json"/>
  <Default Extension=".md" ContentType="text/markdown"/>
  <Default Extension=".png" ContentType="image/png"/>
  <Default Extension=".svg" ContentType="image/svg+xml"/>
  <Default Extension=".vsixmanifest" ContentType="text/xml"/>
</Types>`;

const vsixManifestXml = `<?xml version="1.0" encoding="utf-8"?>
<PackageManifest Version="2.0.0" xmlns="http://schemas.microsoft.com/developer/vsx-schema/2011" xmlns:d="http://schemas.microsoft.com/developer/vsx-schema-design/2011">
  <Metadata>
    <Identity Language="en-US" Id="${pkg.name}" Version="${pkg.version}" Publisher="${pkg.publisher}" />
    <DisplayName>${pkg.displayName}</DisplayName>
    <Description xml:space="preserve">${pkg.description}</Description>
    <Tags>${(pkg.keywords || []).join(',')}</Tags>
    <Categories>${(pkg.categories || []).join(',')}</Categories>
    <Icon>extension/media/icon.png</Icon>
  </Metadata>
  <Installation>
    <InstallationTarget Id="Microsoft.VisualStudio.Code"/>
  </Installation>
  <Dependencies/>
  <Assets>
    <Asset Type="Microsoft.VisualStudio.Code.Manifest" Path="extension/package.json" Addressable="true" />
    <Asset Type="Microsoft.VisualStudio.Services.Content.Details" Path="extension/README.md" Addressable="true" />
    <Asset Type="Microsoft.VisualStudio.Services.Icons.Default" Path="extension/media/icon.png" Addressable="true" />
  </Assets>
</PackageManifest>`;

fs.writeFileSync(path.join(stageRoot, '[Content_Types].xml'), contentTypesXml, 'utf8');
fs.writeFileSync(path.join(stageRoot, 'extension.vsixmanifest'), vsixManifestXml, 'utf8');

const itemsToCopy = [
  'package.json',
  'README.md',
  'language-configuration.json',
  'media',
  'syntaxes',
  'snippets',
  'dist'
];

for (const item of itemsToCopy) {
  const src = path.join(extDir, item);
  const dest = path.join(stageExt, item);
  if (fs.existsSync(src)) {
    fs.cpSync(src, dest, { recursive: true });
  }
}

const outVsix = path.join(extDir, `${pkg.publisher}.${pkg.name}-${pkg.version}.vsix`);
if (fs.existsSync(outVsix)) {
  fs.unlinkSync(outVsix);
}

cp.execFileSync('/usr/bin/zip', ['-r', '-q', outVsix, '.'], { cwd: stageRoot });
fs.rmSync(stageRoot, { recursive: true, force: true });

console.log(`📦 Packaged VSIX: ${outVsix}`);
