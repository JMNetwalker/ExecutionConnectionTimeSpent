
#----------------------------------------------------------------
#Parameters 
#----------------------------------------------------------------
param($server = "", #ServerName parameter to connect,for example, myserver.database.windows.net
      $user = "", #UserName parameter  to connect
      $passwordSecure = "", #Password Parameter  to connect
      $Db = "", #DBName Parameter  to connect
      $Folder = "C:\PerfConn", #Folder Parameter to save the log and solution files, for example, c:\PerfConn
      $PoolingQuestion = "Y",
      $NumberExecutionsQ ="100", 
      $File = "C:\PerfConn\TSQL.SQL")
      

#----------------------------------------------------------------
#Function to connect to the database using a retry-logic
#----------------------------------------------------------------

Function GiveMeConnectionSource($IPReference,$IPControlPort,$IPControlPortProcess,$Pooling)
{ 
  for ($i=1; $i -lt 10; $i++)
  {
   try
    {
      logMsg( "Connecting to the database...Attempt #" + $i) (1)
      logMsg( "Connecting to server: " + $server + " - DB: " + $Db) (1)

      if( TestEmpty($IPReference.InitialIP) -eq $true)
       {$IPReference.InitialIP = CheckDns($server)}
      else
      {
       $IPReference.OtherIP = CheckDns($server)
       If( $IPReference.OtherIP -ne $IPReference.InitialIP )
       {
         #[System.Data.SqlClient.SqlConnection]::ClearAllPools()
         logMsg("IP changed noticed....") (1)
       }
      }


      $SQLConnection = New-Object System.Data.SqlClient.SqlConnection 
      $SQLConnection.ConnectionString = "Server="+$server+";Database="+$Db+";User ID="+$user+";Password="+$password+";Connection Timeout=60;Application Name=PerfCollector" 
      if( $Pooling -eq $true ) 
          {$SQLConnection.ConnectionString = $SQLConnection.ConnectionString + ";Pooling=True"} 
      else 
          {$SQLConnection.ConnectionString = $SQLConnection.ConnectionString + ";Pooling=False"}
      $SQLConnection.StatisticsEnabled = 1
      $SQLConnection.Open()
      logMsg("Connected to the database...") (1)
      return $SQLConnection
      break;
    }
  catch
   {
    logMsg("Not able to connect - Retrying the connection..." + $Error[0].Exception) (2)
    Start-Sleep -s 5
   }
  }
}

#----------------------------------------------------------------
#Function to execute any query using a command retry-logic
#----------------------------------------------------------------

Function ExecuteQuery($SQLConnectionSource, $query)
{ 
  for ($i=1; $i -lt 3; $i++)
  {
   try
    {
      $start = get-date
        $command = New-Object -TypeName System.Data.SqlClient.SqlCommand
        $command.CommandTimeout = 6000
        $command.Connection=$SQLConnectionSource
        $command.CommandText = "SET STATISTICS XML ON;"+$query
        ##$command.ExecuteNonQuery() | Out-Null 
        $rdr = $command.ExecuteReader()
      $end = get-date
      $data = $SQLConnectionSource.RetrieveStatistics()
        do
         {
           $datatable = new-object System.Data.DataTable
           $datatable.Load($rdr)
         } while ($rdr.IsClosed -eq $false)
             LogMsg("-------------------------" ) 
             LogMsg("Query                 :  " + $query) 
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
             LogMsg("Execution Plan        :  " +$datatable[0].Rows[0].Item(0)) 
             LogMsg("-------------------------" )
    break;
    }
  catch
   {
    logMsg("Not able to run the query - Retrying the operation..." + $Error[0].Exception) (2)
    Start-Sleep -s 2
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
    logMsg("Server IP:" + $sAddress) (1)
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
    $IPControlPort.IP1433=0
    $IPControlPort.IPRedirect=0
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
     logMsg("Procs:"  + ($IPControlPortProcess.Count-1).ToString() ) 
     for ($iP=0; $iP -lt $IPControlPortProcess.Count; $iP++)
     {
       $ProcessName = ProcessNameByID($IPControlPortProcess[$IP].NumProcess)
       logMsg("------> Proc Number:"  + $IPControlPortProcess[$IP].NumProcess + "-" + $ProcessName + "/ 1433: " + $IPControlPortProcess[$IP].IP1433 + " Redirect:" + $IPControlPortProcess[$IP].IPRedirect + " Other:" + $IPControlPortProcess[$IP].IPTotal)
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
         [Parameter(Mandatory=$true, Position=0)]
         [string] $msg,
         [Parameter(Mandatory=$false, Position=1)]
         [int] $Color
    )
  try
   {
    $Fecha = Get-Date -format "yyyy-MM-dd HH:mm:ss"
    $msg = $Fecha + " " + $msg
    Write-Output $msg | Out-File -FilePath $LogFile -Append
    $Colores="White"
    $BackGround = 
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
    $BackGround = 
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

$IPReference = [IPReference]::new()
$IPControlPort = [IPControlPort]::new()
$IPControlPortProcess = [System.Collections.ArrayList]::new() 

#--------------------------------
#Check the parameters.
#--------------------------------

if (TestEmpty($server)) { $server = read-host -Prompt "Please enter a Server Name" }
if (TestEmpty($server)) 
   {
    LogMsg("Please, specify the server name") (2)
    exit;
   }
if (TestEmpty($user))  { $user = read-host -Prompt "Please enter a User Name"   }
if (TestEmpty($user)) 
   {
    LogMsg("Please, specify the user name") (2)
    exit;
   }
if (TestEmpty($passwordSecure))  
    {  
    $passwordSecure = read-host -Prompt "Please enter a password"  -assecurestring  
    $password = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($passwordSecure))
    }
else
    {$password = $passwordSecure} 
if (TestEmpty($Db))  { $Db = read-host -Prompt "Please enter a Database Name"  }
if (TestEmpty($DB)) 
   {
    LogMsg("Please, specify the DB name") (2)
    exit;
   }
if (TestEmpty($Folder)) {  $Folder = read-host -Prompt "Please enter a Destination Folder (Don't include the last \) - Example c:\PerfChecker" }

if (TestEmpty($PoolingQuestion)) { $PoolingQuestion = read-host -Prompt "Do you want to use Pooling (Y/N)?" }
if ($PoolingQuestion -eq "N") 
   {
    $Pooling=$false
   }

if (TestEmpty($NumberExecutionsQ)) 
  { $NumberExecutionsQ = read-host -Prompt "How Many times do you want to execute the script?" }
   if (TestEmpty($NumberExecutionsQ)) 
    {
      $NumberExecutions=100
    }
    if ([Int32]::TryParse($NumberExecutionsQ,[ref]$NumberExecutions))
    {

    }
    else {
   {
    LogMsg("Please, specify a correct number of times") (2)
    exit;
   }
  }
  


#--------------------------------
#Run the process
#--------------------------------


logMsg("Creating the folder " + $Folder) (1)
   $result = CreateFolder($Folder) #Creating the folder that we are going to have the results, log and zip.
   If( $result -eq $false)
    { 
     logMsg("Was not possible to create the folder") (2)
     exit;
    }
logMsg("Created the folder " + $Folder) (1)

$sFolderV = GiveMeFolderName($Folder) #Creating a correct folder adding at the end \.

$LogFile = $sFolderV + "Results.Log"                     #Logging the operations.
$LogFileCounter = $sFolderV + "Results_PerfCounter.Log"  #Logging the data of performance counter

logMsg("Deleting Logs") (1)
   $result = DeleteFile($LogFile)        #Delete Log file
   $result = DeleteFile($LogFileCounter) #Delete Log file
logMsg("Deleted Logs") (1)

LogMsg("Number of times " + $NumberExecutions.ToString()) 

$ExistFile= Test-Path $File

    if($ExistFile -eq 1)
    {
      $query = @(Get-Content $File) 
      LogMsg("Using the file content " + $File) 
    }
    else
    {
      $query = @("SELECT 1")
      LogMsg("Using the default value (SELECT 1)") 
    }

 $sw = [diagnostics.stopwatch]::StartNew()
  for ($i=0; $i -lt $NumberExecutions; $i++)
  {
   try
    {
     for ($iQuery=0; $iQuery -lt $query.Count; $iQuery++) 
      {
       try
       {
           $SQLConnectionSource = GiveMeConnectionSource $IPReference $IPControlPort $IPControlPortProcess $Pooling #Connecting to the database.
           if($SQLConnectionSource -eq $null)
           { 
             logMsg("It is not possible to connect to the database") (2)
             exit;
           }
           ExecuteQuery $SQLConnectionSource $query[$iQuery]
           Ports $IPControlPort $IPControlPortProcess
           PerfCounters "\processor(_total)\*"
           PerfCounters "\Memory\*"
           PerfCounters "\Network Interface(*)\*"
           PerfCounters "\Network Adapter(*)\*"
           $SQLConnectionSource.Close()
         }
       catch
       {
         LogMsg("Executing Process - Error:" + $Error[0].Exception) (2)
       }
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
