
Set-Variable -Option Constant -Name SCRIPT_TITEL   -Value "FontViewMax"
Set-Variable -Option Constant -Name SCRIPT_VERSION -Value 0.1.0

$ScriptRoot = if (-not $PSScriptRoot) {
    Split-Path -Parent (Convert-Path ([Environment]::GetCommandLineArgs()[0])) 
} 
else {
    $PSScriptRoot # Use the automatic variable.
}

function Get-UserFontNames {
    $result = @()

    $font_path = Get-ChildItem (Join-Path $env:LOCALAPPDATA Microsoft\Windows\Fonts\)
    $font_path | ForEach-Object {
        $fo = New-Object System.Drawing.Text.PrivateFontCollection
        $fo.AddFontFile($_.FullName)
        $normalName = $fo.Families.Name
        $usName   = $fo.Families[0].GetName([System.Globalization.CultureInfo]::GetCultureInfo("en-us").LCID)
        $result += ,@($_.FullName; $normalName; $usName)
    }
    return $result
}

function Get-SystemFontNames {
    [void] [System.Reflection.Assembly]::LoadWithPartialName("System.Drawing")
    return (
        (New-Object System.Drawing.Text.InstalledFontCollection).Families |
            ForEach-Object {
                $normalName = $_.Name
                $usName     = $_.GetName([System.Globalization.CultureInfo]::GetCultureInfo("en-us").LCID)
                ,@($normalName; $usName)
            }
    )
}

Remove-Item (Join-Path $ScriptRoot "lib\*.dll") -Stream Zone.Identifier -ErrorAction SilentlyContinue

Add-Type -AssemblyName System.Drawing         # フォント操作用
Add-Type -AssemblyName PresentationFramework  # WPF 用
Add-Type -AssemblyName System.Windows.Forms   # Timer 用

$libWebView2Wpf    = (Join-Path $ScriptRoot "lib\Microsoft.Web.WebView2.Wpf.dll")
$libWebView2Core   = (Join-Path $ScriptRoot "lib\Microsoft.Web.WebView2.Core.dll")
$libWebview2Loader = (Join-Path $ScriptRoot "lib\WebView2Loader.dll")

<# WebView2 用アセンブリロード #>
[void][reflection.assembly]::LoadFile($libWebView2Wpf)
[void][reflection.assembly]::LoadFile($libWebView2Core)

<# XAML にて Window 構築 #>
[xml]$xaml  = (Get-Content (Join-Path $ScriptRoot "etc\ui.xaml"))
$nodeReader = (New-Object System.XML.XmlNodeReader $xaml)
$window     = [Windows.Markup.XamlReader]::Load($nodeReader)

$webview  = $window.findName("webView")

<# WebView2 の設定 #>
$webview.CreationProperties = New-Object 'Microsoft.Web.WebView2.Wpf.CoreWebView2CreationProperties'
$webview.CreationProperties.UserDataFolder = (Join-Path $ScriptRoot "data")
$webview.Source = "file:///" + (Join-Path $ScriptRoot "webview/FontViewMax.html")

<# Set EventListener #>

<# WebView2 Messaging #>
$webview.add_WebMessageReceived({
    param($webview, $message)
    $json = ($message.WebMessageAsJson | ConvertFrom-Json)
    if ($json.status -eq "ready") {
        $webview.CoreWebView2.PostWebMessageAsJSON((@{
            system_fonts = Get-SystemFontNames
            user_fonts   = Get-UserFontNames
        } | ConvertTo-Json))
    }
})

<# Window の表示 #>
$window.Title = ("{0} v{1}" -f ($SCRIPT_TITEL,$SCRIPT_VERSION))
[void]$window.ShowDialog()
$webview.Dispose()
$window.Close()

