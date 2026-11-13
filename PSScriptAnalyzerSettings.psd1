@{
    # Windows PowerShell 5.1 is the supported floor; these two rules catch pwsh-7-only syntax and cmdlets without needing a 5.1 runner.
    IncludeRules = @('PSUseCompatibleSyntax', 'PSUseCompatibleCommands')
    Rules        = @{
        PSUseCompatibleSyntax   = @{
            Enable         = $true
            TargetVersions = @('5.1', '7.0')
        }
        PSUseCompatibleCommands = @{
            Enable         = $true
            # Windows Server 2019, PowerShell 5.1
            TargetProfiles = @('win-48_x64_10.0.17763.0_5.1.17763.316_x64_4.0.30319.42000_framework')
        }
    }
}
