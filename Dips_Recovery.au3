#cs ----------------------------------------------------------------------------

	AutoIt Version: 3.3.0.0
	Author:         Jason Powell

	Script Function:
	WinPE multi-purpose scripting component for boot, deployment, and recovery processes

#ce ----------------------------------------------------------------------------

#region ; Includes
	; debug log needs these
	#include <date.au3>			; Needed for millisecond-resolution timestamps in logging

	; Need this for STDOUT redirection
	#include <Constants.AU3>

	; Need these for GUI elements
	#include <GUIConstants.au3>	; Needed for all the GUI windows and whatnot
	#include <StaticConstants.au3>  ; needed for text alignment calls
	#include <WindowsConstants.au3>

	; Needed for the image selection dialog
	#include <File.au3>
	#include <Array.au3>

	; General process handling
	#include <Process.au3>

	; TCP/IP network library
	#include <iNet.au3>

	; Our custom WMI library
	#include <..\..\Include\WMIUtils.au3>

	; Our custom disk info library
	#include <..\..\Include\DiskInfo.au3>

	; Our custom logging library
	#include <..\..\Include\LogUtils.au3>

	; Our custom FileListToArray function
	#include <..\..\Include\_FileListToArray_Recursive.au3>

	; Our custom WinPE utils library
	#include <WinPEUtils.au3>
#endregion ; Includes

#region ; Autoit runtime settings
	; Need this for diskpart
	#RequireAdmin

	; This really shouldn't be an issue, but just in case
	#NoTrayIcon
#endregion ; Autoit runtime settings

#region ; Global variables
	; Build accelerator function
	Global $blnBuildAccelerate = False
	Global $strBuildAccelerate_Method = ""
	Global $strBuildAccelerate_Target = ""

	; This is for the main background text
	Global $gintLeaderBoard = 0

	; This is for the HWEnum section of the background text
	Global $gintHWInfoCounter = 0

	; Get the system drive environment variable
	Global $gstrSystemDrive = EnvGet("SYSTEMDRIVE")

	; The image name relevant to this hardware platform
	Global $gstrImageName = ""

	; Calibration tool for this hardware
	Global $gstrTouchCalibrateEXE = ""

	; Load new network driver
	Global $gstrLoadNetworkDrive = ""

	; setup WMI
	Global $gobjWMI = ObjGet("winmgmts:root\cimv2")

	; CD or USB drive, if so equipped
	$gstrCDSource = ""

	; COM Object error handler
	Global $gobjComEvtHandler = ObjEvent("AutoIt.Error", "_ComObjError") ; COM object error handler

	; TODO: look for unused variables
	; TODO: remove global where possible
	; Source file validation
	Global $gboolBootWIMUpdated = False
	Global Const $gstrTempPath = "C:\temp\"
	Global Const $gstrLocalSourcesPath = "C:\SOURCES\"
	Global Const $gstrSFTPCentral = "sftp.yum.com -privatekey=X:\WinPE\bin\WinSCP\sftp_private.ppk"
	Global Const $gstrWinSCPPath = @ScriptDir & "\WinSCP\WinSCP.exe"
	Global Const $gstrWinScpSysWOW64 =  "X:\Windows\SysWow64\WinSCP\WinSCP.exe"
	Global Const $gstrWinSYSWOW = "X:\Windows\SysWOW64"
	Global $gstrMessageFileName = ""
	Global $gstrMessageFileFullPath = ""
	Global $gstrSubscriptionFileName = ""
	Global $gstrSFTPPOS = ""
	Global $astrSourceFileObjectsAtRemote[1][3]
	Global $gintSleepInterval = 5000
	Global $gintRegNum = 0
	Global $gintRecovery = 0
	Global $gboolMasterPOS = True
	Global $gintMasterPOSNumber = 0
	Global $gstrMasterPOSIP = ""
	Global $ghwndLatestHWText = "" ; since "-1" doesn't seem to always work

	; === Logging details
	Global Const $DRPartitionDriveLetter = getDriveLetterForDRPartitionInWinPE()
	Global Const $IPADDRESS_LOGFILE = $DRPartitionDriveLetter & "\Logs\IPAddress.log"
	Global $constrScriptVersion = ""
	Global $gblnDebugEnabled = True ; Debug logging enabled as a global
	Global $gstrLogFileDestination = $DRPartitionDriveLetter & "\Logs\Recovery.log"
	Global $ghwndLiveLog = 0 ; Window handle for the live logger window, if it's being used
	Global $gintDebugLayers = 0 ; How many "functions deep" are we?
	Global $gstrDebugPadding = "" ; Padding for the "functions deep" portion of debug output

	; IRVLABPXE IP
	Global $gstrIRVLABPXEIP = "169.254.254.10"

#endregion ; Global variables

#region ; Command line handling
	If $CmdLine[0] > 0 Then
		Switch $CmdLine[1]

			; Hotkey poller process for debugging access
			Case "hotkey"
				_HotKey()

				; Configure PAR touch screen interface
			Case "partouch"
				_ParTouch()

				; Configure IBM touch screen interface
			Case "elotouch"
				_EloTouch()

				; Configure NCR touch screen interface
			Case "tsharctouch"
				_TSharcTouch()

				; PXE copy process
			Case "pxecopy"
				_PXE_DoRoboCopy($CmdLine[2], $CmdLine[3])

				; DVD / optical media copy process
			Case "dvdcopy"
				_DVD_DoCopy()

				; WPEInit process
			Case "wpeinit"
				_WPEInit()

				; Image WEPOS to disk
			Case "imagewepos"
				_ImageWEPos($CmdLine[2])

				; Apply WIM to WIndows\Options folder
			Case "applylayer"
				_ApplyLayer()

				; Restore a prior snapshot
			Case "restore"
				_Snapshot_Restore($CmdLine[2])

				; Create a new snapshot
			Case "create"
				_Snapshot_Create($CmdLine[2])

				; Auto discovery for figuring out what our config details might be...
			Case "autodiscovery"
				_AutoDiscovery($CmdLine[2])

				; Execute a diskpart script
			Case "diskpart"
				_DiskPart($CmdLine[2])

				; Connect to IRVLABPXE to pull data
			Case "pxeconnect"
				_PXE_ConnectTo($CmdLine[2])

				; Connect to other available registers to pull data
			Case "registerconnect"
				_PXE_RegisterConnect()

				; Copy data from a specific source
			Case "MultiThreadedCopy"
				_PXE_DoMultiThreadedCopy($CmdLine[2], $CmdLine[3], $CmdLine[4], $CmdLine[5])

		EndSwitch

		; All these recursive calls terminate here
		Exit

	EndIf
#endregion ; Command line handling

; Go go gadget code...
_Main()

; Let's do this!
Func _Main()
	Local $intDebugPID = 0, $hwndMainWindow = 0, $hwndMainPicture = 0
	Local $intGUID = 0, $intResult1 = 0, $intResult2 = 0, $objCol = 0, $strThisName = ""

	_LogWriter("Starting Script: Recovery.exe", $gstrLogFileDestination)

	; If the base directory for Windows isn't X:\, then recovery can't be run
	If StringMid(@WindowsDir, 1, 2) <> "X:" Then
		MsgBox(48, "Error", "Recovery cannot be run outside of Windows PE")
		Exit
	EndIf

	; Start debugging in the background
	$intDebugPID = Run(@ScriptFullPath & " hotkey", @ScriptDir, @SW_HIDE)

	; Build the background GUI - unclickable, un-"on top"-able Window that makes this whole process look like it's just the background art
	; The various flags will also keep it from being visible during a control-tab sequence
	$hwndMainWindow = GUICreate("Main", @DesktopWidth, @DesktopHeight, 0, 0, BitOR($WS_DISABLED, $WS_POPUP, $WS_BORDER, $WS_CLIPSIBLINGS), $WS_EX_TOOLWINDOW)
	$hwndMainPicture = GUICtrlCreatePic(@WindowsDir & "\System32\winpe.bmp", 0, 0, @DesktopWidth, @DesktopHeight)
	GUICtrlSetState(-1, $GUI_DISABLE)
	GUISetState()

	; Start WINPE's plug-n-play service
	$intPnPText = _WindowText("Plug and Play detection")
	$intResult1 = Run(@ScriptFullPath & " wpeinit", @ScriptDir, @SW_HIDE)
	;Get ProcessID of wpeinit
	ProcessWait("wpeinit.exe")
	$intWPEInitPID = ProcessExists("wpeinit.exe")
	; Set the priority on that service to uber-high, because otherwise it sometimes sucks and takes forever
	$colProcesses = $gobjWMI.ExecQuery("Select Priority from Win32_Process Where ProcessID = " & $intWPEInitPID)
	For $objProcess In $colProcesses
		$objProcess.SetPriority(256)
	Next
	; Check for Build Accelerator functions
	If FileExists("C:\Recovery.ini") Then
		$strBuildAccelerate_Method = IniRead("C:\Recovery.ini", "Build Accelerator", "Method", "")
		$strBuildAccelerate_Target = IniRead("C:\Recovery.ini", "Build Accelerator", "Target", "")

		If $strBuildAccelerate_Method <> "" Then
			$blnBuildAccelerate = True
		EndIf
	EndIf

	; Machine-specific support starts here
	$objCol = $gobjWMI.ExecQuery("Select Name from Win32_ComputerSystemProduct")
	If @error Then
		; huh?  Epic failure!
		MsgBox(48, "Hardware Failure", "This hardware platform is not supported for this version of the Taco Bell AutoBuild.")
		_Shutdown(5)

	Else
		; pull the name value from the machine
		For $objName In $objCol
			$strThisName = $objName.Name
			ExitLoop
		Next

		; For each hardware model...
		If ($strThisName = "POS 4Xp") Or ($strThisName = "ViGo") Or ($strThisName = "POS6") Then ;  needs TWTouch driver and PAR OS base
			; launch twtouch setup
			If $blnBuildAccelerate = False Then
				$intResult2 = Run(@ScriptFullPath & " partouch")
				; Calibration file is...
				$gstrTouchCalibrateEXE = "X:\Program Files\MicroTouch\MT 7\TWCalib.exe"
			Else
				$intResult2 = 0
			EndIf
			$gstrImageName = "PAR"
		ElseIf ($strThisName = "EverServ 7700-20") Or ($strThisName = "EverServ 7700B-20") Then
			; EverServe 7000 Series  11/13/2012  Eric
			; launch twtouch setup
			If $blnBuildAccelerate = False Then
				$intResult2 = Run(@ScriptFullPath & " partouch")
				; Calibration file is...
				$gstrTouchCalibrateEXE = "X:\Program Files\MicroTouch\MT 7\TWCalib.exe"
			Else
				$intResult2 = 0
			EndIf
			$gstrLoadNetworkDrive = "drvload X:\WinPE\Drivers\IntelPro1000\e1c6032.inf"
			$gstrImageName = "PAR"
		ElseIf $strThisName = "4852E66" Or ($strThisName = "4852566") Then ; needs ELO Touch driver and IBM SurePOS 500 OS base
			; launch elotouch setup
			If $blnBuildAccelerate = False Then
				$intResult2 = Run(@ScriptFullPath & " elotouch", @ScriptDir, @SW_HIDE)
				; Calibration file is...
				$gstrTouchCalibrateEXE = "X:\WinPE\Drivers\ELOTouch\EloEloVA.exe"
			Else
				$intResult2 = 0
			EndIf
			$gstrLoadNetworkDrive = "drvload X:\WinPE\Drivers\IntelPro1000\e1c6032.inf"
			$gstrImageName = "IBM SurePOS 500"
		ElseIf $strThisName = "4852E70" Then ; needs ELO Touch driver and Toshiba SurePOS 500 OS base
			; launch elotouch setup
			If $blnBuildAccelerate = False Then
				$intResult2 = Run(@ScriptFullPath & " elotouch", @ScriptDir, @SW_HIDE)
				; Calibration file is...
				$gstrTouchCalibrateEXE = "X:\WinPE\Drivers\ELOTouch\EloEloVA.exe"
			Else
				$intResult2 = 0
			EndIf
			$gstrLoadNetworkDrive = "drvload X:\WinPE\Drivers\IntelPro1000\e1c6032.inf"
			$gstrImageName = "IBM SurePOS 500"
			
			; abhishek added for par and toshiba
			ElseIf $strThisName = "6140E3R" Then ; for toshiba 
			; launch elotouch setup
			;commented by abhishek for testing
			;If $blnBuildAccelerate = False Then
				;$intResult2 = Run(@ScriptFullPath & " elotouch", @ScriptDir, @SW_HIDE)
				; Calibration file is...
				;$gstrTouchCalibrateEXE = "X:\WinPE\Drivers\ELOTouch\EloEloVA.exe"
			;Else
				;$intResult2 = 0
			;EndIf
			;$gstrLoadNetworkDrive = "drvload X:\WinPE\Drivers\IntelPro1000\e1c6032.inf"
			$gstrImageName = "PAR"
			ElseIf $strThisName = "EverServ 8300" Then ; For Par machine
			; launch elotouch setup
			;commented by abhishek for testing
			;If $blnBuildAccelerate = False Then
				;$intResult2 = Run(@ScriptFullPath & " elotouch", @ScriptDir, @SW_HIDE)
				; Calibration file is...
				;$gstrTouchCalibrateEXE = "X:\Program Files\MicroTouch\MT 7\TWCalib.exe"
			;Else
				;$intResult2 = 0
			;EndIf
			;$gstrLoadNetworkDrive = "drvload X:\WinPE\Drivers\IntelPro1000\e1c6032.inf"
			$gstrImageName = "PAR"
			;end code
			
			
		ElseIf ($strThisName = "7403-1001-8801") Or ($strThisName = "7403-1200-8801") Then ;needs TSharc Touch driver and NCR 7403 OS base
			; launch tsharc setup
			If $blnBuildAccelerate = False Then
				$intResult2 = Run(@ScriptFullPath & " tsharctouch")
				; Calibration file is...
				$gstrTouchCalibrateEXE = "X:\Program Files\TSharc\HWIncal.exe -q4"
			Else
				$intResult2 = 0
			EndIf
			$gstrLoadNetworkDrive = "drvload X:\WinPE\Drivers\IntelPro1000\e1c6032.inf"
			$gstrImageName = "NCR 7403"
		ElseIf ($strThisName = "7616-1200-8801") Then ;needs TSharc Touch driver and NCR 7616 OS base
			; launch tsharc setup
			If $blnBuildAccelerate = False Then
				$intResult2 = Run(@ScriptFullPath & " tsharctouch")
				; Calibration file is...
				$gstrTouchCalibrateEXE = "X:\Program Files\TSharc\HWIncal.exe -q4"
			Else
				$intResult2 = 0
			EndIf
			$gstrLoadNetworkDrive = "drvload X:\WinPE\Drivers\IntelPro1000\e1c6032.inf"
			$gstrImageName = "NCR 7403"
		ElseIf $strThisName = "VMware Virtual Platform" Then
			$gstrImageName = "PAR"

		ElseIf $strThisName = "HP d530 CMT" Then
			$gstrImageName = "BOH"

		ElseIf $strThisName = "Evo D510 CMT" Then
			$gstrImageName = "BOH"

		ElseIf $strThisName = "HP Compaq dc7100 CMT" Then
			$gstrImageName = "BOH"

		ElseIf $strThisName = "HP Compaq dc7600 CMT" Then
			$gstrImageName = "BOH"

		ElseIf $strThisName = "HP Compaq dc7700 Convertible Minitower" Then
			$gstrImageName = "BOH"

		ElseIf $strThisName = "HP Compaq dc7800 Convertible Minitower" Then
			$gstrImageName = "BOH"

		ElseIf $strThisName = "HP Compaq dc7900 Convertible Minitower" Then
			$gstrImageName = "BOH"

		ElseIf $strThisName = "HP rp5800" Then
			$gstrImageName = "BOH"
			$gstrLoadNetworkDrive = "drvload X:\WinPE\Drivers\IntelPro1000\e1c6032.inf"
		ElseIf StringStripWS($strThisName, 3) = "OptiPlex XE" Then ; dell fails and has trailing whitespace
			$gstrImageName = "BOH"
		Else
			MsgBox(48, "Hardware Failure", "This hardware platform is not supported for this version of the Taco Bell AutoBuild." & @CRLF & "HWID: " & $strThisName)
			_Shutdown(5)
		EndIf
	EndIf

	; Append POSReady2009 to image name (if we're not a BOH device)
	If $gstrImageName <> "BOH" Then
		
		;commented by abhishek for testing POSReady2007
		;$gstrImageName &= "_POSReady2009"
		
		$gstrImageName &= "_POSReady2007"
	EndIf

	; Monitor services for completion
	_ShowBusyApp_New($intResult1)
	If $intResult2 <> 0 Then ; touchscreen wait
		_ShowBusyApp_New($intResult2)
	EndIf
	GUICtrlSetData($intPnPText, "Plug and Play detection is complete")
	; VNC startup in the background
	Run("X:\WinPE\Bin\UltraVNC\winvnc.exe", "X:\WinPE\Bin\UltraVNC", @SW_HIDE)

	; Screen calibration needed?
	If $gstrTouchCalibrateEXE <> "" Then
		; do calibration until it exits with a zero result
		$intResult1 = 99
		While $intResult1 <> 0
			$intResult1 = _CalibrateTouchScreen($gstrTouchCalibrateEXE)
		WEnd
	EndIf

	; Install new network driver?
	If $gstrLoadNetworkDrive <> "" Then
		RunWait($gstrLoadNetworkDrive, @WindowsDir, @SW_HIDE)
	EndIf

	; Hardware stats go here
	$intHWStatsTxt = _WindowText("Detecting hardware statistics")
	_EnumHWInfo()
	GUICtrlSetData($intHWStatsTxt, "Hardware stats are now displayed")

	; Figure out the boot method
	$strBootMethod = _DetectBootMethod()
	Switch $strBootMethod
		Case "PXE"
			_PXEMode()
		Case "HDD"
			_HDRecovery()
		Case "DVD", "USB"
			_CDRecovery()
		Case "SNAP"
			_SnapShotRecovery()
		Case Else
			MsgBox(48, "Error", "Cannot determine boot method.  Please contact the helpdesk!")
	EndSwitch

	_LogWriter("Ending Script: Recovery.exe", $gstrLogFileDestination)

	_Reboot(1)
EndFunc   ;==>_Main


; Figure out how this box was booted
Func _DetectBootMethod()
	; Basic essentials to get the rest of this script started
	_WindowText("Detecting Boot Method")

	; Look at the registry to see if we're booting from PXE...
	$strResult = RegRead("HKLM\System\CurrentControlSet\Control", "PEBootType")
	If $strResult = "Error" Then
		; This key will tell us what physical device was used to boot the system.  If it reports error, it's due to PXE
		GUICtrlSetData(-1, "Boot Method is PXE")
		Return "PXE"

	ElseIf StringInStr($strResult, "SourceIdentified") Then
		; That stupid "SourceIdentified" string means that it booted from (what the system thinks is) a HDD -- but it might be a USB BDD...
		$strSourceDrive = RegRead("HKLM\System\CurrentControlSet\Control", "PEBootRamdiskSourceDrive")
		If @error Then
			; This is bad ...
			Return "ERR"
		EndIf

		; Strip backslash if it exists
		If StringInStr($strSourceDrive, "\") Then $strSourceDrive = StringReplace($strSourceDrive, "\", "")

		; Figure out the disk ID from the drive letter
		$intDiskID = _DiskIDFromDriveLetter($strSourceDrive)

		; Figure out the type of drive from it's ID number
		$strDriveType = _DiskTypeFromID($intDiskID)

		If $strDriveType = "HDD" Then
			If $blnBuildAccelerate = False Then
				GUICtrlSetData(-1, "Boot Method is HDD Recovery")
			Else
				If $strBuildAccelerate_Method = "AutoPXE" Then
					GUICtrlSetData(-1, "Boot Method is PXE (Build Accelerator) ")

				ElseIf $strBuildAccelerate_Method = "Unattended" Then
					$strMessage = "Boot Method is Unattended"
					$intRecovery = IniRead("C:\Recovery.ini", "Config", "IsRecovery", 0)
					If ($intRecovery = 1) Then
						$strMessage = $strMessage & " Recovery (Restore Backups)"
					Else
						$strMessage = $strMessage & " Rebuild"
					EndIf
					GUICtrlSetData(-1, $strMessage)

				ElseIf $strBuildAccelerate_Method = "Restore" Then
					GUICtrlSetData(-1, "Boot Method is Snapshot Restore (Build Accelerator) ")
					Return "SNAP"

				ElseIf $strBuildAccelerate_Method = "Create" Then
					GUICtrlSetData(-1, "Boot Method is Snapshot Create (Build Accelerator) ")
					Return "SNAP"

				Else
					GUICtrlSetData(-1, "Boot Method is UNDEFINED (Build Accelerator) ")
					MsgBox(48, "Build Accelerator Error", "An undefined function was passed via the Build Accelerate function" & @CRLF & "Standard HDD recovery will be invoked")
					$blnBuildAccelerate = False
				EndIf
			EndIf
			Return "HDD"

		ElseIf $strDriveType = "USB" Then
			GUICtrlSetData(-1, "Boot Method is USB")
			$gstrCDSource = $strSourceDrive
			Return "USB"

		Else
			GUICtrlSetData(-1, "Boot Method cannot be determined")
			Return "ERR"
		EndIf
	Else

		; Get all CD/DVD drives in the system
		Global $astrCDROMS = DriveGetDrive("CDROM")

		If @error Then
			; No CD/DVD drives were found
			GUICtrlSetData(-1, "Boot Method is HDD Recovery")
			Return "HDD"

		Else
			; Parse through all drive letters until we find one with the image file
			For $i = 1 To $astrCDROMS[0]
				;MsgBox(default,"Debug","Examining " & $astrCDROMS[$i])
				If FileExists($astrCDROMS[$i] & "\Sources\OS_Layer.wim") Or FileExists($astrCDROMS[$i] & "\Sources\BOH\OS_Layer.wim") Then
					$gstrCDSource = $astrCDROMS[$i]
					ExitLoop
				EndIf
			Next

			; If strCDROM is still blank, we never found the imagefile
			; This is probably because it came from a removable storage device (USB)
			If $gstrCDSource = "" Then
				GUICtrlSetData(-1, "Boot Method is USB Recovery")
				Return "HDD"

			Else
				GUICtrlSetData(-1, "Boot Method is DVD Recovery")
				Return "DVD"

			EndIf
		EndIf
	EndIf

	; How did we get here?
	GUICtrlSetData(-1, "Boot Method cannot be determined")
	Return "ERR"

EndFunc   ;==>_DetectBootMethod


; PXE mode partitions the drive, copies all the WIM files, drops a "PXE Flag" and forces a reboot
Func _PXEMode()
	; Need this for later determination if we booted from another register
	$astrIPPieces = StringSplit(@IPAddress1, ".")
	$strIPAddyPrefix = $astrIPPieces[1] & "." & $astrIPPieces[2] & "." & $astrIPPieces[3]

	; Is IRVLABPXE available?
	$pingResult = Ping($gstrIRVLABPXEIP)
	If $pingResult > 0 Then
		; Irvlab is our PXE source...
		$strSource = $gstrIRVLABPXEIP

	Else
		; We probably PXE'd from a register
		; Start up TCP services so we can kill any pxe services out there...
		TCPStartup()

		$strSource = ""
		For $x = 9 To 1 Step -1
			$pingResult = Ping($strIPAddyPrefix & ".2" & $x, 1000)
			If $pingResult > 0 Then
				; We use the highest-numbered responding register as our primary data source (unrelated to turning off PXE services)...
				If $strSource = "" Then
					$strSource = $strIPAddyPrefix & ".2" & $x
				EndIf

				; This is the 'disable' command that will kill the PXE listener on a register
				TCPConnect($strIPAddyPrefix & ".2" & $x, 30111)
			EndIf
		Next

		; Don't need this any more
		TCPShutdown()

		; Is our source still blank?
		If $strSource = "" Then
			MsgBox(16, "Unrecoverable Error", "No source was found for recovery data")
			_Shutdown(5)
		EndIf
	EndIf

	; Create recovery DPS file
	_CreateCleanDiskpartScript(0)

	; Confirmation prompt before blowing away the box
	_WindowText("Prompting for consent to disk wipe...")
	$intResult = MsgBox(308, "<!> FINAL CONFIRMATION WARNING <!>", "All data on this device will be permanently destroyed and replaced with factory defaults." & @CRLF & @CRLF & _
			"Do you wish to continue?")

	; If answer was anything but yes, we exit.
	If $intResult <> 6 Then
		_Shutdown(5)
	EndIf

	; Splash on!
	GUICtrlSetData(-1, "Disk wipe has been consented")

	; Execute the diskpart script
	_WindowText("Diskpart is erasing the disk")
	$intPID = Run(@ScriptFullPath & " diskpart " & Chr(34) & @TempDir & "\recovery.dps" & Chr(34), @ScriptDir, @SW_HIDE)
	_ShowBusyApp_New($intPID)
	GUICtrlSetData(-1, "Diskpart has completed erasing the disk")

	; Connect to remote server(s)
	; Behavior based on PXE boot source
	If $strSource = $gstrIRVLABPXEIP Then
		_WindowText("Connecting to file share on PXE server")
		$intPID = Run(@ScriptFullPath & " pxeconnect " & $gstrIRVLABPXEIP & "\Boot", @ScriptDir, @SW_HIDE)
		_ShowBusyApp_New($intPID)
		GUICtrlSetData(-1, "Connected to file share on IRVLABPXE")

	Else
		; Connecting to online register(s)
		$hwndRegConn = _WindowText("Connecting to alternate devices")
		$intPID = Run(@ScriptFullPath & " registerconnect", @ScriptDir, @SW_HIDE)
		_ShowBusyApp_New($intPID)
		$strRegConnectString = RegRead("HKLM\Software\POSF", "RegisterConnect")
		GUICtrlSetData($hwndRegConn, "Connected to register numbers: " & $strRegConnectString)
	EndIf

	; Make the Z: drive bootable
	_WindowText("Making local recovery drive bootable")
	$intPID = Run(@ComSpec & " /c " & Chr(34) & "x:\winpe\bin\Create BCD.cmd" & Chr(34) & " PXE Z:", "", @SW_HIDE)
	_ShowBusyApp_New($intPID)
	GUICtrlSetData(-1, "Local recovery drive is now bootable")

	; If we're booting from IRVLABPXE, we do all the stuff for allowing you to choose which image you want
	If $strSource = $gstrIRVLABPXEIP Then
		$dirList = _FileListToArray("\\" & $strSource & "\Boot\", "*", 2)
		If @error = 1 Then
			MsgBox(48, "File Server Error", "Could not find files on PXE server" & @CRLF & @CRLF & "This machine will shut off.")

			; Turn off
			_Shutdown(5)
		EndIf
		If $dirList[0] < 1 Then
			MsgBox(48, "File Server Error", "No directories found on PXE server" & @CRLF & @CRLF & "This machine will shut off.")

			; Turn off
			_Shutdown(5)
		EndIf
		_ArrayDelete($dirList, 0)

		; Build GUI to prompt user for which image to boot
		$frmGetDir = GUICreate("Select Image to Boot", 295, 110)
		GUISetFont(12.75)

		; Create combo box, place first directory found as default value
		$cbDir = GUICtrlCreateCombo($dirList[0], 20, 15, 250, 20)
		_ArrayDelete($dirList, 0)
		$dirList = _ArrayToString($dirList, "|")
		GUICtrlSetData(-1, $dirList)

		$btnOK = GUICtrlCreateButton("OK", 105, 55, 75, 35)

		GUISetState(@SW_SHOW, $frmGetDir)

		While 1
			$nMsg = GUIGetMsg()
			Switch $nMsg
				Case $GUI_EVENT_CLOSE
					ExitLoop
				Case $btnOK
					ExitLoop
			EndSwitch
		WEnd

		$directory = GUICtrlRead($cbDir)
		GUIDelete($frmGetDir)
	Else
		; If we're not booting from IRVLABPXE, then the directory is just 'sources'
		$directory = "Sources"
		If $gstrImageName = "BOH" Then
			$directory = "Sources\BOH"
		EndIf
	EndIf

	; Scan directory contents...
	; If we find Ghost files, then image disk directly over network using Ghost32.exe
	; If we find WIM files, then copy ImageX files over to local recovery partition

	$GhostSearch = FileFindFirstFile("\\" & $strSource & "\boot\" & $directory & "\*.gho")
	$ImageXSearch = FileFindFirstFile("\\" & $strSource & "\boot\" & $directory & "\*.wim")
	If $GhostSearch <> -1 Then
		; We found a Ghost file
		$file = FileFindNextFile($GhostSearch)

		$hwndCopyText = _WindowText("Preparing to ghost drive...")
		GUICtrlSetData($hwndCopyText, "Ghosting drive")
		$result = RunWait("x:\winpe\bin\ghost32.exe -CLONE,mode=LOAD,src=\\" & $strSource & "\boot\" & $directory & "\" & $file & ",dst=1 -ir -batch -sure")
		GUICtrlSetData($hwndCopyText, "Ghosting complete")

		If $result <> 0 Then
			MsgBox($MB_ICONEXCLAMATION, "Imaging Error", "Ghost completed with error code: " & $result & @CRLF & @CRLF & "This machine will shut off.")
		EndIf

	ElseIf $ImageXSearch <> -1 Then
		; things should be stored in Sources\BOH for BOH
		If $gstrImageName = "BOH" Then
			RegWrite("HKLM\Software\POSF", "SrcDir", "REG_SZ", "BOH\")
		EndIf
		; Get file sizes
		$hwndCopyText = _WindowText("Preparing to copy files...")
		$intTotalBytes = 0

		While 1
			$strThisFile = FileFindNextFile($ImageXSearch)
			If @error Then ExitLoop

			$intTotalBytes += FileGetSize("\\" & $strSource & "\boot\" & $directory & "\" & $strThisFile)
		WEnd

		; Copy Files
		GUICtrlSetData($hwndCopyText, "Copying files")
		$hwndCopyProgress = GUICtrlCreateProgress(250, $gintLeaderBoard * 20, 200, 17)

		; Kick off the copy process via recursive call to this script
		$intPID = Run(@ScriptFullPath & " pxecopy " & $strSource & " " & $directory, @ScriptDir)

		; Process that actually does the copy is RoboCopy
		ProcessWait("robocopy.exe")
		$intRoboCopyPID = ProcessExists("robocopy.exe")

		; Progress indicator stuff
		$intImageTimer = TimerInit()
		$intTotalWriteTransfer = 0
		$intLastWriteTransferCount = 0
		$intSpeed = 0

		While ProcessExists($intPID)
			$intCurrentWriteTransferCount = 0
			$objProcess = $gobjWMI.ExecQuery("select WriteTransferCount from Win32_Process where Name='robocopy.exe'")
			If @error Then
				; nop - no status for you!
			Else
				; Collect write bytes for all instances of robocopy
				For $objItem In $objProcess
					$intCurrentWriteTransferCount += $objItem.WriteTransferCount
				Next

				; Build a 'delta' between last time check and this time check
				If $intCurrentWriteTransferCount > $intTotalWriteTransfer Then
					; This really only happens at the beginning of a transfer process
					$intTotalWriteTransfer = $intCurrentWriteTransferCount

				ElseIf $intCurrentWriteTransferCount > $intLastWriteTransferCount Then
					; LoL at this whole thing...
					$intTotalWriteTransfer += ($intCurrentWriteTransferCount - $intLastWriteTransferCount)
				EndIf

				; Calculate speed and percentage values
				$intSpeed = ($intTotalWriteTransfer / TimerDiff($intImageTimer) / 1048.576) * 60 ; rip the * 60 off the end of this, and you have MB per second
				$intPercent = ($intTotalWriteTransfer / $intTotalBytes) * 100 ; percentage complete of unpack

				; Update GUI
				GUICtrlSetData($hwndCopyText, "Copying files at " & Round($intSpeed, 1) & " MB per minute")
				GUICtrlSetData($hwndCopyProgress, $intPercent)

				; Reset counter so we can process delta on next loop
				$intLastWriteTransferCount = $intCurrentWriteTransferCount
			EndIf

			Sleep(1000) ; Update speed indicator once per second so we don't peg out the crappy Vigo and Par 4Xp processors :-(

		WEnd

		; if we're on a boh machine, make sure to copy the boot files to the right spot
		If $gstrImageName = "BOH" Then
			FileCopy("z:\sources\BOH\boot.*", "z:\sources\")
		EndIf

		; Give status
		GUICtrlSetData($hwndCopyText, "Copy is complete")
		GUICtrlDelete($hwndCopyProgress)

	Else
		;We didn't find a Ghost or ImageX file - so display an error and then just shut down.
		MsgBox($MB_ICONEXCLAMATION, "Imaging Error", "No image files found in " & $directory & @CRLF & @CRLF & "This machine will shut off.")
	EndIf


	; Shutdown or reboot, depending on what's up...
	If $strSource = $gstrIRVLABPXEIP Then
		_Shutdown(1)
	Else
		_Reboot(1)
	EndIf

EndFunc   ;==>_PXEMode

; Connect to as many registers as possible to pull data
Func _PXE_RegisterConnect()
	; Figure out IP subnet stuff
	Local $astrIPPieces = StringSplit(@IPAddress1, ".")
	$strIPAddyPrefix = $astrIPPieces[1] & "." & $astrIPPieces[2] & "." & $astrIPPieces[3]

	_LogWriter("_PXE_RegisterConnect,Local IP Prefix: " & $strIPAddyPrefix, $gstrLogFileDestination)

	$strConnectedRegisters = ""

	; Step through each register with a ping statement
	For $x = 1 To 9
		_LogWriter("_PXE_RegisterConnect,Ping register: " & $strIPAddyPrefix & ".2" & $x, $gstrLogFileDestination)
		$intPingResult = Ping($strIPAddyPrefix & ".2" & $x, 1000)
		If $intPingResult > 0 Then
			_LogWriter("_PXE_RegisterConnect,Ping success", $gstrLogFileDestination)
			; found a register that responds to pings - can we map to the boot share via the Iris User account?
			_LogWriter("_PXE_RegisterConnect,DriveMapAdd: " & $strIPAddyPrefix & ".2" & $x & "\boot", $gstrLogFileDestination)
			$intMapResult = DriveMapAdd("", "\\" & $strIPAddyPrefix & ".2" & $x & "\boot", 0, "iris_user", "#12345VigoImage")

			If $intMapResult = 1 Then
				; map worked!
				If $strConnectedRegisters = "" Then
					$strConnectedRegisters = $x
				Else
					$strConnectedRegisters &= "," & $x
				EndIf
				_LogWriter("_PXE_RegisterConnect,DriveMapAdd success", $gstrLogFileDestination)
			Else
				$interrorval = @error
				$interrorext = @extended
				If $interrorval = 1 Then
					_LogWriter("_PXE_RegisterConnect,DriveMapAdd failed with WinAPI result " & $interrorext, $gstrLogFileDestination)
				Else
					_LogWriter("_PXE_RegisterConnect,DriveMapAdd failed with internal result " & $interrorval, $gstrLogFileDestination)
				EndIf
			EndIf
		Else
			_LogWriter("_PXE_RegisterConnect,Ping failure", $gstrLogFileDestination)
		EndIf
	Next

	_LogWriter("_PXE_RegisterConnect,Connected register IDs: " & $strConnectedRegisters, $gstrLogFileDestination)

	If $strConnectedRegisters = "" Then
		MsgBox(48, "Network Error", "Could not connect to any of the available devices.  Please ensure this machine is connected properly to the network, and that other devices are powered on." & @CRLF & @CRLF & "This machine will shut off.")

		; Turn off
		_Shutdown(5)
	EndIf

	RegWrite("HKLM\Software\POSF", "RegisterConnect", "REG_SZ", $strConnectedRegisters)
EndFunc   ;==>_PXE_RegisterConnect


; Connect to a remote server to pull data
; Right now, it's only IRVLABPXE.  Later, it might be another register?
Func _PXE_ConnectTo($strServer)

	If $strServer = $gstrIRVLABPXEIP & "\Boot" Then
		$strUserID = "IRVLABPXE\PXEBoot"
		$strUserPW = "Ilovepixies!"
	EndIf

	$intResult = DriveMapAdd("M:", "\\" & $strServer, 0, $strUserID, $strUserPW)
	If @error Then
		Switch @error
			Case 1
				GUICtrlSetData(-1, "Error: Windows API error " & @extended)

			Case 2
				GUICtrlSetData(-1, "Error: Access is denied to " & $strServer & "\Boot share")

			Case 5
				GUICtrlSetData(-1, "Error: The share " & $strServer & "\Boot does not seem to exist")

			Case 6
				GUICtrlSetData(-1, "Error: logon failed due to wrong password")

			Case Else
				GUICtrlSetData(-1, "Error: Unknown connection error")

		EndSwitch
		MsgBox(48, "Network Error", "Could not connect to " & $strServer & @CRLF & @CRLF & "This machine will shut off.")

		; Turn off
		_Shutdown(5)
	EndIf
EndFunc   ;==>_PXE_ConnectTo


Func _PXE_DoRoboCopy($server, $srcDir = "")
	$strSrcDir = "" ; in case nothing in the registry
	$strSrcDir = RegRead("HKLM\Software\POSF", "SrcDir")
	; Figure out IP subnet stuff
	Local $astrIPPieces = StringSplit(@IPAddress1, ".")
	If Not IsArray($astrIPPieces) Then
		MsgBox(Default, Default, "No IP address?" & @CRLF & @IPAddress1)
		Exit
	EndIf
	$strIPAddyPrefix = $astrIPPieces[1] & "." & $astrIPPieces[2] & "." & $astrIPPieces[3]

	; What hardware is this?
	$strMachineType = ""
	$objCol = $gobjWMI.ExecQuery("Select Name from Win32_ComputerSystemProduct")
	If @error Then
		; nop
	Else
		; pull the name value from the machine
		For $objName In $objCol
			$strMachineType = $objName.Name
			ExitLoop
		Next
	EndIf

	_LogWriter("_PXE_DoRoboCopy,Local IP Prefix: " & $strIPAddyPrefix, $gstrLogFileDestination)
	_LogWriter("_PXE_DoRoboCopy,Server: " & $server & @TAB & "SourceDir: " & $srcDir, $gstrLogFileDestination)

	; Copy failure Retries - 10
	; Wait time between retries - 10 seconds
	; No progress indication (since it's a hidden window anyway)
	; Inter-Packet Gap depends -- 360msec for IRVLABPXE (~25mbit bandwidth per workstation via 1Gbps link - see also http://en.wikipedia.org/wiki/Robocopy#Bandwidth_throttling )
	;                             36msec for ViGo's and Par 4Xp's during an in-store recovery (about 8mbit via 100Mbps link)
	;							  12msec for everything else during an in-store recovery (about 25mbit via 100Mbps link)
	; kicking up the speed for irvlabpxe, so slowwwwww
	If $server = $gstrIRVLABPXEIP Then
		If StringStripWS($strMachineType, 3) = "OptiPlex XE" Then ; keep BOH fast for testing
			$IPG = 90
		ElseIf $strMachineType = "EverServ 7700-20" Or $strMachineType = "7616-1200-8801" Or $strMachineType = "4852E70" Then ; FOH fast testing
			$IPG = 90
		Else
			; General rule for everyone else
			$IPG = 360
		EndIf
	Else
		If ($strMachineType = "ViGo") Or ($strMachineType = "POS 4Xp") Then
			; Vigo's network interface sucks!
			; 4Xp's network interface is actually far better than the ViGo, but they're bus-limited
			$IPG = 36
		Else
			; Everything else is pretty decent and can take a bit of abuse
			$IPG = 12
		EndIf
	EndIf

	_LogWriter("_PXE_DoRoboCopy,Interpacket gap: " & $IPG, $gstrLogFileDestination)

	; Source folder: \\$server\Boot\$srcDir
	; Destination folder: Z:\Sources
	; files of type:  *.WIM
	$intResult = 0
	$intResult2 = 0
	If FileExists("\\" & $server & "\boot\" & $srcDir & "\VigoWePOS_image.wim") Then
		; Working with an older build version, copy fat image to root rather than sources directory
		_LogWriter("_PXE_DoRoboCopy,Copying 'old' image method", $gstrLogFileDestination)
		$intResult = RunWait("robocopy.exe /r:10 /w:10 /np /ipg:" & $IPG & " \\" & $server & "\boot\" & $srcDir & "\ Z:\ VigoWePOS_image.wim", "", @SW_HIDE)
		$intResult2 = RunWait("robocopy.exe /r:10 /w:10 /np /ipg:" & $IPG & " \\" & $server & "\boot\" & $srcDir & "\ Z:\sources\ boot.wim", "", @SW_HIDE)
	Else
		; Old process for server source: IRVLABPXE
		If $server = $gstrIRVLABPXEIP Then
			; Copy all WIM files to sources directory
			_LogWriter("_PXE_DoRoboCopy,Copying via 'new' image method", $gstrLogFileDestination)
			$intResult = RunWait("robocopy.exe /r:10 /w:10 /np /ipg:" & $IPG & " \\" & $server & "\boot\" & $srcDir & "\ Z:\sources\" & $strSrcDir & " *.wim", "", @SW_HIDE)
			$intResult = RunWait("robocopy.exe /r:10 /w:10 /np /ipg:" & $IPG & " \\" & $server & "\boot\" & $srcDir & "\ Z:\sources\" & $strSrcDir & " *.md5", "", @SW_HIDE)
			$intResult = RunWait("robocopy.exe /r:10 /w:10 /np /ipg:" & $IPG & " \\" & $server & "\boot\" & $srcDir & "\ Z:\sources\" & $strSrcDir & " *.txt", "", @SW_HIDE)
			If FileExists("\\" & $server & "\boot\" & $srcDir & "\Third_Party_Applications") Then
				$intResult = RunWait("robocopy.exe /r:10 /w:10 /np /ipg:" & $IPG & " \\" & $server & "\boot\" & $srcDir & "\Third_Party_Applications\ Z:\sources\" & $strSrcDir & "\Third_Party_Applications" & " *.wim", "", @SW_HIDE)
				$intResult = RunWait("robocopy.exe /r:10 /w:10 /np /ipg:" & $IPG & " \\" & $server & "\boot\" & $srcDir & "\Third_Party_Applications\ Z:\sources\" & $strSrcDir & "\Third_Party_Applications" & " *.md5", "", @SW_HIDE)
			EndIf
		Else
			; New process for pulling multiple files from multiple registers...
			_LogWriter("_PXE_DoRoboCopy,Copying via register recovery", $gstrLogFileDestination)

			; Build an 'online registers' array, populate with all false data
			Dim $astrRegisters[10][2]
			For $x = 0 To 9
				$astrRegisters[$x][0] = False
				$astrRegisters[$x][1] = False
			Next

			; Now populate that false array with the registers that are online
			$strRegisters = RegRead("HKLM\Software\POSF", "RegisterConnect")
			$astrResult = StringSplit($strRegisters, ",")
			For $x = 1 To $astrResult[0]
				If $x = "" Then
					; nop
				Else
					_LogWriter("_PXE_DoRoboCopy,Marking register " & $x & " as online", $gstrLogFileDestination)
					$astrRegisters[Int($astrResult[$x])][0] = True
				EndIf
			Next

			; Obtain a list of files from the first register we found that was online
			$astrFiles = 0
			For $x = 1 To 9
				If $astrRegisters[$x][0] = True Then
					; This register has an open connection
					_LogWriter("_PXE_DoRoboCopy,Pulling file data from device " & $x, $gstrLogFileDestination)

					; get file list from that register's recovery partition...
					$hwndSourceFiles = FileFindFirstFile("\\" & $strIPAddyPrefix & ".2" & $x & "\boot\" & $srcDir & "\*.wim")
					While 1
						; List of files
						$strThisFile = FileFindNextFile($hwndSourceFiles)
						If @error Then
							ExitLoop
						EndIf

						; Ignore snapshot files
						If $strThisFile = "snapshot.wim" Then
							; nop
						Else
							; Resize the file array
							If Not IsArray($astrFiles) Then
								Dim $astrFiles[2][4]
							Else
								ReDim $astrFiles[UBound($astrFiles) + 2][4]
							EndIf

							; First element - file name
							; Second element - file size
							; Third element - Register number that is doing this particular copy (0 = not copying right now, -1 = done copying)
							; Fourth element - the source directory, which in this case, will always be "sources".  Later, it might be something else ?
							$astrFiles[UBound($astrFiles) - 2][0] = $strThisFile
							$astrFiles[UBound($astrFiles) - 2][1] = FileGetSize("\\" & $strIPAddyPrefix & ".2" & $x & "\boot\" & $srcDir & "\" & $strThisFile)
							$astrFiles[UBound($astrFiles) - 2][2] = 0
							$astrFiles[UBound($astrFiles) - 2][3] = $srcDir
							; Now for the associated MD5 files
							$astrFiles[UBound($astrFiles) - 1][0] = StringReplace($strThisFile, ".wim", ".md5", -1, False)
							$astrFiles[UBound($astrFiles) - 1][1] = FileGetSize("\\" & $strIPAddyPrefix & ".2" & $x & "\boot\" & $srcDir & "\" & $astrFiles[UBound($astrFiles) - 1][0])
							$astrFiles[UBound($astrFiles) - 1][2] = 0
							$astrFiles[UBound($astrFiles) - 1][3] = $srcDir

							_LogWriter("_PXE_DoRoboCopy,Adding file: " & $srcDir & "\" & $strThisFile & @TAB & "Bytes:" & $astrFiles[UBound($astrFiles) - 1][1], $gstrLogFileDestination)
							; Each file gets it's own registry entry for status - 0 means it isn't copied, 1 means it's in progress, 2 means it's done, 3 means it failed)
							RegWrite("HKLM\Software\POSF", $strThisFile, "REG_DWORD", 0)
						EndIf
					WEnd

					; Grab the version text
					If FileExists("\\" & $strIPAddyPrefix & ".2" & $x & "\boot\" & $srcDir & "\VersionNumber.txt") Then
						; Resize the file array
						If Not IsArray($astrFiles) Then
							Dim $astrFiles[1][4]
						Else
							ReDim $astrFiles[UBound($astrFiles) + 1][4]
						EndIf

						$astrFiles[UBound($astrFiles) - 1][0] = "VersionNumber.txt"
						$astrFiles[UBound($astrFiles) - 1][1] = FileGetSize("\\" & $strIPAddyPrefix & ".2" & $x & "\boot\" & $srcDir & "\VersionNumber.txt")
						$astrFiles[UBound($astrFiles) - 1][2] = 0
						$astrFiles[UBound($astrFiles) - 1][3] = $srcDir
					EndIf

					; get file list from that register's recovery partition boot folder...
					$hwndBootFiles = FileFindFirstFile("\\" & $strIPAddyPrefix & ".2" & $x & "\boot\boot\*.*")
					While 1
						; List of files
						$strThisFile = FileFindNextFile($hwndBootFiles)
						If @error Then
							ExitLoop
						EndIf

						; Resize the file array
						If Not IsArray($astrFiles) Then
							Dim $astrFiles[1][4]
						Else
							ReDim $astrFiles[UBound($astrFiles) + 1][4]
						EndIf

						; First element - file name
						; Second element - file size
						; Third element - Register number that is doing this particular copy (0 = not copying right now, -1 = done copying)
						$astrFiles[UBound($astrFiles) - 1][0] = $strThisFile
						$astrFiles[UBound($astrFiles) - 1][1] = FileGetSize("\\" & $strIPAddyPrefix & ".2" & $x & "\boot\Boot\" & $strThisFile)
						$astrFiles[UBound($astrFiles) - 1][2] = 0
						$astrFiles[UBound($astrFiles) - 1][3] = "Boot"

						_LogWriter("_PXE_DoRoboCopy,Adding file: boot\" & $strThisFile & @TAB & "Bytes:" & $astrFiles[UBound($astrFiles) - 1][1], $gstrLogFileDestination)
						; Each file gets it's own registry entry for status - 0 means it isn't copied, 1 means it's in progress, 2 means it's done, 3 means it failed)
						RegWrite("HKLM\Software\POSF", $strThisFile, "REG_DWORD", 0)
					WEnd

					ExitLoop
				EndIf
			Next

			; Did we get an array?
			If Not IsArray($astrFiles) Then
				_LogWriter("_PXE_DoRoboCopy,NO files were found", $gstrLogFileDestination)
				MsgBox(16, "Unrecoverable Error", "File search returned an empty result - No files were found to copy!")
				_Shutdown(5)
				Exit
			EndIf

			; Sort the file array by size, we want the biggest ones first
			_LogWriter("_PXE_DoRoboCopy,Sorting array", $gstrLogFileDestination)
			_ArraySort($astrFiles, 1, 0, 0, 1)

			; Start handing out file copies
			_LogWriter("_PXE_DoRoboCopy,Outer loop begin...", $gstrLogFileDestination)
			While 1
				; Find a file that needs to be copied
				For $x = 0 To UBound($astrFiles) - 1
					If $astrFiles[$x][2] = 0 Then
						; find an available register that isn't being copied from yet (starting high to low)
						For $y = 9 To 1 Step -1
							If ($astrRegisters[$y][0] = True) And ($astrRegisters[$y][1] = False) Then
								_LogWriter("_PXE_DoRoboCopy,Register " & $y & " to copy file " & $astrFiles[$x][0], $gstrLogFileDestination)
								; We have an available register that isn't copying, and a file that needs copying!  Mark them both as busy
								$astrRegisters[$y][1] = True
								$astrFiles[$x][2] = $y

								; Copy stuff
								If StringInStr($astrFiles[$x][0], " ") Then
									; space in the file name - needed quote characters
									Run(@ScriptFullPath & " MultiThreadedCopy " & $IPG & " " & $y & " " & Chr(34) & $astrFiles[$x][0] & Chr(34) & " " & $astrFiles[$x][3], "", @SW_HIDE)
								Else
									; no space in teh file name, no quote chars!
									Run(@ScriptFullPath & " MultiThreadedCopy " & $IPG & " " & $y & " " & $astrFiles[$x][0] & " " & $astrFiles[$x][3], "", @SW_HIDE)
								EndIf

								If @error Then
									; Couldn't launch?  Hmm...
									_LogWriter("_PXE_DoRoboCopy,Could not perform recursive launch", $gstrLogFileDestination)
									$astrRegisters[$y][1] = False
									$astrFiles[$x][2] = 0
								Else
									; We're good for this particular register + file combo
									ExitLoop
								EndIf
							EndIf
						Next
					EndIf

					; Cleanup portion
					If $astrFiles[$x][2] > 0 Then
						$intResult = RegRead("HKLM\Software\POSF", $astrFiles[$x][0])
						If $intResult = 2 Then
							_LogWriter("_PXE_DoRoboCopy,Register " & $astrFiles[$x][2] & " completed copying file " & $astrFiles[$x][0], $gstrLogFileDestination)
							; This register is no longer busy
							$astrRegisters[$astrFiles[$x][2]][1] = False
							; file copy succeeded, mark it as complete
							$astrFiles[$x][2] = -1

						ElseIf $intResult = 3 Then
							_LogWriter("_PXE_DoRoboCopy,Register " & $astrFiles[$x][2] & " failed while copying file " & $astrFiles[$x][0], $gstrLogFileDestination)
							; this register is no longer busy
							$astrRegisters[$astrFiles[$x][2]][1] = False
							; But, this register seems to be failing file copies, so we should probably remove it from the list of available devices...
							$astrRegisters[$astrFiles[$x][2]][0] = False
							; file copy failed, mark it as incomplete
							$astrFiles[$x][2] = 0
						EndIf
					EndIf
				Next

				; Check for completion of all files
				$blnDone = True
				For $x = 0 To UBound($astrFiles) - 1
					If $astrFiles[$x][2] <> -1 Then
						$blnDone = False
						ExitLoop
					EndIf
				Next

				If $blnDone Then
					; yay!
					ExitLoop
				Else
					; Boo!
					Sleep(250)
				EndIf
			WEnd
		EndIf
	EndIf

	; Did the file copy work?
	If @error Then
		$blnResult = False
		_LogWriter("_PXE_DoRoboCopy,Robocopy launch failed."& $gstrLogFileDestination)
		MsgBox(16, "Unrecoverable Error", "Robocopy could not be started")

	ElseIf $intResult > 7 Or $intResult2 > 7 Then
		; Errorlevel return of 8 or higher mean that at least one failure was encountered
		$blnResult = False
		_LogWriter("_PXE_DoRoboCopy,Robocopy returned error results " & $intResult & "|" & $intResult2, $gstrLogFileDestination)
		MsgBox(16, "Unrecoverable Error", "File copy from PXE server failed")

	Else
		; Errorlevel return of 7 or lower mean that all file copy operations succeeded
		_LogWriter("_PXE_DoRoboCopy,File copy is complete.", $gstrLogFileDestination)
		$blnResult = True
	EndIf

	; Copy the Boot.SDI file
	If $server = $gstrIRVLABPXEIP Then
		_LogWriter("_PXE_DoRoboCopy,Getting boot.sdi", $gstrLogFileDestination)
		FileCopy("\\" & $server & "\boot\boot.sdi", "Z:\boot\", 9)
	EndIf

	; done
	_LogWriter("_PXE_DoRoboCopy,Termination [x]", $gstrLogFileDestination)
EndFunc   ;==>_PXE_DoRoboCopy


; Special copy function written for pulling files from individual registers
; Only used during a PXE boot recovery from another register
Func _PXE_DoMultiThreadedCopy($IPG, $intRegisterSource, $strWimFile, $strPath)
	; Figure out IP subnet stuff
	Local $astrIPPieces = StringSplit(@IPAddress1, ".")
	$strIPAddyPrefix = $astrIPPieces[1] & "." & $astrIPPieces[2] & "." & $astrIPPieces[3]
	$strSource = $strIPAddyPrefix & ".2" & $intRegisterSource
	$strMD5File = StringReplace($strWimFile, ".wim", ".md5")

	; Spaces cause problems :)
	If StringInStr($strWimFile, " ") Then
		$strFile = Chr(34) & $strWimFile & Chr(34)
	EndIf

	; Mark the file as 'in progress' in the registry
	RegWrite("HKLM\Software\POSF", $strWimFile, "REG_DWORD", 1)

	$intResult2 = RunWait("robocopy.exe /r:10 /w:10 /np /ipg:" & $IPG & " \\" & $strSource & "\boot\" & $strPath & "\ Z:\" & $strPath & " " & $strMD5File, "", @SW_HIDE)
	$intResult = RunWait("robocopy.exe /r:10 /w:10 /np /ipg:" & $IPG & " \\" & $strSource & "\boot\" & $strPath & "\ Z:\" & $strPath & " " & $strWimFile, "", @SW_HIDE)

	; Did the file copy work?
	If @error Then
		; wut?
		$blnResult = False

	ElseIf $intResult > 7 Then
		; Errorlevel return of 8 or higher mean that at least one failure was encountered
		$blnResult = False

	Else
		; Errorlevel return of 7 or lower mean that all file copy operations succeeded eventually
		$blnResult = True
	EndIf

	; Return data to registry
	If $blnResult = True Then
		; Good news - 2 = finished without issue
		RegWrite("HKLM\Software\POSF", $strWimFile, "REG_DWORD", 2)
	Else
		; Bad news - 3 = finished with epic facepalm
		RegWrite("HKLM\Software\POSF", $strWimFile, "REG_DWORD", 3)
	EndIf

	; done
	Exit
EndFunc   ;==>_PXE_DoMultiThreadedCopy


; This does the actual file copy during the DVD process so the "parent" process can track file copy status / percentage
Func _DVD_DoCopy()
	; Read back the optical drive letter
	$gstrCDSource = RegRead("HKLM\Software\POSF", "RecoveryDVD")

	; Copy Files
	$intResult = DirCopy($gstrCDSource, "Z:", 1)
	If $intResult = 0 Then
		MsgBox(16, "Unrecoverable Error", "One or more files failed to copy from DVD")
		; Turn off
		_Shutdown()
	EndIf

	Exit
EndFunc   ;==>_DVD_DoCopy


; Performs snapshot functions for Build Accelerator
Func _SnapShotRecovery()
	; What snapshot function are we doing?
	If $strBuildAccelerate_Method = "Create" Then
		_WindowText("Creating drive snapshot: " & $strBuildAccelerate_Target)
	Else
		_WindowText("Restoring drive snapshot: " & $strBuildAccelerate_Target)
	EndIf

	; What are we doing?  Creating, or restoring?
	If $strBuildAccelerate_Method = "Restore" Then

		#region Restore Snapshot

			; I guess the file needs to exist, right?
			If Not FileExists("C:\Snapshot.wim") Then
				_WindowText("No snapshot file available")
				MsgBox(48, "Build Accelerator Error", "No snapshot file exists on the recovery drive" & @CRLF & " This process cannot continue")
				_Reboot(1)
			EndIf

			; Create a DiskPart script in temp directory, flag 2 = erase any previous file and open in write mode
			_WindowText("Creating diskpart script for recovery")
			; Create recovery DPS file
			_CreateRecoveryDiskpartScript(0)

			; Create a DiskPart script in temp directory, flag 2 = erase any previous file and open in write mode
			$objDPSFile = _ScriptOpen(@TempDir, "final.dps", 2)

			; Create final DPS file
			; Select our physical disk ID that we detected
			_dpsMakePartitionActive($objDPSFile, 0, 1)
			; Close final DPS file
			FileClose($objDPSFile)
			GUICtrlSetData(-1, "Done creating diskpart scripts")

			; Execute the 'recovery' diskpart script
			_WindowText("Executing diskpart scripts")
			$intPID = Run(@ScriptFullPath & " diskpart " & Chr(34) & @TempDir & "\recovery.dps" & Chr(34), @ScriptDir, @SW_HIDE)
			_ShowBusyApp_New($intPID)
			GUICtrlSetData(-1, "Diskpart has completed")

			; Begin restoring the snapshot
			$hwndImageText = _WindowText("Writing snapshot data")
			$hwndImageProgress = GUICtrlCreateProgress(250, $gintLeaderBoard * 20, 200, 17)

			; Get uncompressed size of this image
			$intTotalBytes = _EnumWIMSize("C:\Snapshot.wim", $strBuildAccelerate_Target)

			; Apply the Snapshot image to disk
			$intImageXPid = Run(@ScriptFullPath & " restore " & Chr(34) & $strBuildAccelerate_Target & Chr(34))
			ProcessWait("imagex.exe")
			$intImageTimer = TimerInit()
			While ProcessExists("imagex.exe")
				$objProcess = $gobjWMI.ExecQuery("select WriteTransferCount from Win32_Process where Name='imagex.exe'")
				If @error Then
					; nop - no status for you!
				Else
					For $objItem In $objProcess
						$intCurrentWriteBytes = $objItem.WriteTransferCount
						$intSpeed = ($intCurrentWriteBytes / TimerDiff($intImageTimer) / 1048.576) * 60 ; rip the * 60 off the end of this, and you have MB per second
						$intPercent = ($intCurrentWriteBytes / $intTotalBytes) * 100 ; percentage complete of unpack
						GUICtrlSetData($hwndImageText, "Imaging disk at " & Round($intSpeed, 1) & " MB per minute")
						GUICtrlSetData($hwndImageProgress, $intPercent)
						ExitLoop
					Next
				EndIf

				Sleep(1000) ; so ee don't peg out the crappy Vigo processor :-(
			WEnd

			; Clean up the gui
			GUICtrlSetData($hwndImageText, "Shapshot restore is complete")
			GUICtrlDelete($hwndImageProgress)

			; And now, final stages...
			;  Copy recovery.ini
			FileCopy("C:\Recovery.ini", "Z:\", 1)

			; Execute the 'final' diskpart script
			_WindowText("Starting final diskpart script")
			$intPID = Run(@ScriptFullPath & " diskpart " & Chr(34) & @TempDir & "\final.dps" & Chr(34), @ScriptDir, @SW_HIDE)
			_ShowBusyApp_New($intPID)
			GUICtrlSetData(-1, "Final diskpart script has completed.")

		#endregion Restore Snapshot

	Else

		#region Create snapshot

			; Create a DiskPart script in temp directory, flag 2 = erase any previous file and open in write mode
			$objDPSFile = _ScriptOpen(@TempDir, "final.dps", 2)

			; Create final DPS file
			; Select our physical disk ID that we detected, Select the first partition, make active
			_dpsMakePartitionActive($objDPSFile, 0, 1)
			; Close final DPS file
			FileClose($objDPSFile)
			GUICtrlSetData(-1, "Done creating diskpart scripts")

			; Begin creating the snapshot
			$hwndImageText = _WindowText("Creating snapshot data")
			$hwndImageProgress = GUICtrlCreateProgress(250, $gintLeaderBoard * 20, 200, 17)

			; Get size of this disk - with 'fudge factor' of two
			$intTotalBytes = Int(IniRead("C:\Recovery.ini", "Build Accelerator", "Size", 1048576)) * 2

			; Write the Snapshot image to disk
			$intImageXPid = Run(@ScriptFullPath & " create " & Chr(34) & $strBuildAccelerate_Target & Chr(34))
			ProcessWait("imagex.exe")
			$intImageTimer = TimerInit()
			While ProcessExists("imagex.exe")
				$objProcess = $gobjWMI.ExecQuery("select ReadTransferCount from Win32_Process where Name='imagex.exe'")
				If @error Then
					; nop - no status for you!
				Else
					For $objItem In $objProcess
						$intCurrentWriteBytes = $objItem.ReadTransferCount
						$intSpeed = ($intCurrentWriteBytes / TimerDiff($intImageTimer) / 1048.576) * 60 ; rip the * 60 off the end of this, and you have MB per second
						$intPercent = ($intCurrentWriteBytes / $intTotalBytes) * 100 ; percentage complete of unpack
						GUICtrlSetData($hwndImageText, "Imaging disk at " & Round($intSpeed, 1) & " MB per minute")
						GUICtrlSetData($hwndImageProgress, $intPercent)
						ExitLoop
					Next
				EndIf

				Sleep(1000) ; so ee don't peg out the crappy Vigo processor :-(
			WEnd

			; Clean up the gui
			GUICtrlSetData($hwndImageText, "Shapshot creation is complete")
			GUICtrlDelete($hwndImageProgress)

			; Execute the 'final' diskpart script
			_WindowText("Starting final diskpart script")
			$intPID = Run(@ScriptFullPath & " diskpart " & Chr(34) & @TempDir & "\final.dps" & Chr(34), @ScriptDir, @SW_HIDE)
			_ShowBusyApp_New($intPID)
			GUICtrlSetData(-1, "Final diskpart script has completed.")

		#endregion Create snapshot

	EndIf

	; Clean off build accelerator functions from the Recovery INI files before reboot
	IniDelete("Z:\Recovery.ini", "Build Accelerator")
	IniDelete("D:\Recovery.ini", "Build Accelerator")
	IniDelete("C:\Recovery.ini", "Build Accelerator")

	; Done!
	_Reboot(1)
EndFunc   ;==>_SnapShotRecovery


; restores a snapshot file
Func _Snapshot_Restore($strImageName)
	; When restoring an image, the name is always in quotes
	$strImageName = Chr(34) & $strImageName & Chr(34)

	; Apply!
	$intResult = RunWait("X:\WinPE\Bin\Imagex.exe /apply C:\snapshot.wim " & $strImageName & " Z:\", "", @SW_HIDE)

	If $intResult > 0 Then
		; Fail!
		MsgBox(48, "Build Accelerator Error", "Could not restore snapshot; ImageX exited with error result: " & $intResult)
		_Shutdown(1)
	EndIf

	Exit
EndFunc   ;==>_Snapshot_Restore


; Creates a snapshot file
Func _Snapshot_Create($strImageName)
	; When creating an image, the name is always in quotes
	$strImageName = Chr(34) & $strImageName & Chr(34)

	If FileExists("C:\Snapshot.wim") Then
		; add to existing
		$intResult = RunWait("X:\WinPE\Bin\Imagex.exe /append D: C:\snapshot.wim " & $strImageName, "", @SW_HIDE)
	Else
		; create new
		$intResult = RunWait("X:\WinPE\Bin\Imagex.exe /capture /compress fast D: C:\snapshot.wim " & $strImageName, "", @SW_HIDE)
	EndIf

	If $intResult > 0 Then
		; fail!
		MsgBox(48, "Build Accelerator Error", "Could not create snapshot; ImageX exited with error result: " & $intResult)
		_Reboot(1)
	EndIf

	Exit
EndFunc   ;==>_Snapshot_Create


; Performs "local" recovery process for nonremovable media
Func _HDRecovery()
	; Get all hard disks in the system
	_WindowText("Finding recovery image")
	Global $strHDSource = ""
	Global $blnSlickConversion = False
	Global $astrHDDs = DriveGetDrive("Fixed")
	Global $strSrcDir = ""
	If $gstrImageName = "BOH" Then ; if we're a SLICK machine, our sources are in a different directory
		$strSrcDir = "BOH\"
	EndIf

	If @error Then
		; No fixed drives were found - wtf?
		MsgBox(64, "Recovery failure", "Could not find any fixed disks in the system")
		_Shutdown()
	ElseIf Not IsArray($astrHDDs) Then
		; No fixed drives were found - wtf?
		MsgBox(64, "Recovery failure", "Could not find any fixed disks in the system")
		_Shutdown()
	Else
		; Parse through all drive letters until we find one with the image
		For $i = 1 To $astrHDDs[0]
			;MsgBox(default,"Debug","Examining " & $astrHDDs[$i])
			If FileExists($astrHDDs[$i] & "\Sources\OS_Layer.wim") Or FileExists($astrHDDs[$i] & "\Sources\BOH\OS_Layer.wim") Then
				$strHDSource = $astrHDDs[$i]
				GUICtrlSetData(-1, "Recovery image found")
				; Also check if we're doing a slick disk to disk conversion
				If FileExists($astrHDDs[$i] & "\SLICK_CONVERSION") Then
					$blnSlickConversion = True
				EndIf
				ExitLoop
			EndIf
		Next
	EndIf

	; If strHDSource is still blank, we never found the imagefile
	If $strHDSource = "" Then
		MsgBox(64, "Recovery failure", "Could not find the image file on any of the fixed disks")
		_Shutdown()
	EndIf

	; Gotta figure out which physical disk is linked to the partition that holds this image...
	_WindowText("Linking recovery partition to physical disk")
	$intPhysDiskID = _DiskIDfromDriveLetter($strHDSource)

	; Ok, did we find the physical disk ID?
	If $intPhysDiskID = -1 Then
		MsgBox(64, "Unrecoverable error", "Could not determine the physical disk ID for drive letter " & $strHDSource)
		_Shutdown()
	Else
		GUICtrlSetData(-1, "Fixed disk " & $intPhysDiskID & " is the recovery drive")
	EndIf

	; Create recovery DPS file
	; if it said we're doing a slick conversion and we're actually booting from the
	; second drive, write the DiskPart script specifically for that.
	; Check the IT wiki for details on the partitioning scheme during conversion
	If ($blnSlickConversion = True) Then
		If ($intPhysDiskID <> 1) Then
			; don't know how we even got here without two drives
			MsgBox(16, "Unrecoverable Error", "Can't do a slick conversion from a system without 2 drives")
			_Shutdown()
		EndIf
		GUICtrlSetData(-1, "Starting the SLICK conversion")
		; we're actually installing windows to the first disk
		$intPhysDiskID = 0
		_WindowText("Creating diskpart scripts")
		; format the primary drive
		_CreateCleanDiskpartScript($intPhysDiskID)
		; need to modify the default script slightly to make windows the Z drive
		$objDPSFile = _ScriptOpen(@TempDir, "recovery.dps", 1)
		; move recovery partition to w:
		_dpsAssignDrive($objDPSFile, $intPhysDiskID, 2, "W:")
		;point z to windows partition
		_dpsAssignDrive($objDPSFile, $intPhysDiskID, 1, "Z:")
		;set conversion drive to s:
		_dpsAssignDrive($objDPSFile, 1, 1, "S:")
		FileClose($objDPSFile); Close recovery DPS file
	Else ; we're doing a recovery drive install
		_WindowText("Creating diskpart scripts")
		_CreateRecoveryDiskpartScript($intPhysDiskID)
	EndIf

	; Create final DPS file (sets windows drive bootable)
	$objDPSFile = _ScriptOpen(@TempDir, "final.dps", 2)
	; set windows partition as active when install is done
	_dpsMakePartitionActive($objDPSFile, $intPhysDiskID, 1)
	; Close final DPS file
	FileClose($objDPSFile)

	GUICtrlSetData(-1, "Done creating diskpart scripts")

	; Execute the 'recovery' diskpart script
	_WindowText("Executing diskpart scripts")
	$intPID = Run(@ScriptFullPath & " diskpart " & Chr(34) & @TempDir & "\recovery.dps" & Chr(34), @ScriptDir, @SW_HIDE)
	_ShowBusyApp_New($intPID)
	GUICtrlSetData(-1, "Diskpart has completed")

	If $blnSlickConversion = True Then ; we need to make sure we can boot if there's a failure during the install process
		; Build the boot sector
		_WindowText("Creating boot sector")
		$intPID = Run(@ComSpec & " /c " & Chr(34) & "x:\winpe\bin\create bcd.cmd" & Chr(34) & " SLICKPXE W: S:", "", @SW_HIDE)
		_ShowBusyApp_New($intPID)
		GUICtrlSetData(-1, "Boot sector written")
	EndIf

	; A whole lot of stuff is skipped if we're in build accelerator mode
	; TODO - determine if BuildAccelerate is useful for BOH
	If $blnBuildAccelerate = False Then
		; don't use autodiscovery for BOH
		; since it is the cause of the phantom recovery.ini which contains store #0
		If $gstrImageName <> "BOH" Then
			; Do the 'auto discovery' process
			_WindowText("Autodiscovery in progress")
			$intPID = Run(@ScriptFullPath & " autodiscovery Z:", @ScriptDir, @SW_HIDE)
			_ShowBusyApp_New($intPID)
			GUICtrlSetData(-1, "Autodiscovery is complete")
		Else
			; this allows for Recovery.ini on the DR partition (disk 0 part 2) to be used
			If FileExists($DRPartitionDriveLetter & "\Recovery.ini") Then
				FileCopy($DRPartitionDriveLetter & "\Recovery.ini", "Z:\Recovery.ini", 1)
			EndIf
		EndIf

		; In cases where IRVLABPXE is available, we want to allow for the 'toggle' function
		If _isVM() Then
			; Cheater method to make Toggle run in VMWare :-)
			$pingResult = 1000
		Else
			$pingResult = Ping($gstrIRVLABPXEIP, 1000)
		EndIf
         
		 ;abhishek added code for testing
		 ;_LogWriter(" /c X:\WinPE\Bin\Imagex.exe /info C:\Sources\OS_Layer.wim > ")
		; $intResult = RunWait(@ComSpec & " /c X:\WinPE\Bin\Imagex.exe /info C:\Sources\OS_Layer.wim > " & Chr(34) & @TempDir & "\wimdata.txt" & Chr(34), "", @SW_HIDE)
		; MsgBox(64, "OS Layer install", "Result is  " & $intResult)
		 
		 ;end code
		 
		 
		 
		 
		; Do we need to run toggle?
		If $pingResult > 0 Then
			$result = RunWait($gstrSystemDrive & "\WinPE\Bin\Toggle.exe Z:")
		EndIf

		If $gstrImageName <> "BOH" Then
			; OK, kick off the GetRegInfo script to prompt the tech for all the details
			_WindowText("Prompting for register information")
			RunWait($gstrSystemDrive & "\WinPE\Bin\ConfirmRegInfo.exe Z:")
			If @error Then
				MsgBox(64, "Unrecoverable Error", "Error occurred with ConfirmRegInfo.EXE")
				_Shutdown()
			EndIf

			; skip source file validation if in "Staging" mode or invalid IP address
			$validIPAddress = _ValidIPAddress()
			$staging = IniRead("Z:\Recovery.ini", "Config", "Staging", 0)
			If $staging = 0 And $validIPAddress Then
				; Once the recovery mode and register number are selcted, we can start the source file validation process
				_ValidateSourceFiles()
			ElseIf $staging = 1 Then
				$strMessage = "Skipping validation of source files.  User selected ""Staging"" configuration."
				_WindowText($strMessage)
				_LogWriter($strMessage, $gstrLogFileDestination)
			ElseIf Not $validIPAddress Then
				$strMessage = "Skipping validation of source files.  Invalid IP address."
				_WindowText($strMessage)
				_LogWriter($strMessage, $gstrLogFileDestination)
			EndIf
		Else
			_WindowText("Prompting for SLICK information")
			$intRegNumPID = Run($gstrSystemDrive & "\WinPE\Bin\ConfirmBOHInfo.exe Z:")
			If @error Or $intRegNumPID = 0 Then
				MsgBox(64, "Unrecoverable Error", "Could not start ConfirmBOHInfo.EXE")
				_Shutdown()
			EndIf
		EndIf
	Else
		; In build accelerate mode, we do this differently
		FileCopy($strHDSource & "\Recovery.ini", "Z:\", 1)
		$intRegNumPID = 0

		; start the source file validation process
		
		_ValidateSourceFiles()

		; we also entirely bypass QA deployment if it's not needed - goes faster (obviously)
		$qa = IniRead("Z:\Recovery.ini", "Config", "QATools", 0)
		If $qa = 0 Then
			If FileExists($strHDSource & "\Sources\" & $strSrcDir & "QA_Layer.wim") Then FileDelete($strHDSource & "\Sources\" & $strSrcDir & "QA_Layer.wim")
		EndIf
	EndIf

	; Now we can start disk image application stuff
	
	$hwndImageText = _WindowText("Writing OS Layer - " & $gstrImageName)
	$hwndImageProgress = GUICtrlCreateProgress(250, $gintLeaderBoard * 20, 200, 17)
	RegWrite("HKLM\Software\POSF", "HDSource", "REG_SZ", $strHDSource)
	RegWrite("HKLM\Software\POSF", "SrcDir", "REG_SZ", $strSrcDir)
	; Apply the OS_Layer wim file
	; Get uncompressed size of this image
	_WindowText("Apply the OS_Layer wim file - ")
	_LogWriter("Before _EnumWImSize total Bytes ")
	$intTotalBytes = _EnumWIMSize($strHDSource & "\Sources\" & $strSrcDir & "OS_Layer.wim", $gstrImageName)
	$intImageXPid = Run(@ScriptFullPath & " imagewepos " & Chr(34) & $gstrImageName & Chr(34))
    _LogWriter("_EnumWImSize total Bytes " & $intTotalBytes)

      _LogWriter("Initiate OS Layer with Imagex Command ")
	ProcessWait("imagex.exe")
	_LogWriter("Process Wait Imagex ")
	$intImageTimer = TimerInit()
	While ProcessExists("imagex.exe")
	   _LogWriter("While Process Exists imagex ")
		$objProcess = $gobjWMI.ExecQuery("select WriteTransferCount from Win32_Process where Name='imagex.exe'")
		If @error Then
			; nop - no status for you!
			 _LogWriter("Error inside the loop @error " & @error)
		Else
			For $objItem In $objProcess
				$intCurrentWriteBytes = $objItem.WriteTransferCount
				$intSpeed = ($intCurrentWriteBytes / TimerDiff($intImageTimer) / 1048.576) * 60 ; rip the * 60 off the end of this, and you have MB per second
				$intPercent = ($intCurrentWriteBytes / $intTotalBytes) * 100 ; percentage complete of unpack
				GUICtrlSetData($hwndImageText, "Imaging disk at " & Round($intSpeed, 1) & " MB per minute")
				GUICtrlSetData($hwndImageProgress, $intPercent)
				ExitLoop
			Next
		EndIf

		Sleep(1000) ; so ee don't peg out the crappy Vigo processor :-(
	WEnd

	; Clean up the gui
	GUICtrlSetData($hwndImageText, "OS Layer is complete")
	GUICtrlDelete($hwndImageProgress)

	; Now write all the other layers
	Local $startingPath = $strHDSource & "\Sources\" & $strSrcDir
	Local $fileFilter = "*.wim"

	Local $fileListArray = _FileListToArray_Recursive($startingPath, $fileFilter)

	For $i = 1 To $fileListArray[0]
		Local $strThisFileRelPath = $fileListArray[$i]
		Local $strSplitTemp = StringSplit($strThisFileRelPath, "\")
		Local $strThisFile = $strSplitTemp[$strSplitTemp[0]];Gets last element, which be just be file_name.wim

		If $strThisFile = "os_layer.wim" Then
			; nop
		ElseIf $strThisFile = "boot.wim" Then
			; nop again!
		ElseIf $strThisFile = "make_me_boot.wim" Then
			; nop once more!
		Else
			; Layer description text - replace underscore with space
			$strDescription = StringReplace($strThisFile, "_", " ")

			; Layer description text - remove the .WIM extension
			$strDescription = StringReplace($strDescription, ".wim", "")

			; Update gui
			$hwndImageText = _WindowText("Writing " & $strDescription)
			$hwndImageProgress = GUICtrlCreateProgress(250, $gintLeaderBoard * 20, 200, 17)

			; Get uncompressed size of this image
			$intTotalBytes = _EnumWIMSize($strHDSource & "\Sources\" & $strSrcDir & $strThisFileRelPath)
			_LogWriter("Going to Apply Layer " & $strThisFileRelPath)

			$intImageXPid = Run(@ScriptFullPath & " applylayer " & Chr(34) & $strThisFileRelPath & Chr(34))
			ProcessWait("imagex.exe")
			_LogWriter("Running Imagex ")

			$intImageTimer = TimerInit()
			While ProcessExists($intImageXPid)
				$objProcess = $gobjWMI.ExecQuery("select WriteTransferCount from Win32_Process where Name='imagex.exe'")
				If @error Then
					; nop - no status for you!
				Else
					For $objItem In $objProcess
						$intCurrentWriteBytes = $objItem.WriteTransferCount
						$intSpeed = ($intCurrentWriteBytes / TimerDiff($intImageTimer) / 1048.576) * 60 ; rip the * 60 off the end of this, and you have MB per second
						$intPercent = ($intCurrentWriteBytes / $intTotalBytes) * 100 ; percentage complete of unpack
						GUICtrlSetData($hwndImageText, "Imaging disk at " & Round($intSpeed, 1) & " MB per minute")
						GUICtrlSetData($hwndImageProgress, $intPercent)
						ExitLoop
					Next
				EndIf

				Sleep(1000) ; so ee don't peg out the crappy Vigo processor :-(
			WEnd

			; Layer write is complete
			GUICtrlSetData($hwndImageText, $strDescription & " is complete")
			_LogWriter("Layer Write is complete ")
			GUICtrlDelete($hwndImageProgress)
		EndIf
	Next

	; Collect the exit result of ImageX
	$intResult = RegRead("HKLM\Software\POSF", "ImageXResult")
	If $intResult <> 0 Then
		; there's no message box here, because the "child" process will have already given the prompt
		_LogWriter("Shoutdown recovery")
		_Shutdown()
	EndIf

	; Copy VersionNumber.txt file to primary partition
	FileCopy($strHDSource & "\Sources\" & $strSrcDir & "VersionNumber.txt", "Z:\", $FC_OVERWRITE)

	;todo - change the if condition
	;if $gstrImageName <>"Windows 7 64bit Production Image" Then ; this isn't used on BOH
	; looks like this might actually be useful
	; Now kick off the HWDetection Process
	$hwndHWText = _WindowText("Starting HWDetection")
	$intHWDPID = Run(@ScriptDir & "\HWDetection.exe Z:", "")
	ProcessWait("hwdetection.exe", 5)
	_ShowBusyApp_New("hwdetection.exe")
	GUICtrlSetData($hwndHWText, "HWDetection complete")
	;EndIf

	; Set computer name to match target register number in sysprep.inf file

	#cs - no sysprep file for WEPOS :(
		_WindowText("Updating sysprep details")
		$file = FileOpen("Z:\recover.flg", $FO_READ)
		$regNum = FileReadLine($file)
		FileClose($file)
		IniWrite("Z:\sysprep\sysprep.inf","UserData","ComputerName",'"POS' & $regNum & '"')
		GUICtrlSetData(-1,"Sysprep data has been updated")
	#ce

	; And now, final stages...
	;  Copy recovery.ini
	FileCopy("Z:\Recovery.ini", $strHDSource & "\", 1)

	; Clean off build accelerator functions from the Recovery INI files before reboot
	If $blnBuildAccelerate = True Then
		IniDelete("Z:\Recovery.ini", "Build Accelerator")
		IniDelete($strHDSource & "\Recovery.ini", "Build Accelerator")
	EndIf

   ;Commented by abhishek
	;If $gstrImageName <> "BOH"   Then
    ;	"Use below condition in the mentioned piece of the code instead checking agaist the ""BOH"".

    If   StringInStr ($gstrImageName,"_POSReady2007") Then
		; Build the boot sector
		_WindowText("Creating boot sector")
		_LogWriter("Inside Creating boot sect")
		;commented by abhishek for testing win 7
		;$intPID = Run(@ComSpec & " /c " & Chr(34) & "x:\winpe\bin\create bcd.cmd" & Chr(34) & " BOOTMGR Z:", "", @SW_HIDE)
		
		; code start
    
		$intPID = Run(@ComSpec & " /c " & Chr(34) & "x:\winpe\bin\bootsect.exe" & Chr(34) & "  /NT60 Z:", "", @SW_HIDE)
		
		;code end
		
		_LogWriter("Running Create BCD.bat with process id " & $intPID)
		
		_ShowBusyApp_New($intPID)
		_WindowText("CREATING BOOT.INI ")
		;$intPID = Run(@ComSpec & " /c " & Chr(34) & "x:\winpe\bin\bootcfg.exe /Rebuild Z:","", @SW_HIDE)
		
		GUICtrlSetData(-1, "Boot sector written")
		_WindowText("Boot sector written")
	Else
		; Win 7 auto specializes the BCD for us. Just make sure the bootsect record is there and we're good
		_WindowText("Creating boot sector")
		$intPID = Run(@ComSpec & " /c " & Chr(34) & "x:\winpe\bin\bootsect.exe" & Chr(34) & "  /NT60 Z:", "", @SW_HIDE)
		_ShowBusyApp_New($intPID)
		GUICtrlSetData(-1, "Boot sector written")
		; if this is a conversion, fix the recovery partition
		If $blnSlickConversion = True Then
			; Build the boot sector
			_WindowText("Creating boot sector")
			$intPID = Run(@ComSpec & " /c " & Chr(34) & "x:\winpe\bin\create bcd.cmd" & Chr(34) & " PXE W:", "", @SW_HIDE)
			_ShowBusyApp_New($intPID)
			GUICtrlSetData(-1, "Boot sector written")
		EndIf
	EndIf
	; Execute the 'final' diskpart script
	_WindowText("Starting final diskpart script")
	$intPID = Run(@ScriptFullPath & " diskpart " & Chr(34) & @TempDir & "\final.dps" & Chr(34), @ScriptDir, @SW_HIDE)
	_ShowBusyApp_New($intPID)
	GUICtrlSetData(-1, "Final diskpart script has completed.")

	_Reboot(1)
EndFunc   ;==>_HDRecovery

; Performs "CD" recovery process for initial builds / blank drives
Func _CDRecovery()
	; create diskpart script for partitioning the drive
	_CreateCleanDiskpartScript(0)

	; Confirmation prompt before blowing away the box
	_WindowText("Prompting for consent to drive wipe")
	$intResult = MsgBox(308, "<!> FINAL CONFIRMATION WARNING <!>", "All data on this workstation will be destroyed and replaced with factory defaults." & @CRLF & @CRLF & _
			"Do you wish to continue?")

	; If answer was anything but yes, we exit.
	If $intResult <> 6 Then
		_Shutdown()
	EndIf

	#cs

		Here thar be monsters...

	#ce

	; Splash on!
	GUICtrlSetData(-1, "Drive wipe consent given")

	; Execute the diskpart script
	_WindowText("Executing diskpart script")
	$intPID = Run(@ScriptFullPath & " diskpart " & Chr(34) & @TempDir & "\recovery.dps" & Chr(34), @ScriptDir, @SW_HIDE)
	_ShowBusyApp_New($intPID)
	GUICtrlSetData(-1, "Diskpart script has completed")

	; Write optical drive letter to registry
	RegWrite("HKLM\Software\POSF", "RecoveryDVD", "REG_SZ", $gstrCDSource)

	; Copy Files
	_WindowText("Copying files")
	$intTotalBytes = DirGetSize($gstrCDSource)
	; Get file sizes
	$hwndCopyText = _WindowText("Preparing to copy files...")
	$intTotalBytes = DirGetSize($gstrCDSource)

	; Copy Files
	GUICtrlSetData($hwndCopyText, "Copying files")
	$hwndCopyProgress = GUICtrlCreateProgress(250, $gintLeaderBoard * 20, 200, 17)

	$intResult = Run(@ScriptFullPath & " dvdcopy", @ScriptDir)
	$intImageTimer = TimerInit()
	While ProcessExists($intResult)
		$objProcess = $gobjWMI.ExecQuery("select WriteTransferCount from Win32_Process where ProcessID=" & $intResult)
		If @error Then
			; nop - no status for you!
		Else
			For $objItem In $objProcess
				$intCurrentWriteBytes = $objItem.WriteTransferCount
				$intSpeed = ($intCurrentWriteBytes / TimerDiff($intImageTimer) / 1048.576) * 60 ; rip the * 60 off the end of this, and you have MB per second
				$intPercent = ($intCurrentWriteBytes / $intTotalBytes) * 100 ; percentage complete of unpack
				GUICtrlSetData($hwndCopyText, "Copying files at " & Round($intSpeed, 1) & " MB per minute")
				GUICtrlSetData($hwndCopyProgress, $intPercent)
				ExitLoop
			Next
		EndIf

		Sleep(1000) ; so ee don't peg out the crappy Vigo processor :-(
	WEnd

	; Give status
	GUICtrlSetData($hwndCopyText, "Copy is complete")
	GUICtrlDelete($hwndCopyProgress)

	; Prompt to remove USB key if so-booted
	$interface = _DiskTypeFromID(_DiskIDFromDriveLetter($gstrCDSource))
	If $interface = "USB" Then
		MsgBox($MB_ICONASTERISK, "USB Removal Required", "A USB recovery device was detected.  Please remove your USB media before continuing this process.")
		_Shutdown(1)
	ElseIf _IsVM() Then
		; Prompt to eject CD if in a VM
		MsgBox($MB_ICONASTERISK, "Eject CD Required", "A VMWare platform has been detected.  Please use your Lab Manager or VMWare Workstation configuration to disconnect the CD drive media before continuing this process.")
	EndIf

EndFunc   ;==>_CDRecovery

; TODO: make sure everything is getting logged
Func _ValidateSourceFiles()
	_LogWriter("_ValidateSourceFiles() Started" & $gstrLogFileDestination)

	; Populate variables
	$gintRegNum = IniRead("Z:\Recovery.ini", "Locale", "RegisterNum", 1)
	$gintRecovery = IniRead("Z:\Recovery.ini", "Config", "IsRecovery", 0)
	$gstrMessageFileName = "POS" & $gintRegNum & "_MESSAGE.txt"
	$gstrMessageFileFullPath = $gstrLocalSourcesPath & $gstrMessageFileName
	$gstrSubscriptionFileName = "POS" & $gintRegNum & "_SUBSCRIPTION.txt"
	Local $strSourceFilesListFileName = "source_files.csv"
	Local $intSFTPPID = 0

	_LogWriter("Register Number: " & $gintRegNum, $gstrLogFileDestination)
	_LogWriter("Recovery: " & $gintRecovery, $gstrLogFileDestination)

	; If recovering from backups skip validation
	If ($gintRecovery = 1) Then
		_LogWriter("Skipping validation of source files.  User chose to restore existing backups.", $gstrLogFileDestination)
		_LogWriter("_ValidateSourceFiles() Ended", $gstrLogFileDestination)
		Return
	EndIf

	; Clear out any pre-existing message/subscription files
	FileDelete($gstrLocalSourcesPath & "POS*.txt")

	; Clear out temp folder if it already exists to make room for MD5 files
	If FileExists($gstrTempPath) Then
		_RunDos("rmdir /S /Q " & $gstrTempPath)
	EndIf
	_RunDos("mkdir " & $gstrTempPath)

	; Create message file for other registers and set status to "SUBSCRIBING"
	_FileCreate($gstrMessageFileFullPath)
	_FileWriteToLine($gstrMessageFileFullPath, 1, "SUBSCRIBING", 1)

	; Start SFTP server for communication between registers
	$intSFTPPID = _StartSFTPServer()

	; Find a master register to download files from
	$ghwndLatestHWText = _WindowText("Attempting to subscribe to another POS download queue")
	_SubscribeToPOSDownloadQueue()

	; Let the user know if this is master download register
	If ($gboolMasterPOS) Then
	   _LogWriter("Let the user know if this is master download register => "& $gboolMasterPOS)
		GUICtrlSetData($ghwndLatestHWText, "This register will be used to download source files from Central")
	EndIf

	; Verify wim files exist
	_LogWriter(" Verify wim files exist ")
	Local $hndLocalSourceFiles = FileFindFirstFile($gstrLocalSourcesPath & "*.wim")
	_LogWriter("$hndLocalSourceFiles " & $hndLocalSourceFiles)
	If $hndLocalSourceFiles = -1 Or @error = 1 Then
		; No local files found...cannot continue
		_LogWriter("No local files found...cannot continue " & $hndLocalSourceFiles)
		$intResult = MsgBox(16, "<!> NO LOCAL SOURCE FILES FOUND <!>", "Shutting down...")
		_LogWriter("No local source files found.  Shutting down..."& $gstrLogFileDestination)
		_Shutdown()
	 EndIf
	 _LogWriter("EndIF => " & $hndLocalSourceFiles)
	FileClose($hndLocalSourceFiles)

     _LogWriter("Get MD5 Files start...")
	; Get MD5 files
	Local $boolAllMD5FilesDownloaded = _DownloadMD5Files($strSourceFilesListFileName)
	_LogWriter("Get MD5 Files End...")

	; Download missing/incorrect source files as long as all MD5 files downloaded from Central
	Local $boolAllSourceFilesDownloaded = False
	If $boolAllMD5FilesDownloaded Then
	   _LogWriter("$boolAllMD5FilesDownloaded..." & $boolAllMD5FilesDownloaded)
	   _LogWriter("Calling  _DownloadSourceFiles")
		$boolAllSourceFilesDownloaded = _DownloadSourceFiles()
		_LogWriter("Done Calling  _DownloadSourceFiles")
	EndIf

	; If all required source files downloaded
	If ($boolAllSourceFilesDownloaded) Then
        _LogWriter("$boolAllSourceFilesDownloaded => " & $boolAllSourceFilesDownloaded)
		; If we're master POS
		If $gboolMasterPOS Then
		 _LogWriter(" If we're master POS $gboolMasterPOS => " & $gboolMasterPOS)
			; Signal other registers to continue
			_LogWriter("Letting other registers know source files are ready "& $gstrLogFileDestination)
			_FileWriteToLine($gstrMessageFileFullPath, 1, "SOURCE_FILES_READY", 1)

			; Wait here until other registers complete
			_WaitForRegistersToComplete() ; TODO: make this executable so spinning icon shows

			; Delete message file since all registers are done
			_LogWriter("Deleting message file: " & $gstrMessageFileFullPath & " $gstrLogFileDestination " & $gstrLogFileDestination)
			FileDelete($gstrMessageFileFullPath)

			; Kill SFTP server
			_LogWriter("Killing SFTP Server "& $gstrLogFileDestination)
			ProcessClose($intSFTPPID)
		Else
			; Signal master register that this register is done
			$strMessage = "Sending signal to POS" & $gintMasterPOSNumber & " that this register is continuing"
			_WindowText($strMessage)
			_LogWriter($strMessage, $gstrLogFileDestination)
			_RemoveFiles($gstrSFTPPOS, $gstrSubscriptionFileName, "RemoveSubscriptionFileFromPOS" & $gintMasterPOSNumber & ".log", False, False)
		EndIf
	Else
		; else skip validation
		_LogWriter("Skipping source files validation "& $gstrLogFileDestination)
		_WindowText("Skipping source files validation")

		; If master register, signal other registers to continue without us
		If ($gboolMasterPOS) Then
			_LogWriter("Letting other registers know we skipped validation" & $gstrLogFileDestination)
			_FileWriteToLine($gstrMessageFileFullPath, 1, "VALIDATION_SKIPPED", 1)
		EndIf
	EndIf

	; Delete temp directory we used for validation
	If FileExists($gstrTempPath) Then
	   _LogWriter("Delete temp directory we used for validation " & $gstrTempPath)
		_RunDos("rmdir /S /Q " & $gstrTempPath)
	EndIf

	_LogWriter("_ValidateSourceFiles() Ended"& $gstrLogFileDestination)

;Commented by abhishek for testing
	; Reboot and restart validation process if boot.wim was updated
   	;If ($gboolBootWIMUpdated) Then
	;	$strMessage1 = "New BOOT.WIM downloaded"
		;$strMessage2 = "Register will now reboot and restart validation process"
		;_LogWriter($strMessage1, $gstrLogFileDestination)
		;_WindowText($strMessage1)
		;_WindowText($strMessage2)
		;If Not $blnBuildAccelerate Then
		;	MsgBox(64, "<!> WARNING <!>", $strMessage1 & "." & @CRLF & @CRLF & $strMessage2 & ".", 30)
		;EndIf
		;_Reboot(1) ;Force a reboot
	; EndIf
	 _LogWriter("_ValidateSourceFiles End")
EndFunc   ;==>_ValidateSourceFiles

Func _StartSFTPServer()

	; Change IP to .2x so other registers can find us
	Local $intNewIP = _GetPOSIP($gintRegNum)
	_LogWriter("Assigning static IP: " & $intNewIP, $gstrLogFileDestination)
	_WindowText("@IPAddress1 : " & @IPAddress1)
	_WindowText("Assigning static IP: " & $intNewIP)
	_LogWriter("Running AssignStaticIp.exe start: " & $intNewIP, $gstrLogFileDestination)
	_WindowText("Running AssignStaticIp.exe start: " & $intNewIP)
	RunWait(@ScriptDir & "\AssignStaticIP.exe", @ScriptDir, @SW_HIDE)
	_WindowText(" AssignStaticIp.exe Run Successfully " & $intNewIP)
	_LogWriter(" AssignStaticIp.exe Run Successfully : " & $intNewIP, $gstrLogFileDestination)

	; Update IP on screen
	_UpdateIPDisplay($intNewIP)

	_WindowText("Opening communication channel with other registers")

	; Insert SFTP defaults into registry
	RegWrite("HKEY_CURRENT_USER\SOFTWARE\FTPWare\msftpsrvr\msftpsrvr", "path", "REG_SZ", "C:\Sources")
	RegWrite("HKEY_CURRENT_USER\SOFTWARE\FTPWare\msftpsrvr\msftpsrvr", "port", "REG_SZ", "22")
	RegWrite("HKEY_CURRENT_USER\SOFTWARE\FTPWare\msftpsrvr\msftpsrvr", "PW", "REG_SZ", "sources")
	RegWrite("HKEY_CURRENT_USER\SOFTWARE\FTPWare\msftpsrvr\msftpsrvr", "user", "REG_SZ", "sources")
	RegWrite("HKEY_LOCAL_MACHINE\Software\Wow6432Node", "Default", "REG_SZ", "")
	

	; Start SFTP Server
   ;commented by abhishek for making sftp to work on 64 bit
   ;	$sftpCMD = @ScriptDir & "\SFTP\msftpsrvr.exe -start"
   
   $sftpCMD =  "X:\Windows\SysWow64\SFTP\msftpsrvr.exe -start"
	_LogWriter("Starting SFTP Server: " & $sftpCMD, $gstrLogFileDestination)
	$intSFTPPID = Run($sftpCMD, @ScriptDir & "\SFTP\", @SW_MINIMIZE)
	_LogWriter("SFTP server status  : " & $intSFTPPID)

	; Workaround for window not hiding when using @SW_HIDE in previous line
	Sleep(5000)
	_LogWriter(" WInSetState => Before Core FTP mini-sftp-server @SW_HIDE : " & @SW_HIDE)
	WinSetState("Core FTP mini-sftp-server", "", @SW_HIDE)
	_LogWriter(" WInSetState => After Core FTP mini-sftp-server @SW_HIDE : " & @SW_HIDE)
    _LogWriter("SFTP server status  : " & $intSFTPPID)
	Return $intSFTPPID	
	_LogWriter("End OF _StartSFTPServer  : ")
EndFunc   ;==>_StartSFTPServer

Func _DownloadSourceFilesListFromCentral($strSourceFilesListFileName, $strSourceFilesListDestinationDirectory, $strMD5DestinationDirectory)
    _LogWriter("Downloading source files list from Central Source File Name : " & $strSourceFilesListFileName)
	_LogWriter("Source File List Destination Directory : " & $strSourceFilesListDestinationDirectory)
	_LogWriter("MD5 Destination Directory : " & $strMD5DestinationDirectory)
	_WindowText("Downloading source files list from Central")
	Local $strSourceFilesListDestinationFullPath = $strSourceFilesListDestinationDirectory & $strSourceFilesListFileName
   _LogWriter("Source File Destination Full Path : " & $strSourceFilesListDestinationFullPath)
	_WindowText(" " & $strSourceFilesListDestinationFullPath)	
	Local $strMD5DestinationFullPath = $strMD5DestinationDirectory & "*.MD5"
	_LogWriter("MD5 Destination Full Path : " & $strMD5DestinationFullPath)
	_WindowText(" " & $strMD5DestinationFullPath)
	
	_LogWriter("Before Calling GetFiles Path _GetFiles ")
	_GetFiles($gstrSFTPCentral, $strSourceFilesListFileName, $strSourceFilesListDestinationFullPath, "GetSourceFilesListFromCentral.log", False, False)
	_GetFiles($gstrSFTPCentral, "*.MD5", $strMD5DestinationFullPath, "GetMD5FilesFromCentral.log", False, False)
	_LogWriter("End Fuc _DownloadSourceFilesListFromCentral : ")
EndFunc   ;==>_DownloadSourceFilesListFromCentral

Func _DownloadMD5Files($strSourceFilesListFileName)
   _LogWriter("_DownloadMD5Files " & $strSourceFilesListFileName)
	Local $boolAllMD5FilesDownloaded = False
	Local $strSourceFilesListPath = $gstrTempPath & $strSourceFilesListFileName
	_LogWriter("$strSourceFilesListPath " & $strSourceFilesListPath)

	While Not $boolAllMD5FilesDownloaded
	   _LogWriter(" inside while Loop $boolAllMD5FilesDownloaded " & $boolAllMD5FilesDownloaded)
	   _LogWriter("Calling _DownloadSourceFilesListFromCentral " & $strSourceFilesListFileName  &" $gstrTempPath " &  $gstrTempPath)
		_DownloadSourceFilesListFromCentral($strSourceFilesListFileName, $gstrTempPath, $gstrTempPath)
		_LogWriter("Done _DownloadSourceFilesListFromCentral " )
		
		_LogWriter("Calling AllMD5FilesDownloaded " & $gstrTempPath & " $strSourceFilesListPath => " & $strSourceFilesListPath )
		$boolAllMD5FilesDownloaded = AllMD5FilesDownloaded($gstrTempPath, $strSourceFilesListPath)
		_LogWriter("Done Calling AllMD5FilesDownloaded "  & $boolAllMD5FilesDownloaded)
		If (Not $boolAllMD5FilesDownloaded) Then
			_LogWriter("Not all MD5 files were downloaded => "& $gstrLogFileDestination)
			$intResult = MsgBox(2 + 48, "<!> Error occurred while downloading source files list <!>", "Cannot validate source files" & @CRLF & "Would you like to try again?")
			Switch $intResult
				Case 4
					_LogWriter("User chose to retry MD5 download from beginning "& $gstrLogFileDestination)
					ContinueLoop
				Case 5
					_LogWriter("User chose to continue without validating source files "& $gstrLogFileDestination)
					_WindowText("Continuing without validating source files")
					ExitLoop
				Case Else
					_LogWriter("User chose to abort and shutdown "& $gstrLogFileDestination)
					_Shutdown()
			EndSwitch
		Else
			$boolAllMD5FilesDownloaded = True
			_LogWriter("$boolAllMD5FilesDownloaded "& $boolAllMD5FilesDownloaded)
		EndIf
	WEnd
     
	Return $boolAllMD5FilesDownloaded
	_LogWriter("End _DownloadMD5Files "& $boolAllMD5FilesDownloaded)
EndFunc   ;==>_DownloadMD5Files

Func _DownloadSourceFiles()
   _LogWriter("Inside DownloadSourceFiles ")
	Local $astrIncorrectFiles[1]
	Local $boolAllSourceFilesDownloaded = False
	Local $boolMasterPOSSignalReceived = False
	Local $currentFile = ""
	Local $downloadCommand = ""

	While Not $boolAllSourceFilesDownloaded
           _LogWriter("Inside While Loop  $boolAllSourceFilesDownloaded => " & $boolAllSourceFilesDownloaded)
		; Build list of files that are missing or incorrect
		$astrIncorrectFiles = _CompareSourceFiles($gstrTempPath)

		If ($astrIncorrectFiles[0] <> "") Then
			For $i = 0 To UBound($astrIncorrectFiles) - 1
				$currentFile = $astrIncorrectFiles[$i]

				; If we're master, make sure someone else didn't take over while we were offline
				If ($gboolMasterPOS) Then
					_ValidateMaster()
				EndIf

				While (Not $gboolMasterPOS And Not $boolMasterPOSSignalReceived)
					$boolMasterPOSSignalReceived = _WaitForMasterPOSReadySignal(20)
				WEnd

				Local $strDestinationPath = $gstrTempPath & $currentFile
				If ($gboolMasterPOS) Then
					$ghwndLatestHWText = _WindowText("Downloading " & $currentFile & " from Central")
					_GetFiles($gstrSFTPCentral, $currentFile, $strDestinationPath, "GetSourceFilesFromCentral.log", True, True)
					 _LogWriter("Inside DownloadSourceFiles If condition,Setting boolShowWindow as True")
				Else
					$ghwndLatestHWText = _WindowText("Downloading " & $currentFile & " from POS" & $gintMasterPOSNumber)
					_GetFiles($gstrSFTPPOS, $currentFile, $strDestinationPath, "GetSourceFilesFromPOS" & $gintMasterPOSNumber & ".log", True, True)
					_LogWriter("Inside DownloadSourceFiles Else condition,Setting boolShowWindow as True ")
				EndIf

				; move wim file from temp to sources folder
				If (FileExists($gstrTempPath & $currentFile)) Then
					FileMove($gstrTempPath & $currentFile, $gstrLocalSourcesPath & $currentFile, 1)
					If (StringLower($currentFile)) = "boot.wim" Then
						$gboolBootWIMUpdated = True
					EndIf
					FileDelete($gstrTempPath & $currentFile)
				Else
					$strMessage = "DOWNLOAD FAILED: " & $currentFile
					_LogWriter($strMessage, $gstrLogFileDestination)
					GUICtrlSetData($ghwndLatestHWText, $strMessage)
				EndIf
			Next

			; Revalidate source files
			$astrIncorrectFiles = _CompareSourceFiles($gstrTempPath)
			If ($astrIncorrectFiles[0] <> "") Then
				$intResult = MsgBox(2 + 48, "<!> SOURCE FILES STILL NOT VALID <!>", "Would you like to try again?")
				Switch $intResult
					Case 4
						_LogWriter("User chose to retry validation from beginning", $gstrLogFileDestination)
						ContinueLoop
					Case 5
						_LogWriter("User chose to continue without valid source files", $gstrLogFileDestination)
						$boolAllSourceFilesDownloaded = False
						ExitLoop
					Case Else
						_LogWriter("User chose to abort and shutdown", $gstrLogFileDestination)
						_Shutdown()
				EndSwitch
			Else
				$boolAllSourceFilesDownloaded = True
			EndIf
		Else
			$boolAllSourceFilesDownloaded = True
		EndIf
	WEnd

	Return $boolAllSourceFilesDownloaded
	_LogWriter("End DownloadSourceFiles ")
EndFunc   ;==>_DownloadSourceFiles

Func _ValidateMaster()
	Local $boolNewMaster = False
	Local $astrRemoteMessageFileContents[1]

	For $intCurrentPOSNumber = 1 To 9
		If ($intCurrentPOSNumber <> $gintRegNum) Then
			$strCurrentPOSIP = _GetPOSIP($intCurrentPOSNumber)
			$intPingResult = Ping($strCurrentPOSIP, 1000)
			If ($intPingResult <> 0) Then

				; Download message file
				Local $strSFTPPOS = "sftp://sources:sources@" & $strCurrentPOSIP & "/ -hostkey=""*"""
				Local $strRemoteMessageFileName = StringReplace($gstrMessageFileName, "POS" & $gintRegNum, "POS" & $intCurrentPOSNumber)
				Local $strRemoteMessageFileDestination = $gstrTempPath & $strRemoteMessageFileName
				_GetFiles($strSFTPPOS, $strRemoteMessageFileName, $strRemoteMessageFileDestination, "GetMessageFileFromPOS" & $intCurrentPOSNumber & ".log", False, False, True)

				; If download successful
				If (FileExists($strRemoteMessageFileDestination)) Then

					; Read file and look for status
					_FileReadToArray($strRemoteMessageFileDestination, $astrRemoteMessageFileContents)

					; If that register is master, we are no longer master
					If (_ArraySearch($astrRemoteMessageFileContents, "MASTER") > 0) Or (_ArraySearch($astrRemoteMessageFileContents, "SOURCE_FILES_READY") > 0) Then
						$boolNewMaster = True
						_LogWriter("New Master register found: " & $strCurrentPOSIP, $gstrLogFileDestination)
						ExitLoop
					EndIf
				EndIf
			EndIf
		EndIf
	Next

	If ($boolNewMaster) Then
		; Delete any message/subscription register files
		FileDelete($gstrLocalSourcesPath & "POS*.txt")

		; Resubscribe to another Master
		_SubscribeToPOSDownloadQueue(True)
	EndIf
EndFunc   ;==>_ValidateMaster

Func _WaitForRegistersToComplete()
	Local $boolAllRegistersComplete = False

	; Wait here for other registers to complete sync with this register
	$ghwndLatestHWText = _WindowText("Waiting for other registers to finish sync")
	_LogWriter("Waiting for other registers to complete", $gstrLogFileDestination)

	While Not $boolAllRegistersComplete

		; Get all subscription files
		$astrSubscriptionFiles = _FileListToArray($gstrLocalSourcesPath, "POS*_SUBSCRIPTION.txt", 1)

		; If there are no subscribed registers, exit true
		If (@error = 4) Then
			_LogWriter("All subscribed registers have completed", $gstrLogFileDestination)
			GUICtrlSetData($ghwndLatestHWText, "All subscribed registers have completed")
			$boolAllRegistersComplete = True
		ElseIf (IsArray($astrSubscriptionFiles) And $astrSubscriptionFiles[0] > 0) Then

			; Ensure this register is still communicating with other registers
			For $i = 1 To $astrSubscriptionFiles[0]

				; Get IP address of subscribed register from subscription file
				$strCurrentFile = $astrSubscriptionFiles[$i]
				$intRegisterNumber = StringTrimLeft(StringTrimRight($strCurrentFile, 17), 3)
				$file = FileOpen($gstrLocalSourcesPath & $strCurrentFile)
				$strIP = FileReadLine($file, 1)
				FileClose($file)

				; Ping to see if other register is still responding
				$intPingResult = Ping($strIP, 1000)
				If ($intPingResult = 0) Then
					_LogWriter("Lost communication with POS" & $intRegisterNumber & ".", $gstrLogFileDestination)
					$intResult = MsgBox(4, "<!> Error <!>", "Lost communication with POS" & $intRegisterNumber & @CRLF & "Would you like to continue waiting for POS" & $intRegisterNumber & "?")
					If ($intResult = 7) Then
						_LogWriter("User chose to continue without waiting for POS" & $intRegisterNumber, $gstrLogFileDestination)
						FileDelete($gstrLocalSourcesPath & $strCurrentFile)
					EndIf
				EndIf
			Next
		EndIf

		Sleep($gintSleepInterval)
	WEnd
EndFunc   ;==>_WaitForRegistersToComplete

Func _WaitForMasterPOSReadySignal($intMaxPingTries = 1)
	Local $boolSignalReceived = False
	Local $astrMessageFileContents[1]
	Local $boolSubscribed = True

	Local $strMessage = "Waiting for signal from POS" & $gintMasterPOSNumber & " to continue"
	_LogWriter($strMessage, $gstrLogFileDestination)
	$ghwndLatestHWText = _WindowText($strMessage)

	; While master register hasn't completed its downloads
	While Not $boolSignalReceived

		; Give master register a chance to come back online if it went down
		Local $i = 1
		While $i <= $intMaxPingTries And Ping($gstrMasterPOSIP, 3000) = 0
			Sleep($gintSleepInterval)
			$i = $i + 1
		WEnd

		; Keep track of current master register to see if it changes
		Local $intOldMasterPOSNumber = $gintMasterPOSNumber
		Local $strOldMasterPOSIP = $gstrMasterPOSIP
		Local $strOldMasterSFTP = $gstrSFTPPOS

		; Attempt to resubscribe to make sure master hasn't changed
		_SubscribeToPOSDownloadQueue(True)

		; If we ended up subscribed to same master register
		If $gintMasterPOSNumber = $intOldMasterPOSNumber Then

			; Check status of master register
			Local $strRemoteMessageFileName = StringReplace($gstrMessageFileName, "POS" & $gintRegNum, "POS" & $gintMasterPOSNumber)
			Local $strRemoteMessageFileDestination = $gstrTempPath & $strRemoteMessageFileName
			_GetFiles($gstrSFTPPOS, $gstrMessageFileName, $strRemoteMessageFileDestination, "GetSignalFileFromPOS" & $gintMasterPOSNumber & ".log", False, False, True)
			If (FileExists($strRemoteMessageFileDestination)) Then
				_FileReadToArray($strRemoteMessageFileDestination, $astrMessageFileContents)
				If (_ArraySearch($astrMessageFileContents, "SOURCE_FILES_READY") > 0) Then
					$boolSignalReceived = True
					$strMessage = "Signal received from POS" & $gintMasterPOSNumber & " to continue"
					_LogWriter($strMessage, $gstrLogFileDestination)
					GUICtrlSetData($ghwndLatestHWText, $strMessage)
					FileDelete($strRemoteMessageFileDestination)
				ElseIf (_ArraySearch($astrMessageFileContents, "VALIDATION_SKIPPED") > 0) Then
					$strMessage = "POS skipped validation.  Switching to Central."
					_LogWriter($strMessage, $gstrLogFileDestination)
					GUICtrlSetData($ghwndLatestHWText, $strMessage)
					FileDelete($strRemoteMessageFileDestination)
					ExitLoop
				EndIf
			EndIf
		Else
			; Switch to new master
			$strMessage = "Lost subscription to POS" & $intOldMasterPOSNumber & "."
			If ($gboolMasterPOS) Then
				$strMessage = $strMessage & "  Downloading from Central instead."
			Else
				$strMessage = $strMessage & "  Switching to POS" & $gintMasterPOSNumber & "."
			EndIf

			_WindowText($strMessage)
			ExitLoop
		EndIf

		Sleep($gintSleepInterval)
	WEnd

	Return $boolSignalReceived
EndFunc   ;==>_WaitForMasterPOSReadySignal

Func _SubscribeToPOSDownloadQueue($boolSuppressMessages = False)
	
	_LogWriter("Inside _SubscribeToPOSDownloadQueue")
	Local $strSubscriptionFullPath = $gstrTempPath & $gstrSubscriptionFileName
	_LogWriter("$strSubscriptionFullPath => " & $strSubscriptionFullPath)
	Local $astrRemoteMessageFileContents[1]
	;_LogWriter("$astrRemoteMessageFileContents => " & $astrRemoteMessageFileContents[1])
	Local $boolMasterFound = False
	$gintMasterPOSNumber = $gintRegNum
	_LogWriter("$gintMasterPOSNumber => " & $gintMasterPOSNumber)
	Local $boolLowerRegisterFound = False	
	_WindowText(" into _SubscribeToPOSDownloadQueue")
	; Delete any message/subscription files from temp directory
	FileDelete($gstrTempPath & "POS*.txt")

	; Set our status to "SUBSCRIBING"
	_FileCreate($gstrMessageFileFullPath)
	_FileWriteToLine($gstrMessageFileFullPath, 1, "SUBSCRIBING", 1)

	; While a master register has not been determined yet
	While Not $boolMasterFound
      _LogWriter("While a master register has not been determined yet ")
		; Start at POS9 and work downward until a master register is found
		$boolLowerRegisterFound = False
		Local $intCurrentPOSNumber = 1
		While $intCurrentPOSNumber <= 9
            _LogWriter("$intCurrentPOSNumber => " & $intCurrentPOSNumber)
			; Ignore ourselves
			If ($intCurrentPOSNumber <> $gintRegNum) Then
			   _LogWriter("Inside If Condition with Current POS No => " & $intCurrentPOSNumber)
				$strMessage = "Attempting to subscribe to POS" & $intCurrentPOSNumber & " download queue"
				_LogWriter("$strMessage => " &$strMessage)
				_LogWriter(" $gstrLogFileDestination => " & $gstrLogFileDestination)
				If (Not $boolSuppressMessages) Then
				   _LogWriter(" If Not $boolSuppressMessages => " & $boolSuppressMessages)
					GUICtrlSetData($ghwndLatestHWText, $strMessage)
				EndIf

				; Ping remote register to see if accessible
				$strCurrentPOSIP = _GetPOSIP($intCurrentPOSNumber)
				_LogWriter(" $strCurrentPOSIP => " & $strCurrentPOSIP)
				_LogWriter(" Ping  => " & $strCurrentPOSIP)
				$intPingResult = Ping($strCurrentPOSIP, 1000)				
				_LogWriter(" Ping Results => " & $intPingResult)

				; If accessible
				If ($intPingResult > 0) Then

					; Download message file
					Local $strSFTPPOS = "sftp://sources:sources@" & $strCurrentPOSIP & "/ -hostkey=""*"""
					_LogWriter(" $strSFTPPOS  => " & $strSFTPPOS)
					
					Local $strRemoteMessageFileName = StringReplace($gstrMessageFileName, "POS" & $gintRegNum, "POS" & $intCurrentPOSNumber)
					_LogWriter(" $strRemoteMessageFileName  => " & $strRemoteMessageFileName)
					
					Local $strRemoteMessageFileDestination = $gstrTempPath & $strRemoteMessageFileName
					_LogWriter(" $strRemoteMessageFileDestination  => " & $strRemoteMessageFileDestination)
					
					FileDelete($strRemoteMessageFileDestination)
					_LogWriter(" Calling _GetFiles Start  => ")
					_GetFiles($strSFTPPOS, $strRemoteMessageFileName, $strRemoteMessageFileDestination, "GetMessageFileFromPOS" & $intCurrentPOSNumber & ".log", False, False, True)
                     _LogWriter("Calling _GetFiles End   ")

					; If download successful
					If (FileExists($strRemoteMessageFileDestination)) Then

						; Read file and look for status
						_FileReadToArray($strRemoteMessageFileDestination, $astrRemoteMessageFileContents)

                        _LogWriter("If that register is master  => ")
						; If that register is master
						If (_ArraySearch($astrRemoteMessageFileContents, "MASTER") > 0) Or (_ArraySearch($astrRemoteMessageFileContents, "SOURCE_FILES_READY") > 0) Then
						   
						   _LogWriter("Subscribe to that download queue ")

							; Subscribe to that download queue
							_FileCreate($strSubscriptionFullPath)
							_LogWriter("$strSubscriptionFullPath => " & $strSubscriptionFullPath)
							_FileWriteToLine($strSubscriptionFullPath, 1, @IPAddress1, 1)
							
							_LogWriter("Calling _PutFiles Start=> ")
							_PutFiles($strSFTPPOS, $strSubscriptionFullPath, $gstrSubscriptionFileName, "PutSubscriptionFileOnPOS" & $intCurrentPOSNumber & ".log", False, False, True)
                            _LogWriter("Calling _PutFiles End => ")
  
							; Make sure we subscribed successfully by redownloading what we just uploaded
							FileDelete($strSubscriptionFullPath)
							_LogWriter("Make sure we subscribed successfully by redownloading what we just uploaded ")
							_GetFiles($strSFTPPOS, $gstrSubscriptionFileName, $strSubscriptionFullPath, "GetSubscriptionFileFromPOS" & $intCurrentPOSNumber & ".log", False, False, True)

							; If download successful, then we've successfully subscribed
							If (FileExists($strSubscriptionFullPath)) Then

                               _LogWriter("Update our status for other registers")
								; Update our status for other registers
								_FileWriteToLine($gstrMessageFileFullPath, 1, "SUBSCRIBED", 1)
								_FileWriteToLine($gstrMessageFileFullPath, 2, $strCurrentPOSIP, 1)

                                _LogWriter("Assign variables and exit")
								; Assign variables and exit
								$gboolMasterPOS = False
								$boolMasterFound = True
								$gintMasterPOSNumber = $intCurrentPOSNumber
								$gstrMasterPOSIP = $strCurrentPOSIP
								$gstrSFTPPOS = $strSFTPPOS
								_LogWriter("PoS  $gstrSFTPPOS => " & $gstrSFTPPOS)
								$strMessage = "Successfully subscribed to POS" & $intCurrentPOSNumber & " download queue"
								_LogWriter(" $strMessage =>  " & $strMessage)
								_LogWriter("$gstrLogFileDestination  => " & $gstrLogFileDestination)
								If (Not $boolSuppressMessages) Then
									GUICtrlSetData($ghwndLatestHWText, $strMessage)
								 EndIf
								 _LogWriter("ExitLoop  => ")
								ExitLoop
							EndIf
						 ElseIf ($intCurrentPOSNumber < $gintRegNum) Then
							
							 _LogWriter("Else Condition  => " & $intCurrentPOSNumber & " < " & $gintRegNum)

							; We found a register that's attempting to subscribe that takes precedence over us
							_LogWriter("Lower Register Found")
							$boolLowerRegisterFound = True
						   _LogWriter("Reset our status to SUBSCRIBING")
							; Reset our status to "SUBSCRIBING"
							_FileWriteToLine($gstrMessageFileFullPath, 1, "SUBSCRIBING", 1)
						EndIf
					EndIf
				EndIf
			EndIf

			$intCurrentPOSNumber = $intCurrentPOSNumber + 1
			
		WEnd

		Local $astrLocalMessageFileContents[1]
		_FileReadToArray($gstrMessageFileFullPath, $astrLocalMessageFileContents)
		If (Not $boolLowerRegisterFound) And (Not $boolMasterFound) And (_ArraySearch($astrLocalMessageFileContents, "SUBSCRIBING") > 0) Then
             _LogWriter("Elevate our status to PENDING_MASTER")
			; Elevate our status to "PENDING_MASTER"
			_FileWriteToLine($gstrMessageFileFullPath, 1, "PENDING_MASTER", 1)
		ElseIf (Not $boolLowerRegisterFound) And (Not $boolMasterFound) And (_ArraySearch($astrLocalMessageFileContents, "PENDING_MASTER") > 0) Then

			; Elevate our status to "MASTER"
			_LogWriter("Elevate our status to MASTER")
			_FileWriteToLine($gstrMessageFileFullPath, 1, "MASTER", 1)
			$boolMasterFound = True
			_LogWriter("$boolMasterFound => "& $boolMasterFound)
			$gboolMasterPOS = True
		EndIf
	WEnd
EndFunc   ;==>_SubscribeToPOSDownloadQueue

Func _GetPOSIP($intPOS)
	Local $parseIPSuccess = True

	; Need to break out the first three octets of IP address
	Local $aIPData = StringSplit(@IPAddress1, ".")

	If @error Then
		; Nothing to split, bad news
		$parseIPSuccess = False
	ElseIf Not IsArray($aIPData) Then
		; Not an array but somehow wasn't an error? how does that happen?
		$parseIPSuccess = False
	ElseIf $aIPData[1] = "0" Or $aIPData[1] = "127" Then
		; Bad interface IP
		$parseIPSuccess = False
	ElseIf $aIPData[1] = "169" And $aIPData[2] = "254" Then
		; Auto-IP means no local DHCP
		$parseIPSuccess = False
	ElseIf $aIPData[1] = "255" Or $aIPData[4] = "255" Then
		; Check for broadcast addressing
		$parseIPSuccess = False
	EndIf

	If $parseIPSuccess = True Then
		; Yay, good IP address prefix
		Return $aIPData[1] & "." & $aIPData[2] & "." & $aIPData[3] & ".2" & $intPOS
	EndIf
EndFunc   ;==>_GetPOSIP

Func _UpdateIPDisplay($strNewIP)
	_LogWriter("Updating user display IP to: " & $strNewIP, $gstrLogFileDestination)
	_LogWriter("_UpdateIPDisplay : Entering the _GetAllWindowsControls")
	$aResult = _GetAllWindowsControls("Main")

	For $i = 1 To UBound($aResult) - 1
		$intXPos = $aResult[$i][1]
		_LogWriter("_UpdateIPDisplay : $intXPos" & $intXPos) 
		If ($intXPos = 650) Then
			$strText = $aResult[$i][4]
			_LogWriter("_UpdateIPDisplay : $strText" & $strText) 
			$aIPData = StringSplit($strText, ".")
			_LogWriter("_UpdateIPDisplay : $aIPData" & $aIPData[0]) 
			If ($aIPData[0] = 4) Then
				$intControlID = $aResult[$i][3]
				_LogWriter("_UpdateIPDisplay : $intControlID" & $intControlID) 
				_LogWriter("_UpdateIPDisplay : Start GUICtrlSetData") 
				GUICtrlSetData($intControlID, $strNewIP)
				_LogWriter("_UpdateIPDisplay : Exit Loop") 
				ExitLoop
			EndIf
		EndIf
	 Next
	 _LogWriter("_UpdateIPDisplay : Out of  Loop") 
	 _LogWriter("_UpdateIPDisplay : End")
EndFunc   ;==>_UpdateIPDisplay

Func _GetFiles($strServer, $strRemoteFiles, $strLocalDestination, $strLogFileName, $boolAppendLogFile = False, $boolShowWindow = False, $boolSuppressMessages = False)
   _LogWriter("Into Function GetFiles Function : ")
	Local $strLogFile = $DRPartitionDriveLetter & "\Logs\" & $strLogFileName
	_LogWriter("Log File Path : " & $strLogFile)
    _WindowText("Starting Get Files ")
	; Delete existing log file
	If (FileExists($strLogFile) And $boolAppendLogFile = False) Then
		FileDelete($strLogFile)
	EndIf
  ; Change Command
  Local $strGetFilesCommand =""
  If (FileExists($gstrWinSYSWOW)) Then
		 $strGetFilesCommand = $gstrWinScpSysWOW64 & " /console" & " /log=" & $strLogFile & " /command " & """open " & $strServer & """ ""get " & $strRemoteFiles & " " & $strLocalDestination & """ ""exit"""
	_LogWriter("Get Files Command : " & $strGetFilesCommand)
	 Else
		 $strGetFilesCommand = $gstrWinSCPPath & " /console" & " /log=" & $strLogFile & " /command " & """open " & $strServer & """ ""get " & $strRemoteFiles & " " & $strLocalDestination & """ ""exit"""
	_LogWriter("Get Files Command : " & $strGetFilesCommand)
	    EndIf
  
	
   
	If (Not $boolSuppressMessages) Then
		_LogWriter("Executing command: " & $strGetFilesCommand, $gstrLogFileDestination)
		_WindowText("Executing Command in GetFiles ")
	EndIf
   
   If ($boolShowWindow = True) Then	  	 
	   _LogWriter("Bool Show Window : " & $strGetFilesCommand)
	   _LogWriter("Inside GetFiles,Setting boolShowWindow as " & $boolShowWindow)
	   _WindowText("Running Command In IF Condition ")
	   
	   ;abhishek Added Code for WinPE2
     If (FileExists($gstrWinSYSWOW)) Then
		$intPID  = RunWait( @COMSPEC & " /c X:&&cd \Windows\SysWOW64&&" &  $strGetFilesCommand , "", @SW_SHOW )	
	 Else
		$intPID = Run($strGetFilesCommand, @ScriptDir)	
	    EndIf
	   
		    
		
		_LogWriter("in if IntPID : " & $intPID)
		
	 Else		
	    _LogWriter("Bool Show Window : " & $strGetFilesCommand)
        _WindowText("Running Command In Else Condition ")		
	      
		   ;abhishek Added Code for WinPE2
			  If (FileExists($gstrWinSYSWOW)) Then
				 $intPID  = RunWait( @COMSPEC & " /c X:&&cd \Windows\SysWOW64&&" &  $strGetFilesCommand , "", @SW_SHOW )	
			  Else
				$intPID = Run($strGetFilesCommand, @ScriptDir, @SW_HIDE)	
				 EndIf
		  
		  ; $intPID  = RunWait( @COMSPEC & " /c X:&&cd \Windows\SysWOW64&&" &  $strGetFilesCommand , "", @SW_SHOW )
		_LogWriter("Else Condition IntPID : " & $intPID)
		  
		
	EndIf

	_ShowBusyApp_New($intPID)
EndFunc   ;==>_GetFiles

Func _PutFiles($strServer, $strLocalFiles, $strRemoteDestination, $strLogFileName, $boolAppendLogFile = False, $boolShowWindow = False, $boolSuppressMessages = False)
	Local $strLogFile = $DRPartitionDriveLetter & "\Logs\" & $strLogFileName

	; Delete existing log file
	If (FileExists($strLogFile) And $boolAppendLogFile = False) Then
		FileDelete($strLogFile)
	EndIf

	Local $strPutFilesCommand = $gstrWinSCPPath & " /console" & " /log=" & $strLogFile & " /command " & """open " & $strServer & """ ""put " & $strLocalFiles & " " & $strRemoteDestination & """ ""exit"""

	If (Not $boolSuppressMessages) Then
		_LogWriter("Executing command: " & $strPutFilesCommand, $gstrLogFileDestination)
	EndIf

	If ($boolShowWindow = True) Then
		$intPID = Run($strPutFilesCommand, @ScriptDir)
	Else
		$intPID = Run($strPutFilesCommand, @ScriptDir, @SW_HIDE)
	EndIf

	_ShowBusyApp_New($intPID)
EndFunc   ;==>_PutFiles

Func _RemoveFiles($strServer, $strRemoteFiles, $strLogFileName, $boolAppendLogFile = False, $boolShowWindow = False, $boolSuppressMessages = False)
	Local $strLogFile = $DRPartitionDriveLetter & "\Logs\" & $strLogFileName

	; Delete existing log file
	If (FileExists($strLogFile) And $boolAppendLogFile = False) Then
		FileDelete($strLogFile)
	EndIf

	Local $strRemoveFilesCommand = $gstrWinSCPPath & " /console" & " /log=" & $strLogFile & " /command " & """open " & $strServer & """ ""rm " & $strRemoteFiles & """ ""exit"""

	If (Not $boolSuppressMessages) Then
		_LogWriter("Executing command: " & $strRemoveFilesCommand, $gstrLogFileDestination)
	EndIf

	If ($boolShowWindow = True) Then
		$intPID = Run($strRemoveFilesCommand, @ScriptDir)
	Else
		$intPID = Run($strRemoveFilesCommand, @ScriptDir, @SW_HIDE)
	EndIf

	_ShowBusyApp_New($intPID)
EndFunc   ;==>_RemoveFiles

; Compare each Central file to local files and populate array of files that need to be downloaded
Func _CompareSourceFiles($strRemoteMD5FilesDirectory)
   _LogWriter("Inside Comparing Source Files  $strRemoteMD5FilesDirectory => " & $strRemoteMD5FilesDirectory )
	Local $astrSourceFiles[1]
	Local $astrIncorrectFiles[1]

	; Notify user we're starting validation now
	_WindowText("Validating local source files")
	_LogWriter("Validating local source files"& $gstrLogFileDestination)

	; Verify all MD5 files downloaded
	; Get handle to first local source file
	$hndRemoteMD5Files = FileFindFirstFile($strRemoteMD5FilesDirectory & "*.md5")
	_LogWriter(" Verify all MD5 files downloaded  $hndRemoteMD5Files  => " & $hndRemoteMD5Files )
	If $hndRemoteMD5Files = -1 Or @error = 1 Then ; No MD5 files found...continuing without validation
		_LogWriter("No MD5 files found Continuing without error "& $gstrLogFileDestination)
		$intResult = MsgBox(48 + 4, "<!> NO REMOTE SOURCE FILES FOUND TO COMPARE <!>", "Continue without validation?")
		If ($intResult = 7) Then
			_LogWriter("User aborted.  Shutting down"& $gstrLogFileDestination)
			_WindowText("Shutting down")
			_Shutdown()
		Else
			FileClose($hndRemoteMD5Files)
			_LogWriter("User continued without validation."& $gstrLogFileDestination)
		EndIf

		Return $astrIncorrectFiles
	Else
		; Start MD5 comparison
		_LogWriter(" Start MD5 comparison  => " )
		$ghwndLatestHWText = _WindowText("Starting file compare")
		While 1
			$currentFile = FileFindNextFile($hndRemoteMD5Files)
			If @error Then ExitLoop

			; Read the MD5 file, compare it to the local file
			$strRemoteMD5 = StringStripWS(FileRead($strRemoteMD5FilesDirectory & $currentFile), 8)
			$strLocalWIMFile = StringReplace($currentFile, ".md5", ".wim")
			GUICtrlSetData($ghwndLatestHWText, "Validating " & $strLocalWIMFile)
			$strMD5Match = _MD5Match($strRemoteMD5, $gstrLocalSourcesPath & $strLocalWIMFile)

			; If the MDS's do not match and file is required, add it to download queue
			If ($strMD5Match <> 0 And (_FileRequired($currentFile))) Then
				If ($astrIncorrectFiles[0] = "") Then
					; Fill first spot in array with incorrect wim
					_LogWriter("Adding file to download queue: " & StringReplace($currentFile, ".md5", ".wim"), $gstrLogFileDestination)
					$astrIncorrectFiles[0] = StringReplace($currentFile, ".md5", ".wim")
				Else
					; Add incorrect wim
					_LogWriter("Adding file to download queue: " & StringReplace($currentFile, ".md5", ".wim"), $gstrLogFileDestination)
					_ArrayAdd($astrIncorrectFiles, StringReplace($currentFile, ".md5", ".wim"))
				EndIf
			ElseIf ($strMD5Match = 0) Then ; copy in MD5 that was just used to validate existing wim
				FileCopy($strRemoteMD5FilesDirectory & $currentFile, $gstrLocalSourcesPath & $currentFile, 1)
			EndIf
		WEnd
		FileClose($hndRemoteMD5Files)
	EndIf

	If ($astrIncorrectFiles[0] <> "") Then
		_LogWriter("All required missing or incorrect files have been added to download queue", $gstrLogFileDestination)
		GUICtrlSetData($ghwndLatestHWText, "Incorrect or missing source files detected")
	Else
		_LogWriter("All required source files are valid", $gstrLogFileDestination)
		GUICtrlSetData($ghwndLatestHWText, "Source files are valid")
	EndIf
	Return $astrIncorrectFiles
EndFunc   ;==>_CompareSourceFiles

; Validates each MD5 file was downloaded from central according to list
; Populates central files array indicating deploy date and whether file is required
Func AllMD5FilesDownloaded($strRemoteSourcesPath, $strSourceFilesListPath)
   _LogWriter("Inside AllMD5FilesDownloaded "& $gstrLogFileDestination)
   _LogWriter("Remote Source Path "& $strRemoteSourcesPath)
	Local $boolAllMD5FilesDownloaded = True
	Local $astrRemoteFilesDownloaded[1]
	Local $astrSourceFilesAtRemote[1]
	Local $boolFileFound = False
	Global $astrSourceFileObjectsAtRemote[1][3] ; clear array

	_LogWriter("Validating all MD5 files were downloaded "& $gstrLogFileDestination)
	
	$astrRemoteFilesDownloaded = _FileListToArray($strRemoteSourcesPath, "*.md5", 1)
	_LogWriter("$astrRemoteFilesDownloaded => " & $astrRemoteFilesDownloaded[0])
	
	; print  

	If (IsArray($astrRemoteFilesDownloaded) And $astrRemoteFilesDownloaded[0] > 0) Then
	   _LogWriter("Inside ID Condition Array ")
		_FileReadToArray($strSourceFilesListPath, $astrSourceFilesAtRemote)

		For $i = 2 To $astrSourceFilesAtRemote[0] ; Ignore num items in array (index 0) and header row (index 1)
		    _LogWriter("Inside For Loop Counter =>  " & $i)
			$strFileInfo = $astrSourceFilesAtRemote[$i]
			$astrFileArray = StringSplit(StringStripWS($strFileInfo, 8), ",")
			If (IsArray($astrFileArray) And $astrFileArray[0] = 3) Then
			   _LogWriter("Splitting file Array =>  ")
				$strCurrentFile = StringReplace($astrFileArray[1], ".wim", ".md5")

				; check if file was downloaded
				$boolFileFound = False
				For $strDownloadedFile In $astrRemoteFilesDownloaded
				   _LogWriter("Inside For Loop  =>  " & $strDownloadedFile)
					If ($strDownloadedFile = $strCurrentFile) Then
					    _LogWriter("If $strDownloadedFile  =  $strCurrentFile ==>  " & $strDownloadedFile & " =  " & $strCurrentFile)   
						$boolFileFound = True
						 _LogWriter("If $boolFileFound  = " & $boolFileFound)  
						  _LogWriter("Exit Loop  = " & $boolFileFound)  
						ExitLoop
					EndIf
				Next

				If ($boolFileFound = False) Then
					_LogWriter("MD5 file not downloaded: " & $strCurrentFile, $gstrLogFileDestination)
				    _LogWriter("$gstrLogFileDestination  = " & $gstrLogFileDestination) 
					$boolAllMD5FilesDownloaded = False
					ExitLoop
				EndIf

				If ($astrSourceFileObjectsAtRemote[0][0] = "") Then
				   _LogWriter("Inside iF Condition 2  ") 
					$astrSourceFileObjectsAtRemote[$i - 2][0] = $strCurrentFile
					$astrSourceFileObjectsAtRemote[$i - 2][1] = $astrFileArray[2]
					$astrSourceFileObjectsAtRemote[$i - 2][2] = $astrFileArray[3]
				 Else
					 _LogWriter("Inside Else Condition 2  ") 
					ReDim $astrSourceFileObjectsAtRemote[UBound($astrSourceFileObjectsAtRemote) + 1][3]
					$astrSourceFileObjectsAtRemote[$i - 2][0] = $strCurrentFile
					$astrSourceFileObjectsAtRemote[$i - 2][1] = $astrFileArray[2]
					$astrSourceFileObjectsAtRemote[$i - 2][2] = $astrFileArray[3]
				EndIf
			 EndIf
			  
		   Next
		   _LogWriter("End Of For Loop  ") 
	Else
		$boolAllMD5FilesDownloaded = False
		_LogWriter("$boolAllMD5FilesDownloaded ==>   " & $boolAllMD5FilesDownloaded) 
	EndIf

	If ($boolAllMD5FilesDownloaded) Then
		_LogWriter("All MD5 files downloaded successfully " & $gstrLogFileDestination)
	Else
		_LogWriter("Could not download all MD5 files  "& $gstrLogFileDestination)
	EndIf

	Return $boolAllMD5FilesDownloaded
	_LogWriter("End Of  AllMD5FilesDownloaded return  "& $boolAllMD5FilesDownloaded)
 EndFunc   ;==>AllMD5FilesDownloaded
 
 Func _FileListToArray1($sPath, $sFilter = "*", $iFlag = 0)
	_LogWriter("Inside _FileListtoArray1")
	Local $hSearch, $sFile, $sFileList, $sDelim = "|"
	_LogWriter("$sPath => "& $sPath & " $sFilter " & $sFilter)
	$sPath = StringRegExpReplace($sPath, "[\\/]+\z", "") & "\" ; ensure single trailing backslash
	_LogWriter(" Path Variable " & $sPath)
	If Not FileExists($sPath) Then Return SetError(1, 1, "")
	   _LogWriter(" Check If file exist  on SPath")
	If StringRegExp($sFilter, "[\\/:><\|]|(?s)\A\s*\z") Then Return SetError(2, 2, "")
	   _LogWriter("$iFlag => " & $iFlag)
	If Not ($iFlag = 0 Or $iFlag = 1 Or $iFlag = 2) Then Return SetError(3, 3, "")
	   _LogWriter(" Inside 2nd IF statement")
	   _LogWriter("$iFlag  inside condition => " & $iFlag)
	   
	$hSearch = FileFindFirstFile($sPath & $sFilter)
	_LogWriter("$hSearch  => " & $hSearch)
	If @error Then Return SetError(4, 4, "")
	While 1
	   _LogWriter(" Inside While Loop")
		$sFile = FileFindNextFile($hSearch)
		_LogWriter(" $sFile " & $sFile)
		If @error Then ExitLoop
		   _LogWriter(" Error Occured in _FileListTOArray1 " & $sFile)
		If ($iFlag + @extended = 2) Then ContinueLoop
		   _LogWriter(" Third Loop Continue $iFlag " & $iFlag)
		$sFileList &= $sDelim & $sFile
		_LogWriter(" Third Loop Continue $sFileList " & $sFileList)
		_LogWriter("End While Loop " )
	WEnd
	FileClose($hSearch)
	_LogWriter("$hSearch  => " & $hSearch & " $sFileList => "& $sFileList)
	If Not $sFileList Then Return SetError(4, 4, "")
	Return StringSplit(StringTrimLeft($sFileList, 1), "|")
	_LogWriter("End _FileListtoArray1")
EndFunc   ;==>_FileListToArray

; Check remote MD5 against local source file
Func _MD5Match($remoteMD5, $localSourceFile)
	Local $strMD5Path = "X:\WinPE\bin\md5"

	$md5Command = $strMD5Path & " -c" & $remoteMD5 & " " & $localSourceFile
	_LogWriter("MD5 command: " & $md5Command)
	 _WindowText("MD5 command " & $md5Command)
	$result = RunWait($md5Command, "", @SW_HIDE)
	
	_LogWriter("MD5 command Executing result: " & $result)
	If ($result = 0) Then
		_LogWriter("Valid: " & $localSourceFile, $gstrLogFileDestination)
	Else
		_LogWriter("!INVALID!: " & $localSourceFile, $gstrLogFileDestination)
	EndIf

	Return $result
EndFunc   ;==>_MD5Match

Func _FileRequired($strSourceFile)
	Local $boolRequired = True
	Local $intIndex = _ArraySearch($astrSourceFileObjectsAtRemote, $strSourceFile)

	If ($intIndex > -1) Then
		If (StringLower(StringStripWS($astrSourceFileObjectsAtRemote[$intIndex][2], 8)) = "false") Then
			$boolRequired = False
		EndIf
	EndIf

	Return $boolRequired
EndFunc   ;==>_FileRequired

; Shuts off the machine after an error
Func _Shutdown($blnForce = False)
	If $blnForce = False Then
		RunWait($gstrSystemDrive & "\WinPE\Bin\eject.exe " & $gstrCDSource, @SystemDir, @SW_HIDE)
		MsgBox(16, "Machine Shutdown", "The process did not complete successfully." & @CRLF & @CRLF & "The machine will now shut off.")
	EndIf
	RunWait("x:\windows\system32\wpeutil.exe shutdown", "", @SW_HIDE)
	Sleep(99999)
	Exit
EndFunc   ;==>_Shutdown


; Reboots the machine after completion
Func _Reboot($blnForce = False)
	If $blnForce = False Then
		RunWait($gstrSystemDrive & "\WinPE\Bin\eject.exe " & $gstrCDSource, @SystemDir, @SW_HIDE)
	EndIf
	RunWait("x:\windows\system32\wpeutil.exe reboot", "", @SW_HIDE)
	Sleep(99999)
	Exit
EndFunc   ;==>_Reboot


; Apply the OS layer to the Z: drive
Func _ImageWEPos($strImageName)
	$strHDSource = RegRead("HKLM\Software\POSF", "HDSource")
	$strSrcDir = RegRead("HKLM\Software\POSF", "SrcDir")
    _logWriter("Inside ImagewePOS for " & $strImageName)
	
	; Write the OS layer for this hardware spec
	$intResult = RunWait($gstrSystemDrive & "\WinPE\Bin\Imagex.exe /apply " & $strHDSource & "\Sources\" & $strSrcDir & "OS_Layer.wim" & " " & Chr(34) & $strImageName & Chr(34) & " Z:", "", @SW_HIDE)
	_logWriter("\WinPE\Bin\Imagex.exe /apply " & $strHDSource & "\Sources\" & $strSrcDir & "OS_Layer.wim" &  $strImageName  & " Z:")
    
	If @error Then
		MsgBox(16, "Unrecoverable Error", "ImageX could not be started")
		$intResult = -99
	ElseIf $intResult > 0 Then
		MsgBox(16, "Unrecoverable Error", "ImageX exited with an errorlevel of " & $intResult)
	EndIf

	RegWrite("HKLM\Software\POSF", "ImageXResult", "REG_DWORD", $intResult)
	Exit
	_LogWriter("End ImageWe PSO")
EndFunc   ;==>_ImageWEPos


; Apply a WIM file to the Z:\Windows\Options folder
Func _ApplyLayer()
	$strHDSource = RegRead("HKLM\Software\POSF", "HDSource")
	$strSrcDir = RegRead("HKLM\Software\POSF", "SrcDir")

	; Create the Windows\options folder, which will house all of our other data
	If Not FileExists("Z:\Windows\Options") Then
		DirCreate("Z:\Windows\Options")
	EndIf

	; Write the requested WIM to disk
	$intResult = RunWait($gstrSystemDrive & "\WinPE\Bin\Imagex.exe /apply " & Chr(34) & $strHDSource & "\Sources\" & $strSrcDir & $CmdLine[2] & Chr(34) & " 1 Z:\Windows\Options", "", @SW_HIDE)
	If @error Then
		MsgBox(16, "Unrecoverable Error", "ImageX could not be started")
		$intResult = -99
	ElseIf $intResult > 0 Then
		MsgBox(16, "Unrecoverable Error", "ImageX exited with an errorlevel of " & $intResult)
	EndIf

	$intCurrent = RegRead("HKLM\Software\POSF", "ImageXResult")
	$intCurrent += $intResult

	RegWrite("HKLM\Software\POSF", "ImageXResult", "REG_DWORD", $intCurrent)
	Exit
EndFunc   ;==>_ApplyLayer


; Performs tasks related to touch screen calibration on machines so-equipped
Func _CalibrateTouchScreen($gstrTouchCalibrateEXE)
	; Kick off screen calibration, if one is specified
	If $gstrTouchCalibrateEXE <> "" Then
		_WindowText("Prompting for screen calibration")

		; Big prompt in the middle :)
		$hwndTouchIndicator = GUICtrlCreateLabel("Touch the screen anywhere to begin calibration", 0, @DesktopHeight * .7, @DesktopWidth, 50, $SS_CENTER)
		GUICtrlSetBkColor(-1, $GUI_BKCOLOR_TRANSPARENT)
		GUICtrlSetFont(-1, 18, 800)

		; Prep the window
		$blnIsMove = False
		$astrMouseOrig = 0
		$intTimer = TimerInit()
		$blnFontColorSwap = False

		#region ; blink text while waiting for movement / clickage
			While 1
				$astrMousePos = MouseGetPos()
				If @error Then
					; nop - no mouse yet
				Else
					; mouse is available
					If Not IsArray($astrMouseOrig) Then
						; mouse has not ever been moved - first non-error result will be the initial position
						$astrMouseOrig = $astrMousePos
					Else
						; Check to see if the mouse has been moved from it's initial position
						If $astrMouseOrig[0] <> $astrMousePos[0] Then
							; x-axis movement
							$blnIsMove = True
						ElseIf $astrMouseOrig[1] <> $astrMousePos[1] Then
							; y-axis movement
							$blnIsMove = True
						Else
							; nop
						EndIf
					EndIf

				EndIf

				; Did any movement happen?
				If $blnIsMove Then
					GUICtrlDelete($hwndTouchIndicator)
					ExitLoop
				EndIf

				; change font color for added flair!
				If TimerDiff($intTimer) > 1000 Then
					$intTimer = TimerInit()
					$blnFontColorSwap = Not $blnFontColorSwap
					If $blnFontColorSwap = True Then
						GUICtrlSetColor($hwndTouchIndicator, 0xFF0000)
					Else
						GUICtrlSetColor($hwndTouchIndicator, 0x000000)
					EndIf
				EndIf
			WEnd
		#endregion ; blink text while waiting for movement / clickage

		; Start calibration
		$intCalibrateResult = RunWait($gstrTouchCalibrateEXE)
		If @error Then
			MsgBox(48, "Warning", "Could not start screen calibration for this device")
		EndIf

		; NCR calibration - save registry file with alignment data
		; Export happens in the background
		$intPosition = StringInStr($gstrTouchCalibrateEXE, "tsharc", False)
		If $intPosition > 0 Then
			Run("reg.exe export HKLM\System\CurrentControlSet\Services\tsharcu x:\tsharcu.reg", "", @SW_HIDE)
		EndIf
	EndIf

	Return $intCalibrateResult
EndFunc   ;==>_CalibrateTouchScreen


; Add a text label to the background (status updates, that sort of thing)
Func _WindowText($strText)
	Local $intResult = 0

	_LogWriter("Writing to screen: " & $strText, $gstrLogFileDestination)
	If ($gintLeaderBoard >= 29) Then ; at bottom of screen...have to start scrolling
		$intResult = _ScrollText($strText)
	Else
		$gintLeaderBoard += 1
		$intResult = GUICtrlCreateLabel($strText, 40, ($gintLeaderBoard * 20), 450, 20)
		GUICtrlSetBkColor(-1, $GUI_BKCOLOR_TRANSPARENT)
	EndIf

	; Returns the GUID handle if someone wants to mess with it
	Return $intResult
EndFunc   ;==>_WindowText

Func _ScrollText($strNewText)
	Local $aResult = _GetAllWindowsControls("Main")

	For $i = UBound($aResult) - 1 To 1 Step -1
		$intXPos = $aResult[$i][1]
		If ($intXPos = 40) Then
			$intControlID = $aResult[$i][3]
			GUICtrlSetData($intControlID, $strNewText)
			$strNewText = $aResult[$i][4]
		EndIf

	Next

	Return $aResult[UBound($aResult) - 1][3]
EndFunc   ;==>_ScrollText

Func _GetAllWindowsControls($hCallersWindow)
	; Get all list of controls
	$sClassList = WinGetClassList($hCallersWindow)
	;_LogWriter("_GetAllWindowsControls start" & $hCallersWindow )
	; Create array
	;_LogWriter("_GetAllWindowsControls : Creating Array" & $hCallersWindow )
	$aClassList = StringSplit($sClassList, @CRLF, 2)
	; Sort array
	_ArraySort($aClassList)
	_ArrayDelete($aClassList, 0)

	; Loop
	Local $aResult[UBound($aClassList)][5]
	Local $iCurrentClass = "", $iCurrentCount = 1, $iTotalCounter = 1
	;_LogWriter("_GetAllWindowsControls : Current Class" & $iCurrentClass )

	For $i = 0 To UBound($aClassList) - 1
		If $aClassList[$i] = $iCurrentClass Then
		   ;_LogWriter("_GetAllWindowsControls : Inside For Loop")
		  ; _LogWriter("_GetAllWindowsControls : Class List Current Count" & $iCurrentCount)
			$iCurrentCount += 1
		Else
			$iCurrentClass = $aClassList[$i]
			$iCurrentCount = 1
			;_LogWriter("_GetAllWindowsControls : Else Condition Class List Current Count" & $iCurrentCount)
		EndIf

		$hControl = ControlGetHandle($hCallersWindow, "", "[CLASSNN:" & $iCurrentClass & $iCurrentCount & "]")
		$text = StringRegExpReplace(ControlGetText($hCallersWindow, "", $hControl), "[\n\r]", "{@CRLF}")
		;_LogWriter("_GetAllWindowsControls : Text " & $text)
		$aPos = ControlGetPos($hCallersWindow, "", $hControl)
		$sControlID = _WinAPI_GetDlgCtrlID($hControl)

		$aResult[$i][0] = $iCurrentClass
		$aResult[$i][1] = $aPos[0]
		$aResult[$i][2] = $hControl
		$aResult[$i][3] = $sControlID
		$aResult[$i][4] = $text

		If Not WinExists($hCallersWindow) Then ExitLoop
		 ;  _LogWriter("_GetAllWindowsControls : Exit Loop " & $aPos[0])
		$iTotalCounter += 1
	Next

	$aResult[0][0] = "ClassnameNN"
	$aResult[0][1] = "X-Position"
	$aResult[0][2] = "Handle"
	$aResult[0][3] = "ControlID"
	$aResult[0][4] = "Text"
   ; _LogWriter("_GetAllWindowsControls : Results " & $aResult)
	Return $aResult
	;_LogWriter("_GetAllWindowsControls END")
EndFunc   ;==>_GetAllWindowsControls

; Shows a 'busy' animation while an app runs
Func _ShowBusyApp_New($strAppToWatch)
	Local $intCurrentFrame = 1
	Dim $astrFrames[8]
    _WindowText("Inside ShowBusyApp_New  " & $strAppToWatch)
	; Load up the eight frames of animation
	$pic = GUICtrlCreatePic("X:\WinPE\Data\1.bmp", 20, $gintLeaderBoard * 20, 10, 10)

	; Set cursor to "busy"
	GUISetCursor(1)

	; Rotate the picture through the eight frames
	While ProcessExists($strAppToWatch)
		; Sleep for an approximate 10 frames per second
		Sleep(100)

		; hide previous frame, increment framecounter by one
		If $intCurrentFrame = 8 Then
			$intCurrentFrame = 1
		Else
			$intCurrentFrame += 1
		EndIf

		; Update frame to next picture
		GUICtrlSetImage($pic, "X:\WinPE\Data\" & $intCurrentFrame & ".bmp")
	WEnd

	; Delete the pictures
	GUICtrlDelete($pic)

	; Set cursor back to normal
	GUISetCursor(2)
EndFunc   ;==>_ShowBusyApp_New


; Returns the total applied size of the image in a wim file
; Used to determine completion percentage of WIM unpack
Func _EnumWIMSize($strImageName, $intImageID = 1)
	Local $intResult, $strResult = "", $intPOS, $intPOS, $intPos2, $astrTemp, $strImagePath
	Local $intResult = 0
   
   _LogWriter("_EnumWIMSize :- $strImageName " & $strImageName)
     
    
	; Get info from WIM file
	_LogWriter("_EnumWIMSize :- $strImageName " & $strImageName)
	 $intResult = RunWait(@ComSpec & " /c X:\WinPE\Bin\Imagex.exe /info " & Chr(34) & $strImageName & Chr(34) & " " & Chr(34) & $intImageID & Chr(34) & " > " & Chr(34) & @TempDir & "\wimdata.txt" & Chr(34), "", @SW_HIDE)

    ;$intResult = RunWait(@ComSpec & " /c X:\WinPE\Bin\Imagex.exe /info " & Chr(34) & $strImageName & Chr(34) &" > " & Chr(34) & @TempDir & "\wimdata.txt" & Chr(34), "", @SW_HIDE)

    ;$intResult = RunWait(@ComSpec & " /c X:\WinPE\Bin\Imagex.exe /info " & Chr(34) & $strImageName & Chr(34) & " " & " 1 " & " > " & Chr(34) & @TempDir & "\wimdata.txt" & Chr(34), "", @SW_HIDE)
    _LogWriter(" Running Command WimSize /c X:\WinPE\Bin\Imagex.exe /info " & $strImageName & " " & $intImageID & " > " & @TempDir & "\wimdata.txt") 
	 

	If @error Then
		; THe executable didn't even exist - that shouldn't happen!
		MsgBox(48, "WARNING", "IMAGEX could not be started!")
		Return 0

	ElseIf $intResult > 0 Then
		; target file doesn't exist?
		_LogWriter("$intResult  " & $intResult)
		MsgBox(48, "WARNING", "IMAGEX could not read file: " & $strImageName)
		Return 0
	EndIf

	; Read back the temporary file
	$strResult = FileRead(@TempDir & "\wimdata.txt")
	If @error Then
		; couldn't read the file?
		Return 0
	EndIf

	; Break into pieces for easier parsing
	$astrTemp = StringSplit($strResult, @CRLF, 1)
	If @error Then
		; no string to split?
		Return 0
	EndIf

	; Step through results looking for names of images stored in this WIM
	$intSize = 0
	For $x = 1 To $astrTemp[0]
		If StringInStr($astrTemp[$x], "<TOTALBYTES>") Then

			; Break size info out of XML
			$intPOS = StringInStr($astrTemp[$x], ">") + 1
			$intPos2 = StringInStr($astrTemp[$x], "<", False, 2) - $intPOS
			$intSize = StringMid($astrTemp[$x], $intPOS, $intPos2)

			; Done
			ExitLoop
		EndIf
	Next

	; Did we find anything?
	If $intSize = 0 Then
		; Suck!
		Return 0
	EndIf

	; Return the data we found
	Return $intSize
EndFunc   ;==>_EnumWIMSize


; Starts the WindowsPE initialization process
; Also turns off the firewall for uVNC access
Func _WPEInit()
	RunWait("X:\Windows\System32\wpeinit.exe", "", @SW_HIDE)
	Run("wpeutil disablefirewall", "", @SW_HIDE)
EndFunc   ;==>_WPEInit


; Debug hotkey polling
Func _HotKey()
	; Debug access here
	Global $gintDebugKeyTimer = 0
	Global $gintDebugKeyCounter = 0
	HotKeySet("{INSERT}", "_DebugCommandPrompt")

	; Jamie Walling bounce-window here
	Global $gintJamieKeyTimer = 0
	Global $gintJamieKeyCounter = 0
	Global $gblnJamieBounceIsActive = False
	Global $ghwndJamieWindow = 0
	Global $gintJamieWindow_X = 0
	Global $gintJamieWindow_DX = 2
	Global $gintJamieWindow_Y = 0
	Global $gintJamieWindow_DY = 2
	HotKeySet("?", "_JamieBounce")

	; Sleep forever -- this is only here to trap hotkeys
	While 1
		Sleep(100000)
	WEnd
EndFunc   ;==>_HotKey


; Press INSERT three times and you get a command prompt window!
Func _DebugCommandPrompt()
	; Pass through the insert key
	HotKeySet("{INSERT}")
	Send("{INSERT}")
	HotKeySet("{INSERT}", "_DebugCommandPrompt")

	; The insert key must be pressed three times within the span of one second to trigger the debug window
	If $gintDebugKeyTimer = 0 Then
		$gintDebugKeyTimer = TimerInit()
		$gintDebugKeyCounter = 1
		Return

		; More than 1 second has transpired since last keypress - reset counter
	ElseIf TimerDiff($gintDebugKeyTimer) > 1000 Then
		$gintDebugKeyTimer = TimerInit()
		$gintDebugKeyCounter = 1
		Return

		; 2nd keypress in less than a second -- almost there...
	ElseIf (TimerDiff($gintDebugKeyTimer) < 1000) And ($gintDebugKeyCounter < 2) Then
		$gintDebugKeyCounter += 1
		Return

	Else
		; Third keypress in under a second.  Reset all counters and proceed
		$gintDebugKeyTimer = 0
		$gintDebugKeyCounter = 0
	EndIf

	; Kick off a command prompt window
	Run(@ComSpec, "X:\")
EndFunc   ;==>_DebugCommandPrompt


; Easter egg!
Func _JamieBounce()
	; pass through the question mark key
	HotKeySet("?")
	Send("?")
	HotKeySet("?", "_JamieBounce")

	; The ? key must be pressed three times within the span of one second to trigger the easter egg
	If $gintJamieKeyTimer = 0 Then
		$gintJamieKeyTimer = TimerInit()
		$gintJamieKeyCounter = 1
		Return

		; More than 1 second has transpired since last keypress - reset counter
	ElseIf TimerDiff($gintJamieKeyTimer) > 1000 Then
		$gintJamieKeyTimer = TimerInit()
		$gintJamieKeyCounter = 1
		Return

		; 2nd keypress in less than a second -- almost there...
	ElseIf (TimerDiff($gintJamieKeyTimer) < 1000) And ($gintJamieKeyCounter < 2) Then
		$gintJamieKeyCounter += 1
		Return

	Else
		; Third keypress in under a second.  Reset all counters and proceed
		$gintJamieKeyTimer = 0
		$gintJamieKeyCounter = 0
	EndIf

	; If he's already running, calling this function kills him off
	If $gblnJamieBounceIsActive Then
		$gblnJamieBounceIsActive = False
		GUIDelete($ghwndJamieWindow)

	Else
		; start him up!
		$gblnJamieBounceIsActive = True

		; Build window
		$ghwndJamieWindow = GUICreate("JamieBounce", 317, 398, $gintJamieWindow_X, $gintJamieWindow_Y, BitOR($DS_SETFOREGROUND, $WS_DISABLED, $WS_POPUP, $WS_BORDER, $WS_CLIPSIBLINGS), BitOR($WS_EX_TOPMOST, $WS_EX_TOOLWINDOW))
		GUICtrlCreatePic(@ScriptDir & "\..\Data\egads.jpg", 0, 0, 317, 398)
		GUISetState()

		; Now make him bounce
		While $gblnJamieBounceIsActive
			$gintJamieWindow_X += $gintJamieWindow_DX
			$gintJamieWindow_Y += $gintJamieWindow_DY

			; Tracking for left-right dimension
			If $gintJamieWindow_X > @DesktopWidth - 317 Then
				$gintJamieWindow_DX = -2
			ElseIf $gintJamieWindow_X < 1 Then
				$gintJamieWindow_DX = 2
			EndIf

			; Tracking for up-down dimension
			If $gintJamieWindow_Y > @DesktopHeight - 398 Then
				$gintJamieWindow_DY = -2
			ElseIf $gintJamieWindow_Y < 1 Then
				$gintJamieWindow_DY = 2
			EndIf

			Sleep(5)
			WinMove("JamieBounce", "", $gintJamieWindow_X, $gintJamieWindow_Y)
		WEnd
	EndIf
EndFunc   ;==>_JamieBounce


; Start the PAR touch screen interface
Func _ParTouch()
	; Devcon the COM drivers
	RunWait("X:\WinPE\Bin\Devcon.exe updateni x:\windows\inf\msports.inf ACPI\PNP0501", "", @SW_HIDE)

	; Once DEVCON is done, we run the setup silently
	RunWait("X:\WinPE\Drivers\TWTouch\Setup.exe -S", "X:\WinPE\Drivers\TWTouch")

	; The above always seems to exit really fast; waiting for the TWService to show up usually gets us in the right direction
	ProcessWait("TWService.exe")
EndFunc   ;==>_ParTouch


; Start the ELO touch screen interface
Func _EloTouch()
	; Devcon the COM drivers
	RunWait("X:\WinPE\Bin\Devcon.exe updateni x:\windows\inf\msports.inf ACPI\PNP0501", "", @SW_HIDE)

	; Once DEVCON is done, we run the setup silently -- this setup behaves "well" and doesn't immediately exit like the TWTouch driver
	RunWait("X:\WinPE\Drivers\ELOTouch\EloSetup.exe /Is /P:5 /NoReset /S", "X:\WinPE\Drivers\ELOTouch")
EndFunc   ;==>_EloTouch

; Start the TSharc Touch screen interface
Func _TSharcTouch()
	; Devcon the drivers
	RunWait("X:\WinPE\Bin\Devcon.exe updateni x:\winpe\drivers\tsharctouch\tsharcu.inf USB\VID_07DD&PID_0001", "", @SW_HIDE)

	; Wait a few seconds for the interface to start
	Sleep(5000)
EndFunc   ;==>_TSharcTouch


; Execute a given diskpart script
Func _DiskPart($strPathToDPS)
	$blnSuccess = False
	For $i = 1 To 5
		$intResult = RunWait("diskpart.exe -s " & $strPathToDPS, "", @SW_HIDE)

		; Check for errors
		If @error Or $intResult <> 0 Then
			$blnSuccess = False
		Else
			$blnSuccess = True
			ExitLoop
		EndIf
	Next

	; Did it fail miserably?
	If $blnSuccess = False Then
		MsgBox(16, "Unrecoverable Error", "DiskPart exited with an errorlevel of " & $intResult)
		_Shutdown(5)
	EndIf
EndFunc   ;==>_DiskPart


; Display hardware stats
Func _EnumHWInfo()
	Local $int_Func_Timer = TimerInit()
	;_DebugLog("Func _EnumHWInfo() Started", $gstrLogFileDestination)

	Local $blnWMIError = False, $blnDriveError = False, $blnCPUError = False

	; Query for disk details
	; _DebugLog("_EnumHWInfo,Submitting WMI query of Win32_DiskDrive", $gstrLogFileDestination)
	$objColDisk = $gobjWMI.ExecQuery("Select Size, Index from Win32_DiskDrive where MediaType='Fixed hard disk media'")
	If @error Then
		; Disk query failed...
		; _DebugLog("_EnumHWInfo,WMI query failed; drive cannot be identified", $gstrLogFileDestination)
		$blnDriveError = True
	EndIf

	; Query for processor details
	; _DebugLog("_EnumHWInfo,Submitting WMI query of Win32_Processor", $gstrLogFileDestination)
	$objColCPU = $gobjWMI.ExecQuery("Select MaxClockSpeed, NumberOfCores, NumberOfLogicalProcessors from Win32_Processor")
	If @error Then
		; CPU query failed ...
		; _DebugLog("_EnumHWInfo,WMI query failed; CPU cannot be identified", $gstrLogFileDestination)
		$blnCPUError = True
	EndIf

	; Break out the drive data
	$astrDriveData = 0
	$x = 0
	If $blnDriveError = False Then
		For $objItem In $objColDisk
			$x += 1
			If Not IsArray($astrDriveData) Then
				Dim $astrDriveData[$x][2]
			Else
				ReDim $astrDriveData[$x][2]
			EndIf
			$astrDriveData[$x - 1][0] = $objItem.Index
			$astrDriveData[$x - 1][1] = $objItem.Size
		Next
	EndIf

	; Break out the processor data
	$astrCPUData = 0
	$x = 0
	If $blnCPUError = False Then
		For $objItem In $objColCPU
			$x += 1
			If Not IsArray($astrCPUData) Then
				Dim $astrCPUData[$x][3]
			Else
				ReDim $astrCPUData[$x][3]
			EndIf
			$astrCPUData[$x - 1][0] = $objItem.MaxClockSpeed
			$astrCPUData[$x - 1][1] = $objItem.NumberOfCores
			$astrCPUData[$x - 1][2] = $objItem.NumberOfLogicalProcessors
		Next
	EndIf

	; Break out the Memory stats
	$astrMemInfo = MemGetStats()
	$intSystemMemory = Floor($astrMemInfo[1] / 1024)

	; Get correct IP address
	$strIPAddy = "-1"
	Do
		; some machines were failing at getting IPs fast enough, so this will try every 10 seconds
		; with a 30 second timeout to get the right IP. after 30 seconds it will ask you if you want
		; to try again. If you don't and you're not booting from DVD or USB it'll fail miserably
		; in about 30 seconds as it goes to the next step
		For $i = 0 To 3 Step 1
			If @IPAddress1 = "0.0.0.0" Or @IPAddress1 = "127.0.0.1" Then
				Sleep(10000)
			Else
				$strIPAddy = @IPAddress1
				ExitLoop (1)
			EndIf
		Next
		If $strIPAddy = "-1" Then
			; MsgBox option 2 = abort, retry, ignore, MUAHAHAHA
			$response = MsgBox(2, "IP Acquisition Failed", "Couldn't obtain an IP Address yet")
			; TODO NOTE this will affect unattended BOH conversions
			If $response <> 4 Then
				$strIPAddy = @IPAddress1
			EndIf
		EndIf
	Until $strIPAddy <> "-1"

	; Determine software version number
	$strVerNum = ""
	Global $astrHDDs = DriveGetDrive("Fixed")
	For $i = 1 To $astrHDDs[0]
		If FileExists($astrHDDs[$i] & "\sources\VersionNumber.txt") Then
			$file = FileOpen($astrHDDs[$i] & "\sources\VersionNumber.txt", 0)

			If $file <> -1 Then
				$strVerNum = FileReadLine($file)
			EndIf

			FileClose($file)
			ExitLoop
		EndIf
	Next

	; Retry if necessary to get an IP Address via DHCP
	If $gstrImageName = "BOH" Then
		_DebugLog("Initial IP Address before any retries = [" & $strIPAddy & "]", $IPADDRESS_LOGFILE)

		; for 5 minutes, every 10 seconds, attempt to renew IP address
		For $i = 1 To 30
			$ipAddress = StringSplit($strIPAddy, ".")
			If $ipAddress[0] >= 2 And $ipAddress[1] = "169" And $ipAddress[2] = "254" Then
				_DebugLog("WARNING: No DHCP = [" & $strIPAddy & "] attempting ipconfig /renew (attempt #" & $i & ")", $IPADDRESS_LOGFILE)
				;$exitCode = RunWait(@ComSpec & " /c " & Chr(34) & "X:\Windows\System32\ipconfig.exe /renew" & Chr(34),"",@SW_HIDE)
				$exitCode = RunWait(@ComSpec & " /c " & Chr(34) & "ipconfig /renew" & Chr(34), "", @SW_HIDE)
				If @error Then
					_DebugLog("ERROR: Failed attempt to ipconfig /renew", $IPADDRESS_LOGFILE)
				EndIf
				Sleep(10000)
				$strIPAddy = @IPAddress1
				_DebugLog("ipconfig /renew resulted in IP Address [" & $strIPAddy & "] and exit code [" & $exitCode & "]", $IPADDRESS_LOGFILE)
			Else
				; not 169.254.x.x
				; or some unknown IP address format ($ipAddress[0] < 2)
				ExitLoop
			EndIf
		Next
		; 5 mintues could have expired and still no valid DHCP IP address at this point
		_DebugLog("Resulting IP Address = [" & $strIPAddy & "]", $IPADDRESS_LOGFILE)
	EndIf


	; Write stuff to the screen
	; First, IP address
	If $strIPAddy = "0.0.0.0" Or $strIPAddy = "127.0.0.1" Then
		; all zeros or localhost means no link
		_WriteHWInfo("IP:", "<!> NETWORK DISCONNECTED <!>")
		; _DebugLog("_EnumHWInfo,<!> IP address is 0.0.0.0 <!>", $gstrLogFileDestination, $gstrLogFileDestination)
	ElseIf StringLeft($strIPAddy, 3) = "169" Then
		; 169.254.x.x addresses mean DHCP wasn't available and the machine auto-configged an address
		_WriteHWInfo("IP:", "<!> NO DHCP SERVICES <!>")
		; _DebugLog("_EnumHWInfo,<!> IP address is " & @IPAddress1, $gstrLogFileDestination, $gstrLogFileDestination)
	Else
		; this is good news
		_WriteHWInfo("IP:", $strIPAddy)
		; _DebugLog("_EnumHWInfo,IP address is " & @IPAddress1, $gstrLogFileDestination, $gstrLogFileDestination)
	EndIf

	; Next, memory stats
	_WriteHWInfo("Memory:", $intSystemMemory & " Mb")
	; _DebugLog("_EnumHWInfo,Memory reported as " & $intSystemMemory & " Mb", $gstrLogFileDestination, $gstrLogFileDestination)

	; Next, drive information
	If $blnDriveError = True Then
		_WriteHWInfo("Disk:", "<!> WMI FAILURE <!>")
		; _DebugLog("_EnumHWInfo,<!> No drive details available <!>", $gstrLogFileDestination, $gstrLogFileDestination)
	Else
		If IsArray($astrDriveData) Then
			For $x = UBound($astrDriveData) To 1 Step -1
				; output to screen for the current drive
				_WriteHWInfo("Disk" & $astrDriveData[$x - 1][0] & ":", Floor($astrDriveData[$x - 1][1] / 1000000000) & " Gb")
				; _DebugLog("_EnumHWInfo,Disk" & $astrDriveData[$x - 1][0] & " reported as " & Floor($astrDriveData[$x - 1][1] / 1000000000) & " Gb", $gstrLogFileDestination)
			Next
		Else
			; No drive?  Bad news, but entirely possible
			_WriteHWInfo("Disk:", "<!> NO DISKS FOUND <!>")
			; _DebugLog("_EnumHWInfo,<!> No disks found <!>", $gstrLogFileDestination)
		EndIf
	EndIf

	; Next, CPU information
	If $blnCPUError = True Then
		_WriteHWInfo("CPU:", "<!> WMI FAILURE <!>")
		; _DebugLog("_EnumHWInfo,<!> No CPU details available <!>", $gstrLogFileDestination)
	Else
		If IsArray($astrCPUData) Then
			For $x = UBound($astrCPUData) To 1 Step -1
				; Physical cores
				$strCPUDesc = $astrCPUData[$x - 1][1] & " Core"
				If $astrCPUData[$x - 1][1] > 1 Then
					; more than one core means we need plural coreS :-)
					$strCPUDesc &= "s"
				EndIf

				; Check logical cores (to properly report hyperthreading / SMT capable products)
				If $astrCPUData[$x - 1][2] > $astrCPUData[$x - 1][1] Then
					$strCPUDesc &= ", " & $astrCPUData[$x - 1][2] & " Threads"
				EndIf

				; output to screen
				_WriteHWInfo("CPU" & $x - 1 & ":", $strCPUDesc & " @ " & $astrCPUData[$x - 1][0] & "Mhz")
				; _DebugLog("_EnumHWInfo,CPU" & $x - 1 & " reported as " & $strCPUDesc & " @ " & $astrCPUData[$x - 1][0] & "Mhz", $gstrLogFileDestination)
			Next
		Else
			; No CPU?  WTF?
			_WriteHWInfo("CPU:", "<!> WMI FAILURE <!>")
			; _DebugLog("_EnumHWInfo,<!> No CPU details available <!>", $gstrLogFileDestination)
		EndIf
	EndIf

	; Finally, software version number if present
	If $strVerNum <> "" Then
		$arrayVerNum = StringSplit($strVerNum, ': ', 1)
		If ($arrayVerNum[0] = 2) Then
			_WriteHWInfo($arrayVerNum[1] & ":", $arrayVerNum[2])
		EndIf
	EndIf

	; _DebugLog("EndFunc _EnumHWInfo() {" & Round(TimerDiff($int_Func_Timer),1) & "msec}", $gstrLogFileDestination)
EndFunc   ;==>_EnumHWInfo


; Write HW data to the lower right corner of the screen
Func _WriteHWInfo($strLabel, $strData)
	GUICtrlCreateLabel($strLabel, @DesktopWidth - 250, @DesktopHeight - 20 - ($gintHWInfoCounter * 20), 90, 20, $SS_Right)
	GUICtrlSetBkColor(-1, $GUI_BKCOLOR_TRANSPARENT)
	GUICtrlCreateLabel($strData, @DesktopWidth - 150, @DesktopHeight - 20 - ($gintHWInfoCounter * 20), 200, 20)
	GUICtrlSetBkColor(-1, $GUI_BKCOLOR_TRANSPARENT)
	$gintHWInfoCounter += 1
EndFunc   ;==>_WriteHWInfo


; This function provides our best guess as to which register this should be (if XPient is in this story, anyway)
; Also provides the register number to pull data from -- if there are registers available
Func _AutoDiscovery($strDriveLetter = "C:")
	Local $strBaseAddr = "", $intPOS = 0, $intRegisterNum = 0, $intStoreNum = 0, $intSourceID = 0
	Local $intIsProduction = 1, $intIsRecovery = 0, $intAutoStage = 1, $intQATools = 0, $strDNSSuffix = ""
	Local $strTimeZone = "(GMT-08:00) Pacific Time", $intDaylightSavings = 1
	Dim $astrPingResults[10] = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0]

	; First, and most obvious, does the file already exist?  If so, we flip it to recovery mode, and we're done
	If FileExists("C:\Recovery.ini") Then
		If $strDriveLetter <> "C:" Then
			FileCopy("C:\Recovery.ini", $strDriveLetter & "\Recovery.ini", 1)

			IniWrite($strDriveLetter & "\Recovery.ini", "Config", "IsRecovery", 1)
			Return
		EndIf
	EndIf

	; Get the class-C subnet data
	$intPOS = StringInStr(@IPAddress1, ".", False, 3)
	$strBaseAddr = StringLeft(@IPAddress1, $intPOS)

	; Ping registers 1 through 9
	For $x = 21 To 29
		$intResult = Ping($strBaseAddr & $x, 1000)

		If $intResult > 0 Then
			; The zero element records whether we hit *anything*
			$astrPingResults[0] = 1
			$astrPingResults[$x - 20] = 1
		EndIf
	Next

	; If we found anything, then we know we're in an Xpient store already
	; Let's try to guess which register we should be... (looking for the first 'gap', basically)
	If $astrPingResults[0] = 1 Then
		$intIsRecovery = 1

		; Now we should be able to connect to an existing register and pull the other data
		; Start with the highest register number, and work downwards
		For $x = 9 To 1 Step -1
			If $astrPingResults[$x] = 1 Then
				; this IP returned a ping -- can we connect to it?
				If DriveMapAdd("", "\\" & $strBaseAddr & $x + 20 & "\Boot", 0, "iris_user", "#12345VigoImage") Then
					; success
					$intSourceID = $x
					ExitLoop
				EndIf
			EndIf
		Next

		; We should be able to go read the file from the remote register, if we found one
		If $intSourceID <> 0 Then
			; read file, adjust as necessary
			$intIsProduction = IniRead("\\" & $strBaseAddr & $x + 20 & "\Boot\recovery.ini", "Config", "IsProduction", $intIsProduction)
			$intQATools = IniRead("\\" & $strBaseAddr & $x + 20 & "\Boot\recovery.ini", "Config", "QATools", $intQATools)
			$intAutoStage = IniRead("\\" & $strBaseAddr & $x + 20 & "\Boot\recovery.ini", "Config", "AutoStage", $intAutoStage)

			$strTimeZone = IniRead("\\" & $strBaseAddr & $x + 20 & "\Boot\recovery.ini", "Locale", "TimeZone", $strTimeZone)
			$intDaylightSavings = IniRead("\\" & $strBaseAddr & $x + 20 & "\Boot\recovery.ini", "Locale", "DaylightSavings", $intDaylightSavings)
			$intStoreNum = IniRead("\\" & $strBaseAddr & $x + 20 & "\Boot\recovery.ini", "Locale", "StoreNum", $intStoreNum)
		EndIf

		; Let's try to automatically determine what register number we should be...
		For $x = 1 To 9
			If $astrPingResults[$x] = 0 And $intRegisterNum = 0 Then
				$intRegisterNum = $x
				ExitLoop
			EndIf
		Next

	Else
		; This is the track for if NO other prod registers were found...
		; We default to a QA environment if we see the PXE server or we are in a VM
		$intResult = Ping($gstrIRVLABPXEIP)

		If ($intResult > 0) Or _isVM() Then
			; We're somewhere in the QA lab environment (or in a VM)
			$intIsProduction = 0
			$intQATools = 0

			; Get DNS suffix to see if we can figure out the current lab Number
			$objDNSCol = $gobjWMI.ExecQuery("select DNSDomain from Win32_NetworkAdapterConfiguration")
			For $objDNSresult In $objDNSCol
				$strDNSSuffix = $objDNSresult.DNSDomain
				ExitLoop
			Next

			; In the lab, the first six characters should be the store number .. if they're numeric, we're probably right
			$strDNSSuffix = StringLeft($strDNSSuffix, 6)
			If StringIsInt($strDNSSuffix) Then
				$intStoreNum = $strDNSSuffix
			EndIf

		Else
			; We can't find irvlabpxe, and nobody else is responding... Guessing we're in Prod, and in a new store
			; the default data states (other than store number) for this function are assumed correct

			; Determine the store number from the router (router could be .2 or .1)
			TCPStartup()
			$hostname = ""

			For $lastOctet = 2 To 1 Step -1
				$tempIP = $strBaseAddr & $lastOctet
				$hostname = _TCPIpToName($tempIP)

				If StringRegExp($hostname, "\w*\.\d*\.tb\.us\.tgr\.net") Then
					ExitLoop
				EndIf
			Next

			$hostnameParts = StringSplit($hostname, ".")
			If @error Then
				; nop
			ElseIf $hostnameParts[0] < 2 Then
				; nop
			Else
				$intStoreNum = $hostnameParts[2]
			EndIf

			TCPShutdown()
		EndIf
	EndIf

	; One last protection for register Number
	If $intRegisterNum = 0 Then
		$intRegisterNum = ""
	EndIf

	; Write the INI file
	IniWrite($strDriveLetter & "\Recovery.ini", "Locale", "TimeZone", $strTimeZone)
	IniWrite($strDriveLetter & "\Recovery.ini", "Locale", "DaylightSavings", $intDaylightSavings)
	IniWrite($strDriveLetter & "\Recovery.ini", "Locale", "StoreNum", $intStoreNum)
	IniWrite($strDriveLetter & "\Recovery.ini", "Locale", "RegisterNum", $intRegisterNum)

	IniWrite($strDriveLetter & "\Recovery.ini", "Config", "IsProduction", $intIsProduction)
	IniWrite($strDriveLetter & "\Recovery.ini", "Config", "IsRecovery", $intIsRecovery)
	IniWrite($strDriveLetter & "\Recovery.ini", "Config", "QATools", $intQATools)
	IniWrite($strDriveLetter & "\Recovery.ini", "Config", "AutoStage", $intAutoStage)
EndFunc   ;==>_AutoDiscovery

; creates a diskpart script that cleans, partitions, and formats the given disk with our standard setup
Func _CreateCleanDiskpartScript($intPhysDiskID)
	_WindowText("Creating diskpart script for fresh install")
	local $label = "SYSTEM"
	;get the disk size
	$intHDiskSize = _DiskSizeFromID($intPhysDiskID)
	; If HDisk size is zero, something went terribly wrong
	If $intHDiskSize = 0 Then
		MsgBox(16, "Unrecoverable Error", "Local fixed disk is missing, damaged, or is reporting zero space available.")
		_Shutdown(5)
	EndIf
	$objDPSFile = _ScriptOpen(@TempDir, "recovery.dps", 2)
	; Create recovery DPS file
	; Select primary hdisk
	FileWriteLine($objDPSFile, "sel disk " & $intPhysDiskID)
	; "Clean" the disk - make sure there's no other partitions waiting for us
	FileWriteLine($objDPSFile, "clean")
	; create the windows partition leaving 20GB for the recovery partition
	; added by abhishek for system reserved Drive
	;local $primarydrive = $intHDiskSize - 20007
	;$primarydrive = $primarydrive - 400
	;local $systemreserved = $primarydrive - 39000
	;FileWriteLine($objDPSFile, "create partition primary size=" & $intHDiskSize - 20007)	
	
	$intHDiskSize = $intHDiskSize - 800
	;abhishek added for primary
	FileWriteLine($objDPSFile, "create partition primary size=" & $intHDiskSize - 20007)	
	_dpsFormatAssignDrive($objDPSFile, $intPhysDiskID, 1, "Y:")	
	
	; create the 20GB recovery partition
	FileWriteLine($objDPSFile, "create partition primary ")
	_dpsFormatAssignDrive($objDPSFile, $intPhysDiskID, 2, "Z:")	
	
	;abhishek create  400 mb for system reserved file for system image  for system reserve dirve
	;FileWriteLine($objDPSFile, "create partition primary size=" & 400)
	;FileWriteLine($objDPSFile, "format quick fs=ntfs label="& $label)	
	;FileWriteLine($objDPSFile, "assign letter=S")	
	;FileWriteLine($objDPSFile, "Active")
	
	; make recovery partition active
	;commented by abhishek for testing
	;_dpsMakePartitionActive($objDPSFile, $intPhysDiskID, 2)
	_dpsMakePartitionActive($objDPSFile, $intPhysDiskID, 2)

	; Close recovery DPS file
	FileClose($objDPSFile)
	GUICtrlSetData(-1, "Diskpart Script Created")
EndFunc   ;==>_CreateCleanDiskpartScript

; reformats the windows partition and assigns it Z: to prep for recovery
Func _CreateRecoveryDiskpartScript($intPhysDiskID)
	; Create a DiskPart script in temp directory, flag 2 = erase any previous file and open in write mode
	$objDPSFile = _ScriptOpen(@TempDir, "recovery.dps", 2)
	; Format windows partition (1) and assign drive letter Z:
	_dpsFormatAssignDrive($objDPSFile, $intPhysDiskID, 1, "Z:")
	; make sure the recovery partition is bootable
	_dpsMakePartitionActive($objDPSFile, $intPhysDiskID, 2)
	; Close recovery DPS file
	FileClose($objDPSFile)
EndFunc   ;==>_CreateRecoveryDiskpartScript

; Opens a file in the given directory using the specified mode
Func _ScriptOpen($strDir, $strFN, $intMode)
	$objFile = FileOpen($strDir & "\" & $strFN, $intMode)
	;If we can't create the script, we can't continue
	If @error Or $objFile = -1 Then
		MsgBox(16, "Unrecoverable Error", "Could not open " & $strFN & ".")
		_Shutdown(5)
	Else
		Return $objFile
	EndIf
EndFunc   ;==>_ScriptOpen


; Append diskpart script to assign a drive letter
Func _dpsAssignDrive($objFile, $intDiskID, $intPart, $charDriveLetter); note drive letter should include :
	; Select our physical disk ID that we detected
	FileWriteLine($objFile, "sel disk " & $intDiskID)
	; Select partition to format
	FileWriteLine($objFile, "sel par " & $intPart)
	; remove any old letters
	FileWriteLine($objFile, "remove")
	; Give freshly formatted partition a drive letter
	FileWriteLine($objFile, "assign letter=" & $charDriveLetter)
EndFunc   ;==>_dpsAssignDrive


; Append diskpart script to format a partition and assign a drive letter
Func _dpsFormatAssignDrive($objFile, $intDiskID, $intPart, $charDriveLetter); note drive letter should include :
	; Select our physical disk ID that we detected
	FileWriteLine($objFile, "sel disk " & $intDiskID)
	; Select partition to format
	FileWriteLine($objFile, "sel par " & $intPart)
	; Format the windows partition NTFS + quickly
	FileWriteLine($objFile, "format fs=ntfs quick override")
	; Give freshly formatted partition a drive letter
	FileWriteLine($objFile, "assign letter=" & $charDriveLetter)
EndFunc   ;==>_dpsFormatAssignDrive

; Append diskpart script to make a partition active
Func _dpsMakePartitionActive($objFile, $intDiskID, $intPart)
	FileWriteLine($objFile, "sel disk " & $intDiskID)
	FileWriteLine($objFile, "sel par " & $intPart)
	FileWriteLine($objFile, "active")
EndFunc   ;==>_dpsMakePartitionActive
