// WebAppViewport + DeviceFrameSpec (EmbeddedWebAppPreviewView.swift): the viewport presets of the WebApp preview and the
// device hardware frames around them. The macOS app paints Apple's bezel PNGs; Apple's device artwork is not licensed for
// a Windows app, so the frames here are drawn as vectors with the same proportions (screen size, bezel, corner radius,
// camera island). Screen sizes are the devices' real CSS viewports, so media queries hit the same breakpoints as on the device.
using System;
using System.Collections.Generic;
using System.Windows;
using System.Windows.Input;
using System.Windows.Media;
using MicroCode.Core;

namespace MicroCode.Views
{
    public class WebViewport
    {
        public string Id, Name, Icon, Subtitle, UserAgent;
        public double ScreenW, ScreenH;            // portrait CSS px
        public double Bezel, ScreenRadius;         // frame geometry in the same units
        public double IslandW, IslandH, IslandTop; // camera island (0 = none)
        public bool Laptop, Mobile, CanRotate;

        public bool IsResponsive { get { return Id == "responsive"; } }

        const string IPhoneUA = "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1";
        const string IPadUA = "Mozilla/5.0 (iPad; CPU OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1";

        public static readonly WebViewport Responsive = new WebViewport { Id = "responsive", Name = "Responsive", Icon = "arrow.left.and.right", Subtitle = "Fluid Responsive • Drag the edge to resize freely" };

        public static readonly List<WebViewport> All = new List<WebViewport>
        {
            Responsive,
            new WebViewport { Id = "iphone", Name = "iPhone", Icon = "iphone", Subtitle = "iPhone 16 Pro • 402×874 pt", ScreenW = 402, ScreenH = 874, Bezel = 14, ScreenRadius = 55, IslandW = 124, IslandH = 36, IslandTop = 11, Mobile = true, CanRotate = true, UserAgent = IPhoneUA },
            new WebViewport { Id = "iphoneDuoOuter", Name = "iPhone Duo (Outer)", Icon = "iphone", Subtitle = "iPhone Duo — จอนอก (Cover 466×678 pt)", ScreenW = 466, ScreenH = 678, Bezel = 16, ScreenRadius = 46, IslandW = 110, IslandH = 32, IslandTop = 12, Mobile = true, CanRotate = true, UserAgent = IPhoneUA },
            new WebViewport { Id = "iphoneDuoInner", Name = "iPhone Duo (Inner)", Icon = "book.pages", Subtitle = "iPhone Duo — จอใน (Unfolded 951×669 pt)", ScreenW = 951, ScreenH = 669, Bezel = 17, ScreenRadius = 40, Mobile = true, CanRotate = true, UserAgent = IPhoneUA },
            new WebViewport { Id = "ipad", Name = "iPad", Icon = "ipad", Subtitle = "iPad Pro 11-inch • 834×1210 pt", ScreenW = 834, ScreenH = 1210, Bezel = 24, ScreenRadius = 18, Mobile = true, CanRotate = true, UserAgent = IPadUA },
            new WebViewport { Id = "macbook", Name = "MacBook", Icon = "laptopcomputer", Subtitle = "MacBook Pro 14-inch • 1512×982 pt", ScreenW = 1512, ScreenH = 982, Bezel = 18, ScreenRadius = 10, Laptop = true }
        };

        public static WebViewport Find(string id)
        {
            foreach (var v in All) if (v.Id == id) return v;
            return Responsive;
        }

        public static readonly int[] Breakpoints = { 0, 320, 375, 430, 768, 1024, 1280, 1440 };
        public static string BreakpointName(int w)
        {
            switch (w)
            {
                case 0: return "Fluid (100% Full Width)";
                case 320: return "Mobile S (320 px)";
                case 375: return "Mobile M (375 px)";
                case 430: return "Mobile L (430 px)";
                case 768: return "Tablet (768 px)";
                case 1024: return "Laptop (1024 px)";
                case 1280: return "Desktop (1280 px)";
                default: return "Wide (" + w + " px)";
            }
        }
    }

    /// <summary>
    /// Lays out one child (the browser) inside a device frame scaled to fit, and draws the bezel around it. In responsive
    /// mode the browser fills the canvas or a fixed CSS width centred, with a drag handle on its right edge.
    /// </summary>
    public class DeviceFrameView : FrameworkElement
    {
        readonly UIElement _child;
        public WebViewport Viewport = WebViewport.Responsive;
        public bool Landscape, ShowBezel = true, ActualSize;
        public double ResponsiveWidth;          // 0 = fluid
        public event Action<double> ResponsiveWidthChanged;
        public double Scale { get; private set; }
        Rect _screen, _frame;
        bool _dragging; double _dragStartX, _dragStartW;

        public DeviceFrameView(UIElement child)
        {
            _child = child;
            AddVisualChild(child);
            AddLogicalChild(child);
            Scale = 1;
            Cursor = null;
        }

        protected override int VisualChildrenCount { get { return 1; } }
        protected override Visual GetVisualChild(int index) { return _child; }

        public double ScreenCssW { get { return Viewport.IsResponsive ? 0 : (Landscape ? Viewport.ScreenH : Viewport.ScreenW); } }
        public double ScreenCssH { get { return Viewport.IsResponsive ? 0 : (Landscape ? Viewport.ScreenW : Viewport.ScreenH); } }

        protected override Size MeasureOverride(Size available)
        {
            _child.Measure(available);
            return new Size(double.IsInfinity(available.Width) ? 400 : available.Width, double.IsInfinity(available.Height) ? 600 : available.Height);
        }

        protected override Size ArrangeOverride(Size size)
        {
            const double pad = 18, labelSpace = 4;
            if (Viewport.IsResponsive)
            {
                double w = ResponsiveWidth > 0 ? Math.Min(ResponsiveWidth, size.Width - 2 * pad) : size.Width;
                double x = ResponsiveWidth > 0 ? (size.Width - w) / 2 : 0;
                double top = ResponsiveWidth > 0 ? 10 : 0, h = size.Height - (ResponsiveWidth > 0 ? 20 : 0);
                _screen = new Rect(x, top, Math.Max(1, w), Math.Max(1, h));
                _frame = _screen;
                Scale = 1;
            }
            else
            {
                double sw = ScreenCssW, sh = ScreenCssH;
                double bezel = ShowBezel ? Viewport.Bezel : 0;
                double fw = sw + 2 * bezel, fh = sh + 2 * bezel;
                double baseH = 0;
                if (Viewport.Laptop && ShowBezel) { fh = sh + bezel * 2.4; baseH = sw * 0.035; }
                double totalW = Viewport.Laptop && ShowBezel ? fw * 1.12 : fw, totalH = fh + baseH;
                double s = Math.Min((size.Width - 2 * pad) / totalW, (size.Height - 2 * pad - labelSpace) / totalH);
                if (ActualSize) s = Math.Min(1, s);
                s = Math.Max(0.05, s);
                Scale = s;
                double ox = (size.Width - fw * s) / 2, oy = (size.Height - totalH * s) / 2;
                _frame = new Rect(ox, oy, fw * s, fh * s);
                double topBezel = Viewport.Laptop && ShowBezel ? bezel * 1.4 : bezel;
                _screen = new Rect(ox + bezel * s, oy + topBezel * s, sw * s, sh * s);
            }
            _child.Arrange(_screen);
            return size;
        }

        /// <summary>Screen corner radius and island rectangle in the child's own coordinates (DIPs).</summary>
        public void ScreenShape(out double radius, out Rect island, out double islandRadius)
        {
            radius = 0; island = Rect.Empty; islandRadius = 0;
            if (Viewport.IsResponsive) return;
            radius = Viewport.ScreenRadius * Scale;
            if (Viewport.Laptop) radius = Math.Min(radius, 6);
            if (Viewport.IslandW > 0 && ShowBezel)
            {
                double iw = Viewport.IslandW * Scale, ih = Viewport.IslandH * Scale, top = Viewport.IslandTop * Scale;
                island = Landscape ? new Rect(top, (_screen.Height - iw) / 2, ih, iw) : new Rect((_screen.Width - iw) / 2, top, iw, ih);
                islandRadius = Math.Min(iw, ih) / 2;
            }
        }

        protected override void OnRender(DrawingContext dc)
        {
            var t = Theme.Current;
            dc.DrawRectangle(Brushes.Transparent, null, new Rect(RenderSize));
            if (Viewport.IsResponsive)
            {
                if (ResponsiveWidth > 0)
                {
                    // page edge + right-hand resize grip
                    dc.DrawRectangle(null, new Pen(t.P(0.18), 1), Inflate(_screen, 0.5));
                    var grip = new Rect(_screen.Right + 3, _screen.Top + _screen.Height / 2 - 18, 6, 36);
                    dc.DrawRoundedRectangle(t.P(_dragging ? 0.45 : 0.25), null, grip, 3, 3);
                }
                return;
            }
            if (!ShowBezel)
            {
                dc.DrawRoundedRectangle(Brushes.Black, null, Inflate(_screen, 1), Viewport.ScreenRadius * Scale, Viewport.ScreenRadius * Scale);
                return;
            }
            double s = Scale;
            var body = new SolidColorBrush(Color.FromRgb(28, 28, 30));
            var rim = new Pen(new SolidColorBrush(Color.FromRgb(88, 88, 92)), Math.Max(1, 1.6 * s));
            var edge = new Pen(new SolidColorBrush(Color.FromRgb(10, 10, 11)), Math.Max(1, 3 * s));
            if (Viewport.Laptop)
            {
                double lidR = 18 * s;
                dc.DrawRoundedRectangle(body, rim, _frame, lidR, lidR);
                dc.DrawRoundedRectangle(Brushes.Black, null, Inflate(_screen, 1), 6 * s, 6 * s);
                // camera notch
                double nw = 180 * s, nh = 16 * s;
                dc.DrawRoundedRectangle(body, null, new Rect(_frame.Left + (_frame.Width - nw) / 2, _screen.Top - 1, nw, nh), 6 * s, 6 * s);
                // keyboard deck
                double deckW = _frame.Width * 1.12, deckH = ScreenCssW * 0.035 * s;
                var deck = new Rect(_frame.Left - (deckW - _frame.Width) / 2, _frame.Bottom - 1, deckW, deckH);
                var deckBrush = new LinearGradientBrush(Color.FromRgb(120, 122, 128), Color.FromRgb(58, 58, 62), 90);
                dc.DrawRoundedRectangle(deckBrush, null, deck, deckH * 0.35, deckH * 0.35);
                double gw = deckW * 0.16, gh = deckH * 0.38;
                dc.DrawRoundedRectangle(new SolidColorBrush(Color.FromRgb(40, 40, 44)), null, new Rect(deck.Left + (deck.Width - gw) / 2, deck.Top, gw, gh), gh / 2, gh / 2);
                return;
            }
            double outerR = (Viewport.ScreenRadius + Viewport.Bezel) * s;
            // side buttons (power on the right, volume on the left; rotate with the device)
            var btn = new SolidColorBrush(Color.FromRgb(58, 58, 62));
            if (Viewport.Id.StartsWith("iphone"))
            {
                double bw = 3.5 * s;
                if (!Landscape)
                {
                    dc.DrawRoundedRectangle(btn, null, new Rect(_frame.Right - 1, _frame.Top + _frame.Height * 0.24, bw, _frame.Height * 0.11), bw / 2, bw / 2);
                    dc.DrawRoundedRectangle(btn, null, new Rect(_frame.Left - bw + 1, _frame.Top + _frame.Height * 0.18, bw, _frame.Height * 0.04), bw / 2, bw / 2);
                    dc.DrawRoundedRectangle(btn, null, new Rect(_frame.Left - bw + 1, _frame.Top + _frame.Height * 0.25, bw, _frame.Height * 0.07), bw / 2, bw / 2);
                    dc.DrawRoundedRectangle(btn, null, new Rect(_frame.Left - bw + 1, _frame.Top + _frame.Height * 0.34, bw, _frame.Height * 0.07), bw / 2, bw / 2);
                }
                else
                {
                    dc.DrawRoundedRectangle(btn, null, new Rect(_frame.Left + _frame.Width * 0.24, _frame.Top - bw + 1, _frame.Width * 0.11, bw), bw / 2, bw / 2);
                    dc.DrawRoundedRectangle(btn, null, new Rect(_frame.Left + _frame.Width * 0.59, _frame.Bottom - 1, _frame.Width * 0.07, bw), bw / 2, bw / 2);
                }
            }
            dc.DrawRoundedRectangle(body, rim, _frame, outerR, outerR);
            dc.DrawRoundedRectangle(null, edge, Inflate(_screen, 2 * s), (Viewport.ScreenRadius + 2) * s, (Viewport.ScreenRadius + 2) * s);
            dc.DrawRoundedRectangle(Brushes.Black, null, Inflate(_screen, 1), Viewport.ScreenRadius * s, Viewport.ScreenRadius * s);
            double r; Rect island; double ir;
            ScreenShape(out r, out island, out ir);
            if (!island.IsEmpty)
            {
                island.Offset(_screen.Left, _screen.Top);
                dc.DrawRoundedRectangle(Brushes.Black, null, island, ir, ir);
                // camera lens glint
                double lens = island.Height * 0.32;
                var c = Landscape ? new Point(island.Left + island.Width / 2, island.Bottom - island.Width * 0.9) : new Point(island.Right - island.Height * 0.9, island.Top + island.Height / 2);
                dc.DrawEllipse(new SolidColorBrush(Color.FromRgb(24, 30, 48)), null, c, lens, lens);
            }
            else if (Viewport.Id == "ipad")
            {
                double cam = 4 * s;
                var c = Landscape ? new Point(_frame.Left + Viewport.Bezel * s / 2, _frame.Top + _frame.Height / 2) : new Point(_frame.Left + _frame.Width / 2, _frame.Top + Viewport.Bezel * s / 2);
                dc.DrawEllipse(new SolidColorBrush(Color.FromRgb(20, 22, 30)), null, c, cam, cam);
            }
        }

        static Rect Inflate(Rect r, double d) { r.Inflate(d, d); return r; }

        // ── responsive width handle ──
        bool OnGrip(Point p)
        {
            return Viewport.IsResponsive && ResponsiveWidth > 0 && p.X >= _screen.Right && p.X <= _screen.Right + 12 && p.Y >= _screen.Top && p.Y <= _screen.Bottom;
        }

        protected override void OnMouseMove(MouseEventArgs e)
        {
            base.OnMouseMove(e);
            var p = e.GetPosition(this);
            if (_dragging)
            {
                double w = Math.Max(240, Math.Min(ActualWidth - 36, _dragStartW + 2 * (p.X - _dragStartX)));
                ResponsiveWidth = Math.Round(w);
                InvalidateArrange(); InvalidateVisual();
                if (ResponsiveWidthChanged != null) ResponsiveWidthChanged(ResponsiveWidth);
                return;
            }
            Cursor = OnGrip(p) ? Cursors.SizeWE : null;
        }

        protected override void OnMouseLeftButtonDown(MouseButtonEventArgs e)
        {
            base.OnMouseLeftButtonDown(e);
            var p = e.GetPosition(this);
            if (!OnGrip(p)) return;
            _dragging = true; _dragStartX = p.X; _dragStartW = _screen.Width;
            CaptureMouse(); e.Handled = true; InvalidateVisual();
        }

        protected override void OnMouseLeftButtonUp(MouseButtonEventArgs e)
        {
            base.OnMouseLeftButtonUp(e);
            if (!_dragging) return;
            _dragging = false; ReleaseMouseCapture(); InvalidateVisual();
        }
    }
}
