// Port of WelcomeScreen / QuickActionCard / TemplateDetailCard / RecentProjectRow (Views/Workspace/WorkspaceWelcomeAndSheets.swift).
using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Media;
using MicroCode.Core;
using MicroCode.UI;

namespace MicroCode.Views
{
    public static class AppInfo
    {
        public const string Version = "2.5.41";
        public const string Build = "1";
    }

    public class WelcomeScreen : Grid
    {
        enum Tab { Projects, Templates, AIArchitect, Settings }
        readonly AppState _app;
        Tab _tab = Tab.Projects;
        readonly Border _left = new Border(), _right = new Border();

        public WelcomeScreen(AppState app)
        {
            _app = app;
            ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(210) });
            ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1) });
            ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            SetColumn(_left, 0); SetColumn(_right, 2);
            var div = new Border { Background = Theme.Current.P(0.1) };
            SetColumn(div, 1);
            Children.Add(_left); Children.Add(div); Children.Add(_right);
            Render();
        }

        void Render()
        {
            var t = Theme.Current;
            Background = t.WorkspaceBackground;
            // MARK: leftSidebarView (width 210, panelBackground)
            var header = V.VLead(2,
                V.T("MicroCode", 18, FontWeights.Bold, t.Primary),
                V.Box(V.T("Version " + AppInfo.Version + " · Build " + AppInfo.Build, 10, FontWeights.SemiBold, t.Secondary), V.P(6, 2), t.P(0.08), 4));
            var menu = V.Vs(6, NavButton("Projects", "folder", Tab.Projects), NavButton("Templates", "square.grid.2x2", Tab.Templates),
                NavButton("AI Architect", "sparkles", Tab.AIArchitect), NavButton("Settings", "gearshape", Tab.Settings));
            menu.Align = Cross.Stretch;
            var footer = V.VLead(4,
                V.T("Windows Native", 10, FontWeights.Medium, t.Secondary),
                V.H(4, V.Dot(6, t.P(0.6)), V.T("LSP Services Active", 9, FontWeights.Normal, t.Secondary)));
            var left = V.VLead(20,
                V.Box(header, V.P(16, 30, 16, 0), null, 0),
                V.Self(V.Box(menu, V.P(10, 0), null, 0), Cross.Stretch),
                V.Sp(),
                V.Box(footer, V.P(20, 0, 20, 25), null, 0));
            _left.Child = left;
            _left.Background = t.PanelBackground;

            // MARK: rightMainView
            if (_tab == Tab.AIArchitect)
            {
                _right.Child = new AgentView(_app, true);
                return;
            }
            var content = _tab == Tab.Projects ? Projects() : _tab == Tab.Templates ? Templates() : SettingsTab();
            _right.Child = new ScrollViewer { Content = V.Box(content, V.P(40, 35), null, 0), VerticalScrollBarVisibility = ScrollBarVisibility.Auto };
            _right.Background = t.WorkspaceBackground;
        }

        UIElement NavButton(string title, string icon, Tab tab)
        {
            var t = Theme.Current;
            bool sel = _tab == tab;
            var b = V.Button(V.Box(V.H(12,
                V.Size(new Grid { Children = { Sym.Icon(icon, 14, sel ? t.Primary : t.Secondary, sel ? FontWeights.SemiBold : FontWeights.Normal) } }, 20, double.NaN),
                V.T(title, 13, sel ? FontWeights.SemiBold : FontWeights.Medium, sel ? t.Primary : t.Secondary), V.Sp()), V.P(14, 10), sel ? t.P(0.1) : Brushes.Transparent, 8), () => { _tab = tab; Render(); });
            return b;
        }

        static UniformGrid Grid3(int columns) { return new UniformGrid { Columns = columns }; }

        UIElement Projects()
        {
            var t = Theme.Current;
            var root = V.VLead(24);
            root.Align = Cross.Stretch;
            root.Children.Add(V.Box(V.VLead(8,
                V.T("Welcome to MicroCode", 28, FontWeights.Bold, t.Primary),
                V.Wrap(V.T("Start a new project, run interactive scratchpads, or connect remote cloud instances.", 14, FontWeights.Normal, t.Secondary), TextAlignment.Left)), V.P(0, 0, 0, 6), null, 0));
            var grid = Grid3(3);
            Action<string, string, string, string, Action> card = (title, sub, icon, badge, act) => grid.Children.Add(V.Box(QuickActionCard(title, sub, icon, badge, act), V.P(0, 0, 14, 14), null, 0));
            card("New Project", "Choose from 14+ boilerplates", "plus.square", null, () => { _tab = Tab.Templates; Render(); });
            card("Open Folder", "Open an existing workspace", "folder", null, _app.OpenFolderDialog);
            card("Clone Repo", "Checkout from Git remote", "arrow.down.circle", null, CloneRepo);
            card("New Playground Mode", "Scratchpad & live code execution", "play.laptopcomputer", "Instant", () => _app.SwitchToMode(EditorMode.Playground));
            card("New Cell Mode", "Multi-language interactive notebook", "square.split.1x2.fill", "Cells", () => _app.SwitchToMode(EditorMode.Notebook));
            card("SSH Remote Browser", "Cloud instances & remote shell", "terminal.fill", "Remote", () => _app.SwitchToMode(EditorMode.RemoteX));
            card("Embed & IoT Studio", "Hardware flashing, serial & GPIO monitor", "cpu.fill", "IoT", () => _app.SwitchToMode(EditorMode.Embedded));
            card("AI Architect", "Chat & autonomous scaffolding", "sparkles", "Agent", () => { _tab = Tab.AIArchitect; Render(); });
            card("IDE Web Browser", "Built-in live browser & previews", "globe", null, () => _app.SwitchToMode(EditorMode.Browser));
            card("Settings & Cache", "Manage DerivedData & disk quotas", "gearshape", null, () => { _tab = Tab.Settings; Render(); });
            root.Children.Add(new Border { Child = grid, Margin = new Thickness(0, 0, -14, -14) });

            var recent = V.VLead(14, V.T("Recent Workspaces", 14, FontWeights.SemiBold, t.Secondary));
            recent.Align = Cross.Stretch;
            var list = AppState.RecentWorkspaces();
            if (list.Count == 0)
            {
                var empty = V.Box(V.Vs(12, Sym.Icon("folder.badge.questionmark", 24, t.S(0.7)), V.T("No recent projects found", 12, FontWeights.Normal, t.Secondary)), V.P(0, 30), t.P(0.02), 10, t.P(0.05), 1);
                recent.Children.Add(empty);
            }
            else
            {
                var rows = V.Vs(8); rows.Align = Cross.Stretch;
                foreach (var p in list.Take(8))
                {
                    string path = p;
                    var row = V.Button(V.Box(V.H(12, Sym.Icon("folder", 15, t.P(0.8)),
                        V.Flex(V.VLead(2, V.T(Path.GetFileName(path.TrimEnd('\\')), 13, FontWeights.Medium, t.Primary), V.T(Path.GetDirectoryName(path.TrimEnd('\\')) ?? "", 11, FontWeights.Normal, t.Secondary)))), V.P(12, 8), t.P(0.02), 8), () => _app.OpenWorkspace(path));
                    row.OnState = b => ((Border)b.Child).Background = b.IsHover ? t.P(0.06) : t.P(0.02);
                    rows.Children.Add(row);
                }
                recent.Children.Add(rows);
            }
            root.Children.Add(V.Box(recent, V.P(0, 10, 0, 0), null, 0));
            return root;
        }

        UIElement QuickActionCard(string title, string subtitle, string icon, string badge, Action act)
        {
            var t = Theme.Current;
            var circle = new Grid { Width = 38, Height = 38 };
            var circleBg = new System.Windows.Shapes.Ellipse { Fill = t.P(0.06) };
            circle.Children.Add(circleBg);
            circle.Children.Add(Sym.Icon(icon, 16, t.Primary, FontWeights.Medium));
            var top = V.H(0, circle, V.Sp());
            if (badge != null) top.Children.Add(V.Box(V.T(badge, 9, FontWeights.SemiBold, t.Secondary), V.P(6, 2), t.P(0.06), 4));
            var sub = V.T(subtitle, 11, FontWeights.Normal, t.Secondary);
            sub.TextWrapping = TextWrapping.Wrap; sub.MaxHeight = 30;
            var body = V.VLead(12, V.Self(top, Cross.Stretch), V.VLead(4, V.T(title, 13, FontWeights.SemiBold, t.Primary), sub));
            var box = V.Box(body, V.P(14), t.P(0.025), 12, t.P(0.08), 1);
            box.MinHeight = 110;
            var b = V.Button(box, act);
            b.OnState = x =>
            {
                box.Background = x.IsHover ? t.P(0.06) : t.P(0.025);
                box.BorderBrush = x.IsHover ? t.P(0.25) : t.P(0.08);
                circleBg.Fill = t.P(x.IsHover ? 0.12 : 0.06);
                x.RenderTransformOrigin = new Point(0.5, 0.5);
                x.RenderTransform = new ScaleTransform(x.IsHover ? 1.015 : 1, x.IsHover ? 1.015 : 1);
            };
            return b;
        }

        UIElement Templates()
        {
            var t = Theme.Current;
            var root = V.VLead(24);
            root.Align = Cross.Stretch;
            root.Children.Add(V.VLead(6, V.T("Select a Template", 24, FontWeights.Bold, t.Primary),
                V.Wrap(V.T("Bootstrap projects instantly with built-in presets. Conforms strictly to your active theme.", 13, FontWeights.Normal, t.Secondary), TextAlignment.Left)));
            var grid = Grid3(2);
            string[,] tpl = {
                {"Next.js 14 App","Fullstack React framework with App Router, TypeScript, and Server Components.","n.square.fill","Fullstack","nextjs"},
                {"Vite + React","Blazing fast frontend SPA with TypeScript and Hot Module Replacement.","atom","Frontend","vite"},
                {"FastAPI Backend","High-performance async Python API with Pydantic v2 and OpenAPI docs.","bolt.fill","Python","fastapi"},
                {"Rust Axum Service","Ultra-fast asynchronous microservice powered by Tokio runtime.","gearshape.2.fill","Rust","rust-axum"},
                {"SwiftUI App","Native Apple platforms application using SwiftUI declarative framework.","swift","Apple Native","swift"},
                {"Ardium CoreUI","High-performance native GUI using Dotmini's Ardium v2.3 language.","cpu.fill","Ardium","ardium"},
                {"Express.js API","Lightweight, scalable Node.js microservice API with TypeScript.","server.rack","Node.js","express"},
                {"Go Gin Microservice","High-throughput compiled HTTP web API with minimal footprint.","speedometer","Go","go"},
                {"Flutter Multiplatform","Cross-platform mobile, desktop, and web application with Dart.","apps.iphone","Dart","flutter"},
                {"Spring Boot 3","Enterprise-grade Java service with Spring MVC and Virtual Threads.","leaf.fill","Java","spring"},
                {"PyTorch / ML Pipeline","Machine learning training and inference pipeline with Apple MPS.","brain.head.profile","AI / ML","pytorch"},
                {"Docker Microservices","Production Docker compose stack with PostgreSQL and Redis.","shippingbox.fill","DevOps","docker"},
                {"Vue 3 + Vite","Lightweight reactive frontend with Pinia and Vue Router.","v.circle.fill","Frontend","vue"},
                {"NestJS Enterprise","Structured TypeScript enterprise architecture with dependency injection.","shield.fill","TypeScript","nestjs"}
            };
            for (int i = 0; i < tpl.GetLength(0); i++)
            {
                string key = tpl[i, 4];
                grid.Children.Add(V.Box(TemplateCard(tpl[i, 0], tpl[i, 1], tpl[i, 2], tpl[i, 3], () => CreateProject(key)), V.P(0, 0, 14, 14), null, 0));
            }
            root.Children.Add(new Border { Child = grid, Margin = new Thickness(0, 0, -14, -14) });
            return root;
        }

        UIElement TemplateCard(string title, string subtitle, string icon, string tag, Action act)
        {
            var t = Theme.Current;
            var tile = new Border { Width = 42, Height = 42, CornerRadius = new CornerRadius(10), Background = t.P(0.04), Child = Sym.Icon(icon, 18, t.Primary, FontWeights.Medium) };
            var sub = V.T(subtitle, 11, FontWeights.Normal, t.Secondary); sub.TextWrapping = TextWrapping.Wrap; sub.MaxHeight = 30;
            var body = V.H(14, tile, V.Flex(V.VLead(3, V.H(6, V.T(title, 13, FontWeights.SemiBold, t.Primary), V.Box(V.T(tag, 9, FontWeights.Medium, t.Secondary), V.P(6, 2), t.P(0.06), 4)), sub)));
            var box = V.Box(body, V.P(12), t.P(0.025), 10, t.P(0.06), 1);
            var b = V.Button(box, act);
            b.OnState = x =>
            {
                box.Background = x.IsHover ? t.P(0.06) : t.P(0.025);
                box.BorderBrush = x.IsHover ? t.P(0.22) : t.P(0.06);
                tile.Background = t.P(x.IsHover ? 0.08 : 0.04);
            };
            return b;
        }

        void CreateProject(string type)
        {
            var prompts = new Dictionary<string, string>
            {
                {"nextjs","Please scaffold a new Next.js 14 App (TypeScript, Tailwind CSS, App Router) in this workspace. Initialize standard project structure and packages."},
                {"vite","Please scaffold a new Vite + React + TypeScript web app in this workspace with Tailwind CSS and standard config."},
                {"fastapi","Please scaffold a modern Python 3.12 FastAPI project in this workspace with main.py, requirements.txt, Pydantic models, and sample endpoints."},
                {"rust-axum","Please initialize a new Rust Axum asynchronous web microservice in this workspace with Cargo.toml and src/main.rs."},
                {"swift","Please create a new native Apple macOS/iOS SwiftUI application in this workspace with Package.swift or Xcode structure."},
                {"ardium","Please create a new Ardium v2.3 project with CoreUI in this workspace."},
                {"express","Please scaffold a TypeScript Express.js REST API in this workspace with package.json, src/index.ts, and routing."},
                {"go","Please initialize a new Go microservice with Gin in this workspace with go.mod and main.go."},
                {"flutter","Please scaffold a cross-platform Flutter app in this workspace with pubspec.yaml and lib/main.dart."},
                {"spring","Please scaffold a Java 21 Spring Boot 3 microservice in this workspace with pom.xml and Application.java."},
                {"pytorch","Please scaffold a Python PyTorch machine learning pipeline in this workspace with model definition, train.py, and requirements.txt."},
                {"docker","Please generate a Dockerized multi-service development stack with docker-compose.yml, PostgreSQL, Redis, and sample API."},
                {"vue","Please scaffold a Vue 3 + Vite + TypeScript application in this workspace with App.vue and main.ts."},
                {"nestjs","Please scaffold a NestJS enterprise TypeScript API in this workspace with nest-cli config, modules, and controllers."}
            };
            string prompt;
            if (!prompts.TryGetValue(type, out prompt)) prompt = "Please initialize a new " + type + " project in this workspace.";
            var folder = Native.PickFolder("Select a folder for the new project", null);
            if (folder == null) return;
            _app.OpenWorkspace(folder);
            _app.SwitchToMode(EditorMode.AIAgent);
            _app.Notify("agent:send:" + prompt);
        }

        void CloneRepo()
        {
            string url = Prompt.Ask("Clone Repository", "Git repository URL:", "https://github.com/");
            if (string.IsNullOrWhiteSpace(url)) return;
            var parent = Native.PickFolder("Choose where to clone the repository", null);
            if (parent == null) return;
            string name = Path.GetFileNameWithoutExtension(url.TrimEnd('/'));
            string target = Path.Combine(parent, name);
            try
            {
                var p = System.Diagnostics.Process.Start(new System.Diagnostics.ProcessStartInfo("git", "clone \"" + url.Trim() + "\" \"" + target + "\"") { UseShellExecute = false, CreateNoWindow = true, RedirectStandardError = true });
                p.WaitForExit();
                if (p.ExitCode != 0) { MessageBox.Show(p.StandardError.ReadToEnd(), "Clone failed"); return; }
                _app.OpenWorkspace(target);
            }
            catch (Exception ex) { MessageBox.Show(ex.Message, "Clone failed"); }
        }

        UIElement SettingsTab()
        {
            var t = Theme.Current;
            string cache = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "MicroCode", "Cache");
            long size = 0; int count = 0;
            try { if (Directory.Exists(cache)) { foreach (var f in new DirectoryInfo(cache).GetFiles("*", SearchOption.AllDirectories)) { size += f.Length; } count = Directory.GetDirectories(cache).Length; } } catch { }
            var purge = V.Button(V.Box(V.T("Purge Cache", 13, FontWeights.Normal, t.SysRed), V.P(12, 6), t.Op(t.SysRed, 0.15), 6), () => { try { if (Directory.Exists(cache)) Directory.Delete(cache, true); } catch { } Render(); });
            var refresh = V.Button(V.Box(Sym.Icon("arrow.clockwise", 13, t.Primary), V.P(6), Theme.B(Theme.WithAlpha(Colors.White, 0.06)), 6), Render);
            var root = V.VLead(24,
                V.VLead(6, V.T("Workspace & Cache Settings", 24, FontWeights.Bold, t.Primary), V.T("Manage temporary data, purge build caches, and configure disk quotas.", 13, FontWeights.Normal, t.Secondary)),
                V.Self(V.H(10, V.VLead(4, V.T("Derived Data Cache Size", 14, FontWeights.SemiBold, t.Primary), V.T((size / (1024.0 * 1024 * 1024)).ToString("0.00") + " GB (" + count + " projects)", 12, FontWeights.Normal, t.Secondary)), V.Sp(), purge, refresh), Cross.Stretch));
            root.Align = Cross.Stretch;
            return root;
        }
    }
}
