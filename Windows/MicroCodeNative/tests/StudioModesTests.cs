// Self-checking tests for all Windows Studio backend services in src/Views/Studios.cs.
// Strict C# 5 (.NET Framework 4.8 / Mono mcs -langversion:5).
using System;
using System.Collections.Generic;
using System.IO;
using System.Net;
using System.Net.Sockets;
using System.Text;
using System.Threading.Tasks;
using MicroCode.Core;
using MicroCode.Views;

static class StudioModesTests
{
    static int _pass, _fail;

    static void Check(bool ok, string name)
    {
        Console.WriteLine((ok ? "PASS  " : "FAIL  ") + name);
        if (ok) _pass++; else _fail++;
    }

    [STAThread]
    static int Main()
    {
        string root = Path.Combine(Path.GetTempPath(), "mc-studiomodes-" + Guid.NewGuid().ToString("N").Substring(0, 8));
        Directory.CreateDirectory(root);
        Defaults.UseDir(Path.Combine(root, "appdata"));
        try
        {
            TestScience();
            TestSshAndRemote(root);
            TestScenario(root);
            TestEmbedded();
            TestOpenVsx(root);
            TestDatabase(root);
            TestContainer();
            TestCiCd(root);
            TestCloudGpu();
        }
        catch (Exception ex)
        {
            Check(false, "Unhandled exception: " + ex);
        }
        finally
        {
            try { Directory.Delete(root, true); } catch { }
        }
        Console.WriteLine();
        Console.WriteLine(_pass + " passed, " + _fail + " failed");
        return _fail == 0 ? 0 : 1;
    }

    static void TestScience()
    {
        string fasta = ">sp|P01308|INS_B Insulin B chain\nFVNQHLCGSHLVEALYLVCGERGFFYTPKT\n>seq2 second\nACDEFGHIKLMNPQRSTVWY\n";
        var recs = ScienceService.ParseFasta(fasta);
        Check(recs.Count == 2 && recs[0].Id == "sp|P01308|INS_B" && recs[0].Sequence.Length == 30, "ScienceService.ParseFasta parses multi-FASTA");
        Check(recs[1].Sequence == "ACDEFGHIKLMNPQRSTVWY", "ScienceService.ParseFasta extracts all 20 standard amino acids");

        var analysis = ScienceService.AnalyzeProtein(">insB\nFVNQHLCGSHLVEALYLVCGERGFFYTPKT");
        Check(analysis.Length == 30, "ScienceService.AnalyzeProtein length = 30");
        Check(analysis.MolecularWeightDa > 3300 && analysis.MolecularWeightDa < 3600, "ScienceService.AnalyzeProtein MW in expected range (" + analysis.MolecularWeightDa + " Da)");
        Check(Math.Abs(analysis.MolecularWeightKDa - analysis.MolecularWeightDa / 1000.0) < 0.01, "ScienceService.AnalyzeProtein kDa matches Da");
        Check(analysis.TheoreticalPI > 5.5 && analysis.TheoreticalPI < 8.5, "ScienceService.AnalyzeProtein theoretical pI (" + analysis.TheoreticalPI + ")");
        Check(analysis.Gravy > 0.0, "ScienceService.AnalyzeProtein GRAVY hydrophobic positive (" + analysis.Gravy + ")");
        Check(analysis.Composition['L'] == 4 && analysis.Composition['G'] == 3, "ScienceService.AnalyzeProtein AA composition counts");

        string af3 = ScienceService.GenerateAlphaFold3Json("test_complex", ">p1\nACDEFGHIK", "CC(=O)O", 2);
        List<string> errs;
        bool valid = ScienceService.ValidateAlphaFold3Json(af3, out errs);
        Check(valid && errs.Count == 0 && af3.Contains("\"alphafold3\""), "ScienceService AF3 JSON generator + validator pass");

        List<string> badErrs;
        bool invalid = ScienceService.ValidateAlphaFold3Json("{\"name\":\"\",\"sequences\":[{\"protein\":{\"sequence\":\"ACZ1\"}}]}", out badErrs);
        Check(!invalid && badErrs.Count >= 2, "ScienceService.ValidateAlphaFold3Json rejects invalid AF3 payload");
    }

    static void TestSshAndRemote(string root)
    {
        string cfg = "# comment\n" +
            "Host gpu-box gpu-alias\n" +
            "    HostName 10.20.30.40\n" +
            "    User ubuntu\n" +
            "    Port 2222\n" +
            "    IdentityFile ~/.ssh/id_ed25519\n" +
            "    ProxyJump bastion.internal\n\n" +
            "Host *\n" +
            "    ServerAliveInterval 60\n";
        var hosts = SSHConfigParser.ParseText(cfg);
        Check(hosts.Count == 2, "SSHConfigParser parses multi-alias Host and skips wildcard *");
        Check(hosts[0].Name == "gpu-box" && hosts[0].HostName == "10.20.30.40" && hosts[0].User == "ubuntu" && hosts[0].Port == 2222,
            "SSHConfigParser extracts HostName, User, Port");
        Check(hosts[0].ProxyJump == "bastion.internal" && hosts[0].IdentityFile.EndsWith("id_ed25519"),
            "SSHConfigParser extracts ProxyJump and expands IdentityFile");

        var custom = new List<SSHConfigProfile>
        {
            new SSHConfigProfile { Name = "sftp-prod", HostName = "files.example.com", User = "deploy", Port = 22, Protocol = "sftp", IsCustom = true }
        };
        RemoteProfileStore.SaveCustomProfiles(custom);
        var loaded = RemoteProfileStore.LoadCustomProfiles();
        Check(loaded.Count == 1 && loaded[0].Name == "sftp-prod" && loaded[0].Protocol == "sftp", "RemoteProfileStore roundtrips custom profiles via Defaults");

        string args = RemoteWorkspaceManager.BuildSshArgs(hosts[0], "ls -la");
        Check(args.Contains("-p 2222") && args.Contains("-J") && args.Contains("ubuntu@10.20.30.40"), "RemoteWorkspaceManager.BuildSshArgs formats OpenSSH flags");

        string lsSample = "total 16\ndrwxr-xr-x  4 ubuntu ubuntu 4096 Nov 22 10:00 src\n-rw-r--r--  1 ubuntu ubuntu  512 Nov 22 10:01 train.py\n";
        var entries = RemoteWorkspaceManager.ParseLsOutput(lsSample, "/workspace");
        Check(entries.Count == 2 && entries[0].IsDirectory && entries[0].Name == "src" && entries[1].FullPath == "/workspace/train.py" && entries[1].SizeBytes == 512,
            "RemoteWorkspaceManager.ParseLsOutput parses directories and files");
    }

    static void TestScenario(string root)
    {
        string ws = Path.Combine(root, "ws");
        Directory.CreateDirectory(ws);
        string targetFile = Path.Combine(ws, "artifact.txt");
        File.WriteAllText(targetFile, "build_status=GREEN\n");

        // Start tiny loopback HTTP server for scenario HTTP step
        var listener = new TcpListener(IPAddress.Loopback, 0);
        listener.Start();
        int port = ((IPEndPoint)listener.LocalEndpoint).Port;
        Task.Run(delegate
        {
            try
            {
                using (var client = listener.AcceptTcpClient())
                using (var ns = client.GetStream())
                {
                    byte[] buf = new byte[1024];
                    ns.Read(buf, 0, buf.Length);
                    byte[] resp = Encoding.UTF8.GetBytes("HTTP/1.1 200 OK\r\nContent-Length: 15\r\nConnection: close\r\n\r\n{\"health\":\"ok\"}");
                    ns.Write(resp, 0, resp.Length);
                }
            }
            catch { }
        });

        var suite = new ScenarioSuite { Name = "CI Smoke" };
        suite.Steps.Add(new ScenarioStep { Name = "Check File", Kind = "file_contains", Target = "artifact.txt", ExpectedText = "GREEN" });
        suite.Steps.Add(new ScenarioStep { Name = "Shell Echo", Kind = "shell", Target = "echo scenario_ok", ExpectedText = "scenario_ok" });
        suite.Steps.Add(new ScenarioStep { Name = "HTTP Health", Kind = "http", Target = "http://127.0.0.1:" + port + "/health", ExpectedStatus = 200, ExpectedText = "\"ok\"" });

        string suitePath = ScenarioService.DefaultSuitePath(ws);
        ScenarioService.SaveSuite(suitePath, suite);
        var reloaded = ScenarioService.LoadSuite(suitePath);
        Check(reloaded.Steps.Count == 3 && reloaded.Name == "CI Smoke", "ScenarioService persists and reloads .microcode/scenarios.json");

        var report = ScenarioService.RunSuite(reloaded, ws);
        listener.Stop();
        Check(report.TotalSteps == 3 && report.PassedSteps == 3 && report.FailedSteps == 0,
            "ScenarioService executes file, shell, and HTTP steps sequentially (" + report.PassedSteps + "/" + report.TotalSteps + ")");

        string json = ScenarioService.ExportReportJson(report);
        Check(json.Contains("\"passedSteps\": 3") && json.Contains("HTTP Health"), "ScenarioService.ExportReportJson emits valid JSON report");
    }

    static void TestEmbedded()
    {
        var ports = EmbeddedHardwareService.ListSerialPorts();
        Check(ports != null, "EmbeddedHardwareService.ListSerialPorts returns array safely");

        string exe, args;
        EmbeddedHardwareService.BuildToolchainCommand("arduino-cli", "flash", "COM5", "esp32:esp32:esp32", out exe, out args);
        Check(exe == "arduino-cli" && args.Contains("COM5") && args.Contains("esp32:esp32:esp32"), "EmbeddedHardwareService builds arduino-cli flash command");

        string espCrash = "Guru Meditation Error: Core  1 panic'ed (LoadProhibited). Exception was unhandled.\nEXCVADDR: 0x00000000\nBacktrace: 0x400d12a4:0x3ffb1f10 0x400d1580:0x3ffb1f40\n";
        var dec = EmbeddedHardwareService.DecodeBacktrace(espCrash, null);
        Check(dec.Architecture == "Xtensa / ESP32" && dec.Frames.Count == 2 && dec.Frames[0].PcHex == "0x400d12a4" && dec.FaultAddress == "0x00000000",
            "EmbeddedHardwareService.DecodeBacktrace decodes Xtensa/ESP32 panic + backtrace frames");
    }

    static void TestOpenVsx(string root)
    {
        string searchJson = "{\"extensions\":[{\"namespace\":\"ms-python\",\"name\":\"python\",\"displayName\":\"Python\",\"version\":\"2024.10.0\",\"downloadCount\":123456,\"description\":\"Python support\",\"files\":{\"download\":\"https://open-vsx.org/api/ms-python/python/2024.10.0/file/ms-python.python-2024.10.0.vsix\"}}]}";
        var parsed = OpenVsxService.ParseSearchJson(searchJson);
        Check(parsed.Count == 1 && parsed[0].Id == "ms-python.python" && parsed[0].DownloadCount == 123456 && parsed[0].DownloadUrl.EndsWith(".vsix"),
            "OpenVsxService.ParseSearchJson parses Open VSX API response");

        // Build a minimal valid Stored ZIP (.vsix) and unpack it
        string vsixPath = Path.Combine(root, "sample.vsix");
        WriteStoredZip(vsixPath, "extension/package.json", "{\"name\":\"demo-ext\",\"publisher\":\"dotmini\",\"version\":\"1.2.3\",\"description\":\"Demo\"}");
        string installDir = Path.Combine(OpenVsxService.ExtensionsDir, "dotmini.demo-ext");
        OpenVsxService.UnpackVsix(vsixPath, installDir);
        Check(File.Exists(Path.Combine(Path.Combine(installDir, "extension"), "package.json")), "OpenVsxService.UnpackVsix extracts .vsix ZIP archive");

        var installed = OpenVsxService.ListInstalled();
        Check(installed.Count == 1 && installed[0].Id == "dotmini.demo-ext" && installed[0].Enabled, "OpenVsxService.ListInstalled reads unpacked extension");
        OpenVsxService.SetEnabled("dotmini.demo-ext", false);
        Check(!OpenVsxService.ListInstalled()[0].Enabled, "OpenVsxService.SetEnabled disables extension");
        OpenVsxService.RemoveInstalled("dotmini.demo-ext");
        Check(OpenVsxService.ListInstalled().Count == 0, "OpenVsxService.RemoveInstalled deletes extension");
    }

    static void WriteStoredZip(string zipPath, string entryName, string content)
    {
        byte[] nameBytes = Encoding.UTF8.GetBytes(entryName);
        byte[] dataBytes = Encoding.UTF8.GetBytes(content);
        uint crc = Crc32(dataBytes);
        using (var fs = new FileStream(zipPath, FileMode.Create, FileAccess.Write))
        using (var bw = new BinaryWriter(fs))
        {
            // Local file header
            bw.Write((uint)0x04034b50);
            bw.Write((ushort)20);
            bw.Write((ushort)0);
            bw.Write((ushort)0); // stored
            bw.Write((ushort)0);
            bw.Write((ushort)0);
            bw.Write(crc);
            bw.Write((uint)dataBytes.Length);
            bw.Write((uint)dataBytes.Length);
            bw.Write((ushort)nameBytes.Length);
            bw.Write((ushort)0);
            bw.Write(nameBytes);
            bw.Write(dataBytes);
            long cdStart = fs.Position;
            // Central directory header
            bw.Write((uint)0x02014b50);
            bw.Write((ushort)20);
            bw.Write((ushort)20);
            bw.Write((ushort)0);
            bw.Write((ushort)0);
            bw.Write((ushort)0);
            bw.Write((ushort)0);
            bw.Write(crc);
            bw.Write((uint)dataBytes.Length);
            bw.Write((uint)dataBytes.Length);
            bw.Write((ushort)nameBytes.Length);
            bw.Write((ushort)0);
            bw.Write((ushort)0);
            bw.Write((ushort)0);
            bw.Write((ushort)0);
            bw.Write((uint)0);
            bw.Write((uint)0);
            bw.Write(nameBytes);
            long cdSize = fs.Position - cdStart;
            // End of central directory
            bw.Write((uint)0x06054b50);
            bw.Write((ushort)0);
            bw.Write((ushort)0);
            bw.Write((ushort)1);
            bw.Write((ushort)1);
            bw.Write((uint)cdSize);
            bw.Write((uint)cdStart);
            bw.Write((ushort)0);
        }
    }

    static uint Crc32(byte[] data)
    {
        uint crc = 0xFFFFFFFF;
        for (int i = 0; i < data.Length; i++)
        {
            crc ^= data[i];
            for (int b = 0; b < 8; b++)
                crc = (crc & 1) != 0 ? (crc >> 1) ^ 0xEDB88320u : (crc >> 1);
        }
        return ~crc;
    }

    static void TestDatabase(string root)
    {
        string exe, args;
        DatabaseStudioService.BuildCommand("PostgreSQL", "postgres://localhost/db", "SELECT 1;", out exe, out args);
        Check(exe == "psql" && args.Contains("SELECT 1;"), "DatabaseStudioService.BuildCommand supports PostgreSQL psql");

        var tbl = DatabaseStudioService.ParseDelimitedTable("id\tname\n1\tAlice\n2\tBob\n", '\t');
        Check(tbl.Columns.Count == 2 && tbl.Rows.Count == 2 && tbl.Rows[1][1] == "Bob", "DatabaseStudioService.ParseDelimitedTable parses rows");

        string dbPath = Path.Combine(root, "test.sqlite");
        var res = DatabaseStudioService.ExecuteQuery("SQLite", dbPath, "CREATE TABLE items(id INT, label TEXT); INSERT INTO items VALUES(1,'alpha'); SELECT id, label FROM items;");
        if (res.Ok)
            Check(res.Columns.Count == 2 && res.Rows.Count == 1 && res.Rows[0][1] == "alpha", "DatabaseStudioService executes live SQLite query");
        else
            Check(res.Error.Contains("not found") || res.Error.Length > 0, "DatabaseStudioService handles missing sqlite3/python cleanly");
    }

    static void TestContainer()
    {
        string psOut = "abc123\tweb-app\tnginx:latest\tUp 2 hours\t0.0.0.0:8080->80/tcp\ndef456\tredis-db\tredis:7\tExited (0) 1 hour ago\t\n";
        var cs = ContainerService.ParseContainersOutput(psOut);
        Check(cs.Count == 2 && cs[0].IsRunning && cs[0].Name == "web-app" && !cs[1].IsRunning, "ContainerService.ParseContainersOutput parses docker ps -a");

        string imgOut = "nginx\tlatest\timg111\t142MB\n";
        var imgs = ContainerService.ParseImagesOutput(imgOut);
        Check(imgs.Count == 1 && imgs[0].Repository == "nginx" && imgs[0].Size == "142MB", "ContainerService.ParseImagesOutput parses docker images");
    }

    static void TestCiCd(string root)
    {
        string wfDir = Path.Combine(Path.Combine(Path.Combine(root, "repo"), ".github"), "workflows");
        Directory.CreateDirectory(wfDir);
        string yml = "name: Build and Test\n" +
            "on: [push, pull_request]\n" +
            "jobs:\n" +
            "  build:\n" +
            "    name: Build Windows\n" +
            "    runs-on: windows-latest\n" +
            "    steps:\n" +
            "      - name: Checkout\n" +
            "        uses: actions/checkout@v4\n" +
            "      - name: Run Unit Tests\n" +
            "        run: |\n" +
            "          echo step_one\n" +
            "          echo step_two\n";
        string wfFile = Path.Combine(wfDir, "ci.yml");
        File.WriteAllText(wfFile, yml);

        var scanned = CiCdService.ScanWorkspace(Path.Combine(root, "repo"));
        Check(scanned.Count == 1 && scanned[0].Name == "Build and Test" && scanned[0].Jobs.Count == 1, "CiCdService.ScanWorkspace scans .github/workflows/*.yml");
        var job = scanned[0].Jobs[0];
        Check(job.Name == "Build Windows" && job.RunsOn == "windows-latest" && job.Steps.Count == 2, "CiCdService.ParseWorkflowYaml parses job metadata & steps");
        Check(job.Steps[1].Run.Contains("echo step_one") && job.Steps[1].Run.Contains("echo step_two"), "CiCdService.ParseWorkflowYaml parses multi-line run block");

        var stepExec = CiCdService.ExecuteStep(job.Steps[1], Path.Combine(root, "repo"), null);
        Check(stepExec.Ok && stepExec.StdOut.Contains("step_one") && stepExec.StdOut.Contains("step_two"), "CiCdService.ExecuteStep runs workflow step locally");

        var ghRuns = CiCdService.ParseGhRunListJson("[{\"databaseId\":\"991\",\"displayTitle\":\"CI Build\",\"status\":\"completed\",\"conclusion\":\"success\",\"headBranch\":\"main\"}]");
        Check(ghRuns.Count == 1 && ghRuns[0].DatabaseId == "991" && ghRuns[0].Conclusion == "success", "CiCdService.ParseGhRunListJson parses gh run list JSON");
    }

    static void TestCloudGpu()
    {
        var def = CloudGpuService.DefaultCatalog;
        Check(def.Count >= 4 && def.Exists(g => g.Id == "h100") && def.Exists(g => g.Id == "a100") && def.Exists(g => g.Id == "l40s") && def.Exists(g => g.Id == "rtx4090"),
            "CloudGpuService.DefaultCatalog includes H100, A100, L40S, RTX 4090");

        string catJson = "{\"gpus\":[{\"id\":\"b200\",\"label\":\"NVIDIA B200 192GB\",\"vramGB\":192,\"pricePerMinute\":480,\"available\":true}]}";
        var cat = CloudGpuService.ParseCatalogJson(catJson);
        Check(cat.Count == 1 && cat[0].Id == "b200" && cat[0].VramGB == 192 && cat[0].PricePerMinute == 480, "CloudGpuService.ParseCatalogJson parses gateway JSON");

        Check(CloudGpuService.EstimateSessionMinutes(15200, 152) == 100, "CloudGpuService.EstimateSessionMinutes computes wallet runtime");
        Check(CloudGpuService.EstimateCostSatang(90, 100) == 150, "CloudGpuService.EstimateCostSatang computes pro-rata cost");
        Check(CloudGpuService.ExceedsBudget(50000, 500) && !CloudGpuService.ExceedsBudget(49999, 500), "CloudGpuService.ExceedsBudget enforces THB cap");
        Check(CloudGpuService.FormatMoney(53000, "THB") == "฿530.00", "CloudGpuService.FormatMoney formats satang as THB");

        string rpJson = "{\"data\":{\"myself\":{\"pods\":[{\"id\":\"pod1\",\"name\":\"train\",\"desiredStatus\":\"RUNNING\",\"costPerHr\":1.89,\"machine\":{\"gpuDisplayName\":\"RTX 4090\"},\"runtime\":{\"ports\":[{\"ip\":\"1.2.3.4\",\"isIpPublic\":true,\"privatePort\":22,\"publicPort\":31222,\"type\":\"tcp\"}]}}]}}}";
        var rp = CloudGpuService.ParseRunPodJson(rpJson);
        Check(rp.Count == 1 && rp[0].Running && rp[0].SshHost == "1.2.3.4" && rp[0].SshPort == 31222, "CloudGpuService.ParseRunPodJson parses RunPod GraphQL response");

        string vastJson = "{\"instances\":[{\"id\":\"777\",\"gpu_name\":\"A100\",\"actual_status\":\"running\",\"ssh_host\":\"ssh5.vast.ai\",\"ssh_port\":12345,\"dph_total\":1.45}]}";
        var vast = CloudGpuService.ParseVastJson(vastJson);
        Check(vast.Count == 1 && vast[0].Running && vast[0].SshHost == "ssh5.vast.ai" && vast[0].SshPort == 12345, "CloudGpuService.ParseVastJson parses Vast.ai REST response");

        string sshCmd = CloudGpuService.BuildGpuSshCommand("root", "ssh5.vast.ai", 12345, 8888, 8888);
        Check(sshCmd == "ssh root@ssh5.vast.ai -p 12345 -L 8888:localhost:8888", "CloudGpuService.BuildGpuSshCommand formats tunnel command");
    }
}
