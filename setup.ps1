# ===================================
# Einlesen der vmconfig.json Datei
# ===================================

$config = Get-Content "H:\Downloads\Windows\win2k25\vmconfig.json" | ConvertFrom-Json

# ===================================
# Eingaben validieren
# ===================================

$allowedCores = @(1,2,4,6)
$allowedRAM   = @(2,4,6,8)
$allowedDisk  = @(40,60,80)

if ($config.Cores -notin $allowedCores) {
    throw "Ungültige CPU Anzahl"
}

if ($config.RAM -notin $allowedRAM) {
    throw "Ungültige RAM Größe"
}

if ($config.DiskSize -notin $allowedDisk) {
    throw "Ungültige Disk Größe"
}

if ($config.VMName -notmatch '^[a-zA-Z0-9\-]+$') {
    throw "Ungültiger VM Name"
}

# ===================================
# Variablen fuer XML Platzhalter
# ===================================

$vars = @{
    "##ADMINPASSWORD##" = $config.AdminPassword
    "##SERVERNAME##"    = $config.VMName
}

$templatePath = "H:\Downloads\Windows\win2k25\Templates\Autounattend_template.xml"
$xmlPath      = "H:\Downloads\Windows\win2k25\Unattend\Autounattend.xml"

# ===================================
# Variablen fuer VM Setup
# ===================================

$VMName    = $config.VMName
$VMPfad    = "C:\VM\w2k25vm\$VMName"

$SourceISO = "H:\Downloads\Windows\win2k25\WS2025-Auto.iso"

# WICHTIG:
# MountPath pro VM eindeutig
$MountPath = "C:\temp\ISO_Mount_$VMName"

# ISO pro VM
$NewISO = "H:\Downloads\Windows\win2k25\WS2025-$($config.VMName).iso"

$UnattendXML = $xmlPath

# Hardware
$Memory = [Int64]$config.RAM * 1GB
$Disk   = [Int64]$config.DiskSize * 1GB
$Cores  = [Int32]$config.Cores

# Netzwerk
$ExternSwitch = "extern 1"
$InternSwitch = "intern"

# oscdimg
$oscdimg = "C:\Program Files (x86)\Windows Kits\10\Assessment and Deployment Kit\Deployment Tools\amd64\Oscdimg\oscdimg.exe"

# ===================================
# Logging
# ===================================

$LogPath = "H:\Downloads\Windows\win2k25\logs"

if (!(Test-Path $LogPath)) {
    New-Item -ItemType Directory -Path $LogPath | Out-Null
}

Start-Transcript "$LogPath\$VMName.log"

Write-Host ""
Write-Host "====================================="
Write-Host " Starte VM Deployment: $VMName"
Write-Host "====================================="
Write-Host ""

Write-Host "CPU:  $Cores"
Write-Host "RAM:  $($config.RAM) GB"
Write-Host "Disk: $($config.DiskSize) GB"

# ===================================
# XML Template einlesen
# ===================================

$template = Get-Content $templatePath -Raw

if ([string]::IsNullOrWhiteSpace($template)) {
    throw "Template ist leer oder nicht gefunden!"
}

foreach ($key in $vars.Keys) {
    $template = $template -replace $key, $vars[$key]
}

# Alte XML entfernen
if (Test-Path $xmlPath) {
    Remove-Item $xmlPath -Force
}

# UTF8 OHNE BOM schreiben
[System.IO.File]::WriteAllText(
    $xmlPath,
    $template,
    (New-Object System.Text.UTF8Encoding($false))
)

Write-Host "✔ Autounattend.xml erstellt"

# Passwort aus Speicher entfernen
$config.AdminPassword = $null

# ===================================
# Cleanup
# ===================================

Write-Progress -Activity "Setup läuft..." -Status "Cleanup" -PercentComplete 5

Remove-Item $MountPath -Recurse -Force -ErrorAction SilentlyContinue

New-Item -ItemType Directory -Path $MountPath -Force | Out-Null

# ===================================
# ISO mounten
# ===================================

Write-Progress -Activity "Setup läuft..." -Status "Mount ISO" -PercentComplete 10

Mount-DiskImage -ImagePath $SourceISO

Start-Sleep -Seconds 2

$drive = (Get-DiskImage $SourceISO | Get-Volume).DriveLetter + ":"

Write-Host "✔ ISO gemountet auf $drive"

# ===================================
# ISO kopieren
# ===================================

Write-Progress -Activity "Setup läuft..." -Status "Kopiere ISO" -PercentComplete 20

robocopy "$drive\" "$MountPath" /E | Out-Null

Write-Host "✔ ISO Dateien kopiert"

# ===================================
# Autounattend integrieren
# ===================================

Write-Progress -Activity "Setup läuft..." -Status "Autounattend kopieren" -PercentComplete 30

Copy-Item $UnattendXML "$MountPath\Autounattend.xml" -Force

Write-Host "✔ Autounattend integriert"

# ===================================
# bootfix.bin entfernen
# ===================================

Remove-Item "$MountPath\boot\bootfix.bin" -ErrorAction SilentlyContinue

Write-Host "✔ bootfix.bin entfernt"

# ===================================
# Neue ISO erstellen
# ===================================

Write-Progress -Activity "Setup läuft..." -Status "Erstelle ISO" -PercentComplete 50

if (Test-Path $NewISO) {
    Remove-Item $NewISO -Force
}

& "$oscdimg" -m -o -u2 -udfver102 `
-bootdata:2#p0,e,b"$MountPath\boot\etfsboot.com"#pEF,e,b"$MountPath\efi\microsoft\boot\efisys_noprompt.bin" `
"$MountPath" "$NewISO"

Write-Host "✔ Neue unattended ISO erstellt"

# ISO aushängen
Dismount-DiskImage -ImagePath $SourceISO

# ===================================
# Alte VM prüfen
# ===================================

Write-Progress -Activity "Setup läuft..." -Status "Prüfe bestehende VM" -PercentComplete 60

if (Get-VM -Name $VMName -ErrorAction SilentlyContinue) {

    Write-Host ""
    Write-Host "FEHLER:"
    Write-Host "VM existiert bereits!"
    Write-Host ""

    Stop-Transcript

    throw "VM '$VMName' existiert bereits"
}

# ===================================
# VM erstellen
# ===================================

Write-Progress -Activity "Setup läuft..." -Status "Erstelle VM" -PercentComplete 70

New-VM -Name $VMName `
       -MemoryStartupBytes $Memory `
       -Generation 2 `
       -Path $VMPfad `
       -NewVHDPath "$VMPfad\$VMName-C.vhdx" `
       -NewVHDSizeBytes $Disk `
       -SwitchName $ExternSwitch

Write-Host "✔ VM erstellt"

# ===================================
# CPU konfigurieren
# ===================================

Set-VMProcessor -VMName $VMName -Count $Cores

Write-Host "✔ CPU gesetzt: $Cores"

# ===================================
# RAM konfigurieren
# ===================================

Set-VMMemory -VMName $VMName -DynamicMemoryEnabled $false

Write-Host "✔ RAM gesetzt"

# ===================================
# Zweite NIC hinzufügen
# ===================================

Add-VMNetworkAdapter `
    -VMName $VMName `
    -SwitchName $InternSwitch `
    -Name "Local"

Write-Host "✔ Zweite NIC hinzugefügt"

# ===================================
# ISO einbinden
# ===================================

Write-Progress -Activity "Setup läuft..." -Status "Binde ISO ein" -PercentComplete 80

Add-VMDvdDrive -VMName $VMName -Path $NewISO

$dvd = Get-VMDvdDrive -VMName $VMName

Set-VMFirmware -VMName $VMName -FirstBootDevice $dvd

# Secure Boot deaktivieren
Set-VMFirmware -VMName $VMName -EnableSecureBoot Off

Write-Host "✔ ISO eingebunden"

# ===================================
# VM starten
# ===================================

Write-Progress -Activity "Setup läuft..." -Status "Starte VM" -PercentComplete 90

Start-VM -Name $VMName

Write-Host ""
Write-Host "✔ VM gestartet"
Write-Host ""
Write-Host "Windows Setup läuft unattended"
Write-Host ""

# ===================================
# Fertig
# ===================================

Write-Progress -Activity "Setup läuft..." -Status "Fertig" -PercentComplete 100

Write-Host ""
Write-Host "====================================="
Write-Host " Deployment abgeschlossen"
Write-Host "====================================="
Write-Host ""

Stop-Transcript