function Get-ADBitlockerRecoveryKey {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [Alias('CN')]
        [string]$ComputerName
    )

    process {
        $adComputer = Get-ADComputer -Identity $ComputerName
        $adObj = Get-ADObject -SearchBase $adComputer.DistinguishedName -Filter 'ObjectClass -eq "msFVE-RecoveryInformation"' -Properties msFVE-RecoveryPassword, WhenCreated |
            Sort-Object -Property WhenCreated -Descending |
            Select-Object -Property msFVE-RecoveryPassword, WhenCreated

        $adObj
    }
}
