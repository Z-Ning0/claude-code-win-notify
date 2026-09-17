// Claude Code toast activator: COM local server that receives toast clicks
// (body or foreground button) and forwards the launch args to activate.ps1,
// which force-activates the IDE window. Also stamps the Start Menu shortcut
// with AppUserModelID + ToastActivatorClsid (/stamp mode).
// Compile: csc /nologo /target:winexe /out:toast-activator.exe toast-activator.cs
using System;
using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;

namespace CcWinNotify
{
    [ComVisible(true), Guid("53E31837-6600-4A81-9395-75CFFE746F94"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    public interface INotificationActivationCallback
    {
        void Activate(
            [In, MarshalAs(UnmanagedType.LPWStr)] string appUserModelId,
            [In, MarshalAs(UnmanagedType.LPWStr)] string invokedArgs,
            [In] IntPtr data,
            [In] uint dataCount);
    }

    [ComVisible(true), Guid("00000001-0000-0000-C000-000000000046"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    public interface IClassFactory
    {
        [PreserveSig] int CreateInstance(IntPtr pUnkOuter, ref Guid riid, out IntPtr ppvObject);
        [PreserveSig] int LockServer(bool fLock);
    }

    public sealed class Activator : INotificationActivationCallback
    {
        public void Activate(string appUserModelId, string invokedArgs, IntPtr data, uint dataCount)
        {
            try
            {
                string dir = Path.GetDirectoryName(typeof(Activator).Assembly.Location);
                string script = Path.Combine(dir, "activate.ps1");
                Process.Start("powershell.exe",
                    "-NoProfile -ExecutionPolicy Bypass -File \"" + script + "\" \"" + invokedArgs + "\"");
            }
            catch { }
            Program.Quit();
        }
    }

    public sealed class Factory : IClassFactory
    {
        static readonly Guid IUnknown = new Guid("00000000-0000-0000-C000-000000000046");
        static readonly Guid Callback = new Guid("53E31837-6600-4A81-9395-75CFFE746F94");
        static readonly Guid Self = new Guid(Program.CLSID);
        const int E_NOAGG = unchecked((int)0x80040110);
        const int E_NOINTERFACE = unchecked((int)0x80004002);

        public int CreateInstance(IntPtr pUnkOuter, ref Guid riid, out IntPtr ppvObject)
        {
            ppvObject = IntPtr.Zero;
            if (pUnkOuter != IntPtr.Zero) return E_NOAGG;
            if (riid != IUnknown && riid != Callback && riid != Self) return E_NOINTERFACE;
            object act = new Activator();
            ppvObject = Marshal.GetComInterfaceForObject(act, typeof(INotificationActivationCallback));
            return 0;
        }

        public int LockServer(bool fLock) { return 0; }
    }

    public static class Program
    {
        public const string CLSID = "{7E3B5A19-9F1D-4E1B-89B0-48A8E2F8C0AA}";

        [DllImport("ole32.dll")]
        static extern int CoRegisterClassObject(ref Guid rclsid, [MarshalAs(UnmanagedType.IUnknown)] object pUnk, uint dwClsContext, uint flags, out uint lpdwRegister);
        [DllImport("user32.dll")]
        static extern int GetMessage(out MSG lpMsg, IntPtr hWnd, uint wMin, uint wMax);
        [DllImport("user32.dll")]
        static extern bool TranslateMessage(ref MSG msg);
        [DllImport("user32.dll")]
        static extern IntPtr DispatchMessage(ref MSG msg);
        [DllImport("user32.dll")]
        static extern void PostQuitMessage(int code);

        [StructLayout(LayoutKind.Sequential)]
        public struct MSG { IntPtr hwnd; uint message; IntPtr wParam; IntPtr lParam; uint time; int x; int y; }

        public static void Quit() { PostQuitMessage(0); }

        [STAThread]
        public static int Main(string[] argv)
        {
            if (argv.Length >= 3 && argv[0] == "/stamp") return Stamper.Stamp(argv[1], argv[2]);
            Guid clsid = new Guid(CLSID);
            uint reg;
            int hr = CoRegisterClassObject(ref clsid, new Factory(), 4, 1, out reg);
            if (hr != 0) return hr;
            MSG msg;
            while (GetMessage(out msg, IntPtr.Zero, 0, 0) > 0)
            {
                TranslateMessage(ref msg);
                DispatchMessage(ref msg);
            }
            return 0;
        }
    }

    public static class Stamper
    {
        [DllImport("shell32.dll", CharSet = CharSet.Unicode)]
        static extern int SHGetPropertyStoreFromParsingName(string path, IntPtr pbc, uint flags, ref Guid riid, out IPropertyStore pps);

        [ComImport, Guid("886D8EEB-8CF2-4446-8D02-CBA1DBD2E4D0"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
        interface IPropertyStore
        {
            int GetCount(out uint cProps);
            int GetAt(uint iProp, out PROPERTYKEY pkey);
            int GetValue(ref PROPERTYKEY key, out PROPVARIANT pv);
            int SetValue(ref PROPERTYKEY key, ref PROPVARIANT pv);
            int Commit();
        }

        [StructLayout(LayoutKind.Sequential, Pack = 4)]
        public struct PROPERTYKEY { public Guid fmtid; public uint pid; }

        [StructLayout(LayoutKind.Explicit)]
        public struct PROPVARIANT
        {
            [FieldOffset(0)] public ushort vt;
            [FieldOffset(8)] public IntPtr pwszVal;
            [FieldOffset(8)] public Guid guid;
            public static PROPVARIANT FromString(string s)
            {
                PROPVARIANT v = new PROPVARIANT();
                v.vt = 31;
                v.pwszVal = Marshal.StringToCoTaskMemUni(s);
                return v;
            }
            public static PROPVARIANT FromClsid(Guid g)
            {
                PROPVARIANT v = new PROPVARIANT();
                v.vt = 72;
                v.guid = g;
                return v;
            }
        }

        public static int Stamp(string lnk, string clsidStr)
        {
            Guid iidStore = new Guid("886D8EEB-8CF2-4446-8D02-CBA1DBD2E4D0");
            IPropertyStore ps;
            int hr = SHGetPropertyStoreFromParsingName(lnk, IntPtr.Zero, 2, ref iidStore, out ps);
            if (hr != 0) return hr;
            Guid fmt = new Guid("9F4C2855-9F79-4B39-A8D0-E1D42DE1D5F3");
            PROPERTYKEY kAumid = new PROPERTYKEY { fmtid = fmt, pid = 5 };
            PROPVARIANT vAumid = PROPVARIANT.FromString("Claude Code");
            hr = ps.SetValue(ref kAumid, ref vAumid);
            if (hr != 0) return hr;
            PROPERTYKEY kClsid = new PROPERTYKEY { fmtid = fmt, pid = 26 };
            PROPVARIANT vClsid = PROPVARIANT.FromClsid(new Guid(clsidStr));
            hr = ps.SetValue(ref kClsid, ref vClsid);
            if (hr != 0) return hr;
            return ps.Commit();
        }
    }
}
