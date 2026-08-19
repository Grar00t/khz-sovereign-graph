$ErrorActionPreference = 'Stop'

$RuleGroup = 'KHZ Sovereignty'
$LoopbackRule = 'KHZ Sovereignty - Loopback only'

function Test-Administrator {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $p = New-Object Security.Principal.WindowsPrincipal($id)
    return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Apply-KhzFirewall {
    if (-not (Test-Administrator)) { throw 'Administrator privileges required' }
    Get-NetFirewallRule -Group $RuleGroup -ErrorAction SilentlyContinue | Remove-NetFirewallRule
    New-NetFirewallRule -DisplayGroup $RuleGroup -DisplayName $LoopbackRule -Direction Outbound -Action Allow -Protocol Any -RemoteAddress 127.0.0.0/8,::1 -Profile Any | Out-Null
    New-NetFirewallRule -DisplayGroup $RuleGroup -DisplayName 'KHZ Sovereignty - Block all other outbound' -Direction Outbound -Action Block -Protocol Any -RemoteAddress Any -Profile Any | Out-Null
}

function Verify-KhzFirewall {
    $rules = Get-NetFirewallRule -Group $RuleGroup -ErrorAction SilentlyContinue
    if (-not $rules) { throw 'KHZ firewall rules not installed' }
    $block = $rules | Where-Object { $_.DisplayName -eq 'KHZ Sovereignty - Block all other outbound' }
    if (-not $block) { throw 'Outbound deny rule missing' }
    'VERIFIED'
}

param([ValidateSet('apply','verify','remove')] [string]$Mode='apply')

switch ($Mode) {
    'apply' { Apply-KhzFirewall; Verify-KhzFirewall }
    'verify' { Verify-KhzFirewall }
    'remove' { if (-not (Test-Administrator)) { throw 'Administrator privileges required' }; Get-NetFirewallRule -Group $RuleGroup -ErrorAction SilentlyContinue | Remove-NetFirewallRule }
}
