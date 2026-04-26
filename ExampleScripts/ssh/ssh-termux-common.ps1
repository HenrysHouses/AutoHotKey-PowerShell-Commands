function Fail([string]$Message) {
    [Console]::Error.WriteLine($Message)
    exit 1
}

function Get-SshTermuxConfigPath([string]$ConfigPath, [string]$ScriptRoot) {
    if ([string]::IsNullOrWhiteSpace($ConfigPath)) {
        return (Join-Path $ScriptRoot "ssh-termux.json")
    }

    return $ConfigPath
}

function Get-SshTermuxConfig([string]$ConfigPath, [string[]]$RequiredFields) {
    if (-not (Test-Path -LiteralPath $ConfigPath)) {
        Fail "Missing config file: $ConfigPath"
    }

    $config = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json

    foreach ($field in $RequiredFields) {
        if (-not $config.$field) {
            Fail "Config field '$field' is required in $ConfigPath."
        }
    }

    if ($config.host -eq "PHONE_IP" -or $config.user -eq "TERMUX_USER") {
        Fail "Edit $ConfigPath and replace PHONE_IP / TERMUX_USER with your Termux values."
    }

    return $config
}

function Save-SshTermuxConfig($Config, [string]$ConfigPath) {
    ($Config | ConvertTo-Json -Depth 5) | Set-Content -LiteralPath $ConfigPath
}

function Test-ValidIpv4([string]$IpAddress) {
    if ([string]::IsNullOrWhiteSpace($IpAddress)) {
        return $false
    }

    $parts = $IpAddress.Split('.')
    if ($parts.Count -ne 4) {
        return $false
    }

    foreach ($part in $parts) {
        $value = 0
        if (-not [int]::TryParse($part, [ref]$value)) {
            return $false
        }

        if ($value -lt 0 -or $value -gt 255) {
            return $false
        }
    }

    return $true
}

function Get-FirstCandidateHost($Candidates) {
    $first = $Candidates | Select-Object -First 1
    if ($null -eq $first) {
        return $null
    }

    $resolved = [string]$first
    if (-not (Test-ValidIpv4 -IpAddress $resolved)) {
        Fail "Discovery returned an invalid host value: $resolved"
    }

    return $resolved
}

function Get-FzfExe() {
    $fzfCommand = Get-Command fzf -ErrorAction SilentlyContinue
    if (-not $fzfCommand) {
        Fail "fzf was not found on PATH."
    }

    return $fzfCommand.Source
}

function Select-LocalPath([switch]$IncludeFiles, [switch]$IncludeDirectories, [switch]$IncludeCurrentDirectory) {
    $root = (Get-Location).Path
    $entries = New-Object System.Collections.Generic.List[object]

    if ($IncludeCurrentDirectory -and $IncludeDirectories) {
        $entries.Add([pscustomobject]@{
            Label = "./"
            Path  = $root
        })
    }

    if ($IncludeDirectories) {
        Get-ChildItem -LiteralPath $root -Directory -Recurse -Force | ForEach-Object {
            $relative = [System.IO.Path]::GetRelativePath($root, $_.FullName).Replace('\', '/')
            $entries.Add([pscustomobject]@{
                Label = "$relative/"
                Path  = $_.FullName
            })
        }
    }

    if ($IncludeFiles) {
        Get-ChildItem -LiteralPath $root -File -Recurse -Force | ForEach-Object {
            $relative = [System.IO.Path]::GetRelativePath($root, $_.FullName).Replace('\', '/')
            $entries.Add([pscustomobject]@{
                Label = $relative
                Path  = $_.FullName
            })
        }
    }

    if ($entries.Count -eq 0) {
        Fail "No matching items found under $root."
    }

    $fzfExe = Get-FzfExe
    $selection = $entries |
        Sort-Object Label |
        Select-Object -ExpandProperty Label |
        & $fzfExe --prompt "Select source> " --height 60% --layout reverse --border

    if ([string]::IsNullOrWhiteSpace($selection)) {
        Fail "No source selected."
    }

    $selectedEntry = $entries | Where-Object { $_.Label -eq $selection } | Select-Object -First 1
    if (-not $selectedEntry) {
        Fail "Selected item could not be resolved: $selection"
    }

    return $selectedEntry.Path
}

function Test-TcpPort([string]$HostName, [int]$Port, [int]$TimeoutMs = 1000) {
    $client = New-Object System.Net.Sockets.TcpClient
    try {
        $async = $client.BeginConnect($HostName, $Port, $null, $null)
        if (-not $async.AsyncWaitHandle.WaitOne($TimeoutMs, $false)) {
            return $false
        }

        $client.EndConnect($async)
        return $true
    } catch {
        return $false
    } finally {
        $client.Dispose()
    }
}

function Convert-Ipv4ToUInt32([string]$IpAddress) {
    $bytes = [System.Net.IPAddress]::Parse($IpAddress).GetAddressBytes()
    [array]::Reverse($bytes)
    return [BitConverter]::ToUInt32($bytes, 0)
}

function Convert-UInt32ToIpv4([uint32]$Value) {
    $bytes = [BitConverter]::GetBytes($Value)
    [array]::Reverse($bytes)
    return ([System.Net.IPAddress]::new($bytes)).ToString()
}

function Convert-MaskToPrefixLength([string]$Mask) {
    $value = Convert-Ipv4ToUInt32 $Mask
    $count = 0

    for ($bit = 31; $bit -ge 0; $bit--) {
        if (($value -band (1u -shl $bit)) -ne 0) {
            $count++
        }
    }

    return $count
}

function Get-NetworkRange([string]$IpAddress, [int]$PrefixLength) {
    $ipValue = Convert-Ipv4ToUInt32 $IpAddress
    $maskValue = if ($PrefixLength -eq 0) {
        [uint32]0
    } else {
        $allBits = [math]::Pow(2, 32) - 1
        $hostBits = [math]::Pow(2, 32 - $PrefixLength) - 1
        [uint32]($allBits - $hostBits)
    }

    $networkValue = $ipValue -band $maskValue
    $hostMask = [uint32](([math]::Pow(2, 32) - 1) - $maskValue)
    $broadcastValue = [uint32]($networkValue -bor $hostMask)

    return [pscustomobject]@{
        IpAddress      = $IpAddress
        PrefixLength   = $PrefixLength
        NetworkAddress = (Convert-UInt32ToIpv4 $networkValue)
        Broadcast      = (Convert-UInt32ToIpv4 $broadcastValue)
        NetworkValue   = $networkValue
        BroadcastValue = [uint32]$broadcastValue
    }
}

function Test-IpInNetwork([string]$IpAddress, $NetworkInfo) {
    $value = Convert-Ipv4ToUInt32 $IpAddress
    return ($value -ge $NetworkInfo.NetworkValue -and $value -le $NetworkInfo.BroadcastValue)
}

function Get-LocalIpv4NetworkInfo() {
    try {
        $route = Get-NetRoute -DestinationPrefix "0.0.0.0/0" -AddressFamily IPv4 -ErrorAction Stop |
            Sort-Object RouteMetric, InterfaceMetric |
            Select-Object -First 1

        if ($route) {
            $address = Get-NetIPAddress -AddressFamily IPv4 -InterfaceIndex $route.InterfaceIndex -ErrorAction Stop |
                Where-Object {
                    $_.IPAddress -notlike "169.254.*" -and
                    $_.IPAddress -ne "127.0.0.1"
                } |
                Select-Object -First 1

            if ($address) {
                if ($address.PrefixLength) {
                    return (Get-NetworkRange -IpAddress $address.IPAddress -PrefixLength ([int]$address.PrefixLength))
                }
            }
        }
    } catch {
    }

    $ipconfigOutput = ipconfig
    for ($i = 0; $i -lt $ipconfigOutput.Count; $i++) {
        if ($ipconfigOutput[$i] -match 'IPv4[^:]*:\s*(\d+\.\d+\.\d+\.\d+)') {
            $ipAddress = $Matches[1]
            $mask = $null

            for ($j = $i + 1; $j -lt [Math]::Min($i + 6, $ipconfigOutput.Count); $j++) {
                if ($ipconfigOutput[$j] -match 'Subnet Mask[^:]*:\s*(\d+\.\d+\.\d+\.\d+)') {
                    $mask = $Matches[1]
                    break
                }
            }

            if ($ipAddress -and $mask) {
                $prefixLength = Convert-MaskToPrefixLength $mask
                return (Get-NetworkRange -IpAddress $ipAddress -PrefixLength $prefixLength)
            }
        }
    }

    return $null
}

function Get-ArpCandidateIps($NetworkInfo) {
    $arpOutput = arp -a
    $matches = $arpOutput | ForEach-Object {
        $lineMatches = [regex]::Matches($_, '(\d+\.\d+\.\d+\.\d+)')
        foreach ($match in $lineMatches) {
            $candidate = $match.Groups[1].Value
            if (Test-IpInNetwork -IpAddress $candidate -NetworkInfo $NetworkInfo) {
                $candidate
            }
        }
    }

    return @($matches | Sort-Object -Unique)
}

function Get-NearbyIps([string]$IpAddress, $NetworkInfo, [int]$Window = 16) {
    if ([string]::IsNullOrWhiteSpace($IpAddress)) {
        return @()
    }

    if (-not (Test-IpInNetwork -IpAddress $IpAddress -NetworkInfo $NetworkInfo)) {
        return @()
    }

    $center = Convert-Ipv4ToUInt32 $IpAddress
    $start = [uint32][Math]::Max([double]($NetworkInfo.NetworkValue + 1), [double]($center - $Window))
    $end = [uint32][Math]::Min([double]($NetworkInfo.BroadcastValue - 1), [double]($center + $Window))

    $ips = for ($value = $start; $value -le $end; $value++) {
        Convert-UInt32ToIpv4 ([uint32]$value)
    }

    return @($ips)
}

function Find-SshTermuxHosts([int]$Port = 8022, [int]$TimeoutMs = 1000, [switch]$FullScan, [string]$PreferredHost = "") {
    $networkInfo = Get-LocalIpv4NetworkInfo
    if (-not $networkInfo) {
        Fail "Could not determine the local IPv4 subnet."
    }

    if ($FullScan) {
        Write-Host "Scanning $($networkInfo.NetworkAddress)/$($networkInfo.PrefixLength) for Termux sshd on port $Port with ${TimeoutMs}ms timeout"
        $start = [uint32]($networkInfo.NetworkValue + 1)
        $end = [uint32]($networkInfo.BroadcastValue - 1)
        if ($end -lt $start) {
            $candidatesToCheck = @($networkInfo.IpAddress)
        } else {
            $candidatesToCheck = for ($value = $start; $value -le $end; $value++) {
                Convert-UInt32ToIpv4 ([uint32]$value)
            }
        }
    } else {
        Write-Host "Scanning likely hosts on $($networkInfo.NetworkAddress)/$($networkInfo.PrefixLength) for Termux sshd on port $Port with ${TimeoutMs}ms timeout"

        $preferred = @()
        if (-not [string]::IsNullOrWhiteSpace($PreferredHost) -and (Test-IpInNetwork -IpAddress $PreferredHost -NetworkInfo $networkInfo)) {
            $preferred = @($PreferredHost)
        }

        $nearby = Get-NearbyIps -IpAddress $PreferredHost -NetworkInfo $networkInfo -Window 16
        $arpCandidates = Get-ArpCandidateIps -NetworkInfo $networkInfo
        $candidatesToCheck = @($preferred + $arpCandidates + $nearby | Sort-Object -Unique)
    }

    if (-not $candidatesToCheck -or $candidatesToCheck.Count -eq 0) {
        return @()
    }

    $total = @($candidatesToCheck).Count
    $checked = 0
    $progressStep = 10
    $candidates = foreach ($ip in $candidatesToCheck) {
        $checked++
        if ($checked -eq 1 -or $checked % $progressStep -eq 0 -or $checked -eq $total) {
            Write-Host "Checked $checked/$total hosts..."
        }

        if (Test-TcpPort -HostName $ip -Port $Port -TimeoutMs $TimeoutMs) {
            $ip
        }
    }

    return @($candidates)
}

function Resolve-SshTermuxHost($Config, [string]$ConfigPath, [int]$Port = 8022, [int]$TimeoutMs = 1000) {
    $currentHost = [string]$Config.host
    if (-not [string]::IsNullOrWhiteSpace($currentHost)) {
        Write-Host "Testing configured host ${currentHost}:$Port ..."
        $reachable = Test-TcpPort -HostName $currentHost -Port $Port -TimeoutMs $TimeoutMs
        if ($reachable) {
            Write-Host "Configured host is reachable."
            return $Config
        }

        Write-Host "Configured host did not respond within ${TimeoutMs}ms."
    }

    $candidates = @(Find-SshTermuxHosts -Port $Port -TimeoutMs $TimeoutMs -PreferredHost $currentHost)

    if (-not $candidates -or $candidates.Count -eq 0) {
        Fail "No host responded on port $Port."
    }

    if ($candidates.Count -gt 1) {
        $message = @(
            "Multiple hosts responded on port ${Port}:",
            ($candidates | ForEach-Object { "  $_" }),
            "Run ssh-termux-discover to inspect them and then update ssh-termux.json."
        ) -join [Environment]::NewLine
        Fail $message
    }

    $resolvedHost = Get-FirstCandidateHost -Candidates $candidates
    if ([string]::IsNullOrWhiteSpace($resolvedHost)) {
        Fail "Could not resolve a host value from discovery results."
    }

    $Config.host = $resolvedHost
    $Config.port = $Port
    Save-SshTermuxConfig -Config $Config -ConfigPath $ConfigPath
    Write-Host "Updated $ConfigPath with host $resolvedHost"
    return $Config
}
