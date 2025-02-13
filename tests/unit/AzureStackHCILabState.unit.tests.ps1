Describe 'Validation' -Tags Host {
    Context HostOS {
        It "This module must be launched with administrator permissions" {
            $isAdmin = [bool](([System.Security.Principal.WindowsIdentity]::GetCurrent()).groups -match "S-1-5-32-544")
            $isAdmin | Should Be $true
        }

        $NodeOS = Get-CimInstance -ClassName 'Win32_OperatingSystem'

        ### Verify the Host is sufficient version
        #TODO: Can this run on windows 10? - Not without WindowsFeature checking
        It "${env:ComputerName} must be Windows Server 2016, or Server 2019" {
            $NodeOS.Caption | Should be ($NodeOS.Caption -like '*Windows Server 2016*' -or $NodeOS.Caption -like '*Windows Server 2019*' -or $NodeOS.Caption -like '*Windows 10*' -or $NodeOS.Caption -like '*Azure Stack HCI*')
        }

        It "${env:ComputerName} should have enough memory to cover what's specified in LabConfig" {
            (($LabConfig.VMs.MemoryStartupBytes | Measure-Object -Sum).Sum / 1GB + 2) | Should BeLessThan ((Get-CimInstance -ClassName Win32_PhysicalMemory | Measure-Object -Property Capacity -Sum).Sum / 1GB)
        }

        # Not Implemented until everything gets to the PowerShell Gallery
        $RequiredModules = (Get-Module -Name AzureStackHCIJumpstart).RequiredModules

        #TODO: Remove if ($requiredModules) once published on the PoSH Gallery
        if ($RequiredModules) {
            $RequiredModules.GetEnumerator() | ForEach-Object {
                $thisModule = $_

                Remove-Variable module -ErrorAction SilentlyContinue
                $module = Get-Module $thisModule.Name -ListAvailable -ErrorAction SilentlyContinue | Sort-Object Version -Descending | Select-Object -First 1

                It "[TestHost: ${env:ComputerName}] Must have the module [$($thisModule.Name)] available" {
                    $module.Name | Should Not BeNullOrEmpty
                }

                It "[TestHost: ${env:ComputerName}] Must be at least version [$($thisModule.Version)]" {
                    $module.version -ge $_.ModuleVersion | Should be $true
                }
            }
        }

        Switch -Wildcard ($NodeOS.Caption) {
            "*Windows 10*" {
                $HyperVInstallationState = Get-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V

                It "${env:ComputerName} must have $($HyperVInstallationState.DisplayName) installed" {
                    $HyperVInstallationState.State | Should be 'Enabled'
                }
            }

            Default {
                $HyperVInstallationState = (Get-WindowsFeature | Where-Object Name -like *Hyper-V* -ErrorAction SilentlyContinue)

                $HyperVInstallationState | ForEach-Object {
                    It "${env:ComputerName} must have $($_.Name) installed" {
                        $_.InstallState | Should be 'Installed'
                    }
                }
            }
        }
    }

    Context 'Lab Configuration (Get-AzureStackHCILabConfig)' {
        #TODO: Update
        <#If ($LabConfig.ContainsKey('ServerISO') -and $LabConfig.ContainsKey('BaseVHDX')) {
            It "${env:ComputerName} LabConfig should not specify both BaseVHDX and ServerISO properties" { $true | Should be $false }
        }
        ElseIf ( (-not($LabConfig.ContainsKey('ServerISO'))) -and (-not($LabConfig.ContainsKey('BaseVHDX'))) ) {
            It "${env:ComputerName} must specify either LabConfig.ServerISO or LabConfig.BaseVHDX" { $false | Should be $true }
        }
        ElseIf ($LabConfig.ServerISO) {
            It "${env:ComputerName} the specified ISO from LabConfig.ServerISO must exist" {
                Test-Path $LabConfig.ServerISO | Should be $true
            }
        }
        ElseIf ($LabConfig.BaseVHDX) {
            It "(Get-AzureStackHCILabConfig) The specified VHDX from LabConfig.BaseVHDX must actually exist" {
                Test-Path $LabConfig.BaseVHDX | Should be $true
            }
        }#>

        It "(Get-AzureStackHCILabConfig) Should have at least one machine with role 'WAC'" {
            ($LabConfig.VMs.Where{$_.Role -eq 'WAC'}).Count | Should BeGreaterOrEqual 1
        }

        It "(Get-AzureStackHCILabConfig) Should have at least one machine with role 'Domain Controller'" {
            ($LabConfig.VMs.Where{$_.Role -eq 'Domain Controller'}).Count | Should BeGreaterOrEqual 1
        }

        It "(Get-AzureStackHCILabConfig) Should have at least two machines with role 'AzureStackHCI'" {
            ($LabConfig.VMs.Where{$_.Role -eq 'AzureStackHCI'}).Count | Should BeGreaterOrEqual 2
        }

        It "(Get-AzureStackHCILabConfig) DHCP Scope should not already be in use on this system" {
            $DHCPScopePrefix = $LabConfig.DHCPScope | foreach-Object { ([ipaddress]$_).GetAddressBytes()[0..2] -join '.' }
            $InUseAddress = (Get-NetIPAddress | Where IPAddress -like $DHCPScopePrefix*).IPAddress

            if ($InUseAddress) {
                $false | Should be $true
            }
        }
    }
}

Describe 'Lab Validation' -Tags Lab {
    Context VMs {
        $LabConfig.VMs.Where{$_.Role -eq 'AzureStackHCI'} | ForEach-Object {
            $VMName = "$($LabConfig.Prefix)$($_.VMName)"

            It "Should have the VM: $VMName" {
                Get-VM -VMName $VMName -ErrorAction SilentlyContinue | Should BeOfType 'Microsoft.HyperV.PowerShell.VirtualMachine'
            }
        }
    }
}

#TODO: if BaseVHDX specified, test that you have rights to open the file