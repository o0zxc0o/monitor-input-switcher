using System;
using System.Diagnostics;
using System.IO;
using System.Windows.Forms;
class Launcher {
 [STAThread] static int Main(string[] args) {
  bool test = args.Length == 1 && args[0] == "--self-test";
   string root=AppDomain.CurrentDomain.BaseDirectory;
   string script=Path.Combine(root,"MonitorSwitch.ps1");
   if(!File.Exists(script)){MessageBox.Show("缺少 MonitorSwitch.ps1，请保留完整程序目录。");return 1;}
   try {
    ProcessStartInfo start=new ProcessStartInfo(Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System),"WindowsPowerShell\\v1.0\\powershell.exe"));
    start.Arguments="-NoProfile -STA -ExecutionPolicy Bypass -File \""+script+"\""+(test?" -SelfTest":"");
    start.WorkingDirectory=root;start.UseShellExecute=false;start.CreateNoWindow=true;start.WindowStyle=ProcessWindowStyle.Hidden;start.RedirectStandardError=true;
    using(Process child=Process.Start(start)) {
     string error=child.StandardError.ReadToEnd();child.WaitForExit();
     if(child.ExitCode!=0){File.WriteAllText(Path.Combine(root,"startup-error.log"),error);MessageBox.Show(error,"EVA-02 启动失败");}
     return child.ExitCode;
    }
   } catch(Exception e){MessageBox.Show(e.Message,"EVA-02 启动失败");return 1;}
 }
}
