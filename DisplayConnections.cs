using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using Microsoft.Win32;

// Query Windows paths for this selected monitor. Never use capabilities/EDID port
// support as a cable-presence signal, or GPU connectorInstance as an HDMI slot.
public static class DisplayConnections {
 [StructLayout(LayoutKind.Sequential)] struct Luid {public uint Low;public int High;}
 [StructLayout(LayoutKind.Sequential)] struct Header {public uint Type,Size;public Luid Adapter;public uint Id;}
 [StructLayout(LayoutKind.Sequential,CharSet=CharSet.Unicode)] struct SourceName {
  public Header Header;[MarshalAs(UnmanagedType.ByValTStr,SizeConst=32)]public string Name;
 }
 [StructLayout(LayoutKind.Sequential,CharSet=CharSet.Unicode)] struct TargetName {
  public Header Header;public uint Flags,Technology;public ushort Manufacturer,Product;public uint Connector;
  [MarshalAs(UnmanagedType.ByValTStr,SizeConst=64)]public string Name;
  [MarshalAs(UnmanagedType.ByValTStr,SizeConst=128)]public string Path;
 }
 [DllImport("user32.dll")] static extern int GetDisplayConfigBufferSizes(uint flags,out uint paths,out uint modes);
 [DllImport("user32.dll")] static extern int QueryDisplayConfig(uint flags,ref uint pathCount,IntPtr paths,ref uint modeCount,IntPtr modes,IntPtr topology);
 [DllImport("user32.dll",EntryPoint="DisplayConfigGetDeviceInfo")]static extern int GetSource(ref SourceName data);
 [DllImport("user32.dll",EntryPoint="DisplayConfigGetDeviceInfo")]static extern int GetTarget(ref TargetName data);
 class PathInfo {public string Source,Identity,Path;public uint Technology;public bool Available,Active;}
 static string Identity(TargetName target){
  try{
   string[] parts=target.Path.Split('#');if(parts.Length<3)return null;
   using(var key=Registry.LocalMachine.OpenSubKey("SYSTEM\\CurrentControlSet\\Enum\\DISPLAY\\"+parts[1]+"\\"+parts[2]+"\\Device Parameters")){
    byte[] edid=key==null?null:key.GetValue("EDID")as byte[];
    if(edid==null||edid.Length<128)return null;
    uint serial=BitConverter.ToUInt32(edid,12);string text="";
    for(int i=54;i<=108;i+=18)if(edid[i]==0&&edid[i+1]==0&&edid[i+3]==255)text=System.Text.Encoding.ASCII.GetString(edid,i+5,13).Trim('\0','\n','\r',' ');
    if(serial==0&&(text.Length==0||text.Trim('0').Length==0))return null;
    return target.Manufacturer+":"+target.Product+":"+serial+":"+text;
   }
  }catch{return null;}
 }
 public static int[] Detect(string selectedGdi,int currentInput,int configuredHostHdmi){
  var result=new HashSet<int>();if(String.IsNullOrEmpty(selectedGdi))return new int[0];
  var paths=new List<PathInfo>();
  for(int attempt=0;attempt<3;attempt++){
   uint n,m;if(GetDisplayConfigBufferSizes(1,out n,out m)!=0||n>4096||m>4096)return new int[0];
   IntPtr p=Marshal.AllocHGlobal(checked((int)n*72)),modes=Marshal.AllocHGlobal(checked((int)m*64));
   try{
    int error=QueryDisplayConfig(1,ref n,p,ref m,modes,IntPtr.Zero);if(error==122)continue;if(error!=0)return new int[0];
    for(int i=0;i<n;i++){
     IntPtr item=IntPtr.Add(p,i*72);
     SourceName source=new SourceName();source.Header.Type=1;source.Header.Size=(uint)Marshal.SizeOf(typeof(SourceName));source.Header.Adapter=(Luid)Marshal.PtrToStructure(item,typeof(Luid));source.Header.Id=(uint)Marshal.ReadInt32(item,8);
     TargetName target=new TargetName();target.Header.Type=2;target.Header.Size=(uint)Marshal.SizeOf(typeof(TargetName));target.Header.Adapter=(Luid)Marshal.PtrToStructure(IntPtr.Add(item,20),typeof(Luid));target.Header.Id=(uint)Marshal.ReadInt32(item,28);
     if(GetSource(ref source)!=0||GetTarget(ref target)!=0)continue;
     paths.Add(new PathInfo{Source=source.Name,Path=target.Path,Identity=Identity(target),Technology=target.Technology,Available=Marshal.ReadInt32(item,60)!=0,Active=(Marshal.ReadInt32(item,68)&1)!=0});
    }
    break;
   }finally{Marshal.FreeHGlobal(p);Marshal.FreeHGlobal(modes);}
  }
  PathInfo selected=paths.Find(delegate(PathInfo p){return p.Active&&p.Available&&String.Equals(p.Source,selectedGdi,StringComparison.OrdinalIgnoreCase);});
  if(selected==null)selected=paths.Find(delegate(PathInfo p){return p.Available&&String.Equals(p.Source,selectedGdi,StringComparison.OrdinalIgnoreCase);});
  if(selected==null)return new int[0];
  // Cloned outputs can share a GDI name. Without a strong common serial identity
  // there is no safe way to attribute a different physical screen to this handle.
  foreach(var p in paths)if(p.Active&&p.Available&&String.Equals(p.Source,selectedGdi,StringComparison.OrdinalIgnoreCase)&&p.Path!=selected.Path)
   if(String.IsNullOrEmpty(selected.Identity)||p.Identity!=selected.Identity)return new int[0];
  foreach(var p in paths){
   bool same=String.Equals(p.Path,selected.Path,StringComparison.OrdinalIgnoreCase)||(!String.IsNullOrEmpty(selected.Identity)&&p.Identity==selected.Identity);
   if(!p.Available||!same)continue;
   if(p.Technology==10)result.Add(15); // Original project's only external DP input.
   if(p.Technology==5){
    if(configuredHostHdmi==17||configuredHostHdmi==18)result.Add(configuredHostHdmi);
    else if(p.Active&&(currentInput==17||currentInput==18))result.Add(currentInput);
   }
  }
  int[] values=new int[result.Count];result.CopyTo(values);return values;
 }
}
