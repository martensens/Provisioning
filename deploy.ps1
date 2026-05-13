Add-Type -AssemblyName System.Web

$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add("http://+:8099/")
$listener.Start()

$ip = (Get-NetIPAddress -AddressFamily IPv4 `
| Where-Object {
    $_.IPAddress -like "192.168.*" `
    -and $_.InterfaceAlias -notlike "*Hyper-V*"
}).IPAddress

Write-Host "VM Portal läuft auf http://$ip`:8099"
while ($true) {

    $context = $listener.GetContext()
    $request = $context.Request
    $response = $context.Response

    # 🔥 CORS Header
    $response.Headers["Access-Control-Allow-Origin"] = "*"
    $response.Headers["Access-Control-Allow-Headers"] = "*"
    $response.Headers["Access-Control-Allow-Methods"] = "POST, GET, OPTIONS"

    # 🔥 OPTIONS beantworten
    if ($request.HttpMethod -eq "OPTIONS") {
        $response.StatusCode = 200
        $response.Close()
        continue
    }

    if ($request.HttpMethod -eq "POST" -and $request.Url.AbsolutePath -eq "/deploy") {

	Write-Host "Deploy Request empfangen!"

        $reader = New-Object IO.StreamReader($request.InputStream)
        $json = $reader.ReadToEnd()

        $config = $json | ConvertFrom-Json

        # JSON speichern
        $config | ConvertTo-Json | Set-Content "H:\Downloads\Windows\win2k25\vmconfig.json"

        # VM Deployment starten
        Start-Process powershell -ArgumentList "-ExecutionPolicy Bypass -File H:\Downloads\Windows\win2k25\setup.ps1"

        $response.StatusCode = 200
    }

    $response.Close()
}