$enclosure = Get-WMIObject -Class Win32_SystemEnclosure | Select-Object -First 1

Write-Output "chassis_type_external=$($enclosure.ChassisTypes)"
