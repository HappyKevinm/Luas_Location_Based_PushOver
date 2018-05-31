function Get-LuasTimes
{
<#
.SYNOPSIS
    Makes a call to Dublin BUS API https://data.dublinked.ie and returns JSON blob of LUAS stops and times
 
.DESCRIPTION
    Makes a call to Dublin BUS API https://data.dublinked.ie and returns the routes, stops and stop times
 
.PARAMETER Operator
    Default is LUAS, because that all I cared about when writing this.
    Command can be used to call Irish Rail (IR),  Bus Atha Cliath / Dublin Bus (BAC), or Bus Éireann (BE) 

.PARAMETER RouteID  
    Specify the route you are looking at for LUAS this will be red or green

.PARAMETER StopID
    Specify the stop you are looking at stored in stopid use the following command to list stopid's
    (Get-LuasTimes -Operator LUAS -RouteID green).results.stops | ft
 
 .EXAMPLE
     List all of the routes for an operator LUAS 
        Get-LuasTimes -Operator LUAS 
    List all of the routes for an operator LUAS green Line
        Get-LuasTimes -Operator LUAS -RouteID green
    List stop information for Cheerywood
        Get-LuasTimes -StopID LUAS47
    Display the departure times for my LUAS stop
        Get-LuasTimes -StopID LUAS38 |  ? {$_.origin -like "*brid*"} | fl destination,duetime
        
.NOTES
    Author:  Kevin Miller
    Website: http://www.happymillfam.com
    Email: kevinm@wlkmmas.org
#>
  

[CmdletBinding()]
Param(
    [Parameter(Mandatory=$False)][string]$Operator,
    [Parameter(Mandatory=$False)][string]$RouteID,
    # todo [Parameter(Mandatory=$False)][validateset("auto","ca","uk2","us","si",$null)][string]$StopID
    [Parameter(Mandatory=$False)][string]$StopID
)
process
    {
        If ($operator)
        {
            $OOperator = $operator
        }
        else
        {
            $OOperator = "LUAS"           
        }
        If ($RouteID)
        {
            $results = (Invoke-RestMethod -uri "https://data.dublinked.ie/cgi-bin/rtpi/routeinformation?routeid=$($RouteID)&operator=$($OOperator)&&format=json").results.stops 
        }
        elseif ($stopid) 
        {
            $results = (Invoke-RestMethod -uri "https://data.dublinked.ie/cgi-bin/rtpi/realtimebusinformation?operator=$($OOperator)&stopid=$($StopID)&format=json").results
        }
        else
        {
            $results = (Invoke-RestMethod -uri "https://data.dublinked.ie/cgi-bin/rtpi/routelistinformation?operator=$($OOperator)&format=json").results
        }
    return $results 
    }
}

function post-pushovernotification
{
<#
.SYNOPSIS
    pushs a message to pushover API https://api.pushover.net/ 
 
.DESCRIPTION
    pushs a message to pushover API https://api.pushover.net/ 
 
.PARAMETER PushOverAPIToken
    Your pushover API token 

.PARAMETER PushOverUserKey
    Your pushover User Key 

.PARAMETER PushOverMessage
    the Message you want to send to Pushover
 
.EXAMPLE
     send a pushover message
     #push over settings
     $PushOverAPIToken = "apo15mcd9b8xxxxhubh5xutumse"
     $PushOverUserKey = "uuz8v8rhdxxxxxctha2ku6uem" 
     $pushovermessage = "what up hommie"
     post-pushovernotification -PushOverAPIToken $PushOverAPIToken -PushOverUserKey $PushOverUserKey -PushOverMessage $pushovermessage    
   
        
   
.NOTES
    Author:  Kevin Miller
    Website: http://www.happymillfam.com
    Email: kevinm@wlkmmas.org
#>
  

[CmdletBinding()]
Param(
    [Parameter(Mandatory=$True)][string]$PushOverAPIToken,
    [Parameter(Mandatory=$True)][string]$PushOverUserKey,
    [Parameter(Mandatory=$True)][string]$PushOverMessage

)
process 
    {
        $uri = "https://api.pushover.net/1/messages.json"
        $parameters = @{
          token = $PushOverAPIToken
          user = $PushOverUserKey
          message = $PushOverMessage
        }
        $parameters | Invoke-RestMethod -Uri $uri -Method Post
    }  
}

# Settings
# push over settings
$PushOverAPIToken = "apo15mcd9xxxxxxxxxxxxh5xutumse"
$PushOverUserKey = "uuz8v8rhdaxxxxxxxxxxxxvctha2ku6uem" 
# Script settings
# you need to make this file the first time out. Its a text file with the following first line
# What,where,when,mapurl
# Nothing will work if the file is missing, did not add in file check code
$File = "c:\bob\NearLuas.txt"


# Initial grab of the file to establish file count and size and create new file as needed
$Location = import-csv $file
$size = (get-childitem $file).length
# File is larger then 1.5mb IFTTT auto creates a new file at 2mb lets beat them and make a new file
if ($size -gt 1.5mb)
    {
        Rename-Item $file -NewName "LuasLocation.$((get-date).DayOfYear).$((get-date).Year).txt"
        $location[0] | export-csv LuasLocation.txt
        
    }
$locCount = $location.count
do
    {
        $Location = import-csv $file
        if($locCount -lt $location.count)
        {
            Write-Host -ForegroundColor Green "File is bigger, we must have gone some where - we're at " -NoNewline; Write-Host -ForegroundColor yellow "$(($location | select -Last 1).what)"
            $LuasTimes = get-luastimes -StopID ($location | select -Last 1).where | select duetime,destination
            Write-Host -ForegroundColor yellow "checking luas stop ID $(($location | select -Last 1).where)"
            $pushovermessage = $null
            foreach ($luastime in $luastimes)
            {
                if ($luastime.duetime.toLower() -eq "due")
                {
                    $pushovermessage = $pushovermessage + "$(($luastime.Destination).trim("LUAS ")) ARRIVING`n"
                }
                else
                {
                    $pushovermessage = $pushovermessage + "$(($luastime.Destination).trim("LUAS ")) in $($luastime.duetime)`n"
                }
            }
            write-host -ForegroundColor green "The pushover message is :" 
            write-host -ForegroundColor Magenta "$($pushovermessage)"
            post-pushovernotification -PushOverAPIToken $PushOverAPIToken -PushOverUserKey $PushOverUserKey -PushOverMessage $pushovermessage
            write-host -ForegroundColor Green "Message sent at $(get-date)"
            # Increment $LocCount so we do not push another message
            $locCount = $locCount + 1
        }
        else 
        {
            write-host "nothing new - Kev must not be moving. Checking again in 30 seconds at $((get-date).AddSeconds(30))"
        }
        start-sleep -Seconds 30
    }
While ($LocCount -ge 0) 


