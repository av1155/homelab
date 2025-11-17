# Utilities Notes

## UpSnap Setup Instructions for Windows 11

> **Prerequisites:**
>
> - WOL should already be working before you attempt any of this
> - The target device must be on the same network (or same VLAN) as the device hosting UpSnap

### Add Device in UpSnap

After setting up the UpSnap container, add a new device in the web UI:

- **Name**: Name your target device
- **IP**: IP of target device
- **Mac**: The MAC address of the target device
- **Netmask**: The netmask of the target device (e.g., `255.255.255.0`)

### Configure Sleep-On-LAN (SOL)

To enable remote sleep functionality, install Sleep-On-LAN on the Windows 11 target PC.

1. Download Sleep-On-LAN

    Go to [SR-G/sleep-on-lan releases](https://github.com/SR-G/sleep-on-lan/releases/latest) and download the `.zip` file from the latest release.

2. Extract the binary

    Extract the file to a directory like `C:\Tools\SleepOnLan\`. You should see `sol.exe` inside.

3. Create configuration file

    Create or update the `sol.json` file in the same directory as `sol.exe`:

    ```json
    {
        "Listeners": ["UDP:9", "HTTP:8009"],
        "LogLevel": "INFO",
        "BroadcastIP": "192.168.10.255",
        "Commands": [
            {
                "Operation": "sleep",
                "Type": "internal-dll",
                "Default": true
            }
        ]
    }
    ```

    **Important:** Change `BroadcastIP` to match your network's broadcast address. For example, if your "Homelab" VLAN and target Windows 11 PC are in the subnet `192.168.10.X`, use `192.168.10.255`.

4. Install Sleep-On-LAN as a Windows service

    The Sleep-On-Lan process can be run manually or installed as a service. The easiest way to install it as a service is to use [NSSM](https://nssm.cc/) (the Non-Sucking Service Manager).

    **Run as administrator** (Right-click on PowerShell or Command Prompt > Run as administrator):

    **Installation:**

    ```powershell
    nssm install <service name> <full path to binary>
    ```

    **Example installation:**

    ```powershell
    C:\Tools\nssm\2.24\win64\nssm.exe install SleepOnLan C:\Tools\SleepOnLan\sol.exe
    ```

    **Removal example:**

    ```powershell
    C:\Tools\nssm\2.24\win64\nssm.exe remove SleepOnLan confirm
    ```

    **Configure service logs** (adjust paths as needed):

    ```powershell
    C:\Tools\nssm\2.24\win64\nssm.exe set SleepOnLan AppStdout "C:\Tools\SleepOnLan\sleeponlan-windows.log"
    C:\Tools\nssm\2.24\win64\nssm.exe set SleepOnLan AppStderr "C:\Tools\SleepOnLan\sleeponlan-windows.log"
    ```

    Reference: [NSSM usage documentation](https://nssm.cc/usage)

5. Verify the service is running

    Check that the SleepOnLan service is running:

    ```powershell
    Get-Service SleepOnLan
    ```

    Status should be `Running`.

6. Set Wi-Fi network to Private

    Verify the network profile is set to Private by running:

    ```powershell
    Get-NetConnectionProfile
    ```

    Output should show:

    ```txt
    NetworkCategory : Private
    ```

    If it shows `Public`, change it to `Private`:

    ```powershell
    Set-NetConnectionProfile -InterfaceAlias "Wi-Fi" -NetworkCategory Private
    ```

7. Configure Windows Firewall rules

    Allow ICMP (ping):

    ```powershell
    New-NetFirewallRule -DisplayName "Allow ICMPv4" -Protocol ICMPv4 -IcmpType 8 -Direction Inbound -Action Allow
    ```

    Allow Sleep-On-LAN HTTP listener (port 8009):

    ```powershell
    New-NetFirewallRule -DisplayName "Allow Sleep-On-LAN HTTP" -Direction Inbound -LocalPort 8009 -Protocol TCP -Action Allow
    ```

8. Enable Sleep-On-LAN in UpSnap

    In UpSnap's web UI:

    1. Edit your Windows 11 device
    2. In the **Sleep-On-LAN** section:
       - Enable the **"Enable Sleep-On-LAN"** toggle
       - Set **SOL Port** to: `8009`
       - Leave Authorization disabled (unless you configured it in `sol.json`)

    UpSnap will now:
    - Monitor the device state by pinging `http://<WINDOWS_IP>:8009`
    - Send a reversed MAC address magic packet to trigger sleep (via UDP port 9)
    - Show accurate awake/asleep status in the dashboard

9. Test the configuration

    In UpSnap, observe the device status indicator. When the Windows 11 PC is awake, UpSnap should show it as online.

    Click the **sleep button** for your Windows 11 device. The PC should enter sleep mode within a few seconds, and UpSnap should reflect the sleeping state.

    Click the **wake button** to send a standard WOL magic packet and wake the PC.

    **Troubleshooting:**
    - Check that the SleepOnLan service is running: `Get-Service SleepOnLan`
    - Verify firewall rules are active for ICMP and TCP port 8009
    - Check Sleep-On-LAN logs at `C:\Tools\SleepOnLan\sleeponlan-windows.log`
    - Ensure the SOL port (8009) in UpSnap matches the HTTP listener in `sol.json`
    - Verify both devices are on the same network/VLAN
