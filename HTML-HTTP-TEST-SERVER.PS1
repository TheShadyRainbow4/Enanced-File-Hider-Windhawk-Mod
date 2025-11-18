# EliteSoftware HTML - HTTP Test Server v1.5.0.0 - Created by: Zachary Whiteman & Google Gemini Ai. 2025-10-11 - 04:00 EDT

<#
    This script implements a multi-server HTTP test platform GUI using PowerShell WinForms and threading.

    FIXES IN V1.5.0.0:
    - No major bug fixes, focus on feature enhancements.

    FEATURE ENHANCEMENTS IN V1.5.0.0:
    - **Revamped Settings Window:** The settings window now features the same gradient header as the main form and uses a tabbed interface ("General" and "Advanced").
    - **New General Setting:** Added a "Hide Console Window on Next Launch" option.
    - **New Advanced Settings:** Added 5 advanced settings: Enable Directory Listing, Custom 404 Page, Log Request Headers, MIME Type Overrides, and Enable HTTP Keep-Alive.
    - **UI Consistency:** The Help Guide window now also includes the gradient header for a consistent look and feel.
#>

# ==============================================================================
# 1. Dependency and Configuration Setup
# ==============================================================================

# Script Versioning
[string]$ScriptVersion = "v1.5.0.0"

# Load required .NET assemblies
# The 'Add-Type' for Drawing2D often generates a benign file-not-found error in some editors,
# but it loads correctly from the GAC. We suppress the warning.
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Net
try {
    Add-Type -AssemblyName "System.Drawing.Drawing2D, Version=4.0.0.0, Culture=neutral, PublicKeyToken=b03f5f7f11d50a3a" -ErrorAction SilentlyContinue
} catch {
    # This space intentionally left blank.
}

# Enable system visual styles (essential for theming)
[System.Windows.Forms.Application]::EnableVisualStyles()

# --- Configuration Path Update ---
$appId = "HTML_HTTP_TEST_SERVER"
# Requested specific path: C:\Users\Zachary Whiteman\AppData\Roaming\EliteSoftware\HTML_HTTP_TEST_SERVER
$baseConfigPath = "C:\Users\Zachary Whiteman\AppData\Roaming\EliteSoftware"
$configPath = Join-Path -Path $baseConfigPath -ChildPath $appId
$configFile = Join-Path -Path $configPath -ChildPath "server_configs.json"
$iconFile = Join-Path -Path $configPath -ChildPath "custom-icon.ico"

if (-not (Test-Path $configPath)) {
    New-Item -Path $configPath -ItemType Directory -Force | Out-Null
}

# --- Icon Loading ---
function Get-AppIcon {
    if (Test-Path $iconFile) {
        return [System.Drawing.Icon]::new($iconFile)
    }
    # Default icon fallback
    return [System.Drawing.Icon]::ExtractAssociatedIcon("$env:SystemRoot\system32\shell32.dll")
}

# Variable Definitions
[int]$FormWidth = 900 # Increased width for sidebar
[int]$FormHeight = 610
[int]$xStart = 30 # X coordinate for starting controls
[int]$SidebarWidth = 250
[int]$ContentXStart = $SidebarWidth + 30 # Start of main controls
[int]$ContentWidth = $FormWidth - $ContentXStart - $xStart # Width of the right panel
[int]$padding = 20 # Vertical padding offset
[int]$ButtonWidth = 140 # Adjusted button size
[int]$ButtonHeight = 40
[int]$BorderThickness = 2

# --- Global State Variables ---
$Script:ServerConfigs = @() # Array of saved configuration objects
$Script:CurrentConfigIndex = 0 # Index of the currently selected configuration
$Script:ActiveServers = @{} # Hashtable to track running HttpListener objects {ConfigName: {Listener: <obj>, Thread: <obj>}}
$Script:LogQueue = [System.Collections.Queue]::new() # Thread-safe queue for logging
$Script:LogTimer = $null # Timer for polling the log queue
$Script:IsExiting = $false # Flag for graceful exit
$Script:Settings = $null # Global settings object

# ==============================================================================
# 2. Configuration Management Functions
# ==============================================================================

function Load-Settings {
    $settingsFile = Join-Path -Path $configPath -ChildPath "settings.json"
    $defaultSettings = @{
        DefaultRoot = "C:\inetpub\wwwroot"
        DefaultFile = "index.html"
        DefaultPort = 8080
        DefaultIP = "127.0.0.1"
        MaxLogLines = 200
        LogToFile = $false
        LogFilePath = (Join-Path -Path $configPath -ChildPath "server.log")
        ShowGoodbyeWindow = $true
        HideConsoleOnLaunch = $false
        # Advanced Settings
        DirectoryListingEnabled = $false
        Custom404PagePath = ""
        LogRequestHeaders = $false
        MimeTypeOverrides = "log=text/plain;config=application/xml"
        EnableKeepAlive = $true
        CorsAllowedOrigins = "*" # New
        CustomResponseHeaders = "X-Powered-By: EliteSoftware-Server" # New
        RequestTimeoutSec = 30 # New
        MaxConcurrentConnections = 100 # New
        ServeIndexOn404 = $false # New
    }

    if (Test-Path $settingsFile) {
        try {
            $json = Get-Content $settingsFile -Raw
            $Script:Settings = $json | ConvertFrom-Json
            # Ensure all default keys exist
            foreach ($key in $defaultSettings.Keys) {
                if (-not $Script:Settings.PSObject.Properties.Match($key)) {
                    $Script:Settings | Add-Member -MemberType NoteProperty -Name $key -Value $defaultSettings[$key]
                }
            }
        } catch {
            Write-Warning "Failed to load settings.json, using defaults. Error: $($_.Exception.Message)"
            $Script:Settings = [PSCustomObject]$defaultSettings
        }
    } else {
        $Script:Settings = [PSCustomObject]$defaultSettings
    }
}

function Save-Settings {
    $settingsFile = Join-Path -Path $configPath -ChildPath "settings.json"
    try {
        $Script:Settings | ConvertTo-Json -Depth 3 | Out-File -FilePath $settingsFile -Encoding UTF8
    } catch {
        Write-Error "Failed to save settings to '$settingsFile'. Error: $($_.Exception.Message)"
    }
}

function Save-ServerConfig {
    try {
        # Limit to 10 configs as requested
        $configsToSave = $Script:ServerConfigs | Select-Object -First 10
        $json = $configsToSave | ConvertTo-Json -Depth 5
        $json | Out-File $configFile -Encoding UTF8
    } catch {
        Write-Error "Failed to save configuration: $($_.Exception.Message)"
    }
}

function Load-ServerConfigs {
    if (Test-Path $configFile) {
        try {
            $json = Get-Content $configFile -Raw
            $loadedConfigs = $json | ConvertFrom-Json
            if ($loadedConfigs -is [System.Array]) {
                $Script:ServerConfigs = $loadedConfigs
            } elseif ($loadedConfigs -is [System.Management.Automation.PSCustomObject]) {
                 # Handle case where only one config was saved (ConvertFrom-Json returns a single object)
                $Script:ServerConfigs = @($loadedConfigs)
            } else {
                $Script:ServerConfigs = @()
            }
        } catch {
            Write-Log "WARNING: Failed to load configurations. Starting fresh. $($_.Exception.Message)"
            $Script:ServerConfigs = @()
        }
    }

    # Initialize with a default config if none loaded
    if (-not $Script:ServerConfigs) {
        $Script:ServerConfigs = @(
            [PSCustomObject]@{
                Name = "Default Server 1"
                Root = "C:\inetpub\wwwroot"
                DefaultFile = "index.html"
                Port = 8080
                IP = "127.0.0.1"
                Status = "Stopped"
                UseRootFolderMode = $false
                SingleFilePath = "C:\path\to\your\file.html"
                AutoStart = $false
            }
        )
    }

    # Ensure all configs have the required properties and are of the correct type
    $reconstructedConfigs = @()
    foreach ($config in $Script:ServerConfigs) {
        $reconstructedConfigs += [PSCustomObject]@{
            Name = $config.Name
            Root = $config.Root
            DefaultFile = $config.DefaultFile
            Port = $config.Port
            IP = $config.IP
            Status = if ($config.PSObject.Properties.Match('Status')) { $config.Status } else { "Stopped" }
            UseRootFolderMode = if ($config.PSObject.Properties.Match('UseRootFolderMode')) { $config.UseRootFolderMode } else { $false }
            SingleFilePath = if ($config.PSObject.Properties.Match('SingleFilePath')) { $config.SingleFilePath } else { "" }
            AutoStart = if ($config.PSObject.Properties.Match('AutoStart')) { $config.AutoStart } else { $false }
        }
    }
    $Script:ServerConfigs = $reconstructedConfigs
}

function Add-NewConfig {
    # Find the highest port number currently in use and add 1
    $nextPort = if ($Script:ServerConfigs.Count -gt 0) {
        ($Script:ServerConfigs.Port | ForEach-Object { [int]$_ } | Measure-Object -Maximum).Maximum + 1
    } else {
        $Script:Settings.DefaultPort # Start with default if no servers exist
    }

    $newConfig = [PSCustomObject]@{
        Name = "New Server $($Script:ServerConfigs.Count + 1)"
        Root = $Script:Settings.DefaultRoot
        DefaultFile = $Script:Settings.DefaultFile
        Port = $nextPort
        IP = $Script:Settings.DefaultIP
        Status = "Stopped"
        UseRootFolderMode = $false
        SingleFilePath = ""
        AutoStart = $false
    }
    $Script:ServerConfigs += $newConfig
    Save-ServerConfig
}

function Update-GUIFromConfig {
    if ($Script:ServerConfigs.Count -gt $Script:CurrentConfigIndex -and $Form.IsHandleCreated) {
        $Form.Invoke([System.Action] {
            $configParam = $Script:ServerConfigs[$Script:CurrentConfigIndex]
            # Update common controls
            $PortTextBox.Text = $configParam.Port
            $IPComboBox.Text = $configParam.IP

            # Update mode-specific controls
            $RootModeCheckBox.Checked = $configParam.UseRootFolderMode
            $RootTextBox.Text = $configParam.Root
            $DefaultFileTextBox.Text = $configParam.DefaultFile
            $SingleFileTextBox.Text = $configParam.SingleFilePath
            $AutoStartCheckBox.Checked = $configParam.AutoStart

            # Toggle visibility based on mode
            $isRootMode = $configParam.UseRootFolderMode
            $RootLabel.Visible = $isRootMode
            $RootTextBox.Visible = $isRootMode
            $BrowseButton.Visible = $isRootMode
            $DefaultFileLabel.Visible = $isRootMode
            $DefaultFileTextBox.Visible = $isRootMode
            $SingleFileLabel.Visible = -not $isRootMode
            $SingleFileTextBox.Visible = -not $isRootMode
            $SingleFileBrowseButton.Visible = -not $isRootMode

            # Update form text to show current server
            $Form.Text = "EliteSoftware HTML-HTTP Test Server - $($configParam.Name)"

            $SidebarList.SelectedIndex = $Script:CurrentConfigIndex
            Update-ServerButtons $configParam.Status # Update buttons based on the config's status
        })
    }
}

function Update-ConfigFromGUI {
    if ($Script:ServerConfigs.Count -gt $Script:CurrentConfigIndex) {
        $config = $Script:ServerConfigs[$Script:CurrentConfigIndex]
        $config.Root = $RootTextBox.Text
        $config.DefaultFile = $DefaultFileTextBox.Text
        $config.Port = [int]$PortTextBox.Text
        $config.IP = $IPComboBox.Text
        $config.UseRootFolderMode = $RootModeCheckBox.Checked
        $config.SingleFilePath = $SingleFileTextBox.Text
        $config.AutoStart = $AutoStartCheckBox.Checked
        Save-ServerConfig
    }
}

# ==============================================================================
# 3. HTTP Server and Request Handling
# ==============================================================================

function Get-LocalIPv4Addresses {
    Get-NetIPAddress -AddressFamily IPv4 -InterfaceAlias * | Where-Object { $_.AddressFamily -eq 'IPv4' -and $_.InterfaceType -ne 'Loopback' -and $_.IPAddress -ne '127.0.0.1' } | Select-Object -ExpandProperty IPAddress
}



# ==============================================================================
# 3. HTTP Server and Request Handling
# ==============================================================================

function Start-Server {
    param($config)

    # 1. Update Config Status
    $config.Status = "Starting"
    Update-GUIFromConfig # Update buttons/status indicator

    # 2. Check and Adjust Port (Conflict Resolution)
    [string]$prefix = "http://$($config.IP):$($config.Port)/"
    $port = [int]$config.Port

    while ([System.Net.NetworkInformation.IPGlobalProperties]::GetIPGlobalProperties().GetActiveTcpListeners().Port -contains $port) {
        $port++
        $prefix = "http://$($config.IP):$port/"
        Invoke-GUIUpdate { Write-Log "Port $($port-1) is in use. Retrying on port $port..." }
        $config.Port = $port
        $PortTextBox.Text = $port
        Update-ConfigFromGUI
    }

    # 3. Create HttpListener and Thread
    $listener = [System.Net.HttpListener]::new()
    $listener.Prefixes.Add($prefix)
    # Set listener timeout properties from settings
    if ($listener.TimeoutManager.GetType().GetProperty('IdleConnection')) { # Available on Windows 8+
        $listener.TimeoutManager.IdleConnection = [System.TimeSpan]::FromSeconds($Script:Settings.RequestTimeoutSec)
        $listener.TimeoutManager.HeaderWait = [System.TimeSpan]::FromSeconds($Script:Settings.RequestTimeoutSec)
    }

    # Use a semaphore to limit concurrent connections
    $semaphore = [System.Threading.SemaphoreSlim]::new($Script:Settings.MaxConcurrentConnections)

    $thread = [System.Threading.Thread]::new({
        # Thread ScriptBlock
        param($listener, $config, $LogQueue, $Script:IsExiting, $semaphore)
        $listener.Start()

        $LogQueue.Enqueue("Server started successfully on $prefix. Root: $($config.Root)")

        while ($listener.IsListening -and -not $Script:IsExiting) {
            try {
                # Wait for a semaphore slot to be free
                if (-not $semaphore.Wait($Script:Settings.RequestTimeoutSec * 1000)) {
                    $LogQueue.Enqueue("WARN: Timed out waiting for a connection slot. Max concurrent connections may be too low.")
                    continue
                }

                # Wait for a request asynchronously with a timeout
                $asyncResult = $listener.BeginGetContext($null, $null)
                if (-not $asyncResult.AsyncWaitHandle.WaitOne($Script:Settings.RequestTimeoutSec * 1000)) {
                    $LogQueue.Enqueue("WARN: Request timed out waiting for client data.")
                    $semaphore.Release() | Out-Null
                    continue
                }
                $context = $listener.EndGetContext($asyncResult)

                # Process the request
                $request = $context.Request
                $response = $context.Response
                $filePath = ""
                $fullPath = ""
                [int]$status = 404 # Default to Not Found
                [long]$fileSize = 0

                try {
                    # --- CORS and Custom Headers ---
                    # Handle Pre-flight OPTIONS requests
                    if ($request.HttpMethod -eq 'OPTIONS') {
                        $response.AddHeader('Access-Control-Allow-Methods', 'GET, POST, OPTIONS')
                        $response.AddHeader('Access-Control-Allow-Headers', 'Content-Type')
                    }
                    # Add CORS origin header
                    if (-not [string]::IsNullOrEmpty($Script:Settings.CorsAllowedOrigins)) {
                        $response.AddHeader('Access-Control-Allow-Origin', $Script:Settings.CorsAllowedOrigins)
                    }
                    # Add custom headers
                    if (-not [string]::IsNullOrEmpty($Script:Settings.CustomResponseHeaders)) {
                        $headers = $Script:Settings.CustomResponseHeaders -split ';'
                        foreach ($header in $headers) {
                            $parts = $header -split ':', 2
                            if ($parts.Length -eq 2) {
                                $response.AddHeader($parts[0].Trim(), $parts[1].Trim())
                            }
                        }
                    }

                    if ($config.UseRootFolderMode) {
                        # ROOT FOLDER MODE LOGIC
                        $filePath = $request.Url.LocalPath.TrimStart('/')
                        if ([string]::IsNullOrEmpty($filePath) -or $filePath -eq '/') {
                            $filePath = $config.DefaultFile
                        }
                        
                        # Prevent directory traversal
                        if ($filePath.Contains('..')) {
                            throw [System.Security.SecurityException]::new("Directory traversal attempt detected.")
                        }

                        $fullPath = Join-Path -Path $config.Root -ChildPath $filePath
                    } else {
                        # SINGLE FILE MODE LOGIC
                        $filePath = [System.IO.Path]::GetFileName($config.SingleFilePath)
                        $fullPath = $config.SingleFilePath
                    }


                    if (Test-Path $fullPath -PathType Leaf) {
                        # Serve file
                        $fileStream = [System.IO.File]::OpenRead($fullPath)
                        $fileInfo = Get-Item $fullPath
                        $fileSize = $fileInfo.Length

                        $response.ContentType = [System.Web.MimeMapping]::GetMimeMapping($fullPath)
                        $response.ContentLength64 = $fileSize
                        $response.StatusCode = 200
                        $status = 200

                        $fileStream.CopyTo($response.OutputStream)
                        $fileStream.Dispose()

                    } else {
                        # 404 Not Found
                        $status = 404
                        $response.StatusCode = 404
                        $response.StatusDescription = "Not Found"
                        
                        # SPA Support: Serve index on 404
                        if ($Script:Settings.ServeIndexOn404 -and $config.UseRootFolderMode) {
                            $indexPath = Join-Path -Path $config.Root -ChildPath $config.DefaultFile
                            if (Test-Path $indexPath -PathType Leaf) {
                                $LogQueue.Enqueue("INFO: Serving index file for 404 request (SPA mode).")
                                $fileStream = [System.IO.File]::OpenRead($indexPath)
                                $fileInfo = Get-Item $indexPath
                                $fileSize = $fileInfo.Length

                                $response.ContentType = [System.Web.MimeMapping]::GetMimeMapping($indexPath)
                                $response.ContentLength64 = $fileSize
                                $response.StatusCode = 200 # Serve as 200 OK for SPA routing
                                $status = 200

                                $fileStream.CopyTo($response.OutputStream)
                                $fileStream.Dispose()
                            }
                        } else {
                             $outputBytes = $null
                            # Check for custom 404 page
                            if (-not [string]::IsNullOrEmpty($Script:Settings.Custom404PagePath) -and (Test-Path $Script:Settings.Custom404PagePath -PathType Leaf)) {
                                try {
                                    $outputBytes = [System.IO.File]::ReadAllBytes($Script:Settings.Custom404PagePath)
                                    $response.ContentType = [System.Web.MimeMapping]::GetMimeMapping($Script:Settings.Custom404PagePath)
                                } catch {
                                    $LogQueue.Enqueue("ERROR: Failed to read custom 404 page. Falling back to default. Error: $($_.Exception.Message)")
                                    $outputBytes = [System.Text.Encoding]::UTF8.GetBytes("<html><head><title>404 Not Found</title></head><body><h1>EliteServer 404</h1><p>The requested file ($filePath) was not found. Additionally, the configured custom 404 page could not be loaded.</p></body></html>")
                                    $response.ContentType = "text/html"
                                }
                            } else {
                                $outputBytes = [System.Text.Encoding]::UTF8.GetBytes("<html><head><title>404 Not Found</title></head><body><h1>EliteServer 404</h1><p>The requested file ($filePath) was not found in the root directory.</p></body></html>")
                                $response.ContentType = "text/html"
                            }

                            $response.ContentLength64 = $outputBytes.Length
                            $response.OutputStream.Write($outputBytes, 0, $outputBytes.Length)
                        }
                    }

                } catch {
                    # 500 Server Error
                    $status = 500
                    $response.StatusCode = 500
                    $response.StatusDescription = "Internal Server Error"
                    $LogQueue.Enqueue("ERROR: Request for $($filePath) failed: $($_.Exception.Message)")
                } finally {
                    $response.OutputStream.Close()
                    $semaphore.Release() | Out-Null # Release the semaphore slot
                }

                # Log the request
                $logMessage = "[$status] $($request.RemoteEndPoint.Address) - $($request.HttpMethod) /$filePath (File Size: $([Math]::Round($fileSize / 1KB, 2)) KB)"
                $LogQueue.Enqueue($logMessage)

                if ($Script:Settings.LogRequestHeaders) {
                    $headersText = $request.Headers.ToString().Trim()
                    $LogQueue.Enqueue("`tRequest Headers:`n$($headersText)")
                }

            } catch [System.Net.HttpListenerException] {
                # Listener stopped gracefully
                $semaphore.Release() | Out-Null
                break
            } catch {
                # General Thread Error
                $LogQueue.Enqueue("CRITICAL ERROR in listener loop: $($_.Exception.Message)")
                $semaphore.Release() | Out-Null
                # Exit the loop on critical error
                break
            }
        } # End while loop

        # Final cleanup outside the loop
        if ($listener.IsListening) {
             $listener.Close()
        }
        $LogQueue.Enqueue("Listener for $($config.Name) terminated.")
    }).Dispose()

    # 4. Start the Thread
    $thread.IsBackground = $true # Ensure thread stops when main process exits
    $thread.Start($listener, $config, $Script:LogQueue, $Script:IsExiting, $semaphore)

    # 5. Update Global State
    $Script:ActiveServers[$config.Name] = @{
        Listener = $listener
        Thread = $thread
        Prefix = $prefix
    }
    $config.Status = "Running"
    Update-GUIFromConfig # Update buttons/status indicator
    Save-ServerConfig
}

function Stop-Server {
    param($config)
    
    if ($Script:ActiveServers.ContainsKey($config.Name)) {
        $serverInfo = $Script:ActiveServers[$config.Name]

        # Close the listener which will cause the thread's GetContext() to fail gracefully
        $serverInfo.Listener.Stop()
        $serverInfo.Listener.Close()

        # Remove from active list
        $Script:ActiveServers.Remove($config.Name)

        $config.Status = "Stopped"
        Save-ServerConfig
        Update-GUIFromConfig

        Invoke-GUIUpdate { Write-Log "Server '$($config.Name)' stopped gracefully." }
    }
}

# ==============================================================================
# 4. UI/Event Helper Functions
# ==============================================================================

function Draw-GradientHeader {
    param(
        [Parameter(Mandatory=$true)][System.Object]$sender,
        [Parameter(Mandatory=$true)][System.Windows.Forms.PaintEventArgs]$e
    )
    # Gradient Fix: Using static new() method and explicit casting to ensure correct overload matching
    $g = $e.Graphics
    $rect = $sender.ClientRectangle
    $color1 = [System.Drawing.Color]::FromArgb(255, 0, 128, 128) # Teal
    $color2 = [System.Drawing.Color]::FromArgb(255, 128, 0, 128) # Violet

    try {
        $brush = [System.Drawing.Drawing2D.LinearGradientBrush]::new(
            $rect,
            $color1,
            $color2,
            [System.Drawing.Drawing2D.LinearGradientMode]::Horizontal
        )
    } catch {
        $brush = [System.Drawing.SolidBrush]::new($color1)
    }
    if ($brush) {
        $g.FillRectangle($brush, $rect)
        $brush.Dispose()
    }
}

function Update-ServerButtons {
    param($status)
    $StartButton.Enabled = ($status -ne "Running")
    $StopButton.Enabled = ($status -eq "Running")
    $OpenBrowserButton.Enabled = ($status -eq "Running")

    if ($status -eq "Running") {
        $StatusIndicator.Text = "Status: Running on $($PortTextBox.Text)"
        $StatusIndicator.ForeColor = [System.Drawing.Color]::Green
    } else {
        $StatusIndicator.Text = "Status: Stopped"
        $StatusIndicator.ForeColor = [System.Drawing.Color]::Red
    }
}

function Write-Log ($message) {
    if ($LogTextBox) {
        $LogTextBox.AppendText("$(Get-Date -Format 'HH:mm:ss') - $message`r`n")
        # Clean up old log lines if it gets too long
        if ($LogTextBox.Lines.Count -gt $Script:Settings.MaxLogLines) {
            $LogTextBox.Text = $LogTextBox.Text.Substring($LogTextBox.Lines[0].Length + 2)
        }
    } else {
        # Fallback to console if LogTextBox is not yet initialized
        Write-Host "$(Get-Date -Format 'HH:mm:ss') - $message"
    }

    if ($Script:Settings.LogToFile) {
        try {
            "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - $message" | Out-File -FilePath $Script:Settings.LogFilePath -Append -Encoding UTF8
        } catch {
            # Disable to prevent spamming errors
            $Script:Settings.LogToFile = $false
            Write-Log "ERROR: Could not write to log file '$($Script:Settings.LogFilePath)'. Disabling file logging. Error: $($_.Exception.Message)"
        }
    }
}

# Timer to poll the log queue and update the GUI safely
function Start-LogTimer {
    $Script:LogTimer = [System.Windows.Forms.Timer]::new()
    $Script:LogTimer.Interval = 100 # Check every 100ms
    $Script:LogTimer.Add_Tick({
        # Process log messages from the queue
        while ($Script:LogQueue.Count -gt 0) {
            $message = $Script:LogQueue.Dequeue()
            Write-Log $message
        }
    })
    $Script:LogTimer.Start()
}

function Show-GoodbyeWindow {
    param($Message)
    
    $GoodbyeForm = [System.Windows.Forms.Form]::new()
    $GoodbyeForm.Text = "Closing Application"
    $GoodbyeForm.Size = [System.Drawing.Size]::new(500, 200)
    $GoodbyeForm.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterScreen
    $GoodbyeForm.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::None
    
    # Paint the gradient directly onto the form's background
    $GoodbyeForm.Add_Paint({
        param($sender, $e)
        Draw-GradientHeader $sender $e
    })

    # Message Label (Matches Header Font/Color)
    $GoodbyeLabel = [System.Windows.Forms.Label]::new()
    $GoodbyeLabel.Text = $Message
    $GoodbyeLabel.Font = [System.Drawing.Font]::new("Segoe UI", 24, [System.Drawing.FontStyle]::Bold)
    $GoodbyeLabel.ForeColor = [System.Drawing.Color]::White
    $GoodbyeLabel.BackColor = [System.Drawing.Color]::Transparent
    $GoodbyeLabel.AutoSize = $true
    
    # Center the label
    $GoodbyeForm.Controls.Add($GoodbyeLabel)

    # Show the modal form non-blockingly
    $GoodbyeForm.Show() | Out-Null
    
    # Update label location after it has been shown and sized
    $GoodbyeLabel.Location = [System.Drawing.Point]::new(($GoodbyeForm.Width - $GoodbyeLabel.Width) / 2, ($GoodbyeForm.Height - $GoodbyeLabel.Height) / 2)

    # Use a System.Threading.Timer for non-blocking delay
    $delayTimer = [System.Threading.Timer]::new({
        $GoodbyeForm.Close()
        $Form.Close()
    }, $null, 2500, [System.Threading.Timeout]::Infinite)
    
    $GoodbyeForm.Tag = $delayTimer # Hold reference to prevent garbage collection
}

function Show-SettingsWindow {
    $SettingsForm = [System.Windows.Forms.Form]::new()
    $SettingsForm.Text = "Application Settings"
    $SettingsForm.Size = [System.Drawing.Size]::new(600, 550) # Increased height
    $SettingsForm.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterParent
    $SettingsForm.MinimizeBox = $false
    $SettingsForm.MaximizeBox = $false
    $SettingsForm.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
    $SettingsForm.BackColor = [System.Drawing.Color]::FromArgb(255, 240, 240, 240)
    $SettingsForm.Icon = $AppIcon

    # --- Header ---
    $HeaderPanel = [System.Windows.Forms.Panel]::new()
    $HeaderPanel.Dock = [System.Windows.Forms.DockStyle]::Top
    $HeaderPanel.Height = 70
    $HeaderPanel.Add_Paint({Draw-GradientHeader $HeaderPanel $_})
    $SettingsForm.Controls.Add($HeaderPanel)

    $HeaderLabel = [System.Windows.Forms.Label]::new()
    $HeaderLabel.Text = "Settings"
    $HeaderLabel.Font = [System.Drawing.Font]::new("Segoe UI", 16, [System.Drawing.FontStyle]::Bold)
    $HeaderLabel.ForeColor = [System.Drawing.Color]::White
    $HeaderLabel.AutoSize = $true
    $HeaderLabel.Location = [System.Drawing.Point]::new(20, 20)
    $HeaderLabel.BackColor = [System.Drawing.Color]::Transparent
    $HeaderPanel.Controls.Add($HeaderLabel)

    # --- Tab Control ---
    $TabControl = [System.Windows.Forms.TabControl]::new()
    $TabControl.Location = [System.Drawing.Point]::new(10, $HeaderPanel.Height + 10)
    $TabControl.Size = [System.Drawing.Size]::new($SettingsForm.ClientSize.Width - 20, $SettingsForm.ClientSize.Height - $HeaderPanel.Height - 70)
    $TabControl.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right
    $SettingsForm.Controls.Add($TabControl)

    $GeneralTabPage = [System.Windows.Forms.TabPage]::new("General")
    $AdvancedTabPage = [System.Windows.Forms.TabPage]::new("Advanced")
    $TabControl.TabPages.Add($GeneralTabPage) | Out-Null
    $TabControl.TabPages.Add($AdvancedTabPage) | Out-Null

    # =================== GENERAL SETTINGS TAB ===================
    $yPos = 20
    $xPos = 20
    $labelWidth = 200
    $controlWidth = 320

    # --- Default Root ---
    $DefaultRootLabel = [System.Windows.Forms.Label]::new()
    $DefaultRootLabel.Text = "Default Root for New Servers:"
    $DefaultRootLabel.AutoSize = $true
    $DefaultRootLabel.Location = [System.Drawing.Point]::new($xPos, $yPos + 3)
    $GeneralTabPage.Controls.Add($DefaultRootLabel)

    $DefaultRootTextBox = [System.Windows.Forms.TextBox]::new()
    $DefaultRootTextBox.Text = $Script:Settings.DefaultRoot
    $DefaultRootTextBox.Width = $controlWidth
    $DefaultRootTextBox.Location = [System.Drawing.Point]::new($xPos + $labelWidth, $yPos)
    $GeneralTabPage.Controls.Add($DefaultRootTextBox)
    $yPos += 35

    # --- Default File ---
    $DefaultFileLabel = [System.Windows.Forms.Label]::new()
    $DefaultFileLabel.Text = "Default File for New Servers:"
    $DefaultFileLabel.AutoSize = $true
    $DefaultFileLabel.Location = [System.Drawing.Point]::new($xPos, $yPos + 3)
    $GeneralTabPage.Controls.Add($DefaultFileLabel)

    $DefaultFileTextBox = [System.Windows.Forms.TextBox]::new()
    $DefaultFileTextBox.Text = $Script:Settings.DefaultFile
    $DefaultFileTextBox.Width = $controlWidth
    $DefaultFileTextBox.Location = [System.Drawing.Point]::new($xPos + $labelWidth, $yPos)
    $GeneralTabPage.Controls.Add($DefaultFileTextBox)
    $yPos += 35

    # --- Default Port ---
    $DefaultPortLabel = [System.Windows.Forms.Label]::new()
    $DefaultPortLabel.Text = "Default Port for New Servers:"
    $DefaultPortLabel.AutoSize = $true
    $DefaultPortLabel.Location = [System.Drawing.Point]::new($xPos, $yPos + 3)
    $GeneralTabPage.Controls.Add($DefaultPortLabel)

    $DefaultPortTextBox = [System.Windows.Forms.TextBox]::new()
    $DefaultPortTextBox.Text = $Script:Settings.DefaultPort
    $DefaultPortTextBox.Width = $controlWidth
    $DefaultPortTextBox.Location = [System.Drawing.Point]::new($xPos + $labelWidth, $yPos)
    $GeneralTabPage.Controls.Add($DefaultPortTextBox)
    $yPos += 35

    # --- Default IP Address ---
    $DefaultIPLabel = [System.Windows.Forms.Label]::new()
    $DefaultIPLabel.Text = "Default IP for New Servers:"
    $DefaultIPLabel.AutoSize = $true
    $DefaultIPLabel.Location = [System.Drawing.Point]::new($xPos, $yPos + 3)
    $GeneralTabPage.Controls.Add($DefaultIPLabel)

    $DefaultIPComboBox = [System.Windows.Forms.ComboBox]::new()
    $DefaultIPComboBox.Items.Add("127.0.0.1")
    $DefaultIPComboBox.Items.AddRange((Get-LocalIPv4Addresses))
    $DefaultIPComboBox.Text = $Script:Settings.DefaultIP
    $DefaultIPComboBox.Width = $controlWidth
    $DefaultIPComboBox.Location = [System.Drawing.Point]::new($xPos + $labelWidth, $yPos)
    $GeneralTabPage.Controls.Add($DefaultIPComboBox)
    $yPos += 35

    # --- Max Log Lines ---
    $MaxLogLinesLabel = [System.Windows.Forms.Label]::new()
    $MaxLogLinesLabel.Text = "Max Log Lines in GUI:"
    $MaxLogLinesLabel.AutoSize = $true
    $MaxLogLinesLabel.Location = [System.Drawing.Point]::new($xPos, $yPos + 3)
    $GeneralTabPage.Controls.Add($MaxLogLinesLabel)

    $MaxLogLinesTextBox = [System.Windows.Forms.TextBox]::new()
    $MaxLogLinesTextBox.Text = $Script:Settings.MaxLogLines
    $MaxLogLinesTextBox.Width = $controlWidth
    $MaxLogLinesTextBox.Location = [System.Drawing.Point]::new($xPos + $labelWidth, $yPos)
    $GeneralTabPage.Controls.Add($MaxLogLinesTextBox)
    $yPos += 35

    # --- Log to File Checkbox ---
    $LogToFileCheckBox = [System.Windows.Forms.CheckBox]::new()
    $LogToFileCheckBox.Text = "Enable Logging to File"
    $LogToFileCheckBox.Checked = $Script:Settings.LogToFile
    $LogToFileCheckBox.AutoSize = $true
    $LogToFileCheckBox.Location = [System.Drawing.Point]::new($xPos, $yPos)
    $GeneralTabPage.Controls.Add($LogToFileCheckBox)
    $yPos += 30

    # --- Log File Path ---
    $LogFilePathLabel = [System.Windows.Forms.Label]::new()
    $LogFilePathLabel.Text = "Log File Path:"
    $LogFilePathLabel.AutoSize = $true
    $LogFilePathLabel.Location = [System.Drawing.Point]::new($xPos, $yPos + 3)
    $GeneralTabPage.Controls.Add($LogFilePathLabel)

    $LogFilePathTextBox = [System.Windows.Forms.TextBox]::new()
    $LogFilePathTextBox.Text = $Script:Settings.LogFilePath
    $LogFilePathTextBox.Width = $controlWidth
    $LogFilePathTextBox.Location = [System.Drawing.Point]::new($xPos + $labelWidth, $yPos)
    $GeneralTabPage.Controls.Add($LogFilePathTextBox)
    $yPos += 35

    # --- Show Goodbye Window Checkbox ---
    $ShowGoodbyeCheckBox = [System.Windows.Forms.CheckBox]::new()
    $ShowGoodbyeCheckBox.Text = "Show Goodbye Window on Exit"
    $ShowGoodbyeCheckBox.Checked = $Script:Settings.ShowGoodbyeWindow
    $ShowGoodbyeCheckBox.AutoSize = $true
    $ShowGoodbyeCheckBox.Location = [System.Drawing.Point]::new($xPos, $yPos)
    $GeneralTabPage.Controls.Add($ShowGoodbyeCheckBox)
    $yPos += 30

    # --- Hide Console Window Checkbox ---
    $HideConsoleCheckBox = [System.Windows.Forms.CheckBox]::new()
    $HideConsoleCheckBox.Text = "Hide Console Window on Next Launch"
    $HideConsoleCheckBox.Checked = $Script:Settings.HideConsoleOnLaunch
    $HideConsoleCheckBox.AutoSize = $true
    $HideConsoleCheckBox.Location = [System.Drawing.Point]::new($xPos, $yPos)
    $GeneralTabPage.Controls.Add($HideConsoleCheckBox)

    # =================== ADVANCED SETTINGS TAB ===================
    $yPos = 20 # Reset Y for new tab

    # --- Enable Directory Listing ---
    $DirListingCheckBox = [System.Windows.Forms.CheckBox]::new()
    $DirListingCheckBox.Text = "Enable Directory Listing"
    $DirListingCheckBox.Checked = $Script:Settings.DirectoryListingEnabled
    $DirListingCheckBox.AutoSize = $true
    $DirListingCheckBox.Location = [System.Drawing.Point]::new($xPos, $yPos)
    $AdvancedTabPage.Controls.Add($DirListingCheckBox)
    $yPos += 30

    # --- Enable Keep-Alive ---
    $KeepAliveCheckBox = [System.Windows.Forms.CheckBox]::new()
    $KeepAliveCheckBox.Text = "Enable HTTP Keep-Alive"
    $KeepAliveCheckBox.Checked = $Script:Settings.EnableKeepAlive
    $KeepAliveCheckBox.AutoSize = $true
    $KeepAliveCheckBox.Location = [System.Drawing.Point]::new($xPos, $yPos)
    $AdvancedTabPage.Controls.Add($KeepAliveCheckBox)
    $yPos += 30

    # --- Log Request Headers ---
    $LogHeadersCheckBox = [System.Windows.Forms.CheckBox]::new()
    $LogHeadersCheckBox.Text = "Log Full Request Headers (Verbose)"
    $LogHeadersCheckBox.Checked = $Script:Settings.LogRequestHeaders
    $LogHeadersCheckBox.AutoSize = $true
    $LogHeadersCheckBox.Location = [System.Drawing.Point]::new($xPos, $yPos)
    $AdvancedTabPage.Controls.Add($LogHeadersCheckBox)
    $yPos += 35

    # --- Custom 404 Page ---
    $Custom404Label = [System.Windows.Forms.Label]::new()
    $Custom404Label.Text = "Custom 404 Error Page:"
    $Custom404Label.AutoSize = $true
    $Custom404Label.Location = [System.Drawing.Point]::new($xPos, $yPos + 3)
    $AdvancedTabPage.Controls.Add($Custom404Label)

    $Custom404TextBox = [System.Windows.Forms.TextBox]::new()
    $Custom404TextBox.Text = $Script:Settings.Custom404PagePath
    $Custom404TextBox.Width = $controlWidth - 100
    $Custom404TextBox.Location = [System.Drawing.Point]::new($xPos + $labelWidth, $yPos)
    $AdvancedTabPage.Controls.Add($Custom404TextBox)

    $Custom404BrowseButton = [System.Windows.Forms.Button]::new()
    $Custom404BrowseButton.Text = "Browse..."
    $Custom404BrowseButton.Size = [System.Drawing.Size]::new(90, 25)
    $Custom404BrowseButton.Location = [System.Drawing.Point]::new($Custom404TextBox.Right + 10, $yPos - 2)
    $Custom404BrowseButton.FlatStyle = [System.Windows.Forms.FlatStyle]::System
    $Custom404BrowseButton.Add_Click({
        $FileBrowser = [System.Windows.Forms.OpenFileDialog]::new()
        $FileBrowser.Filter = "HTML Files (*.html, *.htm)|*.html;*.htm|All files (*.*)|*.*"
        if ($FileBrowser.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
            $Custom404TextBox.Text = $FileBrowser.FileName
        }
    })
    $AdvancedTabPage.Controls.Add($Custom404BrowseButton)
    $yPos += 35

    # --- MIME Type Overrides ---
    $MimeTypesLabel = [System.Windows.Forms.Label]::new()
    $MimeTypesLabel.Text = "MIME Type Overrides:"
    $MimeTypesLabel.AutoSize = $true
    $MimeTypesLabel.Location = [System.Drawing.Point]::new($xPos, $yPos + 3)
    $AdvancedTabPage.Controls.Add($MimeTypesLabel)

    $MimeTypesTextBox = [System.Windows.Forms.TextBox]::new()
    $MimeTypesTextBox.Text = $Script:Settings.MimeTypeOverrides
    $MimeTypesTextBox.Width = $controlWidth
    $MimeTypesTextBox.Location = [System.Drawing.Point]::new($xPos + $labelWidth, $yPos)
    $AdvancedTabPage.Controls.Add($MimeTypesTextBox)
    $yPos += 35

    $MimeTypesHelpLabel = [System.Windows.Forms.Label]::new()
    $MimeTypesHelpLabel.Text = "(Format: ext=type;ext2=type2)"
    $MimeTypesHelpLabel.AutoSize = $true
    $MimeTypesHelpLabel.ForeColor = [System.Drawing.Color]::Gray
    $MimeTypesHelpLabel.Location = [System.Drawing.Point]::new($xPos + $labelWidth, $yPos)
    $AdvancedTabPage.Controls.Add($MimeTypesHelpLabel)
    $yPos += 35

    # --- CORS Allowed Origins ---
    $CorsLabel = [System.Windows.Forms.Label]::new()
    $CorsLabel.Text = "CORS Allowed Origins:"
    $CorsLabel.AutoSize = $true
    $CorsLabel.Location = [System.Drawing.Point]::new($xPos, $yPos + 3)
    $AdvancedTabPage.Controls.Add($CorsLabel)

    $CorsTextBox = [System.Windows.Forms.TextBox]::new()
    $CorsTextBox.Text = $Script:Settings.CorsAllowedOrigins
    $CorsTextBox.Width = $controlWidth
    $CorsTextBox.Location = [System.Drawing.Point]::new($xPos + $labelWidth, $yPos)
    $AdvancedTabPage.Controls.Add($CorsTextBox)
    $yPos += 35

    # --- Custom Response Headers ---
    $CustomHeadersLabel = [System.Windows.Forms.Label]::new()
    $CustomHeadersLabel.Text = "Custom Response Headers:"
    $CustomHeadersLabel.AutoSize = $true
    $CustomHeadersLabel.Location = [System.Drawing.Point]::new($xPos, $yPos + 3)
    $AdvancedTabPage.Controls.Add($CustomHeadersLabel)

    $CustomHeadersTextBox = [System.Windows.Forms.TextBox]::new()
    $CustomHeadersTextBox.Text = $Script:Settings.CustomResponseHeaders
    $CustomHeadersTextBox.Width = $controlWidth
    $CustomHeadersTextBox.Location = [System.Drawing.Point]::new($xPos + $labelWidth, $yPos)
    $AdvancedTabPage.Controls.Add($CustomHeadersTextBox)
    $yPos += 35

    # --- Request Timeout ---
    $RequestTimeoutLabel = [System.Windows.Forms.Label]::new()
    $RequestTimeoutLabel.Text = "Request Timeout (seconds):"
    $RequestTimeoutLabel.AutoSize = $true
    $RequestTimeoutLabel.Location = [System.Drawing.Point]::new($xPos, $yPos + 3)
    $AdvancedTabPage.Controls.Add($RequestTimeoutLabel)

    $RequestTimeoutTextBox = [System.Windows.Forms.TextBox]::new()
    $RequestTimeoutTextBox.Text = $Script:Settings.RequestTimeoutSec
    $RequestTimeoutTextBox.Width = $controlWidth
    $RequestTimeoutTextBox.Location = [System.Drawing.Point]::new($xPos + $labelWidth, $yPos)
    $AdvancedTabPage.Controls.Add($RequestTimeoutTextBox)
    $yPos += 35

    # --- Max Concurrent Connections ---
    $MaxConnectionsLabel = [System.Windows.Forms.Label]::new()
    $MaxConnectionsLabel.Text = "Max Concurrent Connections:"
    $MaxConnectionsLabel.AutoSize = $true
    $MaxConnectionsLabel.Location = [System.Drawing.Point]::new($xPos, $yPos + 3)
    $AdvancedTabPage.Controls.Add($MaxConnectionsLabel)

    $MaxConnectionsTextBox = [System.Windows.Forms.TextBox]::new()
    $MaxConnectionsTextBox.Text = $Script:Settings.MaxConcurrentConnections
    $MaxConnectionsTextBox.Width = $controlWidth
    $MaxConnectionsTextBox.Location = [System.Drawing.Point]::new($xPos + $labelWidth, $yPos)
    $AdvancedTabPage.Controls.Add($MaxConnectionsTextBox)
    $yPos += 35

    # --- Serve Index on 404 ---
    $ServeIndexOn404CheckBox = [System.Windows.Forms.CheckBox]::new()
    $ServeIndexOn404CheckBox.Text = "Serve Index File on 404 (for SPAs)"
    $ServeIndexOn404CheckBox.Checked = $Script:Settings.ServeIndexOn404
    $ServeIndexOn404CheckBox.AutoSize = $true
    $ServeIndexOn404CheckBox.Location = [System.Drawing.Point]::new($xPos, $yPos)
    $AdvancedTabPage.Controls.Add($ServeIndexOn404CheckBox)

    # --- Save and Cancel Buttons ---
    $SaveButton = [System.Windows.Forms.Button]::new()
    $SaveButton.Text = "Save"
    $SaveButton.DialogResult = [System.Windows.Forms.DialogResult]::OK
    $SaveButton.Location = [System.Drawing.Point]::new($SettingsForm.ClientSize.Width - 180, $SettingsForm.ClientSize.Height - 45)
    $SaveButton.Anchor = [System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Right
    $SaveButton.FlatStyle = [System.Windows.Forms.FlatStyle]::System
    $SettingsForm.Controls.Add($SaveButton)

    $CancelButton = [System.Windows.Forms.Button]::new()
    $CancelButton.Text = "Cancel"
    $CancelButton.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    $CancelButton.Location = [System.Drawing.Point]::new($SettingsForm.ClientSize.Width - 95, $SettingsForm.ClientSize.Height - 45)
    $CancelButton.Anchor = [System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Right
    $CancelButton.FlatStyle = [System.Windows.Forms.FlatStyle]::System
    $SettingsForm.Controls.Add($CancelButton)

    $SettingsForm.AcceptButton = $SaveButton
    $SettingsForm.CancelButton = $CancelButton

    if ($SettingsForm.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        # Save General settings
        $Script:Settings.DefaultRoot = $DefaultRootTextBox.Text
        $Script:Settings.DefaultFile = $DefaultFileTextBox.Text
        $Script:Settings.DefaultPort = [int]$DefaultPortTextBox.Text
        $Script:Settings.DefaultIP = $DefaultIPComboBox.Text
        $Script:Settings.MaxLogLines = [int]$MaxLogLinesTextBox.Text
        $Script:Settings.LogToFile = $LogToFileCheckBox.Checked
        $Script:Settings.LogFilePath = $LogFilePathTextBox.Text
        $Script:Settings.ShowGoodbyeWindow = $ShowGoodbyeCheckBox.Checked
        $Script:Settings.HideConsoleOnLaunch = $HideConsoleCheckBox.Checked

        # Save Advanced settings
        $Script:Settings.DirectoryListingEnabled = $DirListingCheckBox.Checked
        $Script:Settings.Custom404PagePath = $Custom404TextBox.Text
        $Script:Settings.LogRequestHeaders = $LogHeadersCheckBox.Checked
        $Script:Settings.MimeTypeOverrides = $MimeTypesTextBox.Text
        $Script:Settings.EnableKeepAlive = $KeepAliveCheckBox.Checked
        $Script:Settings.CorsAllowedOrigins = $CorsTextBox.Text
        $Script:Settings.CustomResponseHeaders = $CustomHeadersTextBox.Text
        $Script:Settings.RequestTimeoutSec = [int]$RequestTimeoutTextBox.Text
        $Script:Settings.MaxConcurrentConnections = [int]$MaxConnectionsTextBox.Text
        $Script:Settings.ServeIndexOn404 = $ServeIndexOn404CheckBox.Checked

        Save-Settings
        Write-Log "Application settings saved."
    }

    $SettingsForm.Dispose()
}

function Show-HelpGuideWindow {
    $HelpForm = [System.Windows.Forms.Form]::new()
    $HelpForm.Text = "Help Guide"
    $HelpForm.Size = [System.Drawing.Size]::new(700, 600) # Made window larger
    $HelpForm.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterParent
    $HelpForm.MinimizeBox = $false
    $HelpForm.MaximizeBox = $false
    $HelpForm.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
    $HelpForm.BackColor = [System.Drawing.Color]::White
    $HelpForm.Icon = $AppIcon # Added application icon

    # --- Header ---
    $HeaderPanel = [System.Windows.Forms.Panel]::new()
    $HeaderPanel.Dock = [System.Windows.Forms.DockStyle]::Top
    $HeaderPanel.Height = 70
    $HeaderPanel.Add_Paint({Draw-GradientHeader $HeaderPanel $_})
    $HelpForm.Controls.Add($HeaderPanel)

    $HeaderLabel = [System.Windows.Forms.Label]::new()
    $HeaderLabel.Text = "EliteSoftware HTTP Test Server - Help Guide"
    $HeaderLabel.Font = [System.Drawing.Font]::new("Segoe UI", 14, [System.Drawing.FontStyle]::Bold)
    $HeaderLabel.ForeColor = [System.Drawing.Color]::White
    $HeaderLabel.AutoSize = $true
    $HeaderLabel.Location = [System.Drawing.Point]::new(20, 20)
    $HeaderLabel.BackColor = [System.Drawing.Color]::Transparent
    $HeaderPanel.Controls.Add($HeaderLabel)

    # --- RichTextBox for content ---
    $HelpTextBox = [System.Windows.Forms.RichTextBox]::new()
    $HelpTextBox.ReadOnly = $true
    $HelpTextBox.BorderStyle = [System.Windows.Forms.BorderStyle]::None
    $HelpTextBox.ScrollBars = [System.Windows.Forms.RichTextBoxScrollBars]::Vertical
    $HelpTextBox.BackColor = $HelpForm.BackColor # Blend with form background

    # --- Close Button ---
    $CloseButton = [System.Windows.Forms.Button]::new()
    $CloseButton.Text = "Close"
    $CloseButton.Size = [System.Drawing.Size]::new(90, 30)
    $CloseButton.FlatStyle = [System.Windows.Forms.FlatStyle]::System
    $CloseButton.Location = [System.Drawing.Point]::new($HelpForm.ClientSize.Width - $CloseButton.Width - 15, $HelpForm.ClientSize.Height - $CloseButton.Height - 10)
    $CloseButton.Anchor = [System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Right
    $CloseButton.Add_Click({ $HelpForm.Close() })
    $HelpForm.Controls.Add($CloseButton)
    $HelpForm.CancelButton = $CloseButton # Allow Esc key to close

    # Set location and size to create padding, and anchor it
    $leftPadding = 20
    $HelpTextBox.Location = [System.Drawing.Point]::new($leftPadding, $HeaderPanel.Height)
    $HelpTextBox.Size = [System.Drawing.Size]::new($HelpForm.ClientSize.Width - $leftPadding, $HelpForm.ClientSize.Height - $HeaderPanel.Height - $CloseButton.Height - 20)
    $HelpTextBox.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right
    $HelpForm.Controls.Add($HelpTextBox)

    # --- Define Fonts ---
    $headingFont = [System.Drawing.Font]::new("Segoe UI", 11, [System.Drawing.FontStyle]::Bold)
    $bodyFont = [System.Drawing.Font]::new("Segoe UI", 10)
    $headingColor = [System.Drawing.Color]::FromArgb(255, 0, 128, 128) # Teal

    # --- Helper function to append formatted text ---
    $AppendText = {
        param($Text, $Font, $Color = [System.Drawing.Color]::Black, $AddNewLine = $true)
        $HelpTextBox.SelectionStart = $HelpTextBox.TextLength
        $HelpTextBox.SelectionLength = 0
        $HelpTextBox.SelectionFont = $Font
        $HelpTextBox.SelectionColor = $Color
        $HelpTextBox.AppendText($Text + $(if ($AddNewLine) { "`r`n" } else { "" }))
    }

    # --- Build the Help Document ---
    $HelpTextBox.Clear()

    # --- Helper function to append formatted text ---
    $AppendText = {
        param($Text, $Font, $Color = [System.Drawing.Color]::Black, $AddNewLine = $true, $IsListItem = $false)
        $HelpTextBox.SelectionStart = $HelpTextBox.TextLength
        $HelpTextBox.SelectionLength = 0
        $HelpTextBox.SelectionFont = $Font
        $HelpTextBox.SelectionColor = $Color
        if ($IsListItem) {
            $HelpTextBox.SelectionBullet = $true
            $HelpTextBox.SelectionIndent = 20
        }
        $HelpTextBox.AppendText($Text + $(if ($AddNewLine) { "`r`n" } else { "" }))
        if ($IsListItem) {
            $HelpTextBox.SelectionBullet = $false
            $HelpTextBox.SelectionIndent = 0
        }
    }

    # Introduction
    & $AppendText -Text "Welcome to the EliteSoftware HTTP Test Server! This guide explains how to use the application's features." -Font $bodyFont
    & $AppendText -Text "" -Font $bodyFont

    # Section 1: Server Configurations
    & $AppendText -Text "1. Managing Server Configurations" -Font $headingFont -Color $headingColor
    & $AppendText -Text "The panel on the left allows you to save and manage multiple server configurations. All settings on the right (port, IP, file paths, etc.) are saved per-server." -Font $bodyFont
    & $AppendText -Text "Add a Server:" -Font $bodyFont -IsListItem $true
    & $AppendText -Text "   Go to File > New Server Configuration. A new server with default settings will be created." -Font $bodyFont
    & $AppendText -Text "Switch Servers:" -Font $bodyFont -IsListItem $true
    & $AppendText -Text "   Simply click on a server name in the list to load its configuration." -Font $bodyFont
    & $AppendText -Text "Rename/Duplicate:" -Font $bodyFont -IsListItem $true
    & $AppendText -Text "   Right-click a server in the list to access options for duplicating or renaming it." -Font $bodyFont
    & $AppendText -Text "Start/Stop from List:" -Font $bodyFont -IsListItem $true
    & $AppendText -Text "   You can also start or stop a server directly from the right-click context menu." -Font $bodyFont
    & $AppendText -Text "" -Font $bodyFont

    # Section 2: Server Modes
    & $AppendText -Text "2. Server Modes" -Font $headingFont -Color $headingColor
    & $AppendText -Text "This application provides two primary modes for serving files:" -Font $bodyFont
    & $AppendText -Text "" -Font $bodyFont
    & $AppendText -Text "a) Single File Mode (Default)" -Font $bodyFont
    & $AppendText -Text "   Use this mode to quickly serve a single HTML file. The server will always respond with the content of this one file, regardless of the URL path requested. Ideal for simple tests or single-page applications." -Font $bodyFont
    & $AppendText -Text "   How to use:" -Font $bodyFont
    & $AppendText -Text "     1. Ensure 'Use Root Folder Mode' is UNCHECKED." -Font $bodyFont
    & $AppendText -Text "     2. Click 'Browse...' next to 'Single HTML File to Serve' to select your file." -Font $bodyFont
    & $AppendText -Text "     3. Set your Port and IP, then click 'Start Server'." -Font $bodyFont
    & $AppendText -Text "" -Font $bodyFont
    & $AppendText -Text "b) Root Folder Mode" -Font $bodyFont
    & $AppendText -Text "   Use this mode to simulate a traditional web server. It serves files from a directory structure, mapping URL paths to files and folders within your selected root. Essential for testing multi-page websites." -Font $bodyFont
    & $AppendText -Text "   How to use:" -Font $bodyFont
    & $AppendText -Text "     1. CHECK the 'Use Root Folder Mode' box." -Font $bodyFont
    & $AppendText -Text "     2. Click 'Browse...' next to 'Server Root Folder' to select the main folder for your website." -Font $bodyFont
    & $AppendText -Text "     3. Specify the 'Default File Name' (e.g., index.html) to be served for root requests ('/')." -Font $bodyFont
    & $AppendText -Text "     4. Set your Port and IP, then click 'Start Server'." -Font $bodyFont
    & $AppendText -Text "" -Font $bodyFont

    # Section 3: Main Controls
    & $AppendText -Text "3. Main Controls" -Font $headingFont -Color $headingColor
    & $AppendText -Text "Auto-Start This Server on Launch:" -Font $bodyFont -IsListItem $true
    & $AppendText -Text "   If checked, this specific server configuration will attempt to start automatically when the application launches." -Font $bodyFont
    & $AppendText -Text "IP Address to Bind:" -Font $bodyFont -IsListItem $true
    & $AppendText -Text "   The network interface to use. '127.0.0.1' is for local machine access only. Select a specific IP to allow other devices on your network to connect." -Font $bodyFont
    & $AppendText -Text "Server Port:" -Font $bodyFont -IsListItem $true
    & $AppendText -Text "   The network port the server will listen on. If the port is in use, the server will automatically try the next available port." -Font $bodyFont
    & $AppendText -Text "Start/Stop/Open Buttons:" -Font $bodyFont -IsListItem $true
    & $AppendText -Text "   These control the currently selected server and allow you to open its URL in your default web browser." -Font $bodyFont
    & $AppendText -Text "Log Window:" -Font $bodyFont -IsListItem $true
    & $AppendText -Text "   Displays live server activity, including requests, status codes, file sizes, and errors." -Font $bodyFont
    & $AppendText -Text "" -Font $bodyFont

    # Section 4: Settings
    & $AppendText -Text "4. Application Settings (File > Settings...)" -Font $headingFont -Color $headingColor
    & $AppendText -Text "Settings are organized into General and Advanced tabs and apply globally." -Font $bodyFont
    & $AppendText -Text "" -Font $bodyFont
    & $AppendText -Text "a) General Settings" -Font $bodyFont
    & $AppendText -Text "Default Root/File/Port/IP:" -Font $bodyFont -IsListItem $true
    & $AppendText -Text "   Sets the default values for newly created server configurations." -Font $bodyFont
    & $AppendText -Text "Max Log Lines:" -Font $bodyFont -IsListItem $true
    & $AppendText -Text "   Controls how many lines are kept in the log window to prevent performance issues." -Font $bodyFont
    & $AppendText -Text "Enable Logging to File:" -Font $bodyFont -IsListItem $true
    & $AppendText -Text "   When checked, all log entries are also written to the specified file path." -Font $bodyFont
    & $AppendText -Text "Hide Console Window:" -Font $bodyFont -IsListItem $true
    & $AppendText -Text "   If checked, the black PowerShell console window will be hidden the next time you launch the application." -Font $bodyFont
    & $AppendText -Text "" -Font $bodyFont

    & $AppendText -Text "b) Advanced Settings" -Font $bodyFont
    & $AppendText -Text "Enable Directory Listing:" -Font $bodyFont -IsListItem $true
    & $AppendText -Text "   (NOT YET IMPLEMENTED) When a user requests a directory instead of a file, this will show a list of its contents." -Font $bodyFont
    & $AppendText -Text "Custom 404 Error Page:" -Font $bodyFont -IsListItem $true
    & $AppendText -Text "   Specify a path to an HTML file that will be served whenever a requested file is not found (404 error)." -Font $bodyFont
    & $AppendText -Text "Log Full Request Headers:" -Font $bodyFont -IsListItem $true
    & $AppendText -Text "   A verbose option for debugging. When checked, the full HTTP headers of every incoming request will be printed to the log." -Font $bodyFont
    & $AppendText -Text "MIME Type Overrides:" -Font $bodyFont -IsListItem $true
    & $AppendText -Text "   (NOT YET IMPLEMENTED) Manually define content types for specific file extensions (e.g., 'log=text/plain')." -Font $bodyFont
    & $AppendText -Text "Enable HTTP Keep-Alive:" -Font $bodyFont -IsListItem $true
    & $AppendText -Text "   (NOT YET IMPLEMENTED) Allows clients to reuse the same TCP connection for multiple requests, improving performance." -Font $bodyFont
    & $AppendText -Text "" -Font $bodyFont

    # Version Info
    & $AppendText -Text "Version: $ScriptVersion" -Font $bodyFont
    & $AppendText -Text "Created by Zachary Whiteman & GitHub Copilot" -Font $bodyFont

    $HelpForm.Controls.Add($HelpTextBox)

    $HelpForm.ShowDialog() | Out-Null
    $HelpForm.Dispose()
}

# ==============================================================================
# 5. Form and Control Setup
# ==============================================================================

# Load configs and initialize icon before creating form
Load-Settings
Load-ServerConfigs
$AppIcon = Get-AppIcon

# Create the main form
$Form = [System.Windows.Forms.Form]::new()
$Form.Text = "EliteSoftware HTML-HTTP Test Server"
$Form.Size = [System.Drawing.Size]::new($FormWidth, $FormHeight)
$Form.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterScreen
$Form.MinimizeBox = $true
$Form.MaximizeBox = $false
$Form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedSingle
$Form.BackColor = [System.Drawing.Color]::FromArgb(255, 240, 240, 240) # Light grey background
$Form.Icon = $AppIcon

# --- Menu Strip (Top) ---
$MenuStrip = [System.Windows.Forms.MenuStrip]::new()
$MenuStrip.BackColor = [System.Drawing.Color]::FromArgb(255, 220, 220, 220) # Light Gray

# File Menu
$FileMenuItem = [System.Windows.Forms.ToolStripMenuItem]::new("File")
$NewMenuItem = [System.Windows.Forms.ToolStripMenuItem]::new("New Server Configuration")
$SettingsMenuItem = [System.Windows.Forms.ToolStripMenuItem]::new("Settings...")
$ExitMenuItem = [System.Windows.Forms.ToolStripMenuItem]::new("Exit")

$FileMenuItem.DropDownItems.Add($NewMenuItem) | Out-Null
$FileMenuItem.DropDownItems.Add("-") | Out-Null
$FileMenuItem.DropDownItems.Add($SettingsMenuItem) | Out-Null
$SettingsMenuItem.Add_Click({ Show-SettingsWindow })
$FileMenuItem.DropDownItems.Add("-") | Out-Null
$FileMenuItem.DropDownItems.Add($ExitMenuItem) | Out-Null
$MenuStrip.Items.Add($FileMenuItem) | Out-Null

# Help Menu
$HelpMenuItem = [System.Windows.Forms.ToolStripMenuItem]::new("Help")
$ViewHelpMenuItem = [System.Windows.Forms.ToolStripMenuItem]::new("View Help Guide")
$ViewHelpMenuItem.Add_Click({ Show-HelpGuideWindow })
$HelpMenuItem.DropDownItems.Add($ViewHelpMenuItem) | Out-Null
$MenuStrip.Items.Add($HelpMenuItem) | Out-Null


$Form.Controls.Add($MenuStrip)

# --- Sidebar Panel (Left) ---
$SidebarPanel = [System.Windows.Forms.Panel]::new()
$SidebarPanel.Dock = [System.Windows.Forms.DockStyle]::Left
$SidebarPanel.Width = $SidebarWidth
$SidebarPanel.BackColor = [System.Drawing.Color]::FromArgb(255, 220, 220, 220) # Light Gray sidebar
$Form.Controls.Add($SidebarPanel)

$SidebarTitle = [System.Windows.Forms.Label]::new()
$SidebarTitle.Text = "Server Configurations"
$SidebarTitle.Font = [System.Drawing.Font]::new("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
$SidebarTitle.AutoSize = $true
$SidebarTitle.Location = [System.Drawing.Point]::new(10, 5)
$SidebarPanel.Controls.Add($SidebarTitle)

$SidebarList = [System.Windows.Forms.ListBox]::new()
$SidebarList.Location = [System.Drawing.Point]::new(10, 30)
$SidebarList.Width = $SidebarWidth - 20
$SidebarList.Height = $FormHeight - 100
$SidebarList.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Left

# Populate sidebar list
$Script:ServerConfigs | ForEach-Object {
    [void]$SidebarList.Items.Add($_.Name)
}

$SidebarPanel.Controls.Add($SidebarList)

# Sidebar selection change handler
$SidebarList.Add_SelectedIndexChanged({
    Update-ConfigFromGUI # Save the old config before changing
    $Script:CurrentConfigIndex = $SidebarList.SelectedIndex
    Update-GUIFromConfig # Load the new config
    Write-Log "Configuration loaded: $($Script:ServerConfigs[$Script:CurrentConfigIndex].Name)"
})
# Select the first item initially
if ($SidebarList.Items.Count -gt 0) {
    $SidebarList.SelectedIndex = 0
}

# --- Context Menu for Sidebar ---
$SidebarContextMenu = [System.Windows.Forms.ContextMenuStrip]::new()

$DuplicateMenuItem = [System.Windows.Forms.ToolStripMenuItem]::new("Duplicate Configuration")
$RenameMenuItem = [System.Windows.Forms.ToolStripMenuItem]::new("Rename Configuration")
$StartServerMenuItem = [System.Windows.Forms.ToolStripMenuItem]::new("Start Server")
$StopServerMenuItem = [System.Windows.Forms.ToolStripMenuItem]::new("Stop Server")

$SidebarContextMenu.Items.Add($DuplicateMenuItem) | Out-Null
$SidebarContextMenu.Items.Add($RenameMenuItem) | Out-Null
$SidebarContextMenu.Items.Add("-") | Out-Null # Separator
$SidebarContextMenu.Items.Add($StartServerMenuItem) | Out-Null
$SidebarContextMenu.Items.Add($StopServerMenuItem) | Out-Null

$SidebarList.ContextMenuStrip = $SidebarContextMenu

# Tooltip for sidebar items
$SidebarToolTip = [System.Windows.Forms.ToolTip]::new()
$SidebarToolTip.InitialDelay = 500
$SidebarToolTip.ReshowDelay = 500
$SidebarToolTip.AutoPopDelay = 5000

$SidebarList.Add_MouseMove({
    param($sender, $e)
    $index = $sender.IndexFromPoint($e.Location)
    if ($index -ge 0 -and $index -lt $Script:ServerConfigs.Count) {
        $config = $Script:ServerConfigs[$index]
        $tooltipText = "URL: http://$($config.IP):$($config.Port)/`nRoot: $($config.Root)"
        if ($SidebarToolTip.GetToolTip($sender) -ne $tooltipText) {
            $SidebarToolTip.SetToolTip($sender, $tooltipText)
        }
    } else {
        $SidebarToolTip.SetToolTip($sender, "")
    }
})

# --- Main Content Panel (Right) ---
$ContentPanel = [System.Windows.Forms.Panel]::new()
$ContentPanel.Location = [System.Drawing.Point]::new($SidebarWidth, $MenuStrip.Height)
$ContentPanel.Width = $FormWidth - $SidebarWidth
$ContentPanel.Height = $FormHeight - $MenuStrip.Height
$Form.Controls.Add($ContentPanel)

# Create Header Panel
$HeaderPanel = [System.Windows.Forms.Panel]::new()
$HeaderPanel.Dock = [System.Windows.Forms.DockStyle]::Top
$HeaderPanel.Height = 70
$HeaderPanel.Add_Paint({Draw-GradientHeader $HeaderPanel $_}) # Attach the custom draw function
$ContentPanel.Controls.Add($HeaderPanel)

# Header Title
$HeaderLabel = [System.Windows.Forms.Label]::new()
$HeaderLabel.Text = "EliteSoftware HTML-HTTP Test Server"
$HeaderLabel.Font = [System.Drawing.Font]::new("Segoe UI", 16, [System.Drawing.FontStyle]::Bold)
$HeaderLabel.ForeColor = [System.Drawing.Color]::White
$HeaderLabel.AutoSize = $true
$HeaderLabel.Location = [System.Drawing.Point]::new(20, 20)
$HeaderLabel.BackColor = [System.Drawing.Color]::Transparent
$HeaderPanel.Controls.Add($HeaderLabel)

# --- Auto-Start Checkbox ---
$yPos = 80
$AutoStartCheckBox = [System.Windows.Forms.CheckBox]::new()
$AutoStartCheckBox.Text = "Auto-Start This Server on Launch"
$AutoStartCheckBox.AutoSize = $true
$AutoStartCheckBox.Font = [System.Drawing.Font]::new("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
$AutoStartCheckBox.Location = [System.Drawing.Point]::new([int]$xStart, $yPos)
$ContentPanel.Controls.Add($AutoStartCheckBox)
$yPos += 30

# --- Mode Selection Checkbox ---
$RootModeCheckBox = [System.Windows.Forms.CheckBox]::new()
$RootModeCheckBox.Text = "Use Root Folder Mode"
$RootModeCheckBox.AutoSize = $true
$RootModeCheckBox.Font = [System.Drawing.Font]::new("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
$RootModeCheckBox.Location = [System.Drawing.Point]::new([int]$xStart, $yPos)
$ContentPanel.Controls.Add($RootModeCheckBox)
$yPos += 35 # Increased spacing

# --- Server Root Folder Controls (Root Mode) ---
$RootLabel = [System.Windows.Forms.Label]::new()
$RootLabel.Text = "Server Root Folder:"
$RootLabel.Font = [System.Drawing.Font]::new("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
$RootLabel.AutoSize = $true
$RootLabel.Location = [System.Drawing.Point]::new([int]$xStart, $yPos)
$ContentPanel.Controls.Add($RootLabel)

$RootTextBox = [System.Windows.Forms.TextBox]::new()
$RootTextBox.Width = 320
$RootTextBox.Location = [System.Drawing.Point]::new([int]$xStart, ($yPos + 25))
$ContentPanel.Controls.Add($RootTextBox)

$BrowseButton = [System.Windows.Forms.Button]::new()
$BrowseButton.Text = "Browse..."
$BrowseButton.Width = 100
$BrowseButton.Height = 25
$BrowseButton.Location = [System.Drawing.Point]::new(([int]$xStart + 330), ($yPos + 25))
$BrowseButton.FlatStyle = [System.Windows.Forms.FlatStyle]::System
$ContentPanel.Controls.Add($BrowseButton)

# --- Single HTML File Controls (Single File Mode) ---
$SingleFileLabel = [System.Windows.Forms.Label]::new()
$SingleFileLabel.Text = "Single HTML File to Serve:"
$SingleFileLabel.Font = [System.Drawing.Font]::new("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
$SingleFileLabel.AutoSize = $true
$SingleFileLabel.Location = [System.Drawing.Point]::new([int]$xStart, $yPos)
$ContentPanel.Controls.Add($SingleFileLabel)

$SingleFileTextBox = [System.Windows.Forms.TextBox]::new()
$SingleFileTextBox.Width = 320
$SingleFileTextBox.Location = [System.Drawing.Point]::new([int]$xStart, ($yPos + 25))
$ContentPanel.Controls.Add($SingleFileTextBox)

$SingleFileBrowseButton = [System.Windows.Forms.Button]::new()
$SingleFileBrowseButton.Text = "Browse..."
$SingleFileBrowseButton.Width = 100
$SingleFileBrowseButton.Height = 25
$SingleFileBrowseButton.Location = [System.Drawing.Point]::new(([int]$xStart + 330), ($yPos + 25))
$SingleFileBrowseButton.FlatStyle = [System.Windows.Forms.FlatStyle]::System
$ContentPanel.Controls.Add($SingleFileBrowseButton)


# --- Default File Name Controls ---
$yPos += 60 # Corrected Y position
$DefaultFileLabel = [System.Windows.Forms.Label]::new()
$DefaultFileLabel.Text = "Default File Name (e.g., index.html):"
$DefaultFileLabel.Font = [System.Drawing.Font]::new("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
$DefaultFileLabel.AutoSize = $true
$DefaultFileLabel.Location = [System.Drawing.Point]::new([int]$xStart, $yPos)
$ContentPanel.Controls.Add($DefaultFileLabel)

$DefaultFileTextBox = [System.Windows.Forms.TextBox]::new()
$DefaultFileTextBox.Width = 250
$DefaultFileTextBox.Location = [System.Drawing.Point]::new([int]$xStart, ($yPos + 25))
$ContentPanel.Controls.Add($DefaultFileTextBox)


# --- IP Address and Port Controls ---
$yPos += 60 # Corrected Y position
$IPLabel = [System.Windows.Forms.Label]::new()
$IPLabel.Text = "IP Address to Bind:"
$IPLabel.Font = [System.Drawing.Font]::new("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
$IPLabel.AutoSize = $true
$IPLabel.Location = [System.Drawing.Point]::new([int]$xStart, $yPos)
$ContentPanel.Controls.Add($IPLabel)

$IPComboBox = [System.Windows.Forms.ComboBox]::new()
$IPComboBox.Width = 250 # Adjusted width
$IPComboBox.DropDownHeight = 150
$IPComboBox.Items.AddRange((Get-LocalIPv4Addresses))
$IPComboBox.Location = [System.Drawing.Point]::new([int]$xStart, ($yPos + 25))
$ContentPanel.Controls.Add($IPComboBox)

$PortLabel = [System.Windows.Forms.Label]::new()
$PortLabel.Text = "Server Port:"
$PortLabel.Font = [System.Drawing.Font]::new("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
$PortLabel.AutoSize = $true
$PortLabel.Location = [System.Drawing.Point]::new($IPComboBox.Right + 20, $yPos)
$ContentPanel.Controls.Add($PortLabel)

$PortTextBox = [System.Windows.Forms.TextBox]::new()
$PortTextBox.Text = "8080"
$PortTextBox.Width = 100
$PortTextBox.Location = [System.Drawing.Point]::new($IPComboBox.Right + 20, ($yPos + 25))
$ContentPanel.Controls.Add($PortTextBox)


# --- Action Buttons with Colored Border Panels ---
$yPos += 70 # Corrected Y position

# 1. Start Button
$StartButton = [System.Windows.Forms.Button]::new()
$StartButton.Text = "Start Server"
$StartButton.Width = $ButtonWidth
$StartButton.Height = $ButtonHeight
$StartButton.Font = [System.Drawing.Font]::new("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
$StartButton.Location = [System.Drawing.Point]::new([int]$xStart, $yPos)
$StartButton.FlatStyle = [System.Windows.Forms.FlatStyle]::System
$ContentPanel.Controls.Add($StartButton)

# 2. Stop Button
$StopButton = [System.Windows.Forms.Button]::new()
$StopButton.Text = "Stop Server"
$StopButton.Width = $ButtonWidth
$StopButton.Height = $ButtonHeight
$StopButton.Font = [System.Drawing.Font]::new("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
$StopButton.Location = [System.Drawing.Point]::new(([int]$xStart + $ButtonWidth + 20), $yPos)
$StopButton.FlatStyle = [System.Windows.Forms.FlatStyle]::System
$ContentPanel.Controls.Add($StopButton)

# 3. Open in Browser Button
$OpenBrowserButton = [System.Windows.Forms.Button]::new()
$OpenBrowserButton.Text = "Open in Browser"
$OpenBrowserButton.Width = $ButtonWidth
$OpenBrowserButton.Height = $ButtonHeight
$OpenBrowserButton.Font = [System.Drawing.Font]::new("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
$OpenBrowserButton.Location = [System.Drawing.Point]::new(([int]$xStart + 2*($ButtonWidth + 20)), $yPos)
$OpenBrowserButton.FlatStyle = [System.Windows.Forms.FlatStyle]::System
$ContentPanel.Controls.Add($OpenBrowserButton)


# --- Status Log (Adjusted for Content Panel) ---
$LogTextBox = [System.Windows.Forms.TextBox]::new()
$LogTextBox.Width = $ContentWidth - 2 * $xStart
$LogTextBox.Height = 100
$LogTextBox.Multiline = $true
$LogTextBox.ScrollBars = [System.Windows.Forms.ScrollBars]::Vertical
$LogTextBox.ReadOnly = $true
$LogTextBox.BackColor = [System.Drawing.Color]::Black
$LogTextBox.ForeColor = [System.Drawing.Color]::Lime
# Y position adjusted relative to ContentPanel
$LogTextBox.Location = [System.Drawing.Point]::new([int]$xStart, $yPos + $ButtonHeight + 20) # Position below buttons
$ContentPanel.Controls.Add($LogTextBox)


# --- Exit Button (REQUESTED) ---
$ExitButton = [System.Windows.Forms.Button]::new()
$ExitButton.Text = "Exit"
$ExitButton.Width = 60
$ExitButton.Height = 25
$ExitButton.Location = [System.Drawing.Point]::new($ContentWidth - 60 - $xStart, $LogTextBox.Location.Y + $LogTextBox.Height + 15) # Position below log box
$ExitButton.FlatStyle = [System.Windows.Forms.FlatStyle]::System
$ContentPanel.Controls.Add($ExitButton)

# Tooltip for Exit Button
$ExitTooltip = [System.Windows.Forms.ToolTip]::new()
$ExitTooltip.SetToolTip($ExitButton, "Gracefully stop all active servers before closing the window.")

# --- Main Control Tooltips ---
$MainTooltip = [System.Windows.Forms.ToolTip]::new()
$MainTooltip.SetToolTip($RootModeCheckBox, "Check this to serve files from a directory. Uncheck to serve a single file.")
$MainTooltip.SetToolTip($RootTextBox, "The root directory your website files are in (Root Folder Mode).")
$MainTooltip.SetToolTip($SingleFileTextBox, "The single HTML file to serve for all requests (Single File Mode).")
$MainTooltip.SetToolTip($DefaultFileTextBox, "The default file to serve for root requests, e.g., 'index.html' (Root Folder Mode).")
$MainTooltip.SetToolTip($PortTextBox, "The network port the server will listen on (e.g., 8080).")
$MainTooltip.SetToolTip($IPComboBox, "The IP address the server will bind to. 127.0.0.1 is for local access only.")
$MainTooltip.SetToolTip($StartButton, "Starts the server with the current configuration.")
$MainTooltip.SetToolTip($StopButton, "Stops the currently running server.")
$MainTooltip.SetToolTip($OpenBrowserButton, "Opens the server URL in your default browser.")
$MainTooltip.SetToolTip($LogTextBox, "Displays live server activity, requests, and errors.")
$MainTooltip.SetToolTip($AutoStartCheckBox, "If checked, this server will attempt to start automatically when the application launches.")


# --- Status Bar ---

$StatusBar = [System.Windows.Forms.StatusStrip]::new()
$StatusBar.Dock = [System.Windows.Forms.DockStyle]::Bottom
$StatusBar.SizingGrip = $false
$StatusBar.BackColor = [System.Drawing.Color]::FromArgb(255, 220, 220, 220)

$CompanyLabel = [System.Windows.Forms.ToolStripStatusLabel]::new()
$CompanyLabel.Text = "EliteSoftware"
$CompanyLabel.Spring = $true
$CompanyLabel.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
$StatusBar.Items.Add($CompanyLabel) | Out-Null

$VersionLabel = [System.Windows.Forms.ToolStripStatusLabel]::new()
$VersionLabel.Text = "Version: $ScriptVersion"
$VersionLabel.TextAlign = [System.Drawing.ContentAlignment]::MiddleRight
$StatusBar.Items.Add($VersionLabel) | Out-Null

$StatusIndicator = [System.Windows.Forms.ToolStripStatusLabel]::new()
$StatusIndicator.Text = "Status: Stopped"
$StatusIndicator.ForeColor = [System.Drawing.Color]::Red
$StatusBar.Items.Add($StatusIndicator) | Out-Null

$Form.Controls.Add($StatusBar)

# ==============================================================================
# 6. Event Handling and Main Loop
# ==============================================================================

$StartButton.Add_Click({
    Update-ConfigFromGUI
    $currentConfig = $Script:ServerConfigs[$Script:CurrentConfigIndex]
    
    if ($Script:ActiveServers.ContainsKey($currentConfig.Name)) {
        Write-Log "Server '$($currentConfig.Name)' is already running."
        return
    }
    
    # Check for root path existence
    if ($currentConfig.UseRootFolderMode -and -not (Test-Path $currentConfig.Root -PathType Container)) {
        Write-Log "ERROR: Server Root Path not found: $($currentConfig.Root)"
        return
    }

    # Check for single file existence
    if (-not $currentConfig.UseRootFolderMode -and -not (Test-Path $currentConfig.SingleFilePath -PathType Leaf)) {
        Write-Log "ERROR: Single HTML file not found: $($currentConfig.SingleFilePath)"
        return
    }

    Start-Server $currentConfig
})

$StopButton.Add_Click({
    $currentConfig = $Script:ServerConfigs[$Script:CurrentConfigIndex]
    Stop-Server $currentConfig
})

$BrowseButton.Add_Click({
    $FolderBrowser = [System.Windows.Forms.FolderBrowserDialog]::new()
    $FolderBrowser.SelectedPath = $RootTextBox.Text
    if ($FolderBrowser.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        $RootTextBox.Text = $FolderBrowser.SelectedPath
        Update-ConfigFromGUI
        Write-Log "Root folder set to: $($RootTextBox.Text)"
    }
})

$SingleFileBrowseButton.Add_Click({
    $FileBrowser = [System.Windows.Forms.OpenFileDialog]::new()
    $FileBrowser.Filter = "HTML Files (*.html, *.htm)|*.html;*.htm|All files (*.*)|*.*"
    if ($FileBrowser.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        $SingleFileTextBox.Text = $FileBrowser.FileName
        Update-ConfigFromGUI
        Write-Log "Single file set to: $($SingleFileTextBox.Text)"
    }
})

$RootModeCheckBox.Add_CheckedChanged({
    Update-ConfigFromGUI
    Update-GUIFromConfig
})

$OpenBrowserButton.Add_Click({
    $currentConfig = $Script:ServerConfigs[$Script:CurrentConfigIndex]
    if ($currentConfig.Status -eq "Running") {
        $prefix = $Script:ActiveServers[$currentConfig.Name].Prefix
        $startUrl = $prefix.TrimEnd('/') # Use the actual running prefix
        [void][System.Diagnostics.Process]::Start($startUrl)
        Write-Log "Opening $startUrl in default browser."
    } else {
        Write-Log "Cannot open browser: Server is not running."
    }
})

$NewMenuItem.Add_Click({
    Add-NewConfig
    $SidebarList.Items.Add($Script:ServerConfigs[-1].Name) | Out-Null
    $SidebarList.SelectedIndex = $Script:ServerConfigs.Count - 1
})

$ExitButton.Add_Click({
    $Form.Close() # This triggers FormClosing event
})

$ExitMenuItem.Add_Click({
    $Form.Close() # This triggers FormClosing event
})

# IMPORTANT: A SINGLE FormClosing handler for orderly shutdown
$Form.Add_FormClosing({
    param($sender, $e)

    # Prevent the form from closing immediately while we show the goodbye message
    if (-not $Script:IsExiting) {
        $e.Cancel = $true # Always cancel the first close event to allow for graceful shutdown

        # 1. Signal all background threads to stop
        $Script:IsExiting = $true

        # 2. Stop all running servers gracefully
        $Script:ServerConfigs | Where-Object { $_.Status -eq "Running" } | ForEach-Object {
            Stop-Server $_
        }

        # 3. Stop the log timer
        if ($Script:LogTimer -and $Script:LogTimer.Enabled) {
            $Script:LogTimer.Stop()
        }

        # 4. Show goodbye window or close immediately
        if ($Script:Settings.ShowGoodbyeWindow) {
            Show-GoodbyeWindow "Goodbye see you soon!"
        } else {
            # This will re-trigger FormClosing, but $Script:IsExiting is now true, so it will fall through
            $Form.Close()
        }
    }
    # On the second pass (triggered by Show-GoodbyeWindow or immediate close), $Script:IsExiting is true, and the form closes without canceling.
})

$DuplicateMenuItem.Add_Click({
    if ($SidebarList.SelectedIndex -ge 0) {
        $originalConfig = $Script:ServerConfigs[$SidebarList.SelectedIndex]
        $newConfig = $originalConfig | Select-Object * # Easiest way to clone a PSCustomObject
        $newConfig.Name = "$($originalConfig.Name) (Copy)"
        $newConfig.Port = $originalConfig.Port + 1 # Suggest a new port
        $newConfig.Status = "Stopped"
        
        $Script:ServerConfigs += $newConfig
        $SidebarList.Items.Add($newConfig.Name) | Out-Null
        Save-ServerConfig
        Write-Log "Duplicated configuration: $($newConfig.Name)"
    }
})

$RenameMenuItem.Add_Click({
    if ($SidebarList.SelectedIndex -ge 0) {
        $currentConfig = $Script:ServerConfigs[$SidebarList.SelectedIndex]
        $inputBox = [Microsoft.VisualBasic.Interaction]::InputBox("Enter new name for configuration:", "Rename Configuration", $currentConfig.Name)
        if (-not [string]::IsNullOrEmpty($inputBox)) {
            $currentConfig.Name = $inputBox
            $SidebarList.Items[$SidebarList.SelectedIndex] = $inputBox
            Save-ServerConfig
            Update-GUIFromConfig # Update header if current config is renamed
            Write-Log "Renamed configuration to: $($inputBox)"
        }
    }
})

$StartServerMenuItem.Add_Click({
    if ($SidebarList.SelectedIndex -ge 0) {
        $currentConfig = $Script:ServerConfigs[$SidebarList.SelectedIndex]
        if ($currentConfig.Status -ne "Running") {
            Start-Server $currentConfig
        } else {
            Write-Log "Server '$($currentConfig.Name)' is already running."
        }
    }
})

$StopServerMenuItem.Add_Click({
    if ($SidebarList.SelectedIndex -ge 0) {
        $currentConfig = $Script:ServerConfigs[$SidebarList.SelectedIndex]
        if ($currentConfig.Status -eq "Running") {
            Stop-Server $currentConfig
        } else {
            Write-Log "Server '$($currentConfig.Name)' is not running."
        }
    }
})

# --- Final Initialization ---
# This handler runs when the form is fully loaded and the handle is created
$Form.Add_Shown({
    # 1. Update the GUI with the initially selected config
    Update-GUIFromConfig

    # 2. Auto-start servers that are configured to do so
    $autoStartConfigs = $Script:ServerConfigs | Where-Object { $_.AutoStart -eq $true }
    if ($autoStartConfigs) {
        Write-Log "Found $($autoStartConfigs.Count) server(s) configured for auto-start..."
        foreach ($config in $autoStartConfigs) {
            Write-Log "Auto-starting server: $($config.Name)"
            Start-Server $config
        }
    }
})

Start-LogTimer
Write-Log "EliteSoftware HTTP Test Server v$ScriptVersion Initialized."

# Main loop to show the form
$Form.ShowDialog() | Out-Null

# Minimize the console window upon running
if ($Script:Settings.HideConsoleOnLaunch) {
    $consoleHandle = (Get-Host).UI.RawUI.Handle
    $windowHandle = [System.Diagnostics.Process]::GetCurrentProcess().MainWindowHandle
    $showWindowAsync = Add-Type -MemberDefinition '
[DllImport("user32.dll")]
public static extern bool ShowWindowAsync(IntPtr hWnd, int nCmdShow);
' -Name "Win32ShowWindowAsync" -Namespace "Win32" -PassThru
    # SW_HIDE = 0, SW_MINIMIZE = 6
    $showWindowAsync::ShowWindowAsync($windowHandle, 0) | Out-Null
}