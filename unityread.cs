// Minimal reader for the Unity data files of an installed game (Unity 6, SerializedFile v22):
// UnityFS bundles (LZ4), serialized files with type trees, and a YAML writer that mirrors
// the layout of an AssetRipper export so build.ps1 can read either source the same way.
// It only reads files; nothing in the game folder is changed.
using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Text;

public static class UnityRead {
    // ---------------------------------------------------------------- UnityFS bundles
    public static byte[] Lz4(byte[] src, int srcOff, int srcLen, int dstLen) {
        var dst = new byte[dstLen]; int si = srcOff, di = 0, end = srcOff + srcLen;
        while (si < end) {
            int tok = src[si++]; int lit = tok >> 4;
            if (lit == 15) { int b; do { b = src[si++]; lit += b; } while (b == 255); }
            Buffer.BlockCopy(src, si, dst, di, lit); si += lit; di += lit;
            if (si >= end || di >= dstLen) break;
            int off = src[si] | (src[si + 1] << 8); si += 2;
            int ml = tok & 15; if (ml == 15) { int b; do { b = src[si++]; ml += b; } while (b == 255); } ml += 4;
            int from = di - off;
            if (off >= ml) { Buffer.BlockCopy(dst, from, dst, di, ml); di += ml; }
            else for (int k = 0; k < ml; k++) dst[di++] = dst[from + k];
        }
        return dst;
    }
    static string CStr(BinaryReader r) { var sb = new StringBuilder(); byte c; while ((c = r.ReadByte()) != 0) sb.Append((char)c); return sb.ToString(); }
    static long BE64(BinaryReader r) { var b = r.ReadBytes(8); Array.Reverse(b); return BitConverter.ToInt64(b, 0); }
    static uint BE32(BinaryReader r) { var b = r.ReadBytes(4); Array.Reverse(b); return BitConverter.ToUInt32(b, 0); }

    // name -> bytes of every file inside a bundle (serialized files and .resS streams)
    public static Dictionary<string, byte[]> OpenBundle(string path) {
        var all = File.ReadAllBytes(path); var r = new BinaryReader(new MemoryStream(all));
        if (CStr(r) != "UnityFS") throw new InvalidDataException("not a UnityFS bundle: " + path);
        BE32(r); CStr(r); CStr(r); BE64(r);
        uint cbi = BE32(r), ubi = BE32(r), flags = BE32(r);
        if ((flags & 0x200) != 0) Align(r, 16);
        byte[] infoC = r.ReadBytes((int)cbi);
        byte[] info = (flags & 0x3F) == 0 ? infoC : Lz4(infoC, 0, infoC.Length, (int)ubi);
        if ((flags & 0x200) != 0) Align(r, 16);
        long p = r.BaseStream.Position;
        var ir = new BinaryReader(new MemoryStream(info)); ir.ReadBytes(16);
        int nb = (int)BE32(ir); long total = 0; var blocks = new List<uint[]>();
        for (int i = 0; i < nb; i++) { uint u = BE32(ir), c = BE32(ir); uint f = (uint)(ir.ReadByte() << 8 | ir.ReadByte()); blocks.Add(new[] { u, c, f }); total += u; }
        var data = new byte[total]; long di = 0;
        foreach (var bk in blocks) {
            if ((bk[2] & 0x3F) == 0) Buffer.BlockCopy(all, (int)p, data, (int)di, (int)bk[1]);
            else { var d = Lz4(all, (int)p, (int)bk[1], (int)bk[0]); Buffer.BlockCopy(d, 0, data, (int)di, d.Length); }
            p += bk[1]; di += bk[0];
        }
        var res = new Dictionary<string, byte[]>();
        int nn = (int)BE32(ir);
        for (int i = 0; i < nn; i++) {
            long off = BE64(ir), sz = BE64(ir); BE32(ir); string name = CStr(ir);
            var f = new byte[sz]; Buffer.BlockCopy(data, (int)off, f, 0, (int)sz); res[name] = f;
        }
        return res;
    }
    static void Align(BinaryReader r, int n) { while (r.BaseStream.Position % n != 0) r.ReadByte(); }

    // ---------------------------------------------------------------- serialized files
    public class Node { public string Type, Name; public int Level, Size, Flags, Meta; public List<Node> Kids = new List<Node>(); }
    public class TypeInfo { public int ClassId; public Node Root; }
    public class ObjInfo { public long PathId, Start; public uint Size; public int TypeIndex; public int ClassId; }

    public class SFile {
        public byte[] Data; public long DataOffset; public bool TypeTrees;
        public List<TypeInfo> Types = new List<TypeInfo>();
        public List<ObjInfo> Objects = new List<ObjInfo>();
        public Dictionary<long, ObjInfo> ById = new Dictionary<long, ObjInfo>();
    }

    public static SFile ParseSerialized(byte[] f) {
        var r = new BinaryReader(new MemoryStream(f));
        r.ReadBytes(8); uint ver = BE32(r); r.ReadBytes(4);
        if (ver < 22) throw new InvalidDataException("unsupported serialized file version " + ver);
        r.ReadBytes(4); BE32(r); BE64(r); long dataOffset = BE64(r); BE64(r);
        var s = new SFile { Data = f, DataOffset = dataOffset };
        CStr(r); r.ReadInt32(); s.TypeTrees = r.ReadBoolean();
        int nt = r.ReadInt32();
        for (int i = 0; i < nt; i++) {
            var t = new TypeInfo { ClassId = r.ReadInt32() };
            r.ReadBoolean(); short scriptIdx = r.ReadInt16();
            if (t.ClassId == 114) r.ReadBytes(16);
            r.ReadBytes(16);
            if (s.TypeTrees) {
                int nodes = r.ReadInt32(), strSize = r.ReadInt32();
                var raw = new List<int[]>();
                for (int k = 0; k < nodes; k++) {
                    r.ReadUInt16(); int level = r.ReadByte(), tflags = r.ReadByte();
                    uint typeOff = r.ReadUInt32(), nameOff = r.ReadUInt32();
                    int size = r.ReadInt32(); r.ReadInt32(); int meta = r.ReadInt32(); r.ReadUInt64();
                    raw.Add(new[] { level, tflags, (int)typeOff, (int)nameOff, size, meta });
                }
                var strs = r.ReadBytes(strSize);
                Node root = null; var stack = new List<Node>();
                foreach (var a in raw) {
                    var n = new Node { Level = a[0], Flags = a[1], Type = Str(strs, (uint)a[2]), Name = Str(strs, (uint)a[3]), Size = a[4], Meta = a[5] };
                    if (n.Level == 0) { root = n; stack.Clear(); stack.Add(n); continue; }
                    while (stack.Count > n.Level) stack.RemoveAt(stack.Count - 1);
                    stack[stack.Count - 1].Kids.Add(n); stack.Add(n);
                }
                t.Root = root;
                int deps = r.ReadInt32(); for (int k = 0; k < deps; k++) r.ReadInt32();
            }
            s.Types.Add(t);
        }
        int no = r.ReadInt32();
        for (int i = 0; i < no; i++) {
            Align(r, 4);
            var o = new ObjInfo { PathId = r.ReadInt64(), Start = r.ReadInt64(), Size = r.ReadUInt32(), TypeIndex = r.ReadInt32() };
            o.ClassId = s.Types[o.TypeIndex].ClassId;
            s.Objects.Add(o); s.ById[o.PathId] = o;
        }
        return s;
    }

    static string Str(byte[] local, uint off) {
        if ((off & 0x80000000) != 0) { string v; return Common.TryGetValue((int)(off & 0x7FFFFFFF), out v) ? v : "?" + (off & 0x7FFFFFFF); }
        int e = (int)off; while (e < local.Length && local[e] != 0) e++;
        return Encoding.UTF8.GetString(local, (int)off, e - (int)off);
    }

    // Unity's built-in type-tree string table; offsets are the running byte positions
    static readonly Dictionary<int, string> Common = BuildCommon();
    static Dictionary<int, string> BuildCommon() {
        string[] names = {
            "AABB","AnimationClip","AnimationCurve","AnimationState","Array","Base","BitField","bitset","bool","char",
            "ColorRGBA","Component","data","deque","double","dynamic_array","FastPropertyName","first","float","Font",
            "GameObject","Generic Mono","GradientNEW","GUID","GUIStyle","int","list","long long","map","Matrix4x4f",
            "MdFour","MonoBehaviour","MonoScript","m_ByteSize","m_Curve","m_EditorClassIdentifier","m_EditorHideFlags","m_Enabled","m_ExtensionPtr","m_GameObject",
            "m_Index","m_IsArray","m_IsStatic","m_MetaFlag","m_Name","m_ObjectHideFlags","m_PrefabInternal","m_PrefabParentObject","m_Script","m_StaticEditorFlags",
            "m_Type","m_Version","Object","pair","PPtr<Component>","PPtr<GameObject>","PPtr<Material>","PPtr<MonoBehaviour>","PPtr<MonoScript>","PPtr<Object>",
            "PPtr<Prefab>","PPtr<Sprite>","PPtr<TextAsset>","PPtr<Texture>","PPtr<Texture2D>","PPtr<Transform>","Prefab","Quaternionf","Rectf","RectInt",
            "RectOffset","second","set","short","size","SInt16","SInt32","SInt64","SInt8","staticvector",
            "string","TextAsset","TextMesh","Texture","Texture2D","Transform","TypelessData","UInt16","UInt32","UInt64",
            "UInt8","unsigned int","unsigned long long","unsigned short","vector","Vector2f","Vector3f","Vector4f","m_ScriptingClassIdentifier","Gradient",
            "Type*","int2_storage","int3_storage","BoundsInt","m_CorrespondingSourceObject","m_PrefabInstance","m_PrefabAsset","FileSize","Hash128","RenderingLayerMask"
        };
        var d = new Dictionary<int, string>(); int pos = 0;
        foreach (var n in names) { d[pos] = n; pos += Encoding.ASCII.GetByteCount(n) + 1; }
        return d;
    }

    // ---------------------------------------------------------------- values
    // object -> Dictionary<string,object> / List<object> / string / long / double / bool / byte[]
    public static object ReadObject(SFile s, ObjInfo o) {
        var t = s.Types[o.TypeIndex].Root;
        if (t == null) throw new InvalidDataException("no type tree for class " + o.ClassId);
        var r = new BinaryReader(new MemoryStream(s.Data, (int)(s.DataOffset + o.Start), (int)o.Size));
        return Read(r, t);
    }
    public static string ReadName(SFile s, ObjInfo o) {
        // m_Name is the first field of named objects (Texture2D, MonoBehaviour after its PPtrs)
        var t = s.Types[o.TypeIndex].Root; if (t == null) return null;
        var r = new BinaryReader(new MemoryStream(s.Data, (int)(s.DataOffset + o.Start), (int)o.Size));
        foreach (var k in t.Kids) { if (k.Name == "m_Name") return (string)Read(r, k); Read(r, k); }
        return null;
    }

    static bool IsArrayWrap(Node n) { return n.Kids.Count == 1 && n.Kids[0].Type == "Array"; }
    static object Read(BinaryReader r, Node n) {
        object v;
        if (n.Type == "string" && IsArrayWrap(n)) { int len = r.ReadInt32(); v = Encoding.UTF8.GetString(r.ReadBytes(len)); Align(r, 4); return v; }
        if (n.Type == "TypelessData") { int len = r.ReadInt32(); v = r.ReadBytes(len); Align(r, 4); return v; }
        if (IsArrayWrap(n) || n.Type == "Array") {
            var arr = n.Type == "Array" ? n : n.Kids[0];
            var elem = arr.Kids[1]; int count = r.ReadInt32();
            if (elem.Kids.Count == 0 && elem.Size == 1) { v = r.ReadBytes(count); }
            else { var list = new List<object>(count); for (int i = 0; i < count; i++) list.Add(Read(r, elem)); v = list; }
            if (((arr.Meta | n.Meta) & 0x4000) != 0) Align(r, 4);
            return v;
        }
        if (n.Kids.Count == 0) {
            switch (n.Type) {
                case "bool": v = r.ReadBoolean(); break;
                case "float": v = (double)r.ReadSingle(); break;
                case "double": v = r.ReadDouble(); break;
                case "SInt8": v = (long)r.ReadSByte(); break;
                case "UInt8": case "char": v = (long)r.ReadByte(); break;
                case "SInt16": case "short": v = (long)r.ReadInt16(); break;
                case "UInt16": case "unsigned short": v = (long)r.ReadUInt16(); break;
                case "SInt64": case "long long": case "FileSize": v = r.ReadInt64(); break;
                case "UInt64": case "unsigned long long": v = (long)r.ReadUInt64(); break;
                case "UInt32": case "unsigned int": v = (long)r.ReadUInt32(); break;
                default:
                    if (n.Size == 1) v = (long)r.ReadByte();
                    else if (n.Size == 2) v = (long)r.ReadInt16();
                    else if (n.Size == 8) v = r.ReadInt64();
                    else v = (long)r.ReadInt32();
                    break;
            }
            if ((n.Meta & 0x4000) != 0) Align(r, 4);
            return v;
        }
        var map = new Dictionary<string, object>();
        var order = new List<string>();
        foreach (var k in n.Kids) { map[k.Name] = Read(r, k); order.Add(k.Name); }
        map["\u0001order"] = order;
        if ((n.Meta & 0x4000) != 0) Align(r, 4);
        return map;
    }

    // ---------------------------------------------------------------- lookups
    // MonoBehaviours with the given m_Name, searched across every bundle in a folder
    public static Dictionary<string, object> FindMonoBehaviours(string bundleDir, string[] names) {
        var want = new HashSet<string>(names); var found = new Dictionary<string, object>();
        foreach (var path in Directory.GetFiles(bundleDir, "*.bundle")) {
            if (found.Count == want.Count) break;
            Dictionary<string, byte[]> files;
            try { files = OpenBundle(path); } catch { continue; }
            foreach (var kv in files) {
                if (kv.Key.EndsWith(".resS") || kv.Key.EndsWith(".resource")) continue;
                SFile s; try { s = ParseSerialized(kv.Value); } catch { continue; }
                if (!s.TypeTrees) continue;
                foreach (var o in s.Objects) {
                    if (o.ClassId != 114) continue;
                    var n = ReadName(s, o);
                    if (n != null && want.Contains(n) && !found.ContainsKey(n)) found[n] = ReadObject(s, o);
                }
            }
        }
        return found;
    }

    // StringsMapping lives in resources.assets, which has no type trees: read its known layout
    //   MonoBehaviour header (PPtr m_GameObject, m_Enabled, PPtr m_Script, m_Name), then
    //   Mappings: [{ Key, English, Japanese, Korean, TraditionalChinese, SimplifiedChinese, HasMappingBitMask }]
    public static string StringsMappingYaml(string resourcesAssets) {
        var s = ParseSerialized(File.ReadAllBytes(resourcesAssets));
        foreach (var o in s.Objects) {
            if (o.ClassId != 114) continue;
            var r = new BinaryReader(new MemoryStream(s.Data, (int)(s.DataOffset + o.Start), (int)o.Size));
            try {
                r.ReadInt32(); r.ReadInt64(); r.ReadByte(); Align(r, 4); r.ReadInt32(); r.ReadInt64();
                if (RStr(r) != "StringsMapping") continue;
                var sb = new StringBuilder("%YAML 1.1\n%TAG !u! tag:unity3d.com,2011:\n--- !u!114 &11400000\nMonoBehaviour:\n  m_Name: StringsMapping\n  Mappings:\n");
                int n = r.ReadInt32();
                for (int i = 0; i < n; i++) {
                    sb.Append("  - Key: ").Append(r.ReadInt32()).Append('\n');
                    foreach (var f in new[] { "English", "Japanese", "Korean", "TraditionalChinese", "SimplifiedChinese" }) {
                        string v = Scalar(RStr(r)); sb.Append("    ").Append(f).Append(v.Length > 0 ? ": " : ":").Append(v).Append('\n');
                    }
                    sb.Append("    HasMappingBitMask: ").Append(r.ReadInt32()).Append('\n');
                }
                return sb.ToString();
            } catch (EndOfStreamException) { }
        }
        throw new InvalidDataException("StringsMapping not found in " + resourcesAssets);
    }
    static string RStr(BinaryReader r) { int len = r.ReadInt32(); if (len < 0 || len > (1 << 24)) throw new EndOfStreamException(); var v = Encoding.UTF8.GetString(r.ReadBytes(len)); Align(r, 4); return v; }

    // ---------------------------------------------------------------- textures
    // Texture2D objects with the given m_Name -> PNG files (mip 0). Returns how many were written.
    public static int ExportTextures(string bundleDir, Dictionary<string, string> nameToPng) {
        int done = 0; var left = new HashSet<string>(nameToPng.Keys);
        foreach (var path in Directory.GetFiles(bundleDir, "*.bundle")) {
            if (left.Count == 0) break;
            Dictionary<string, byte[]> files;
            try { files = OpenBundle(path); } catch { continue; }
            foreach (var kv in files) {
                if (kv.Key.EndsWith(".resS") || kv.Key.EndsWith(".resource")) continue;
                SFile s; try { s = ParseSerialized(kv.Value); } catch { continue; }
                if (!s.TypeTrees) continue;
                foreach (var o in s.Objects) {
                    if (o.ClassId != 28) continue;
                    var n = ReadName(s, o);
                    if (n == null || !left.Contains(n)) continue;
                    var t = (Dictionary<string, object>)ReadObject(s, o);
                    var px = DecodeTexture(t, files);
                    if (px == null) continue;
                    SavePng(px, (int)(long)t["m_Width"], (int)(long)t["m_Height"], nameToPng[n]);
                    left.Remove(n); done++;
                }
            }
        }
        return done;
    }

    // mip 0 as BGRA rows, top row first; null for formats not handled here
    static byte[] DecodeTexture(Dictionary<string, object> t, Dictionary<string, byte[]> bundleFiles) {
        int w = (int)(long)t["m_Width"], h = (int)(long)t["m_Height"], fmt = (int)(long)t["m_TextureFormat"];
        byte[] raw = t["image data"] as byte[];
        if (raw == null || raw.Length == 0) {
            var sd = (Dictionary<string, object>)t["m_StreamData"];
            string p = (string)sd["path"]; long off = (long)sd["offset"], size = (long)sd["size"];
            byte[] res;
            if (string.IsNullOrEmpty(p) || !bundleFiles.TryGetValue(p.Substring(p.LastIndexOf('/') + 1), out res)) return null;
            raw = new byte[size]; Buffer.BlockCopy(res, (int)off, raw, 0, (int)size);
        }
        var outp = new byte[w * h * 4];
        if (fmt == 25) {   // BC7
            int bw = (w + 3) / 4, bh = (h + 3) / 4; var px = new byte[64];
            for (int by = 0; by < bh; by++) for (int bx = 0; bx < bw; bx++) {
                Bc7Block(raw, (by * bw + bx) * 16, px);
                for (int i = 0; i < 16; i++) {
                    int x = bx * 4 + (i & 3), y = by * 4 + (i >> 2); if (x >= w || y >= h) continue;
                    int d = ((h - 1 - y) * w + x) * 4;   // Unity stores the bottom row first
                    outp[d] = px[i * 4 + 2]; outp[d + 1] = px[i * 4 + 1]; outp[d + 2] = px[i * 4]; outp[d + 3] = px[i * 4 + 3];
                }
            }
            return outp;
        }
        if (fmt == 4 || fmt == 3 || fmt == 5) {   // RGBA32, RGB24, ARGB32
            int bpp = fmt == 3 ? 3 : 4;
            for (int y = 0; y < h; y++) for (int x = 0; x < w; x++) {
                int sI = (y * w + x) * bpp, d = ((h - 1 - y) * w + x) * 4;
                if (fmt == 5) { outp[d + 3] = raw[sI]; outp[d + 2] = raw[sI + 1]; outp[d + 1] = raw[sI + 2]; outp[d] = raw[sI + 3]; }
                else { outp[d + 2] = raw[sI]; outp[d + 1] = raw[sI + 1]; outp[d] = raw[sI + 2]; outp[d + 3] = bpp == 4 ? raw[sI + 3] : (byte)255; }
            }
            return outp;
        }
        return null;
    }

    static void SavePng(byte[] bgra, int w, int h, string path) {
        Directory.CreateDirectory(Path.GetDirectoryName(path));
        using (var bmp = new System.Drawing.Bitmap(w, h, System.Drawing.Imaging.PixelFormat.Format32bppArgb)) {
            var bd = bmp.LockBits(new System.Drawing.Rectangle(0, 0, w, h), System.Drawing.Imaging.ImageLockMode.WriteOnly, System.Drawing.Imaging.PixelFormat.Format32bppArgb);
            for (int y = 0; y < h; y++) System.Runtime.InteropServices.Marshal.Copy(bgra, y * w * 4, bd.Scan0 + y * bd.Stride, w * 4);
            bmp.UnlockBits(bd);
            bmp.Save(path, System.Drawing.Imaging.ImageFormat.Png);
        }
    }

    // ---- BC7 (BPTC) block decoder -> 16 RGBA pixels
    // per mode: subsets, partition bits, rotation bits, index-select bits, color bits, alpha bits,
    //           per-endpoint P bits, shared P bits, index bits, second index bits
    static readonly int[,] Bc7Modes = {
        { 3, 4, 0, 0, 4, 0, 1, 0, 3, 0 }, { 2, 6, 0, 0, 6, 0, 0, 1, 3, 0 }, { 3, 6, 0, 0, 5, 0, 0, 0, 2, 0 }, { 2, 6, 0, 0, 7, 0, 1, 0, 2, 0 },
        { 1, 0, 2, 1, 5, 6, 0, 0, 2, 3 }, { 1, 0, 2, 0, 7, 8, 0, 0, 2, 2 }, { 1, 0, 0, 0, 7, 7, 1, 0, 4, 0 }, { 2, 6, 0, 0, 5, 5, 1, 0, 2, 0 } };
    static readonly int[] W2 = { 0, 21, 43, 64 }, W3 = { 0, 9, 18, 27, 37, 46, 55, 64 }, W4 = { 0, 4, 9, 13, 17, 21, 26, 30, 34, 38, 43, 47, 51, 55, 60, 64 };
    static readonly ushort[] P2 = {
        0xCCCC, 0x8888, 0xEEEE, 0xECC8, 0xC880, 0xFEEC, 0xFEC8, 0xEC80, 0xC800, 0xFFEC, 0xFE80, 0xE800, 0xFFE8, 0xFF00, 0xFFF0, 0xF000,
        0xF710, 0x008E, 0x7100, 0x08CE, 0x008C, 0x7310, 0x3100, 0x8CCE, 0x088C, 0x3110, 0x6666, 0x366C, 0x17E8, 0x0FF0, 0x718E, 0x399C,
        0xAAAA, 0xF0F0, 0x5A5A, 0x33CC, 0x3C3C, 0x55AA, 0x9696, 0xA55A, 0x73CE, 0x13C8, 0x324C, 0x3BDC, 0x6996, 0xC33C, 0x9966, 0x0660,
        0x0272, 0x04E4, 0x4E40, 0x2720, 0xC936, 0x936C, 0x39C6, 0x639C, 0x9336, 0x9CC6, 0x817E, 0xE718, 0xCCF0, 0x0FCC, 0x7744, 0xEE22 };
    static readonly string[] P3 = {
        "0011001102212222", "0001001122112221", "0000200122112211", "0222002200110111", "0000000011221122", "0011001100220022", "0022002211111111", "0011001122112211",
        "0000000011112222", "0000111111112222", "0000111122222222", "0012001200120012", "0112011201120112", "0122012201220122", "0011011211221222", "0011200122002220",
        "0001001101121122", "0111001120012200", "0000112211221122", "0022002200221111", "0111011102220222", "0001000122212221", "0000001101220122", "0000110022102210",
        "0122012200110000", "0012001211222222", "0110122112210110", "0000011012211221", "0022110211020022", "0110011020022222", "0011012201220011", "0000200022112221",
        "0000000211221222", "0222002200120011", "0011001200220222", "0120012001200120", "0000111122220000", "0120120120120120", "0120201212010120", "0011220011220011",
        "0011112222000011", "0101010122222222", "0000000021212121", "0022112200221122", "0022001100220011", "0220122102201221", "0101222222220101", "0000212121212121",
        "0101010101012222", "0222011102220111", "0002111200021112", "0000211221122112", "0222011101110222", "0002111211120002", "0110011001102222", "0000000021122112",
        "0110011022222222", "0022001100110022", "0022112211220022", "0000000000002112", "0002000100020001", "0222122202221222", "0101222222222222", "0111201122012220" };
    static readonly byte[] A2 = {
        15,15,15,15,15,15,15,15,15,15,15,15,15,15,15,15, 15, 2, 8, 2, 2, 8, 8,15, 2, 8, 2, 2, 8, 8, 2, 2,
        15,15, 6, 8, 2, 8,15,15, 2, 8, 2, 2, 2,15,15, 6, 6, 2, 6, 8,15,15, 2, 2,15,15,15,15,15, 2, 2,15 };
    static readonly byte[] A3a = {
         3, 3,15,15, 8, 3,15,15, 8, 8, 6, 6, 6, 5, 3, 3, 3, 3, 8,15, 3, 3, 6,10, 5, 8, 8, 6, 8, 5,15,15,
         8,15, 3, 5, 6,10, 8,15,15, 3,15, 5,15,15,15,15, 3,15, 5, 5, 5, 8, 5,10, 5,10, 8,13,15,12, 3, 3 };
    static readonly byte[] A3b = {
        15, 8, 8, 3,15,15, 3, 8,15,15,15,15,15,15,15, 8,15, 8,15, 3,15, 8,15, 8, 3,15, 6,10,15,15,10, 8,
        15, 3,15,10,10, 8, 9,10, 6,15, 8,15, 3, 6, 6, 8,15, 3,15,15,15,15,15,15,15,15,15,15, 3,15,15, 8 };

    static int Subset(int ns, int part, int i) {
        if (ns == 2) return (P2[part] >> i) & 1;
        if (ns == 3) return P3[part][i] - '0';
        return 0;
    }
    static bool IsAnchor(int ns, int part, int i) {
        if (i == 0) return true;
        if (ns == 2) return i == A2[part];
        if (ns == 3) return i == A3a[part] || i == A3b[part];
        return false;
    }

    static void Bc7Block(byte[] src, int off, byte[] px) {
        ulong lo = BitConverter.ToUInt64(src, off), hi = BitConverter.ToUInt64(src, off + 8);
        int pos = 0;
        Func<int, int> bits = n => {
            int v = 0;
            for (int k = 0; k < n; k++, pos++) { ulong b = pos < 64 ? (lo >> pos) & 1 : (hi >> (pos - 64)) & 1; v |= (int)b << k; }
            return v;
        };
        int mode = 0; while (mode < 8 && bits(1) == 0) mode++;
        if (mode == 8) { Array.Clear(px, 0, 64); return; }
        int ns = Bc7Modes[mode, 0], pb = Bc7Modes[mode, 1], rb = Bc7Modes[mode, 2], isbb = Bc7Modes[mode, 3], cb = Bc7Modes[mode, 4],
            ab = Bc7Modes[mode, 5], epb = Bc7Modes[mode, 6], spb = Bc7Modes[mode, 7], ib = Bc7Modes[mode, 8], ib2 = Bc7Modes[mode, 9];
        int part = bits(pb), rot = bits(rb), isb = bits(isbb);
        int ne = ns * 2; var ep = new int[ne, 4];
        for (int c = 0; c < 3; c++) for (int e = 0; e < ne; e++) ep[e, c] = bits(cb);
        if (ab > 0) for (int e = 0; e < ne; e++) ep[e, 3] = bits(ab);
        int cp = cb, ap = ab;
        if (epb != 0) { for (int e = 0; e < ne; e++) { int p = bits(1); for (int c = 0; c < 4; c++) ep[e, c] = (ep[e, c] << 1) | p; } cp++; if (ab > 0) ap++; }
        if (spb != 0) { for (int s = 0; s < ns; s++) { int p = bits(1); for (int c = 0; c < 4; c++) { ep[s * 2, c] = (ep[s * 2, c] << 1) | p; ep[s * 2 + 1, c] = (ep[s * 2 + 1, c] << 1) | p; } } cp++; if (ab > 0) ap++; }
        for (int e = 0; e < ne; e++) {
            for (int c = 0; c < 3; c++) ep[e, c] = Unq(ep[e, c], cp);
            ep[e, 3] = ab > 0 ? Unq(ep[e, 3], ap) : 255;
        }
        var i1 = new int[16]; var i2 = new int[16];
        for (int i = 0; i < 16; i++) i1[i] = bits(IsAnchor(ns, part, i) ? ib - 1 : ib);
        if (ib2 > 0) for (int i = 0; i < 16; i++) i2[i] = bits(i == 0 ? ib2 - 1 : ib2);
        for (int i = 0; i < 16; i++) {
            int s = Subset(ns, part, i), e0 = s * 2, e1 = s * 2 + 1;
            int cw, aw;
            if (ib2 == 0) { cw = Weight(ib, i1[i]); aw = cw; }
            else if (isb == 0) { cw = Weight(ib, i1[i]); aw = Weight(ib2, i2[i]); }
            else { cw = Weight(ib2, i2[i]); aw = Weight(ib, i1[i]); }
            int r = Lerp(ep[e0, 0], ep[e1, 0], cw), g = Lerp(ep[e0, 1], ep[e1, 1], cw), b = Lerp(ep[e0, 2], ep[e1, 2], cw), a = Lerp(ep[e0, 3], ep[e1, 3], aw);
            if (rot == 1) { int t = a; a = r; r = t; } else if (rot == 2) { int t = a; a = g; g = t; } else if (rot == 3) { int t = a; a = b; b = t; }
            px[i * 4] = (byte)r; px[i * 4 + 1] = (byte)g; px[i * 4 + 2] = (byte)b; px[i * 4 + 3] = (byte)a;
        }
    }
    static int Unq(int v, int prec) { v <<= 8 - prec; return v | (v >> prec); }
    static int Weight(int bitsN, int idx) { return bitsN == 2 ? W2[idx] : bitsN == 3 ? W3[idx] : W4[idx]; }
    static int Lerp(int a, int b, int w) { return ((64 - w) * a + w * b + 32) >> 6; }

    // ---------------------------------------------------------------- YAML (AssetRipper layout)
    public static string ToYaml(object root) {
        var sb = new StringBuilder();
        sb.Append("%YAML 1.1\n%TAG !u! tag:unity3d.com,2011:\n--- !u!114 &11400000\nMonoBehaviour:\n");
        WriteMap(sb, (Dictionary<string, object>)root, 2, false);
        return sb.ToString();
    }
    static IEnumerable<string> Keys(Dictionary<string, object> m) { return (List<string>)m["\u0001order"]; }
    static void WriteMap(StringBuilder sb, Dictionary<string, object> m, int ind, bool firstInline) {
        bool first = true;
        foreach (var k in Keys(m)) {
            if (!(first && firstInline)) sb.Append(' ', ind);
            first = false;
            WriteField(sb, k, m[k], ind);
        }
    }
    static void WriteField(StringBuilder sb, string key, object v, int ind) {
        var map = v as Dictionary<string, object>;
        var list = v as List<object>;
        if (map != null) {
            if (IsPPtr(map)) { sb.Append(key).Append(": {fileID: ").Append(map["m_FileID"]).Append("}\n"); return; }
            sb.Append(key).Append(":\n"); WriteMap(sb, map, ind + 2, false); return;
        }
        if (list != null) {
            if (list.Count == 0) { sb.Append(key).Append(": []\n"); return; }
            sb.Append(key).Append(":\n");
            foreach (var item in list) {
                sb.Append(' ', ind).Append("- ");
                var im = item as Dictionary<string, object>;
                if (im != null && !IsPPtr(im)) WriteMap(sb, im, ind + 2, true);
                else sb.Append(Scalar(item)).Append('\n');
            }
            return;
        }
        if (v is byte[]) { sb.Append(key).Append(": ").Append(Hex((byte[])v)).Append('\n'); return; }
        string sc = Scalar(v);
        sb.Append(key).Append(sc.Length > 0 ? ": " : ":").Append(sc).Append('\n');
    }
    static bool IsPPtr(Dictionary<string, object> m) { return m.ContainsKey("m_FileID") && m.ContainsKey("m_PathID"); }
    static string Hex(byte[] b) { var sb = new StringBuilder(b.Length * 2); foreach (var x in b) sb.Append(x.ToString("x2")); return sb.ToString(); }
    static string Scalar(object v) {
        if (v == null) return "";
        if (v is bool) return (bool)v ? "1" : "0";
        if (v is double) return ((double)v).ToString("R", CultureInfo.InvariantCulture);
        if (v is long) return ((long)v).ToString(CultureInfo.InvariantCulture);
        var s = v as string;
        if (s != null) {
            if (s.Length == 0) return "";
            bool plain = true;
            foreach (char c in s) if (!(char.IsLetterOrDigit(c) || c == ' ' || c == '_' || c == '-' || c == '.' || c == '/' || c == '(' || c == ')')) { plain = false; break; }
            if (plain && s[0] != ' ' && s[s.Length - 1] != ' ' && s[0] != '-') return s;
            var q = new StringBuilder("\"");
            foreach (char c in s) {
                if (c == '\\') q.Append("\\\\"); else if (c == '"') q.Append("\\\""); else if (c == '\n') q.Append("\\n");
                else if (c == '\r') q.Append("\\r"); else if (c == '\t') q.Append("\\t"); else q.Append(c);
            }
            return q.Append('"').ToString();
        }
        var map = v as Dictionary<string, object>;
        if (map != null && IsPPtr(map)) return "{fileID: " + map["m_FileID"] + "}";
        return v.ToString();
    }
}
