// Win32 / COM interop: modern folder picker (IFileOpenDialog), DWM window attributes.
using System;
using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Interop;

namespace MicroCode.Core
{
    public static class Native
    {
        // ---- DWM (Windows 11 rounded corners, dark frame) ----
        [DllImport("dwmapi.dll")] static extern int DwmSetWindowAttribute(IntPtr hwnd, int attr, ref int value, int size);

        public static void StyleWindow(Window w, bool dark)
        {
            var hwnd = new WindowInteropHelper(w).Handle;
            if (hwnd == IntPtr.Zero) return;
            int on = dark ? 1 : 0;
            try { DwmSetWindowAttribute(hwnd, 20, ref on, 4); } catch { }      // DWMWA_USE_IMMERSIVE_DARK_MODE
            int round = 2;
            try { DwmSetWindowAttribute(hwnd, 33, ref round, 4); } catch { }   // DWMWA_WINDOW_CORNER_PREFERENCE = DWMWCP_ROUND
            int border = dark ? 0x00343434 : 0x00C8C8C8;                       // COLORREF 0x00BBGGRR — macOS-like hairline
            try { DwmSetWindowAttribute(hwnd, 34, ref border, 4); } catch { }   // DWMWA_BORDER_COLOR
        }

        // ---- IFileOpenDialog folder picker ----
        [ComImport, Guid("DC1C5A9C-E88A-4dde-A5A1-60F82A20AEF7")] class FileOpenDialogRCW { }

        [ComImport, Guid("42f85136-db7e-439c-85f1-e4075d135fc8"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
        interface IFileOpenDialog
        {
            [PreserveSig] int Show(IntPtr parent);
            void SetFileTypes(uint cFileTypes, IntPtr rgFilterSpec);
            void SetFileTypeIndex(uint iFileType);
            void GetFileTypeIndex(out uint piFileType);
            void Advise(IntPtr pfde, out uint pdwCookie);
            void Unadvise(uint dwCookie);
            void SetOptions(uint fos);
            void GetOptions(out uint pfos);
            void SetDefaultFolder(IShellItem psi);
            void SetFolder(IShellItem psi);
            void GetFolder(out IShellItem ppsi);
            void GetCurrentSelection(out IShellItem ppsi);
            void SetFileName([MarshalAs(UnmanagedType.LPWStr)] string pszName);
            void GetFileName([MarshalAs(UnmanagedType.LPWStr)] out string pszName);
            void SetTitle([MarshalAs(UnmanagedType.LPWStr)] string pszTitle);
            void SetOkButtonLabel([MarshalAs(UnmanagedType.LPWStr)] string pszText);
            void SetFileNameLabel([MarshalAs(UnmanagedType.LPWStr)] string pszLabel);
            void GetResult(out IShellItem ppsi);
            void AddPlace(IShellItem psi, int fdap);
            void SetDefaultExtension([MarshalAs(UnmanagedType.LPWStr)] string pszDefaultExtension);
            void Close(int hr);
            void SetClientGuid(ref Guid guid);
            void ClearClientData();
            void SetFilter(IntPtr pFilter);
            void GetResults(out IntPtr ppenum);
            void GetSelectedItems(out IntPtr ppsai);
        }

        [ComImport, Guid("43826D1E-E718-42EE-BC55-A1E261C37BFE"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
        interface IShellItem
        {
            void BindToHandler(IntPtr pbc, ref Guid bhid, ref Guid riid, out IntPtr ppv);
            void GetParent(out IShellItem ppsi);
            void GetDisplayName(uint sigdnName, [MarshalAs(UnmanagedType.LPWStr)] out string ppszName);
            void GetAttributes(uint sfgaoMask, out uint psfgaoAttribs);
            void Compare(IShellItem psi, uint hint, out int piOrder);
        }

        [DllImport("shell32.dll", CharSet = CharSet.Unicode, PreserveSig = false)]
        static extern void SHCreateItemFromParsingName(string pszPath, IntPtr pbc, [MarshalAs(UnmanagedType.LPStruct)] Guid riid, out IShellItem ppv);

        public static string PickFolder(string title, string initial)
        {
            try
            {
                var dlg = (IFileOpenDialog)new FileOpenDialogRCW();
                dlg.SetOptions(0x20 | 0x40 | 0x800); // FOS_PICKFOLDERS | FOS_FORCEFILESYSTEM | FOS_PATHMUSTEXIST
                dlg.SetTitle(title);
                dlg.SetOkButtonLabel("Open");
                if (!string.IsNullOrEmpty(initial) && System.IO.Directory.Exists(initial))
                {
                    IShellItem folder;
                    SHCreateItemFromParsingName(initial, IntPtr.Zero, typeof(IShellItem).GUID, out folder);
                    if (folder != null) dlg.SetFolder(folder);
                }
                var owner = Application.Current != null && Application.Current.MainWindow != null ? new WindowInteropHelper(Application.Current.MainWindow).Handle : IntPtr.Zero;
                if (dlg.Show(owner) != 0) return null;
                IShellItem item;
                dlg.GetResult(out item);
                string path;
                item.GetDisplayName(0x80058000, out path); // SIGDN_FILESYSPATH
                return path;
            }
            catch (Exception)
            {
                return null;
            }
        }
    }
}
