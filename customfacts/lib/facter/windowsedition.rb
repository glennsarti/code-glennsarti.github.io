Facter.add('windows_edition_custom') do
  confine :osfamily => :windows
  setcode do
    begin
      value = nil
      Win32::Registry::HKEY_LOCAL_MACHINE.open('SOFTWARE\Microsoft\Windows NT\CurrentVersion') do |regkey|
        value = regkey['EditionID']
      end
      value
    rescue
      nil
    end
  end
end
