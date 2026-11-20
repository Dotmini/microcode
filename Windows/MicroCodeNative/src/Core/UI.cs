// MicroCode for Windows — native WPF port.
// SwiftUI-style layout primitives so each SwiftUI view ports 1:1 (HStack/VStack/Spacer/padding/background/cornerRadius).
using System;
using System.Collections.Generic;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Effects;
using System.Windows.Shapes;
using System.Windows.Shell;

namespace MicroCode.UI
{
    public enum Cross { Start, Center, End, Stretch }

    /// <summary>SwiftUI HStack/VStack: spacing, cross-axis alignment, flexible children (Spacer / maxWidth: .infinity)
    /// and shrinkable children (truncating text with low layout priority).</summary>
    public class Stack : Panel
    {
        public Orientation Orientation { get; set; }
        public double Spacing { get; set; }
        public Cross Align { get; set; }

        public static readonly DependencyProperty FlexProperty = DependencyProperty.RegisterAttached(
            "Flex", typeof(double), typeof(Stack), new FrameworkPropertyMetadata(0.0, FrameworkPropertyMetadataOptions.AffectsParentMeasure));
        public static double GetFlex(DependencyObject o) { return (double)o.GetValue(FlexProperty); }
        public static void SetFlex(DependencyObject o, double v) { o.SetValue(FlexProperty, v); }

        public static readonly DependencyProperty ShrinkProperty = DependencyProperty.RegisterAttached(
            "Shrink", typeof(bool), typeof(Stack), new FrameworkPropertyMetadata(false, FrameworkPropertyMetadataOptions.AffectsParentMeasure));
        public static bool GetShrink(DependencyObject o) { return (bool)o.GetValue(ShrinkProperty); }
        public static void SetShrink(DependencyObject o, bool v) { o.SetValue(ShrinkProperty, v); }

        public static readonly DependencyProperty SelfProperty = DependencyProperty.RegisterAttached(
            "Self", typeof(object), typeof(Stack), new FrameworkPropertyMetadata(null, FrameworkPropertyMetadataOptions.AffectsParentArrange));
        public static void SetSelf(DependencyObject o, Cross c) { o.SetValue(SelfProperty, c); }

        public Stack() { Align = Cross.Center; }

        bool Horz { get { return Orientation == Orientation.Horizontal; } }
        static double MainOf(Size s, bool h) { return h ? s.Width : s.Height; }
        static double CrossOf(Size s, bool h) { return h ? s.Height : s.Width; }
        static Size Mk(double main, double cross, bool h) { return h ? new Size(main, cross) : new Size(cross, main); }

        double[] _main = new double[0];

        protected override Size MeasureOverride(Size avail)
        {
            bool h = Horz;
            double mainAvail = MainOf(avail, h), crossAvail = CrossOf(avail, h);
            var kids = InternalChildren;
            int n = kids.Count;
            _main = new double[n];
            int vis = 0; double used = 0, crossMax = 0, flexTotal = 0;
            for (int i = 0; i < n; i++)
            {
                var c = kids[i];
                if (c == null || c.Visibility == Visibility.Collapsed) continue;
                vis++;
                double f = GetFlex(c);
                if (f > 0) { flexTotal += f; continue; }
                if (GetShrink(c)) continue;
                c.Measure(Mk(double.PositiveInfinity, crossAvail, h));
                _main[i] = MainOf(c.DesiredSize, h);
                used += _main[i];
                crossMax = Math.Max(crossMax, CrossOf(c.DesiredSize, h));
            }
            if (vis > 1) used += Spacing * (vis - 1);
            bool inf = double.IsInfinity(mainAvail);
            double rem = inf ? double.PositiveInfinity : Math.Max(0, mainAvail - used);
            for (int i = 0; i < n; i++)
            {
                var c = kids[i];
                if (c == null || c.Visibility == Visibility.Collapsed || GetFlex(c) > 0 || !GetShrink(c)) continue;
                c.Measure(Mk(rem, crossAvail, h));
                double m = MainOf(c.DesiredSize, h);
                if (!inf) { m = Math.Min(m, rem); rem -= m; }
                _main[i] = m; used += m;
                crossMax = Math.Max(crossMax, CrossOf(c.DesiredSize, h));
            }
            double flexSpace = inf ? 0 : Math.Max(0, mainAvail - used);
            for (int i = 0; i < n; i++)
            {
                var c = kids[i];
                if (c == null || c.Visibility == Visibility.Collapsed) continue;
                double f = GetFlex(c);
                if (f <= 0) continue;
                if (inf)
                {
                    c.Measure(Mk(double.PositiveInfinity, crossAvail, h));
                    _main[i] = MainOf(c.DesiredSize, h);
                }
                else
                {
                    double share = flexTotal > 0 ? flexSpace * f / flexTotal : 0;
                    c.Measure(Mk(share, crossAvail, h));
                    _main[i] = share;
                }
                used += _main[i];
                crossMax = Math.Max(crossMax, CrossOf(c.DesiredSize, h));
            }
            return Mk(used, crossMax, h);
        }

        protected override Size ArrangeOverride(Size final)
        {
            bool h = Horz;
            double mainFinal = MainOf(final, h), crossFinal = CrossOf(final, h);
            var kids = InternalChildren;
            int n = kids.Count;
            if (_main.Length != n) _main = new double[n];
            double fixedUsed = 0, flexTotal = 0; int vis = 0;
            for (int i = 0; i < n; i++)
            {
                var c = kids[i];
                if (c == null || c.Visibility == Visibility.Collapsed) continue;
                vis++;
                double f = GetFlex(c);
                if (f > 0) flexTotal += f; else fixedUsed += _main[i];
            }
            if (vis > 1) fixedUsed += Spacing * (vis - 1);
            double flexSpace = Math.Max(0, mainFinal - fixedUsed);
            double pos = 0;
            for (int i = 0; i < n; i++)
            {
                var c = kids[i];
                if (c == null || c.Visibility == Visibility.Collapsed) continue;
                double f = GetFlex(c);
                double m = f > 0 ? (flexTotal > 0 ? flexSpace * f / flexTotal : 0) : _main[i];
                double cs = Math.Min(CrossOf(c.DesiredSize, h), crossFinal);
                object self = c.GetValue(SelfProperty);
                Cross a = self is Cross ? (Cross)self : Align;
                double cp = 0, csz = cs;
                switch (a)
                {
                    case Cross.Stretch: cp = 0; csz = crossFinal; break;
                    case Cross.Start: cp = 0; break;
                    case Cross.Center: cp = (crossFinal - cs) / 2; break;
                    case Cross.End: cp = crossFinal - cs; break;
                }
                c.Arrange(h ? new Rect(pos, cp, m, csz) : new Rect(cp, pos, csz, m));
                pos += m + Spacing;
            }
            return final;
        }
    }

    /// <summary>SwiftUI Spacer().</summary>
    public class Spacer : FrameworkElement
    {
        public double MinLength { get; set; }
        public Spacer() { Stack.SetFlex(this, 1); }
        protected override Size MeasureOverride(Size availableSize) { return new Size(MinLength, MinLength); }
    }

    /// <summary>Plain button (SwiftUI .buttonStyle(.plain)): hit-testable over transparent areas, dims while pressed,
    /// reports hover so the owner can restyle, opens a SwiftUI-style Menu when MenuItems is set.</summary>
    public class Btn : Border
    {
        public event Action Click;
        public Action<Btn> OnState;
        public Func<List<MenuItemSpec>> MenuItems;
        public bool IsHover, IsPressed;
        public double PressedOpacity = 0.72;
        public bool MenuAlignRight;

        public Btn()
        {
            Background = Brushes.Transparent;
            Focusable = false;
            SnapsToDevicePixels = true;
            WindowChrome.SetIsHitTestVisibleInChrome(this, true);
            ToolTipService.SetInitialShowDelay(this, 700);
            MouseEnter += delegate { IsHover = true; Refresh(); };
            MouseLeave += delegate { IsHover = false; IsPressed = false; Refresh(); };
            MouseLeftButtonDown += delegate(object s, MouseButtonEventArgs e)
            {
                IsPressed = true; CaptureMouse(); Refresh(); e.Handled = true;
            };
            MouseLeftButtonUp += delegate(object s, MouseButtonEventArgs e)
            {
                bool was = IsPressed;
                IsPressed = false;
                if (IsMouseCaptured) ReleaseMouseCapture();
                Refresh();
                e.Handled = true;
                var p = e.GetPosition(this);
                if (was && p.X >= 0 && p.Y >= 0 && p.X <= ActualWidth && p.Y <= ActualHeight) Fire();
            };
        }

        public void Fire()
        {
            if (MenuItems != null)
            {
                MacMenu.Show(this, MenuItems(), MenuAlignRight);
                return;
            }
            if (Click != null) Click();
        }

        public void Refresh()
        {
            Opacity = IsPressed ? PressedOpacity : 1.0;
            if (OnState != null) OnState(this);
        }
    }

    public class MenuItemSpec
    {
        public string Title, Icon, Shortcut;
        public Action Action;
        public bool IsSeparator, IsHeader, Checked, Disabled, Destructive;
        public List<MenuItemSpec> Children;
        public static MenuItemSpec Sep() { return new MenuItemSpec { IsSeparator = true }; }
        public static MenuItemSpec Header(string t) { return new MenuItemSpec { IsHeader = true, Title = t }; }
        public static MenuItemSpec Item(string t, string icon, Action a) { return new MenuItemSpec { Title = t, Icon = icon, Action = a }; }
        public static MenuItemSpec Sub(string t, string icon, List<MenuItemSpec> kids) { return new MenuItemSpec { Title = t, Icon = icon, Children = kids }; }
    }

    /// <summary>NSMenu look-alike (dark vibrancy panel, 22pt rows, accent highlight, sections, submenus).</summary>
    public static class MacMenu
    {
        static readonly List<Popup> Open = new List<Popup>();

        public static void CloseAll()
        {
            var copy = Open.ToArray();
            Open.Clear();
            foreach (var p in copy) p.IsOpen = false;
        }

        public static Popup Show(FrameworkElement anchor, List<MenuItemSpec> items, bool alignRight)
        {
            CloseAll();
            return ShowAt(anchor, items, alignRight ? PlacementMode.Custom : PlacementMode.Bottom, 0, 2, 0);
        }

        public static Popup ShowAtMouse(List<MenuItemSpec> items)
        {
            CloseAll();
            return ShowAt(null, items, PlacementMode.MousePoint, 0, 0, 0);
        }

        static Popup ShowAt(FrameworkElement anchor, List<MenuItemSpec> items, PlacementMode mode, double h, double v, int depth)
        {
            var t = Core.Theme.Current;
            var pop = new Popup
            {
                AllowsTransparency = true,
                StaysOpen = depth > 0,
                PlacementTarget = anchor,
                Placement = mode,
                HorizontalOffset = h - 14,
                VerticalOffset = v - 8,
                PopupAnimation = PopupAnimation.Fade,
                Focusable = false
            };
            if (mode == PlacementMode.Custom)
            {
                pop.CustomPopupPlacementCallback = delegate(Size popupSize, Size targetSize, Point offset)
                {
                    return new[] { new CustomPopupPlacement(new Point(targetSize.Width - popupSize.Width + 14, targetSize.Height - 6), PopupPrimaryAxis.Horizontal) };
                };
            }
            var list = new StackPanel { Orientation = Orientation.Vertical };
            bool anyIcon = false, anyCheck = false;
            foreach (var it in items) { if (!string.IsNullOrEmpty(it.Icon)) anyIcon = true; if (it.Checked) anyCheck = true; }
            foreach (var it in items)
            {
                var item = it;
                if (item.IsSeparator)
                {
                    list.Children.Add(new Border { Height = 1, Margin = new Thickness(10, 5, 10, 5), Background = t.Separator });
                    continue;
                }
                if (item.IsHeader)
                {
                    list.Children.Add(new TextBlock
                    {
                        Text = item.Title, FontFamily = UIFonts.UI, FontSize = 11, FontWeight = FontWeights.SemiBold,
                        Foreground = t.Secondary, Margin = new Thickness(anyCheck ? 22 : 10, 4, 10, 2)
                    });
                    continue;
                }
                var row = new Btn { Height = 22, CornerRadius = new CornerRadius(4), Padding = new Thickness(anyCheck ? 4 : 8, 0, 8, 0), PressedOpacity = 1 };
                var g = new Stack { Orientation = Orientation.Horizontal, Spacing = 6 };
                Brush fg = item.Disabled ? t.Tertiary : (item.Destructive ? (Brush)t.SysRed : t.Primary);
                if (anyCheck) g.Children.Add(new TextBlock { Text = item.Checked ? "✓" : "", Width = 12, FontFamily = UIFonts.UI, FontSize = 12, Foreground = fg });
                if (anyIcon)
                {
                    var ic = string.IsNullOrEmpty(item.Icon) ? (UIElement)new Border { Width = 15 } : Sym.Icon(item.Icon, 12, fg);
                    if (ic is FrameworkElement) ((FrameworkElement)ic).Width = 15;
                    g.Children.Add(ic);
                }
                var label = V.T(item.Title, 13, FontWeights.Normal, fg);
                g.Children.Add(label);
                g.Children.Add(new Spacer { MinLength = 20 });
                if (!string.IsNullOrEmpty(item.Shortcut)) g.Children.Add(V.T(item.Shortcut, 12.5, FontWeights.Normal, t.Secondary));
                if (item.Children != null) g.Children.Add(Sym.Icon("chevron.right", 9, t.Secondary));
                row.Child = g;
                row.OnState = delegate(Btn b)
                {
                    bool hl = b.IsHover && !item.Disabled;
                    b.Background = hl ? t.MenuHighlight : Brushes.Transparent;
                    var fgNow = hl ? Brushes.White : fg;
                    foreach (var child in g.Children)
                    {
                        var tb = child as TextBlock;
                        if (tb != null) tb.Foreground = hl ? Brushes.White : (tb == label ? fg : (Brush)(tb.Text == "✓" || tb.Text == "" ? fg : t.Secondary));
                        var sym = child as SymbolIcon;
                        if (sym != null) sym.SetBrush(fgNow);
                    }
                    if (hl && item.Children != null)
                    {
                        while (Open.Count > depth + 1) { Open[Open.Count - 1].IsOpen = false; Open.RemoveAt(Open.Count - 1); }
                        ShowAt(b, item.Children, PlacementMode.Right, 4, 2, depth + 1);
                    }
                    else if (hl)
                    {
                        while (Open.Count > depth + 1) { Open[Open.Count - 1].IsOpen = false; Open.RemoveAt(Open.Count - 1); }
                    }
                };
                row.Click += delegate
                {
                    if (item.Disabled || item.Children != null) return;
                    CloseAll();
                    if (item.Action != null) Application.Current.Dispatcher.BeginInvoke(item.Action);
                };
                list.Children.Add(row);
            }
            var panel = new Border
            {
                Child = list,
                Background = t.MenuBackground,
                BorderBrush = t.MenuBorder,
                BorderThickness = new Thickness(1),
                CornerRadius = new CornerRadius(7),
                Padding = new Thickness(5),
                MinWidth = 190,
                Margin = new Thickness(14, 8, 14, 20),
                Effect = new DropShadowEffect { BlurRadius = 22, ShadowDepth = 6, Direction = 270, Opacity = 0.45, Color = Colors.Black }
            };
            pop.Child = panel;
            pop.Closed += delegate { Open.Remove(pop); };
            Open.Add(pop);
            pop.IsOpen = true;
            if (depth == 0)
            {
                pop.Opened += delegate { };
            }
            return pop;
        }
    }

    public static class UIFonts
    {
        public static readonly FontFamily UI = new FontFamily("Segoe UI");
        public static readonly FontFamily Mono = new FontFamily("Consolas");
        public static readonly FontFamily Icons = new FontFamily("Segoe Fluent Icons, Segoe MDL2 Assets");

        /// <summary>Maps the macOS font names offered in Settings to fonts available on Windows.</summary>
        public static FontFamily Map(string macName)
        {
            switch (macName)
            {
                case "SF Pro": case "Helvetica Neue": return UI;
                case "Courier New": return new FontFamily("Courier New");
                case "Fira Code": case "JetBrains Mono": case "Cascadia Code": case "Cascadia Mono":
                    foreach (var f in System.Windows.Media.Fonts.SystemFontFamilies) if (f.Source == macName) return f;
                    return Mono;
                default: return Mono; // SF Mono, Menlo, Monaco
            }
        }

        public static FontFamily Code(string key, string def) { return Map(Core.Defaults.Str(key, def)); }
    }

    /// <summary>View builders mirroring SwiftUI modifiers.</summary>
    public static class V
    {
        public static Stack H(double spacing, params UIElement[] kids)
        {
            var s = new Stack { Orientation = Orientation.Horizontal, Spacing = spacing };
            foreach (var k in kids) if (k != null) s.Children.Add(k);
            return s;
        }

        public static Stack Vs(double spacing, params UIElement[] kids)
        {
            var s = new Stack { Orientation = Orientation.Vertical, Spacing = spacing, Align = Cross.Center };
            foreach (var k in kids) if (k != null) s.Children.Add(k);
            return s;
        }

        public static Stack VLead(double spacing, params UIElement[] kids)
        {
            var s = Vs(spacing, kids);
            s.Align = Cross.Start;
            return s;
        }

        public static Spacer Sp() { return new Spacer(); }
        public static Spacer Sp(double min) { return new Spacer { MinLength = min }; }

        public static TextBlock T(string text, double size, FontWeight weight, Brush fg)
        {
            return new TextBlock
            {
                Text = text ?? "", FontFamily = UIFonts.UI, FontSize = size, FontWeight = weight, Foreground = fg,
                TextTrimming = TextTrimming.CharacterEllipsis, TextWrapping = TextWrapping.NoWrap,
                VerticalAlignment = VerticalAlignment.Center
            };
        }

        public static TextBlock Mono(string text, double size, FontWeight weight, Brush fg)
        {
            var t = T(text, size, weight, fg);
            t.FontFamily = UIFonts.Mono;
            return t;
        }

        public static TextBlock Wrap(TextBlock t, TextAlignment align)
        {
            t.TextWrapping = TextWrapping.Wrap;
            t.TextTrimming = TextTrimming.None;
            t.TextAlignment = align;
            return t;
        }

        public static T Flex<T>(T e) where T : UIElement { Stack.SetFlex(e, 1); return e; }
        public static T Shrink<T>(T e) where T : UIElement { Stack.SetShrink(e, true); return e; }
        public static T Self<T>(T e, Cross c) where T : UIElement { Stack.SetSelf(e, c); return e; }

        public static Border Box(UIElement child, Thickness pad, Brush bg, double radius)
        {
            return new Border { Child = child, Padding = pad, Background = bg, CornerRadius = new CornerRadius(radius), SnapsToDevicePixels = true };
        }

        public static Border Box(UIElement child, Thickness pad, Brush bg, double radius, Brush stroke, double strokeWidth)
        {
            var b = Box(child, pad, bg, radius);
            b.BorderBrush = stroke;
            b.BorderThickness = new Thickness(strokeWidth);
            return b;
        }

        public static Thickness P(double all) { return new Thickness(all); }
        public static Thickness P(double h, double v) { return new Thickness(h, v, h, v); }
        public static Thickness P(double l, double t, double r, double b) { return new Thickness(l, t, r, b); }

        public static T Size<T>(T e, double w, double h) where T : FrameworkElement
        {
            if (!double.IsNaN(w)) e.Width = w;
            if (!double.IsNaN(h)) e.Height = h;
            return e;
        }

        public static T Tip<T>(T e, string tip) where T : FrameworkElement { e.ToolTip = tip; return e; }

        public static Btn Button(UIElement content, Action click)
        {
            var b = new Btn { Child = content };
            if (click != null) b.Click += click;
            return b;
        }

        public static Border Line(Brush brush, bool horizontal)
        {
            return horizontal ? new Border { Height = 1, Background = brush } : new Border { Width = 1, Background = brush };
        }

        public static Ellipse Dot(double size, Brush fill)
        {
            return new Ellipse { Width = size, Height = size, Fill = fill, VerticalAlignment = VerticalAlignment.Center };
        }
    }

    /// <summary>Shared WPF styles (tooltips, scrollbars, plain text fields) built from loose XAML at runtime
    /// so the app compiles with the in-box .NET Framework compiler (no markup compiler needed).</summary>
    public static class Styles
    {
        public static void Install(Application app)
        {
            var t = Core.Theme.Current;
            string xaml = @"<ResourceDictionary xmlns='http://schemas.microsoft.com/winfx/2006/xaml/presentation' xmlns:x='http://schemas.microsoft.com/winfx/2006/xaml'>
  <Style TargetType='ToolTip'>
    <Setter Property='OverridesDefaultStyle' Value='True'/>
    <Setter Property='HasDropShadow' Value='True'/>
    <Setter Property='Template'><Setter.Value><ControlTemplate TargetType='ToolTip'>
      <Border Background='#F2303033' BorderBrush='#33FFFFFF' BorderThickness='1' CornerRadius='5' Padding='7,3,7,4' Margin='0,0,6,6'>
        <Border.Effect><DropShadowEffect BlurRadius='8' ShadowDepth='2' Opacity='0.4'/></Border.Effect>
        <ContentPresenter TextElement.Foreground='#E6FFFFFF' TextElement.FontSize='11.5' TextElement.FontFamily='Segoe UI'/>
      </Border></ControlTemplate></Setter.Value></Setter>
  </Style>
  <Style x:Key='MacScrollThumb' TargetType='Thumb'>
    <Setter Property='Template'><Setter.Value><ControlTemplate TargetType='Thumb'>
      <Border x:Name='b' CornerRadius='3.5' Background='#47FFFFFF' Margin='2'/>
      <ControlTemplate.Triggers><Trigger Property='IsMouseOver' Value='True'><Setter TargetName='b' Property='Background' Value='#80FFFFFF'/></Trigger></ControlTemplate.Triggers>
    </ControlTemplate></Setter.Value></Setter>
  </Style>
  <Style TargetType='ScrollBar'>
    <Setter Property='Background' Value='Transparent'/>
    <Style.Triggers>
      <Trigger Property='Orientation' Value='Vertical'>
        <Setter Property='Width' Value='11'/>
        <Setter Property='Template'><Setter.Value><ControlTemplate TargetType='ScrollBar'>
          <Track x:Name='PART_Track' IsDirectionReversed='True'>
            <Track.Thumb><Thumb Style='{StaticResource MacScrollThumb}'/></Track.Thumb>
          </Track></ControlTemplate></Setter.Value></Setter>
      </Trigger>
      <Trigger Property='Orientation' Value='Horizontal'>
        <Setter Property='Height' Value='11'/>
        <Setter Property='Template'><Setter.Value><ControlTemplate TargetType='ScrollBar'>
          <Track x:Name='PART_Track'>
            <Track.Thumb><Thumb Style='{StaticResource MacScrollThumb}'/></Track.Thumb>
          </Track></ControlTemplate></Setter.Value></Setter>
      </Trigger>
    </Style.Triggers>
  </Style>
  <Style x:Key='PlainTextBox' TargetType='TextBox'>
    <Setter Property='Background' Value='Transparent'/>
    <Setter Property='BorderThickness' Value='0'/>
    <Setter Property='Padding' Value='0'/>
    <Setter Property='CaretBrush' Value='#FFFFFFFF'/>
    <Setter Property='SelectionBrush' Value='#0A84FF'/>
    <Setter Property='SelectionOpacity' Value='0.45'/>
    <Setter Property='FocusVisualStyle' Value='{x:Null}'/>
    <Setter Property='Template'><Setter.Value><ControlTemplate TargetType='TextBox'>
      <ScrollViewer x:Name='PART_ContentHost' Focusable='False' HorizontalScrollBarVisibility='Hidden' VerticalScrollBarVisibility='Hidden'/>
    </ControlTemplate></Setter.Value></Setter>
  </Style>
</ResourceDictionary>";
            var dict = (ResourceDictionary)System.Windows.Markup.XamlReader.Parse(xaml);
            app.Resources.MergedDictionaries.Add(dict);
        }

        public static TextBox PlainField(string placeholderOwnerText, double size, Brush fg)
        {
            var tb = new TextBox
            {
                Style = (Style)Application.Current.FindResource("PlainTextBox"),
                FontFamily = UIFonts.UI, FontSize = size, Foreground = fg,
                VerticalContentAlignment = VerticalAlignment.Center, VerticalAlignment = VerticalAlignment.Center
            };
            WindowChrome.SetIsHitTestVisibleInChrome(tb, true);
            return tb;
        }

        /// <summary>TextField with SwiftUI-style placeholder.</summary>
        public static Grid Field(string placeholder, double size, Brush fg, Brush placeholderBrush, out TextBox box)
        {
            var g = new Grid();
            var ph = V.T(placeholder, size, FontWeights.Normal, placeholderBrush);
            ph.IsHitTestVisible = false;
            ph.Margin = new Thickness(2, 0, 0, 0);
            var tb = PlainField(placeholder, size, fg);
            tb.TextChanged += delegate { ph.Visibility = tb.Text.Length == 0 ? Visibility.Visible : Visibility.Collapsed; };
            g.Children.Add(ph);
            g.Children.Add(tb);
            box = tb;
            return g;
        }
    }
}
