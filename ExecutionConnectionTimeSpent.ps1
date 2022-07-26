    

#----------------------------------------------------------------
#Function to connect to the database using a retry-logic
#----------------------------------------------------------------

Function GiveMeConnectionSource($IPReference,$IPControlPort,$IPControlPortProcess)
{ 
  $NumberAttempts= ReadConfigFile("RetryLogicNumberAttempts")
  for ($i=1; $i -le [int]$NumberAttempts; $i++)
  {
   try
    {
     if( $(ReadConfigFile("ShowConnectionMessage")) -eq "Y")
     {
      logMsg( "Connecting to the database: " + $(ReadConfigFile("server")) + " - DB: " + $(ReadConfigFile("Db")) + "...Attempt #" + $i + " of " + $NumberAttempts) (1) -SaveFile $false 
     }

      if( TestEmpty($IPReference.InitialIP) -eq $true)
       {$IPReference.InitialIP = CheckDns($(ReadConfigFile("server")))}
      else
      {
       $IPReference.OtherIP = CheckDns($(ReadConfigFile("server")))
       If( $IPReference.OtherIP -ne $IPReference.InitialIP )
       {
        if( $(ReadConfigFile("ShowIPChangedMessage")) -eq "Y")
        {
         logMsg("IP changed noticed....") (1)
        }
       }
      }

       if( $(ReadConfigFile("ShowPortConnection")) -eq "Y")
       {
        CheckPort $(ReadConfigFile("server")) $(ReadConfigFile("Port"))
        if( $(ReadConfigFile("ShowIPPortTest")) -eq "Y")
        {
         logMsg("IP changed noticed....") (1)
        }
       }


      $SQLConnection = New-Object System.Data.SqlClient.SqlConnection 

      $SQLConnection.ConnectionString = "Server="+$(ReadConfigFile("Protocol"))
      $SQLConnection.ConnectionString = $SQLConnection.ConnectionString + $(ReadConfigFile("server"))+"," + $(ReadConfigFile("port"))
      $SQLConnection.ConnectionString = $SQLConnection.ConnectionString + ";Database="+$(ReadConfigFile("Db"))
      $SQLConnection.ConnectionString = $SQLConnection.ConnectionString + ";User ID="+ $(ReadConfigFileSecrets("user"))
      $SQLConnection.ConnectionString = $SQLConnection.ConnectionString + ";Password="+$(ReadConfigFileSecrets("password"))
      $SQLConnection.ConnectionString = $SQLConnection.ConnectionString + ";Connection Timeout="+$(ReadConfigFile("ConnectionTimeout"))
      $SQLConnection.ConnectionString = $SQLConnection.ConnectionString + ";Application Name="+$(ReadConfigFile("ApplicationName"))
      $SQLConnection.ConnectionString = $SQLConnection.ConnectionString + ";ConnectRetryCount="+$(ReadConfigFile("ConnectRetryCount"))
      $SQLConnection.ConnectionString = $SQLConnection.ConnectionString + ";ConnectRetryInterval="+$(ReadConfigFile("ConnectRetryInterval"))
      $SQLConnection.ConnectionString = $SQLConnection.ConnectionString + ";Max Pool Size="+$(ReadConfigFile("Max Pool Size"))
      $SQLConnection.ConnectionString = $SQLConnection.ConnectionString + ";Min Pool Size="+$(ReadConfigFile("Min Pool Size"))
      $SQLConnection.ConnectionString = $SQLConnection.ConnectionString + ";MultipleActiveResultSets="+$(ReadConfigFile("MultipleActiveResultSets"))
      $SQLConnection.ConnectionString = $SQLConnection.ConnectionString + ";Pooling="+$(ReadConfigFile("Pooling"))
      If( $(ReadConfigFile("Packet Size")) -ne "-1" )
      {
        $SQLConnection.ConnectionString = $SQLConnection.ConnectionString + ";Packet Size="+$(ReadConfigFile("Packet Size"))
      }

      $SQLConnection.StatisticsEnabled = 1

      $start = get-date
        $SQLConnection.Open()
      $end = get-date

      $LatencyAndOthers.ConnectionsDone_Number_Success = $LatencyAndOthers.ConnectionsDone_Number_Success+1
      $LatencyAndOthers.ConnectionsDone_MS = $LatencyAndOthers.ConnectionsDone_MS+(New-TimeSpan -Start $start -End $end).TotalMilliseconds

      if( $(ReadConfigFile("ShowConnectionMessage")) -eq "Y")
      {
       logMsg("Connected to the database in (ms):" +(New-TimeSpan -Start $start -End $end).TotalMilliseconds + " - ID:" + $SQLConnection.ClientConnectionId.ToString() + " -- " + $SQLConnection.WorkstationId + " Server Version:" + $SQLConnection.ServerVersion) (3)
       logMsg("Connections Failed :" + $LatencyAndOthers.ConnectionsDone_Number_Failed.ToString())
       logMsg("Connections Success:" + $LatencyAndOthers.ConnectionsDone_Number_Success.ToString())
       logMsg("Connections ms     :" + ($LatencyAndOthers.ConnectionsDone_MS / $LatencyAndOthers.ConnectionsDone_Number_Success).ToString())
      }
      
      return $SQLConnection
      break;
    }
  catch
   {
    $LatencyAndOthers.ConnectionsDone_Number_Failed = $LatencyAndOthers.ConnectionsDone_Number_Failed +1
    logMsg("Not able to connect - Retrying the connection..." + $Error[0].Exception.ErrorRecord + "-" + $Error[0].Exception.ToString().Replace("\t"," ").Replace("\n"," ").Replace("\r"," ").Replace("\r\n","").Trim()) (2)
    logMsg("Waiting for next retry in " + $(ReadConfigFile("RetryLogicNumberAttemptsBetweenAttemps")) + " seconds ..")
    Start-Sleep -s $(ReadConfigFile("RetryLogicNumberAttemptsBetweenAttemps"))
    if( $(ReadConfigFile("ClearAllPools").ToUpper()) -eq "Y" )
      {
        [System.Data.SqlClient.SqlConnection]::ClearAllPools()
      }
   }
  }
}

#----------------------------------------------------------------
#Function to execute any query using a command retry-logic
#----------------------------------------------------------------

Function ExecuteQuery($SQLConnectionSource, $query)
{ 
  $Retries=$(ReadConfigFile("CommandExecutionRetries"))
  $ShowXMLPlan=$(ReadConfigFile("ShowXMLPlan"))
  $bError=$false
  for ($i=1; $i -le $Retries; $i++)
  {
   try
    {
      If($bError)
      {
       $bError=$false 
         If($rdr.IsClosed -eq $false)
         {
          $rdr.Close()
         }
      }
      $start = get-date
        $command = New-Object -TypeName System.Data.SqlClient.SqlCommand
        $command.CommandTimeout = $(ReadConfigFile("CommandTimeout"))
        If($i -ge 2) 
        {
          $command.CommandTimeout = [int]$(ReadConfigFile("CommandTimeout")) + [int]$(ReadConfigFile("CommandTimeoutFactor"))
        } 
        $command.Connection=$SQLConnectionSource
        If($ShowXMLPlan -eq "Y")
         {
          $command.CommandText = "SET STATISTICS XML ON;"+$query
         }
         else
         {
          $command.CommandText = $query
         }
        ##$command.ExecuteNonQuery() | Out-Null 
        $SQLConnectionSource.ResetStatistics()
        $rdr = $command.ExecuteReader()
      $data = $SQLConnectionSource.RetrieveStatistics()
      $end = get-date

        If($ShowXMLPlan -eq "Y")
         {
          do
           {
            $datatable = new-object System.Data.DataTable
            $datatable.Load($rdr)
           } while ($rdr.IsClosed -eq $false)
         }
             $LatencyAndOthers.ExecutionsDone_Number_Success = $LatencyAndOthers.ExecutionsDone_Number_Success+1
             $LatencyAndOthers.ExecutionsDone_MS = $LatencyAndOthers.ExecutionsDone_MS+(New-TimeSpan -Start $start -End $end).TotalMilliseconds

             LogMsg("-------------------------" ) -Color 3
             LogMsg("Query                 :  " +$query) 
             LogMsg("Iteration             :  " +$i) 
             LogMsg("Time required (ms)    :  " +(New-TimeSpan -Start $start -End $end).TotalMilliseconds) 
             LogMsg("NetworkServerTime (ms):  " +$data.NetworkServerTime) ##Returns the cumulative amount of time (in milliseconds) that the provider spent waiting for replies from the server once the application has started using the provider and has enabled statistics.
             LogMsg("Execution Time (ms)   :  " +$data.ExecutionTime) ##Returns the cumulative amount of time (in milliseconds) that the provider has spent processing once statistics have been enabled, including the time spent waiting for replies from the server as well as the time spent executing code in the provider itself.
             LogMsg("Connection Time       :  " +$data.ConnectionTime) ##The amount of time (in milliseconds) that the connection has been opened after statistics have been enabled (total connection time if statistics were enabled before opening the connection).
             LogMsg("ServerRoundTrips      :  " +$data.ServerRoundtrips) ##Returns the number of times the connection sent commands to the server and got a reply back once the application has started using the provider and has enabled statistics.
             LogMsg("BuffersReceived       :  " +$data.BuffersReceived) 
             LogMsg("SelectRows            :  " +$data.SelectRows) 
             LogMsg("SelectCount           :  " +$data.SelectCount) 
             LogMsg("BytesSent             :  " +$data.BytesSent) 
             LogMsg("BytesReceived         :  " +$data.BytesReceived) 
             LogMsg("CommandTimeout        :  " +$command.CommandTimeout ) 
             LogMsg("Total Exec.Failed     :  " + $LatencyAndOthers.ExecutionsDone_Number_Failed.ToString())
             LogMsg("Total Exec.Success    :  " + $LatencyAndOthers.ExecutionsDone_Number_Success.ToString())
             LogMsg("Avg. Executions ms    :  " + ($LatencyAndOthers.ExecutionsDone_MS / $LatencyAndOthers.ExecutionsDone_Number_Success).ToString())

             If($ShowXMLPlan -eq "Y")
             {
               LogMsg("Execution Plan        :  " +$datatable[0].Rows[0].Item(0)) 
             }
             $rdr.Close()

             LogMsg("-------------------------" ) -Color 3
    break;
    }
  catch
   {
    $LatencyAndOthers.ExecutionsDone_Number_Failed = $LatencyAndOthers.ExecutionsDone_Number_Failed+1
    $bError=$true
    LogMsg("------------------------" ) -Color 3
    LogMsg("Query                 : " +$query) 
    LogMsg("Iteration             : " +$i) 
    LogMsg("Time required (ms)    : " +(New-TimeSpan -Start $start -End $end).TotalMilliseconds) 
    LogMsg("Total Exec.Failed     :  " + $LatencyAndOthers.ExecutionsDone_Number_Failed.ToString())
    LogMsg("Total Exec.Success    :  " + $LatencyAndOthers.ExecutionsDone_Number_Success.ToString())
    LogMsg("Avg. Executions ms    :  " + ($LatencyAndOthers.ExecutionsDone_MS / $LatencyAndOthers.ExecutionsDone_Number_Success).ToString())
    logMsg("Not able to run the query - Retrying the operation..." + $Error[0].Exception.ErrorRecord + ' ' + $Error[0].Exception) (2)
    LogMsg("-------------------------" ) -Color 3
    $Timeout = $(ReadConfigFile("CommandExecutionRetriesWaitTime"))
    logMsg("Retrying in..." + $Timeout + " seconds ") (2)
    Start-Sleep -s $Timeout
   }
  }
}

#--------------------------------
#Obtain the DNS details resolution.
#--------------------------------
function CheckDns($sReviewServer)
{
try
 {
    $IpAddress = [System.Net.Dns]::GetHostAddresses($sReviewServer)
    foreach ($Address in $IpAddress)
    {
        $sAddress = $sAddress + $Address.IpAddressToString + " ";
    }
    if( $(ReadConfigFile("ShowIPResolution")) -eq "Y")
    {
      logMsg("Server IP:" + $sAddress) (3)
    }
    return $sAddress
    break;
 }
  catch
 {
  logMsg("Imposible to resolve the name - Error: " + $Error[0].Exception) (2)
  return ""
 }
}

#--------------------------------
#Obtain the PORT details connectivity
#--------------------------------
function CheckPort($sReviewServer,$Port)
{
try
 {
    $TcpConnection = Test-NetConnection $sReviewServer -Port $Port -InformationLevel Detailed
    if( $(ReadConfigFile("ShowIPPortTest")) -eq "Y")
    {
      logMsg("Test " + $sReviewServer + " Port:" + $Port + " Status:" + $TcpConnection.TcpTestSucceeded) (3)
    }
    return $TcpConnection.TcpTestSucceeded
    break;
 }
  catch
 {
  logMsg("Imposible to test the port - Error: " + $Error[0].Exception) (2)
  return "Error"
 }
}

#--------------------------------
#Obtain Process Name By ID
#--------------------------------
function ProcessNameByID($Id)
{
try
 {
    $Proc = Get-Process -id $id 
    return $Proc.ProcessName + "-" + $Proc.Description
 }
  catch
 {
  return ""
 }
}

#--------------------------------
#Obtain the list of ports, process and calculate how many are for 1433 and redirect ports
#--------------------------------
function Ports($IPControlPort,$IPControlPortProcess)
{
try
 {
    $IPControlPortProcess.Clear()
    $IPControlPort.IP1433=0
    $IPControlPort.IPRedirect=0
    $IPControlPort.IPTotal=0
    $bFound=$false
    $Number=-1
    $IpAddress = Get-NetTCPConnection
    for ($i=0; $i -lt $IpAddress.Count; $i++)
    {

     $bFound = $false
     $IPControlPort.IPTotal=$IPControlPort.IPTotal+1 

     for ($iP=0; $iP -lt $IPControlPortProcess.Count; $iP++)
     {
       if( $IpAddress[$i].OwningProcess -eq $IPControlPortProcess[$iP].NumProcess)
       {
          $bFound=$true
          $Number=$iP
          break
       }
     }

     if($bFound -eq $false)
     {
        $Tmp = [IPControlPortProcess]::new()
        $TMP.IP1433=0
        $TMP.IPRedirect=0
        $TMP.IPTotal=0
        $TMP.NumProcess = $IpAddress[$i].OwningProcess
        $IPControlPortProcess.Add($TMP) | Out-Null
        $Number=$IPControlPortProcess.Count-1
     }

     If( $IpAddress[$i].RemotePort -eq 1433 )
     {
       $IPControlPort.IP1433=$IPControlPort.IP1433+1 
       $IPControlPortProcess[$Number].IP1433=$IPControlPortProcess[$Number].IP1433+1
     }
     If( $IpAddress[$i].RemotePort -ge 11000 -and $IpAddress[$i].RemotePort -le 12999)
     {
       $IPControlPort.IPRedirect=$IPControlPort.IPRedirect+1 
       $IPControlPortProcess[$Number].IPRedirect=$IPControlPortProcess[$Number].IPRedirect+1
     }
       $IPControlPortProcess[$Number].IPTotal=$IPControlPortProcess[$Number].IPTotal+1
    }
     logMsg("Ports - 1433 : " + $IPControlPort.Ip1433 + " Redirect: " + $IPControlPort.IPRedirect + " Total: " + $IPControlPort.IPTotal)

     If($(ReadConfigFile("ShowPortsDetails")) -eq "Y" )
     {
      logMsg("Procs:"  + ($IPControlPortProcess.Count-1).ToString() ) 
      for ($iP=0; $iP -lt $IPControlPortProcess.Count; $iP++)
      {
        $ProcessName = ProcessNameByID($IPControlPortProcess[$IP].NumProcess)
        logMsg("------> Proc Number:"  + $IPControlPortProcess[$IP].NumProcess + "-" + $ProcessName + "/ 1433: " + $IPControlPortProcess[$IP].IP1433 + " Redirect:" + $IPControlPortProcess[$IP].IPRedirect + " Other:" + $IPControlPortProcess[$IP].IPTotal)
      }
     }
 }
  catch
 {
  logMsg("Imposible to obtain the ports - Error: " + $Error[0].Exception) (2)
 }
}

#--------------------------------
#Obtain the Performance counters.
#--------------------------------
function PerfCounters($CounterPattern)
{
try
 {
    logMsgPerfCounter( "Obtaining Performance Counters of : " + $CounterPattern )
    $Counters = Get-Counter -Counter $CounterPattern 
    foreach ($Counter in $Counters.CounterSamples)
    {
        logMsgPerfCounter( "Counter: " + $Counter.Path + " - " + $Counter.InstanceName + "-" + $Counter.CookedValue )
    }
    logMsgPerfCounter( "Obtained Performance Counters of : " + $CounterPattern )
 }
  catch
 {
  logMsgPerfCounter( "Imposible to obtain Performance Counters of : " + $CounterPattern + "- Error: " + $Error[0].Exception) (2)
  return ""
 }
}

#--------------------------------------------------------------
#Create a folder 
#--------------------------------------------------------------
Function CreateFolder
{ 
  Param( [Parameter(Mandatory)]$Folder ) 
  try
   {
    $FileExists = Test-Path $Folder
    if($FileExists -eq $False)
    {
     $result = New-Item $Folder -type directory 
     if($result -eq $null)
     {
      logMsg("Imposible to create the folder " + $Folder) (2)
      return $false
     }
    }
    return $true
   }
  catch
  {
   return $false
  }
 }

#-------------------------------
#Delete the file
#-------------------------------
Function DeleteFile{ 
  Param( [Parameter(Mandatory)]$FileName ) 
  try
   {
    $FileExists = Test-Path $FileNAme
    if($FileExists -eq $True)
    {
     Remove-Item -Path $FileName -Force 
    }
    return $true 
   }
  catch
  {
   return $false
  }
 }

#--------------------------------
#Log the operations
#--------------------------------
function logMsg
{
    Param
    (
         [Parameter(Mandatory=$false, Position=0)]
         [string] $msg,
         [Parameter(Mandatory=$false, Position=1)]
         [int] $Color,
         [Parameter(Mandatory=$false, Position=2)]
         [boolean] $Show=$true,
         [Parameter(Mandatory=$false, Position=3)]
         [boolean] $ShowDate=$true,
         [Parameter(Mandatory=$false, Position=4)]
         [boolean] $SaveFile=$true,
         [Parameter(Mandatory=$false, Position=5)]
         [boolean] $NewLine=$true 
 
    )
  try
   {
    If(TestEmpty($msg))
    {
     $msg = " "
    }

    if($ShowDate -eq $true)
    {
      $Fecha = Get-Date -format "yyyy-MM-dd HH:mm:ss"
    }
    $msg = $Fecha + " " + $msg
    If($SaveFile -eq $true)
    {
      Write-Output $msg | Out-File -FilePath $LogFile -Append
    }
    $Colores="White"

    If($Color -eq 1 )
     {
      $Colores ="Cyan"
     }
    If($Color -eq 3 )
     {
      $Colores ="Yellow"
     }
    If($Color -eq 4 )
     {
      $Colores ="Green"
     }
    If($Color -eq 5 )
     {
      $Colores ="Magenta"
     }

     if($Color -eq 2 -And $Show -eq $true)
      {
         if($NewLine)
         {
           Write-Host -ForegroundColor White -BackgroundColor Red $msg 
         }
         else
         {
          Write-Host -ForegroundColor White -BackgroundColor Red $msg -NoNewline
         }
      } 
     else 
      {
       if($Show -eq $true)
       {
        if($NewLine)
         {
           Write-Host -ForegroundColor $Colores $msg 
         }
        else
         {
           Write-Host -ForegroundColor $Colores $msg -NoNewline
         }  
       }
      } 


   }
  catch
  {
    Write-Host $msg 
  }
}

#--------------------------------
#Log the operations
#--------------------------------
function logMsgPerfCounter
{
    Param
    (
         [Parameter(Mandatory=$true, Position=0)]
         [string] $msg,
         [Parameter(Mandatory=$false, Position=1)]
         [int] $Color
    )
  try
   {
    $Fecha = Get-Date -format "yyyy-MM-dd HH:mm:ss"
    $msg = $Fecha + " " + $msg
    Write-Output $msg | Out-File -FilePath $LogFileCounter -Append
    $Colores="White"
 
    If($Color -eq 1 )
     {
      $Colores ="Cyan"
     }
    If($Color -eq 3 )
     {
      $Colores ="Yellow"
     }

     if($Color -eq 2)
      {
        Write-Host -ForegroundColor White -BackgroundColor Red $msg 
      } 
     else 
      {
        Write-Host -ForegroundColor $Colores $msg 
      } 


   }
  catch
  {
    Write-Host $msg 
  }
}
#--------------------------------
#The Folder Include "\" or not???
#--------------------------------

function GiveMeFolderName([Parameter(Mandatory)]$FolderSalida)
{
  try
   {
    $Pos = $FolderSalida.Substring($FolderSalida.Length-1,1)
    If( $Pos -ne "\" )
     {return $FolderSalida + "\"}
    else
     {return $FolderSalida}
   }
  catch
  {
    return $FolderSalida
  }
}

#--------------------------------
#Validate Param
#--------------------------------
function TestEmpty($s)
{
if ([string]::IsNullOrWhitespace($s))
  {
    return $true;
  }
else
  {
    return $false;
  }
}

#--------------------------------
#Separator
#--------------------------------

function GiveMeSeparator
{
Param([Parameter(Mandatory=$true)]
      [System.String]$Text,
      [Parameter(Mandatory=$true)]
      [System.String]$Separator)
  try
   {
    [hashtable]$return=@{}
    $Pos = $Text.IndexOf($Separator)
    $return.Text= $Text.substring(0, $Pos) 
    $return.Remaining = $Text.substring( $Pos+1 ) 
    return $Return
   }
  catch
  {
    $return.Text= $Text
    $return.Remaining = ""
    return $Return
  }
}

#--------------------------------
#Remove invalid chars
#--------------------------------

Function Remove-InvalidFileNameChars {

param([Parameter(Mandatory=$true,
    Position=0,
    ValueFromPipeline=$true,
    ValueFromPipelineByPropertyName=$true)]
    [String]$Name
)

return [RegEx]::Replace($Name, "[{0}]" -f ([RegEx]::Escape([String][System.IO.Path]::GetInvalidFileNameChars())), '')}

#--------------------------------------
#Read the configuration file
#--------------------------------------
Function ReadConfigFile
{ 
    Param
    (
         [Parameter(Mandatory=$false, Position=0)]
         [string] $Param
    )
  try
   {

    $return = ""

    If(TestEmpty($Param))
    {
     return $return
    }

    $stream_reader = New-Object System.IO.StreamReader($FileConfig)
    while (($current_line =$stream_reader.ReadLine()) -ne $null) ##Read the file
    {
     If(-not (TestEmpty($current_line)))
     {
      if($current_line.Substring(0,2) -ne "//" )
      {
        $Text = GiveMeSeparator $current_line "="
        if($Text.Text -eq $Param )
        {
         $return = $Text.Remaining;
         break;
        }
      }
     }
    }
    $stream_reader.Close()
    return $return
   }
 catch
 {
   logMsg("Error Reading the config file..." + $Error[0].Exception) (2) 
   return ""
 }
}

#--------------------------------------
#Read the TSQL command to test
#--------------------------------------
Function ReadTSQL($query)
{ 
  try
   {

    If(-not ($(FileExist($File))))
    {
      $Null = $query.Add("SELECT 1")
      return $true
    }
    $bRead = $false

    $stream_reader = New-Object System.IO.StreamReader($File)
    while (($current_line =$stream_reader.ReadLine()) -ne $null) ##Read the file
    {
     If(-not (TestEmpty($current_line)))
     {
      $bRead = $true
      $Null = $query.Add($current_line)
     }
    }
    $stream_reader.Close()
    if(-not($bRead)) {  $Null = $query.add("SELECT 1") }
    return $true
   }
 catch
 {
   logMsg("Error Reading the config file..." + $Error[0].Exception) (2) 
   return $false
 }
}

#--------------------------------------
#Read the configuration file - Secrets
#--------------------------------------
Function ReadConfigFileSecrets
{ 
    Param
    (
         [Parameter(Mandatory=$false, Position=0)]
         [string] $Param
    )
  try
   {

    $return = ""

    If(TestEmpty($Param))
    {
     return $return
    }

    $stream_reader = New-Object System.IO.StreamReader($FileSecrets)
    while (($current_line =$stream_reader.ReadLine()) -ne $null) ##Read the file
    {
     If(-not (TestEmpty($current_line)))
     {
      $Text = GiveMeSeparator $current_line "="
      if($Text.Text -eq $Param )
      {
       $return = $Text.Remaining;
       break;
      }
     }
    }
    $stream_reader.Close()
    return $return
   }
 catch
 {
   logMsg("Error Reading the config file..." + $Error[0].Exception) (2) 
   return ""
 }
}

#-------------------------------
#File Exists
#-------------------------------
Function FileExist{ 
  Param( [Parameter(Mandatory)]$FileName ) 
  try
   {
    $return=$false
    $FileExists = Test-Path $FileName
    if($FileExists -eq $True)
    {
     $return=$true
    }
    return $return
   }
  catch
  {
   return $false
  }
 }


#--------------------------------
#Execute the process.
#--------------------------------


try
{
 cls
 $Pooling=$true
 $NumberExecutions=0
 
Class IPReference #Class to manage the IP address changes
{
 [string]$InitialIP = ""
 [string]$OtherIP = ""
}

Class IPControlPort #Class to manage how many ports are opened
{
 [int]$IP1433 = 0
 [int]$IPRedirect = 0
 [int]$IPTotal = 0
}

Class IPControlPortProcess #Class to manage by process how many ports are opened
{
 [int]$IP1433 = 0
 [int]$IPRedirect = 0
 [int]$NumProcess = 0
 [int]$IPTotal = 0
}

Class LatencyAndOthers #Class to manage the connection latency
{
 [long]$ConnectionsDone_MS = 0
 [long]$ConnectionsDone_Number_Success = 0
 [long]$ConnectionsDone_Number_Failed = 0
 [long]$ExecutionsDone_MS = 0
 [long]$ExecutionsDone_Number_Success = 0
 [long]$ExecutionsDone_Number_Failed = 0
}

$IPReference = [IPReference]::new()
$IPControlPort = [IPControlPort]::new()
$IPControlPortProcess = [System.Collections.ArrayList]::new() 
$LatencyAndOthers = [LatencyAndOthers]::new()


[System.Collections.ArrayList]$IPArrayConnection = @()
[System.Collections.ArrayList]$Query = @()
Class Connection #Class to manage by process how many ports are opened
{
 $Tmp = [System.Data.SqlClient.SqlConnection]
}

#--------------------------------
#Run the process
#--------------------------------

$invocation = (Get-Variable MyInvocation).Value
$Folder = Split-Path $invocation.MyCommand.Path

$sFolderV = GiveMeFolderName($Folder) #Creating a correct folder adding at the end \.

$LogFile = $sFolderV + "Results.Log"                     #Logging the operations.
$LogFileCounter = $sFolderV + "Results_PerfCounter.Log"  #Logging the data of performance counter
$FileConfig = $sFolderV + "Config.Txt"                   #Configuration of parameter values
$FileSecrets = $sFolderV + "Secrets.Txt"                  #Configuration of User&Passowrd
$File = $sFolderV +"TSQL.SQL"                            #TSQL instructtions

logMsg("Deleting Logs") (1)
   $result = DeleteFile($LogFile)        #Delete Log file
   $result = DeleteFile($LogFileCounter) #Delete Log file
logMsg("Deleted Logs") (1)

 $Null = ReadTSQL $Query
 $sw = [diagnostics.stopwatch]::StartNew()

 $NumberExecutions= $(ReadConfigFile("NumberExecutions"))
 LogMsg("Number of execution times " + $NumberExecutions) 
 
 for ($i=1; $i -le $NumberExecutions; $i++)
  {
   try
    {
      LogMsg(" ---> Operation Number#: " + $i) -SaveFile $false
      $Null = $IPArrayConnection.Add($(GiveMeConnectionSource $IPReference $IPControlPort $IPControlPortProcess)) #Connecting to the database.
      if($IPArrayConnection[$i-1] -eq $null)
      { 
        If( $(ReadConfigFile("ShowWhatHappenedMsgAtTheEnd")) -eq "Y")
        {
          LogMsg("What happened?") (2) 
        }
          exit;
      }
      if( $(ReadConfigFile("ShowExecutedQuery").ToUpper()) -eq "Y" ) 
      { 
       for ($iQuery=0; $iQuery -lt $query.Count; $iQuery++) 
        {
         try
         {
          
           LogMsg(" ---> Query Number#: " + ($iQuery+1)) -SaveFile $false
           ExecuteQuery $IPArrayConnection[$i-1] $query[$iQuery] 


           if( $(ReadConfigFile("ShowCounters").ToUpper()) -eq "Y" )
           {  
              PerfCounters "\Processor(_total)\*"
              PerfCounters "\Memory\*"
              PerfCounters "\Network Interface(*)\*"
              PerfCounters "\Network Adapter(*)\*"
           }
         }
       catch
       {
         LogMsg("Executing Process - Error:" + $Error[0].Exception) (2)
       }
      }  
     }

        if( $(ReadConfigFile("ShowPorts").ToUpper()) -eq "Y" ) 
          { 
           Ports $IPControlPort $IPControlPortProcess 
          }

        if( $(ReadConfigFile("CloseConnections").ToUpper()) -eq "Y" )
        {
           $IPArrayConnection[$i-1].Close()
           if( $(ReadConfigFile("ShowConnectionMessage")) -eq "Y")
           {
              LogMsg("Closed Connection") (1) -SaveFile $false      
           }
        }
        else
        {
           if( $(ReadConfigFile("ShowConnectionMessage")) -eq "Y")
           {
             LogMsg("Without closing the connection") (2) -SaveFile $false
           }
        }

        If($(ReadConfigFile("WaitTimeBetweenConnections")) -ne "0")
        {
          LogMsg("Waiting for " + $(ReadConfigFile("WaitTimeBetweenConnections")) + " seconds to continue (Demo purpose)")  -SaveFile $false
          Start-Sleep -s $(ReadConfigFile("WaitTimeBetweenConnections"))
        }

 
     } 
       catch
       {
         LogMsg("Executing Query Interaction: " + $Error[0].Exception) (2) 
       }
    } ##
    LogMsg("Time spent (ms) Procces :  " +$sw.elapsed) 
    LogMsg("Review: https://docs.microsoft.com/en-us/dotnet/framework/data/adonet/sql/provider-statistics-for-sql-server") 
}
catch
{
    LogMsg("Complete Process - Error:" + $Error[0].Exception) (2)
}
