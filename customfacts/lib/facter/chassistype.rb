Facter.add('chassis_type_custom') do
  confine :osfamily => :windows
  setcode do
    begin
      require 'win32ole'
      wmi = WIN32OLE.connect("winmgmts:\\\\.\\root\\cimv2")
      enclosure = wmi.ExecQuery("SELECT * FROM Win32_SystemEnclosure").each.first
      
      enclosure.ChassisTypes
      # enclosure.ChassisTypes.first
      # enclosure.ChassisTypes.first.to_s
    rescue
    end
  end
end
