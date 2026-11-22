// Port of FirstLaunchWelcomeView.swift: optional first-run onboarding over the window. Signing in is a convenience —
// dismissing the card leaves the whole local editor available. Completion is a file flag (.welcome_done) like the Mac.
using System;
using System.IO;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Effects;
using MicroCode.Core;
using MicroCode.UI;

namespace MicroCode.Views
{
    public class FirstLaunchWelcome : Grid
    {
        /// <summary>Snapshot runs keep the overlay off unless --first-launch asks for it.</summary>
        public static bool Suppressed;
        static string FlagPath { get { return Path.Combine(Defaults.Dir, ".welcome_done"); } }
        /// <summary>Shown once per install (like the Mac's .welcome_done flag); someone already signed in to Dotmini is not asked again.</summary>
        public static bool ShouldShow { get { return !Suppressed && !File.Exists(FlagPath) && DotminiAuth.Session == null; } }

        readonly Action _done;
        bool _showDotmini, _working;
        string _status = "";
        readonly Border _card = new Border();
        TextBox _email;
        PasswordBox _password;

        public FirstLaunchWelcome(Action done)
        {
            _done = done;
            var t = Theme.Current;
            Background = Theme.B(Theme.WithAlpha(Colors.Black, 0.72));
            _card.Width = 500;
            _card.Padding = new Thickness(28);
            _card.CornerRadius = new CornerRadius(14);
            _card.Background = t.ElevatedBackground;
            _card.BorderBrush = t.P(0.12);
            _card.BorderThickness = new Thickness(1);
            _card.Margin = new Thickness(30);
            _card.HorizontalAlignment = HorizontalAlignment.Center;
            _card.VerticalAlignment = VerticalAlignment.Center;
            _card.Effect = new DropShadowEffect { BlurRadius = 56, ShadowDepth = 12, Direction = 270, Opacity = 0.4, Color = Colors.Black };
            Children.Add(_card);
            DotminiAuth.Changed += OnAuthChanged;
            Unloaded += delegate { DotminiAuth.Changed -= OnAuthChanged; };
            Render();
        }

        void OnAuthChanged()
        {
            // MicroCodeAccountLoggedIn: a browser (Google) sign-in that lands through the local bridge completes onboarding
            Dispatcher.BeginInvoke(new Action(() => { if (DotminiAuth.Session != null) Complete(); }));
        }

        void Complete()
        {
            try { Directory.CreateDirectory(Defaults.Dir); File.WriteAllText(FlagPath, ""); }
            catch (IOException ex) { System.Diagnostics.Debug.WriteLine("welcome flag: " + ex.Message); }
            DotminiAuth.Changed -= OnAuthChanged;
            _done();
        }

        void Render()
        {
            var t = Theme.Current;
            var col = V.VLead(0); col.Align = Cross.Stretch;
            var close = V.Button(V.Box(Sym.Icon("xmark", 12, t.Secondary, FontWeights.SemiBold), V.P(6), Brushes.Transparent, 4), Complete);
            close.ToolTip = "Dismiss Welcome Screen";
            close.VerticalAlignment = VerticalAlignment.Top;
            var title = V.VLead(10, V.T("Welcome to MicroCode", 25, FontWeights.SemiBold, t.Primary),
                V.Wrap(V.T("An agent-first workspace for understanding, changing, and shipping code.", 13, FontWeights.Normal, t.Secondary), TextAlignment.Left));
            var top = V.H(8, V.Flex(title), close); top.Align = Cross.Start; top.Margin = new Thickness(0, 0, 0, 22);
            col.Children.Add(top);
            Func<string, UIElement> row = s => V.H(10, V.Dot(5, t.S(0.45)), V.T(s, 12, FontWeights.Normal, t.P(0.9)));
            var rows = V.VLead(10, row("Work with the AI Agent as your primary workspace"), row("Open and edit code whenever you need direct control"), row("Projects and local editing work without an account"));
            rows.Margin = new Thickness(0, 0, 0, 24);
            col.Children.Add(rows);
            var line = V.Line(t.Separator, true); line.Margin = new Thickness(0, 0, 0, 18); col.Children.Add(line);
            var label = V.T("SIGN IN — OPTIONAL", 9, FontWeights.SemiBold, t.Secondary); label.Margin = new Thickness(0, 0, 0, 10); col.Children.Add(label);
            Func<UIElement, Action, Btn> wide = (content, a) =>
            {
                var b = V.Button(V.Size(V.Box(content, V.P(12, 0), t.PanelBackground, 7, t.P(0.12), 1), double.NaN, 38), a);
                b.IsEnabled = !_working;
                return b;
            };
            var g = V.T("G", 13, FontWeights.Bold, t.Primary); g.Width = 18; g.TextAlignment = TextAlignment.Center;
            col.Children.Add(wide(V.H(9, g, V.T(_working && !_showDotmini ? "Opening Google…" : "Continue with Google", 12, FontWeights.Medium, t.Primary), V.Sp()), Google));
            var gap = new Border { Height = 9 }; col.Children.Add(gap);
            col.Children.Add(wide(V.H(6, V.T("Dotmini ID", 12, FontWeights.Medium, t.Primary), V.Sp(), V.T(_showDotmini ? "Hide" : "Sign in", 10, FontWeights.Normal, t.Secondary)), () => { _showDotmini = !_showDotmini; _status = ""; Render(); }));
            if (_showDotmini)
            {
                var form = V.VLead(9); form.Align = Cross.Stretch; form.Margin = new Thickness(0, 10, 0, 0);
                string keepEmail = _email != null ? _email.Text : "";
                var ef = Styles.Field("Email", 12, t.Primary, t.Secondary, out _email);
                _email.Text = keepEmail;
                form.Children.Add(V.Size(V.Box(ef, V.P(11, 0), t.WorkspaceBackground, 7, t.P(0.12), 1), double.NaN, 36));
                string keepPw = _password != null ? _password.Password : "";
                _password = new PasswordBox { Password = keepPw, FontSize = 12, Foreground = t.Primary, Background = Brushes.Transparent, BorderThickness = new Thickness(0), VerticalContentAlignment = VerticalAlignment.Center, CaretBrush = t.Primary };
                var ph = V.T("Password", 12, FontWeights.Normal, t.Secondary); ph.IsHitTestVisible = false; ph.Margin = new Thickness(2, 0, 0, 0);
                ph.Visibility = keepPw.Length == 0 ? Visibility.Visible : Visibility.Collapsed;
                _password.PasswordChanged += delegate { ph.Visibility = _password.Password.Length == 0 ? Visibility.Visible : Visibility.Collapsed; };
                _password.KeyDown += (s, e) => { if (e.Key == Key.Enter) SignIn(); };
                var pg = new Grid(); pg.Children.Add(ph); pg.Children.Add(_password);
                form.Children.Add(V.Size(V.Box(pg, V.P(11, 0), t.WorkspaceBackground, 7, t.P(0.12), 1), double.NaN, 36));
                var signIn = V.Button(V.Box(V.T(_working ? "Signing in…" : "Sign in with Dotmini ID", 13, FontWeights.SemiBold, Brushes.White), V.P(16, 7), t.Accent, 7), SignIn);
                signIn.HorizontalAlignment = HorizontalAlignment.Right; signIn.IsEnabled = !_working;
                form.Children.Add(V.Self(signIn, Cross.End));
                col.Children.Add(form);
            }
            if (_status.Length > 0) { var st = V.Wrap(V.T(_status, 10, FontWeights.Normal, t.Secondary), TextAlignment.Left); st.Margin = new Thickness(0, 10, 0, 0); col.Children.Add(st); }
            var foot = V.H(8, V.T("You can sign in later from Settings.", 10, FontWeights.Normal, t.Secondary), V.Sp(), V.Button(V.T("Continue without signing in", 11, FontWeights.Medium, t.Primary), Complete));
            foot.Margin = new Thickness(0, 20, 0, 0);
            col.Children.Add(foot);
            _card.Child = col;
        }

        void Google()
        {
            _working = true; _status = "Opening secure Dotmini sign-in…"; Render();
            bool ok = DotminiAuth.StartBrowserSignIn("google");
            _working = false;
            _status = ok ? "Finish signing in in your browser — MicroCode picks up the session automatically." : "Could not start the local sign-in bridge on 127.0.0.1:" + LocalBridge.Port + " (" + LocalBridge.Error + "). Use Dotmini ID below instead.";
            Render();
        }

        async void SignIn()
        {
            if (_working || _email == null || _password == null) return;
            string email = _email.Text.Trim(), pw = _password.Password;
            if (email.Length == 0 || pw.Length == 0) return;
            _working = true; _status = ""; Render();
            try
            {
                await DotminiAuth.SignIn(email, pw);
                _working = false;
                Complete();
            }
            catch (Exception ex)
            {
                _working = false;
                _status = ex is AIException ? ex.Message : AIException.Describe(ex, true);
                Render();
            }
        }
    }
}
