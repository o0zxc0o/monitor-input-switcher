using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.Runtime.InteropServices;
using System.Windows.Forms;

public static class NeonSkin {
 public static Image Art; public static bool English;
 public static void Slice(Graphics g, Rectangle target, Rectangle source) { if(Art!=null) g.DrawImage(Art,target,source,GraphicsUnit.Pixel); }
 public static GraphicsPath Plate(int w,int h,int c) {var p=new GraphicsPath();p.AddPolygon(new Point[]{new Point(c,0),new Point(w-c,0),new Point(w,c),new Point(w,h-c),new Point(w-c,h),new Point(c,h),new Point(0,h-c),new Point(0,c)});return p;}
}
public static class ConnectionEvidence {
 public static int Resolve(int port,int current,int[] detected,Dictionary<int,int> confirmed){
  // VCP 0x60 is selection, not signal/cable presence. Only independent evidence colors the portrait.
  if(detected!=null)foreach(int value in detected)if(value==port)return 1;
  int manual;if(confirmed!=null&&confirmed.TryGetValue(port,out manual)&&(manual==0||manual==1))return manual;
  return -1;
 }
}
public class ArmorForm:Form {
 public Rectangle CaptionRect=new Rectangle(0,0,840,36);
 public List<Control> CaptionExempt=new List<Control>();
 public Image Badge;
 [DllImport("user32.dll")] static extern bool ReleaseCapture();
 [DllImport("user32.dll")] static extern IntPtr SendMessage(IntPtr h,int m,IntPtr w,IntPtr l);
 public ArmorForm(){FormBorderStyle=FormBorderStyle.None;AutoScaleMode=AutoScaleMode.None;SetStyle(ControlStyles.OptimizedDoubleBuffer|ControlStyles.AllPaintingInWmPaint|ControlStyles.ResizeRedraw,true);}
 public void LayoutArt(){
  float sx=ClientSize.Width/1398f,sy=ClientSize.Height/1125f;
  CaptionRect=new Rectangle(0,0,ClientSize.Width,(int)(59*sy));
  foreach(Control c in Controls) if(c.Tag is Rectangle){Rectangle r=(Rectangle)c.Tag;c.SetBounds((int)(r.X*sx),(int)(r.Y*sy),(int)(r.Width*sx),(int)(r.Height*sy));}
 }
 protected override void OnSizeChanged(EventArgs e){base.OnSizeChanged(e);LayoutArt();Invalidate();}
 protected override void OnPaintBackground(PaintEventArgs e){
  Graphics g=e.Graphics;var paintState=g.Save();g.Clear(Color.FromArgb(5,6,8));g.InterpolationMode=InterpolationMode.HighQualityBicubic;
  g.ScaleTransform(ClientSize.Width/1398f,ClientSize.Height/1125f);
  // Original artwork is rendered in decorative regions. Cards and actions are separate live controls.
  NeonSkin.Slice(g,new Rectangle(0,0,1398,610),new Rectangle(0,0,1398,610));
  NeonSkin.Slice(g,new Rectangle(579,610,819,116),new Rectangle(579,610,819,116));
  NeonSkin.Slice(g,new Rectangle(0,610,64,104),new Rectangle(0,610,64,104));
  NeonSkin.Slice(g,new Rectangle(0,990,828,135),new Rectangle(0,990,828,135));
  NeonSkin.Slice(g,new Rectangle(828,1090,570,35),new Rectangle(828,1090,570,35));
  NeonSkin.Slice(g,new Rectangle(0,944,1398,56),new Rectangle(0,944,1398,56));
  // Clear baked shortcut labels; each shortcut is rendered by a real label below its card.
  using(var b=new SolidBrush(Color.FromArgb(240,4,5,7)))g.FillRectangle(b,100,948,1180,32);
  using(var p=new Pen(Color.FromArgb(143,29,27),2))g.DrawRectangle(p,4,5,1389,1115);
  g.Restore(paintState);
 }
 protected override void WndProc(ref Message m){
  if(m.Msg==0x84){Point p=PointToClient(Cursor.Position);bool exempt=false;foreach(Control c in CaptionExempt)if(c.Bounds.Contains(p))exempt=true;if(!exempt&&CaptionRect.Contains(p)){m.Result=(IntPtr)2;return;}}
  base.WndProc(ref m);
 }
}
public class NeonNotice:Label { protected override void OnTextChanged(EventArgs e){base.OnTextChanged(e);Visible=!String.IsNullOrWhiteSpace(Text);} public NeonNotice(){Visible=false;AutoSize=false;BackColor=Color.FromArgb(8,8,10);ForeColor=Color.Orange;TextAlign=ContentAlignment.MiddleLeft;Padding=new Padding(7,0,3,0);} protected override void OnPaint(PaintEventArgs e){base.OnPaint(e);using(var p=new Pen(Color.FromArgb(110,76,35)))e.Graphics.DrawRectangle(p,0,0,Width-1,Height-1);} }
public class NeonCurrent:Control {
 public NeonCurrent(){SetStyle(ControlStyles.UserPaint|ControlStyles.OptimizedDoubleBuffer|ControlStyles.ResizeRedraw,true);}
 protected override void OnTextChanged(EventArgs e){base.OnTextChanged(e);Invalidate();}
 protected override void OnPaint(PaintEventArgs e){
  Graphics g=e.Graphics;var paintState=g.Save();g.ScaleTransform(Width/515f,Height/96f);
  NeonSkin.Slice(g,new Rectangle(0,0,515,96),new Rectangle(64,608,515,96));
  using(var b=new SolidBrush(Color.FromArgb(8,8,10)))g.FillRectangle(b,174,28,290,48);
  using(var f=new Font("Segoe UI",32,FontStyle.Bold)){
   using(var shadow=new SolidBrush(Color.FromArgb(110,255,30,0))) {g.DrawString(Text,f,shadow,182,28);g.DrawString(Text,f,shadow,178,26);}
   using(var b=new SolidBrush(ForeColor))g.DrawString(Text,f,b,180,27);
  }
  g.Restore(paintState);
 }
}
public class ArmorButton:Control {
 public string BigText="",SmallText="";
 public bool Active=false;
 public int ConnectionState=-1; // -1 unknown, 0 explicitly disconnected, 1 connected
 public Font BigFont=new Font("Microsoft YaHei UI",12,FontStyle.Bold),SmallFont=new Font("Microsoft YaHei UI",8);
 public int CardIndex=-1,ActionIndex=-1;
 public Action OnActivated;
 bool hover,down;
 public ArmorButton(){SetStyle(ControlStyles.OptimizedDoubleBuffer|ControlStyles.UserPaint|ControlStyles.ResizeRedraw,true);Cursor=Cursors.Hand;TabStop=true;BackColor=Color.FromArgb(8,8,10);}
 public static GraphicsPath Chamfer(int w,int h,int c){return NeonSkin.Plate(w,h,c);}
 void DrawPortCard(Graphics g){
  var paintState=g.Save();
  g.ScaleTransform(Width/420f,Height/236f);
  g.SmoothingMode=SmoothingMode.AntiAlias;
  using(var plate=NeonSkin.Plate(404,218,17)){
   g.TranslateTransform(8,8);
   using(var fill=new LinearGradientBrush(new Rectangle(0,0,404,218),Active?Color.FromArgb(38,9,13):Color.FromArgb(18,19,23),Color.FromArgb(5,7,10),90f))g.FillPath(fill,plate);
   g.SetClip(plate);
   using(var grid=new Pen(Active?Color.FromArgb(65,118,17,25):Color.FromArgb(28,78,80,86),1)){
    for(int x=12;x<404;x+=10)g.DrawLine(grid,x,24,x,218);
    for(int y=26;y<218;y+=10)g.DrawLine(grid,0,y,404,y);
   }
   g.ResetClip();
   if(Active){
    using(var p=new Pen(Color.FromArgb(24,255,45,12),18))g.DrawPath(p,plate);
    using(var p=new Pen(Color.FromArgb(55,255,55,18),12))g.DrawPath(p,plate);
    using(var p=new Pen(Color.FromArgb(105,255,66,24),8))g.DrawPath(p,plate);
    using(var p=new Pen(Color.FromArgb(255,87,43),4.5f))g.DrawPath(p,plate);
    using(var p=new Pen(Color.FromArgb(255,220,177),1.5f))g.DrawPath(p,plate);
   }else{
    using(var p=new Pen(Color.FromArgb(118,118,123),1.4f))g.DrawPath(p,plate);
    using(var inset=NeonSkin.Plate(392,206,14))using(var p=new Pen(Color.FromArgb(48,50,56),1)){g.TranslateTransform(6,6);g.DrawPath(p,inset);g.TranslateTransform(-6,-6);}
   }
   g.TranslateTransform(-8,-8);
  }
  if(Active){

   using(var f=new Font("Microsoft YaHei UI",19,FontStyle.Bold,GraphicsUnit.Pixel))g.DrawString("ACTIVE",f,Brushes.White,23,26);
  }
  // The icon canvas is invariant: selection cannot stretch or reposition a glyph.
  if(CardIndex==0){
   Rectangle source=new Rectangle(154,742,98,75),target=new Rectangle(161,31,98,75);
   // Display only the original white DP mark, making the underlying artwork transparent at paint time.
   var white=new ColorMatrix(new float[][]{new float[]{0,0,0,1.5f,0},new float[]{0,0,0,1.5f,0},new float[]{0,0,0,1.5f,0},new float[]{0,0,0,0,0},new float[]{1,1,1,-3.5f,1}});
   using(var attributes=new ImageAttributes()){attributes.SetColorMatrix(white);if(NeonSkin.Art!=null)g.DrawImage(NeonSkin.Art,target,source.X,source.Y,source.Width,source.Height,GraphicsUnit.Pixel,attributes);}
  }else{
   g.TranslateTransform(48,0);using(var path=new GraphicsPath())using(var pen=new Pen(Color.White,5f)){
    path.AddPolygon(new Point[]{new Point(119,58),new Point(205,58),new Point(211,63),new Point(211,80),new Point(202,85),new Point(198,94),new Point(126,94),new Point(122,85),new Point(113,80),new Point(113,63)});
    g.DrawPath(pen,path);g.DrawLine(pen,131,78,193,78);
   }
  }
  if(CardIndex!=0)g.TranslateTransform(-48,0);
  using(var f=new Font("Segoe UI",28,FontStyle.Bold,GraphicsUnit.Pixel))using(var format=new StringFormat{Alignment=StringAlignment.Center,LineAlignment=StringAlignment.Center})
   g.DrawString(CardIndex==0?"DisplayPort":"HDMI "+CardIndex,f,Brushes.White,new RectangleF(15,106,390,36),format);
  Rectangle thumb=new Rectangle(16,146,388,72),photo=new Rectangle(180,855,188,72);
  // Fit by cropping the photographic strip, never by changing its aspect ratio.
  int photoHeight=(int)(photo.Width*thumb.Height/(float)thumb.Width);photo.Y+=(photo.Height-photoHeight)/2;photo.Height=photoHeight;
  if(ConnectionState==1)NeonSkin.Slice(g,thumb,photo);
  else{
   var gray=new ColorMatrix(new float[][]{new float[]{.3f,.3f,.3f,0,0},new float[]{.59f,.59f,.59f,0,0},new float[]{.11f,.11f,.11f,0,0},new float[]{0,0,0,1,0},new float[]{0,0,0,0,1}});
   using(var attributes=new ImageAttributes()){attributes.SetColorMatrix(gray);if(NeonSkin.Art!=null)g.DrawImage(NeonSkin.Art,thumb,photo.X,photo.Y,photo.Width,photo.Height,GraphicsUnit.Pixel,attributes);}
  }
  using(var edge=new Pen(Active?Color.FromArgb(191,36,41):Color.FromArgb(68,70,77)))g.DrawRectangle(edge,thumb);
  using(var b=new SolidBrush(ConnectionState==1?Color.FromArgb(238,225,21,34):Color.FromArgb(240,33,35,40)))
   g.FillPolygon(b,new Point[]{new Point(16,146),new Point(127,146),new Point(112,175),new Point(16,175)});
  using(var f=new Font("Segoe UI",23,FontStyle.Bold,GraphicsUnit.Pixel))g.DrawString((CardIndex+1).ToString("00"),f,ConnectionState==1?Brushes.Black:Brushes.Silver,24,145);
  using(var b=new SolidBrush(ConnectionState==1?Color.FromArgb(18,3,5):Color.FromArgb(125,128,136))){
   for(int x=67;x<111;x+=12)g.FillPolygon(b,new Point[]{new Point(x,151),new Point(x+8,151),new Point(x-1,170),new Point(x-9,170)});
  }

  using(var f=new Font("Microsoft YaHei UI",19,FontStyle.Regular,GraphicsUnit.Pixel))g.DrawString(NeonSkin.English?(ConnectionState==1?"Connected":ConnectionState==0?"Offline":"Unknown"):(ConnectionState==1?"已连接":ConnectionState==0?"未连接":"未确认"),f,ConnectionState==1?Brushes.LightGreen:Brushes.Silver,NeonSkin.English?300:332,26);
  if(!Enabled)using(var b=new SolidBrush(Color.FromArgb(55,0,0,0)))g.FillRectangle(b,0,0,420,236);
  g.Restore(paintState);
 }
 protected override void OnPaint(PaintEventArgs e){
  Graphics g=e.Graphics;g.InterpolationMode=InterpolationMode.HighQualityBicubic;
  if(CardIndex>=0){DrawPortCard(g);}
  else if(ActionIndex>=0){Rectangle[] src={new Rectangle(835,1011,180,74),new Rectangle(1022,1011,173,74),new Rectangle(1199,1011,170,74)};NeonSkin.Slice(g,new Rectangle(0,0,Width,Height),src[ActionIndex]);if(NeonSkin.English){using(var b=new SolidBrush(Color.FromArgb(8,8,10)))g.FillRectangle(b,Width*0.4f,8,Width*0.57f,Height-16);TextRenderer.DrawText(g,new string[]{"Settings","Logs","Exit"}[ActionIndex],new Font("Segoe UI",10),new Rectangle((int)(Width*.38f),0,(int)(Width*.62f),Height),Color.White,TextFormatFlags.HorizontalCenter|TextFormatFlags.VerticalCenter);}}
  else {
   using(var path=NeonSkin.Plate(Width-1,Height-1,5))using(var b=new SolidBrush(Color.FromArgb(18,18,22)))using(var p=new Pen(Color.FromArgb(130,39,36))){g.FillPath(b,path);g.DrawPath(p,path);}
   TextRenderer.DrawText(g,BigText,BigFont,ClientRectangle,Color.FromArgb(240,225,222),TextFormatFlags.HorizontalCenter|TextFormatFlags.VerticalCenter);
  }
  if(hover&&Enabled){using(var b=new SolidBrush(Color.FromArgb(down?45:15,220,220,220)))g.FillRectangle(b,ClientRectangle);}
  if(Focused&&Enabled){using(var p=new Pen(Color.FromArgb(115,120,126))){p.DashStyle=DashStyle.Dot;g.DrawRectangle(p,3,3,Width-7,Height-7);}}
 }
 protected override void OnMouseEnter(EventArgs e){hover=true;Invalidate();base.OnMouseEnter(e);}
 protected override void OnMouseLeave(EventArgs e){hover=false;down=false;Invalidate();base.OnMouseLeave(e);}
 protected override void OnMouseDown(MouseEventArgs e){if(e.Button==MouseButtons.Left){down=true;Focus();Invalidate();}base.OnMouseDown(e);}
 protected override void OnMouseUp(MouseEventArgs e){bool fire=down&&Enabled&&ClientRectangle.Contains(e.Location)&&e.Button==MouseButtons.Left;down=false;Invalidate();base.OnMouseUp(e);if(fire&&OnActivated!=null)OnActivated();}
 protected override void OnKeyDown(KeyEventArgs e){base.OnKeyDown(e);if(Enabled&&(e.KeyCode==Keys.Enter||e.KeyCode==Keys.Space)&&OnActivated!=null){e.Handled=true;OnActivated();}}
 protected override void OnEnabledChanged(EventArgs e){base.OnEnabledChanged(e);Invalidate();}
 protected override void OnGotFocus(EventArgs e){base.OnGotFocus(e);Invalidate();}
 protected override void OnLostFocus(EventArgs e){base.OnLostFocus(e);Invalidate();}
}
public class CaptionButton:Control {
 public bool IsClose=false,IsMax=false;
 public Action OnActivated;
 bool hover;
 public CaptionButton(){SetStyle(ControlStyles.UserPaint|ControlStyles.OptimizedDoubleBuffer|ControlStyles.ResizeRedraw,true);Cursor=Cursors.Hand;BackColor=Color.FromArgb(4,5,7);}
 protected override void OnPaint(PaintEventArgs e){
  e.Graphics.Clear(hover?Color.FromArgb(IsClose?155:42,18,20):BackColor);
  var g=e.Graphics;float s=Width/80f;g.ScaleTransform(s,Height/50f);
  using(var p=new Pen(Color.FromArgb(220,220,220),1.7f)){if(IsClose){g.DrawLine(p,28,12,48,32);g.DrawLine(p,48,12,28,32);}else if(IsMax)g.DrawRectangle(p,28,13,20,19);else g.DrawLine(p,28,23,48,23);}
 }
 protected override void OnMouseEnter(EventArgs e){hover=true;Invalidate();base.OnMouseEnter(e);}
 protected override void OnMouseLeave(EventArgs e){hover=false;Invalidate();base.OnMouseLeave(e);}
 protected override void OnClick(EventArgs e){base.OnClick(e);if(OnActivated!=null)OnActivated();}
}
