using System;
using System.Diagnostics;
using System.IO.MemoryMappedFiles;
using System.Runtime.InteropServices;
using System.Threading;

// The UI process owns the mutex; all launchers and script entry points share it.
public sealed class AppInstance : IDisposable {
 public const string MutexName="Local\\EVA02MonitorSwitch.UI.v1";
 const string EventName="Local\\EVA02MonitorSwitch.Activate.v1";
 const string MapName="Local\\EVA02MonitorSwitch.Owner.v1";
 const string ExitName="Local\\EVA02MonitorSwitch.Exit.v1";
 Mutex mutex;EventWaitHandle activation,exit;MemoryMappedFile map;
 public bool IsOwner {get;private set;}
 public int ActivationCount {get;private set;}
 public static readonly uint ShowMessage=RegisterWindowMessage("EVA02MonitorSwitch.Show.v1");
 [DllImport("user32.dll")] static extern uint RegisterWindowMessage(string value);
 [DllImport("user32.dll")] static extern bool AllowSetForegroundWindow(uint pid);
 [DllImport("user32.dll")] static extern bool PostMessage(IntPtr h,uint msg,IntPtr w,IntPtr l);
 [DllImport("user32.dll")] static extern bool SetForegroundWindow(IntPtr h);
 [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr h);
 [DllImport("user32.dll")] static extern bool IsIconic(IntPtr h);
 [DllImport("user32.dll")] static extern int GetWindowLong(IntPtr h,int index);
 [DllImport("user32.dll")] static extern bool ShowWindow(IntPtr h,int action);
 public AppInstance(){
  mutex=new Mutex(false,MutexName);
  try{IsOwner=mutex.WaitOne(0);}catch(AbandonedMutexException){IsOwner=true;}
  if(IsOwner){
   activation=new EventWaitHandle(false,EventResetMode.AutoReset,EventName);
   exit=new EventWaitHandle(false,EventResetMode.AutoReset,ExitName);
   map=MemoryMappedFile.CreateOrOpen(MapName,64);
   using(var v=map.CreateViewAccessor()){v.Write(0,Process.GetCurrentProcess().Id);v.Write(8,0L);v.Write(16,0);v.Write(20,0);}
  }
 }
 public void Publish(IntPtr hwnd,int trayCount){using(var v=map.CreateViewAccessor()){v.Write(8,hwnd.ToInt64());v.Write(20,trayCount);}}
 public bool ConsumeActivation(){bool value=activation.WaitOne(0);if(value){ActivationCount++;using(var v=map.CreateViewAccessor())v.Write(16,ActivationCount);}return value;}
 public bool ExitRequested(){return exit.WaitOne(0);}
 public static void RequestExit(){using(var e=EventWaitHandle.OpenExisting(ExitName))e.Set();}
 public static void HideForTest(){using(var m=MemoryMappedFile.OpenExisting(MapName))using(var v=m.CreateViewAccessor())ShowWindow(new IntPtr(v.ReadInt64(8)),0);}
 public static void MinimizeForTest(){using(var m=MemoryMappedFile.OpenExisting(MapName))using(var v=m.CreateViewAccessor())ShowWindow(new IntPtr(v.ReadInt64(8)),6);}
 public static void SignalExisting(){
  // A duplicate can arrive while the first process is loading artwork or compiling interop.
  for(int i=0;i<100;i++){
   try{
    using(var m=MemoryMappedFile.OpenExisting(MapName))using(var v=m.CreateViewAccessor()){
     uint pid=(uint)v.ReadInt32(0);IntPtr h=new IntPtr(v.ReadInt64(8));
     if(pid!=0)AllowSetForegroundWindow(pid);
     using(var e=EventWaitHandle.OpenExisting(EventName))e.Set();
     if(h!=IntPtr.Zero)PostMessage(h,ShowMessage,IntPtr.Zero,IntPtr.Zero);
    }
    return;
   }catch(System.IO.FileNotFoundException){Thread.Sleep(50);}
    catch(WaitHandleCannotBeOpenedException){Thread.Sleep(50);}
  }
 }
 public static string[] Snapshot(){
  using(var m=MemoryMappedFile.OpenExisting(MapName))using(var v=m.CreateViewAccessor()){
   IntPtr h=new IntPtr(v.ReadInt64(8));
   return new string[]{v.ReadInt32(0).ToString(),h.ToInt64().ToString(),v.ReadInt32(16).ToString(),v.ReadInt32(20).ToString(),IsWindowVisible(h).ToString(),IsIconic(h).ToString(),((GetWindowLong(h,-20)&8)!=0).ToString()};
  }
 }
 public static void BringToFront(System.Windows.Forms.Form form){
  form.Show();if(form.WindowState==System.Windows.Forms.FormWindowState.Minimized)form.WindowState=System.Windows.Forms.FormWindowState.Normal;
  form.TopMost=true;form.BringToFront();form.Activate();SetForegroundWindow(form.Handle);
 }
 public void Dispose(){if(map!=null)map.Dispose();if(activation!=null)activation.Dispose();if(exit!=null)exit.Dispose();if(IsOwner){mutex.ReleaseMutex();IsOwner=false;}mutex.Dispose();}
}
