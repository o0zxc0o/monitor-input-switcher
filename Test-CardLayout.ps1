#Requires -Version 5.1
$ErrorActionPreference='Stop'
$source=Get-Content (Join-Path $PSScriptRoot 'MonitorSwitch.ps1') -Raw
$cards=@()
foreach($name in 'btnA','btnB','btnC'){
 $match=[regex]::Match($source,'Add-ArtControl \$'+$name+' (\d+) (\d+) (\d+) (\d+)')
 if(-not $match.Success){throw ('Missing card '+$name)}
 $cards+=@{X=[int]$match.Groups[1].Value;Y=[int]$match.Groups[2].Value;W=[int]$match.Groups[3].Value;H=[int]$match.Groups[4].Value}
}
foreach($card in $cards){if($card.W -ne $cards[0].W -or $card.H -ne $cards[0].H -or $card.Y -ne $cards[0].Y){throw 'Three port cards must have identical width, height and vertical position'}}
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Windows.Forms
Add-Type -TypeDefinition (Get-Content (Join-Path $PSScriptRoot 'NeonSkin.cs') -Raw) -ReferencedAssemblies 'System.Drawing','System.Windows.Forms'
[NeonSkin]::Art=[Drawing.Image]::FromFile((Join-Path $PSScriptRoot 'assets\eva-neon-reference.png'))
try{
 for($index=0;$index -lt 3;$index++){
  $card=New-Object ArmorButton;$card.CardIndex=$index;$card.ConnectionState=1;$card.Size=New-Object Drawing.Size(420,236)
  $neutral=New-Object Drawing.Bitmap(420,236);$active=New-Object Drawing.Bitmap(420,236)
  try{
   $card.Active=$false;$card.DrawToBitmap($neutral,(New-Object Drawing.Rectangle(0,0,420,236)))
   $card.Active=$true;$card.DrawToBitmap($active,(New-Object Drawing.Rectangle(0,0,420,236)))
   for($y=30;$y -lt 105;$y++){for($x=146;$x -lt 274;$x++){
    $n=$neutral.GetPixel($x,$y);$a=$active.GetPixel($x,$y)
    $nw=$n.R -ge 254 -and $n.G -ge 254 -and $n.B -ge 254;$aw=$a.R -ge 254 -and $a.G -ge 254 -and $a.B -ge 254
    if($nw -ne $aw){throw ('Port glyph moves or changes size on activation: '+$index)}
   }}
   for($y=151;$y -lt 211;$y++){for($x=150;$x -lt 300;$x++){
    if($neutral.GetPixel($x,$y).ToArgb() -ne $active.GetPixel($x,$y).ToArgb()){throw ('Portrait moves or changes on activation: '+$index)}
   }}
   if($index -eq 0){$expected=$active.GetPixel(160,8).ToArgb()}elseif($active.GetPixel(160,8).ToArgb() -ne $expected){throw 'Active border style differs between ports'}
  }finally{$card.Dispose();$neutral.Dispose();$active.Dispose()}
 }
 $status=[regex]::Match($source,'Add-ArtControl \$lblStatus (\d+) (\d+) (\d+) (\d+)')
 if(([int]$status.Groups[2].Value+[int]$status.Groups[4].Value) -ge $cards[0].Y){throw 'Status overlaps the cards'}
 Write-Host 'PASS: three equal card geometries, stable glyphs/portraits, shared active border, independent status row.'
}finally{[NeonSkin]::Art.Dispose()}
