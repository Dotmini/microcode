// Native PDF page rendering through the Windows Runtime (Windows.Data.Pdf) — no WebView, no third-party library.
// WinRT async operations are awaited through small TaskCompletionSource bridges so the build needs only the
// per-namespace metadata in System32\WinMetadata (no Windows SDK union metadata).
using System;
using System.Collections.Generic;
using System.IO;
using System.Threading.Tasks;
using Windows.Data.Pdf;
using Windows.Foundation;
using Windows.Storage;
using Windows.Storage.Streams;

namespace MicroCode.Views
{
    public static class PdfRender
    {
        // documents and rendered pages are keyed by path + last-write time, so an edited PDF is reloaded automatically
        static readonly Dictionary<string, PdfDocument> Docs = new Dictionary<string, PdfDocument>(StringComparer.OrdinalIgnoreCase);
        static readonly Dictionary<string, byte[]> Pages = new Dictionary<string, byte[]>(StringComparer.OrdinalIgnoreCase);
        static readonly LinkedList<string> PageOrder = new LinkedList<string>();
        const int MaxCachedPages = 48;

        static Task<R> Op<R>(IAsyncOperation<R> op)
        {
            var tcs = new TaskCompletionSource<R>();
            op.Completed = (info, status) =>
            {
                if (status == AsyncStatus.Completed) tcs.TrySetResult(info.GetResults());
                else if (status == AsyncStatus.Error) tcs.TrySetException(info.ErrorCode);
                else tcs.TrySetCanceled();
            };
            return tcs.Task;
        }

        static Task Act(IAsyncAction a)
        {
            var tcs = new TaskCompletionSource<bool>();
            a.Completed = (info, status) =>
            {
                if (status == AsyncStatus.Completed) tcs.TrySetResult(true);
                else if (status == AsyncStatus.Error) tcs.TrySetException(info.ErrorCode);
                else tcs.TrySetCanceled();
            };
            return tcs.Task;
        }

        static string Key(string path) { return path + "|" + File.GetLastWriteTimeUtc(path).Ticks; }

        static async Task<PdfDocument> Open(string path)
        {
            string key = Key(path);
            PdfDocument doc;
            lock (Docs) if (Docs.TryGetValue(key, out doc)) return doc;
            var file = await Op(StorageFile.GetFileFromPathAsync(path));
            doc = await Op(PdfDocument.LoadFromFileAsync(file));
            lock (Docs) { if (Docs.Count > 8) Docs.Clear(); Docs[key] = doc; }
            return doc;
        }

        public static void Forget(string path)
        {
            lock (Docs)
            {
                var stale = new List<string>();
                foreach (var k in Docs.Keys) if (k.StartsWith(path + "|", StringComparison.OrdinalIgnoreCase)) stale.Add(k);
                foreach (var k in stale) Docs.Remove(k);
            }
        }

        public static async Task<int> PageCount(string path) { return (int)(await Open(path)).PageCount; }

        /// <summary>Page sizes in DIPs (the first <paramref name="measure"/> pages are measured; later pages reuse the last size).</summary>
        public static async Task<List<System.Windows.Size>> PageSizes(string path, int measure)
        {
            var doc = await Open(path);
            var sizes = new List<System.Windows.Size>();
            var last = new System.Windows.Size(612, 792);
            for (uint i = 0; i < doc.PageCount; i++)
            {
                if (i < measure)
                    using (var p = doc.GetPage(i)) last = new System.Windows.Size(Math.Max(1, p.Size.Width), Math.Max(1, p.Size.Height));
                sizes.Add(last);
            }
            return sizes;
        }

        /// <summary>PNG bytes of one page rendered <paramref name="width"/> pixels wide (cached).</summary>
        public static async Task<byte[]> Page(string path, int index, uint width)
        {
            string key = Key(path) + "|" + index + "|" + width;
            byte[] cached;
            lock (Pages) if (Pages.TryGetValue(key, out cached)) return cached;
            var doc = await Open(path);
            byte[] bytes;
            using (var page = doc.GetPage((uint)index))
            {
                var ms = new InMemoryRandomAccessStream();
                var opt = new PdfPageRenderOptions();
                opt.DestinationWidth = width;
                await Act(page.RenderToStreamAsync(ms, opt));
                var reader = new DataReader(ms.GetInputStreamAt(0));
                uint n = await Op(reader.LoadAsync((uint)ms.Size));
                bytes = new byte[n];
                reader.ReadBytes(bytes);
            }
            lock (Pages)
            {
                if (!Pages.ContainsKey(key)) { Pages[key] = bytes; PageOrder.AddLast(key); }
                while (PageOrder.Count > MaxCachedPages) { Pages.Remove(PageOrder.First.Value); PageOrder.RemoveFirst(); }
            }
            return bytes;
        }
    }
}
